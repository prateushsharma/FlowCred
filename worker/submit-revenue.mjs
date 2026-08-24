import {
  Interface,
  JsonRpcProvider,
  Wallet,
  Contract,
  getAddress,
  isHexString,
} from "ethers";
import { proofProvider } from "@gluwa/usc-sdk";

const required = [
  "SEPOLIA_RPC_URL",
  "CREDITCOIN_RPC_URL",
  "CREDITCOIN_PROOF_BUILDER_URL",
  "CREDITCOIN_PRIVATE_KEY",
  "SOURCE_CHAIN_TXN_HASH",
  "REGISTRY_ADDRESS",
  "REVENUE_ASC_ADDRESS",
  "CREDIT_MANAGER_ADDRESS",
];

function env(name) {
  const value = process.env[name];
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

const revenueEventInterface = new Interface([
  "event RevenuePaymentForCredit(address indexed business,address indexed payer,bytes32 indexed paymentId,address token,uint256 amount)",
]);

const ascAbi = [
  "function execute(uint64 chainKey,uint64 blockHeight,bytes encodedTransaction,bytes32 merkleRoot,tuple(bytes32 hash,bool isLeft)[] siblings,bytes32 lowerEndpointDigest,bytes32[] continuityRoots) returns (bool)",
  "event RevenueProofConsumed(bytes32 indexed queryId,address indexed business,address indexed payer,uint256 amount,bytes32 paymentId)",
];

const managerAbi = [
  "function verifiedRevenue(address business) view returns (uint256)",
  "function asc() view returns (address)",
  "event VerifiedRevenueRecorded(address indexed business,address indexed payer,uint256 amount,bytes32 indexed paymentId,bytes32 queryId)",
];

function parseRevenueEvent(receipt, registryAddress) {
  for (const log of receipt.logs) {
    if (getAddress(log.address) !== registryAddress) continue;

    try {
      const parsed = revenueEventInterface.parseLog({
        topics: log.topics,
        data: log.data,
      });

      if (parsed?.name === "RevenuePaymentForCredit") {
        return {
          business: getAddress(parsed.args.business),
          payer: getAddress(parsed.args.payer),
          paymentId: parsed.args.paymentId,
          token: getAddress(parsed.args.token),
          amount: parsed.args.amount,
        };
      }
    } catch {
      // Ignore non-matching logs.
    }
  }

  throw new Error("RevenuePaymentForCredit event not found.");
}

async function main() {
  for (const name of required) env(name);

  const sourceRpc = env("SEPOLIA_RPC_URL");
  const cc3Rpc = env("CREDITCOIN_RPC_URL");
  const builderUrl = env("CREDITCOIN_PROOF_BUILDER_URL");
  const privateKey = env("CREDITCOIN_PRIVATE_KEY");
  const txHash = env("SOURCE_CHAIN_TXN_HASH");

  if (!isHexString(txHash, 32)) {
    throw new Error(`Invalid source tx hash: ${txHash}`);
  }

  const chainKey = Number(process.env.SOURCE_CHAIN_KEY ?? "1");
  const registry = getAddress(env("REGISTRY_ADDRESS"));
  const ascAddress = getAddress(env("REVENUE_ASC_ADDRESS"));
  const managerAddress = getAddress(env("CREDIT_MANAGER_ADDRESS"));

  const sourceProvider = new JsonRpcProvider(sourceRpc);
  const cc3Provider = new JsonRpcProvider(cc3Rpc);
  const wallet = new Wallet(privateKey, cc3Provider);

  console.log("\n=== FlowCred: ingest verified revenue on CC3 ===");
  console.log("Relayer:", wallet.address);
  console.log("Source tx:", txHash);
  console.log("RevenueASC:", ascAddress);
  console.log("CreditManager:", managerAddress);

  console.log("\n[1/6] Reading source transaction...");

  const [sourceTx, sourceReceipt] = await Promise.all([
    sourceProvider.getTransaction(txHash),
    sourceProvider.getTransactionReceipt(txHash),
  ]);

  if (!sourceTx || !sourceReceipt) {
    throw new Error("Source transaction or receipt not found.");
  }
  if (sourceReceipt.status !== 1) {
    throw new Error("Source transaction did not succeed.");
  }
  if (!sourceTx.to || getAddress(sourceTx.to) !== registry) {
    throw new Error(
      `Source tx target mismatch: expected ${registry}, got ${sourceTx.to}`,
    );
  }

  const revenue = parseRevenueEvent(sourceReceipt, registry);

  console.log("✓ Revenue event found");
  console.log("Business:", revenue.business);
  console.log("Payer:", revenue.payer);
  console.log("Amount:", revenue.amount.toString(), "raw USDC");
  console.log("Payment ID:", revenue.paymentId);

  console.log("\n[2/6] Waiting for attestation + building a FRESH proof...");

  // Continuity proofs are time-sensitive operational artifacts; fetch one
  // immediately before submission rather than reusing an old JSON fixture.
  const proofBuilder = new proofProvider.service.ProofBuilder(
    chainKey,
    builderUrl,
    5000,
  );

  await proofBuilder.waitUntilHeightAttested(
    chainKey,
    sourceReceipt.blockNumber,
  );

  const result = await proofBuilder.getProof(txHash);
  if (!result.success || !result.data) {
    throw new Error(`Proof generation failed: ${result.error ?? "unknown"}`);
  }

  const proof = result.data;

  console.log("✓ Fresh proof generated");
  console.log("Header:", proof.headerNumber);
  console.log("Merkle siblings:", proof.merkleProof.siblings.length);
  console.log("Continuity roots:", proof.continuityProof.roots.length);

  console.log("\n[3/6] Verifying deployment wiring...");

  const manager = new Contract(managerAddress, managerAbi, cc3Provider);
  const configuredAsc = getAddress(await manager.asc());

  if (configuredAsc !== ascAddress) {
    throw new Error(
      `Manager ASC mismatch: expected ${ascAddress}, got ${configuredAsc}`,
    );
  }

  console.log("✓ RevenueCreditManager trusts this RevenueASC");

  const before = await manager.verifiedRevenue(revenue.business);
  console.log(
    "Verified revenue before:",
    before.toString(),
    "raw USDC",
  );

  console.log("\n[4/6] Estimating RevenueASC.execute gas...");

  const asc = new Contract(ascAddress, ascAbi, wallet);

  const args = [
    proof.chainKey,
    proof.headerNumber,
    proof.txBytes,
    proof.merkleProof.root,
    proof.merkleProof.siblings,
    proof.continuityProof.lowerEndpointDigest,
    proof.continuityProof.roots,
  ];

  let estimated;
  try {
    estimated = await asc.execute.estimateGas(...args);
  } catch (error) {
    console.error(
      "Gas estimation reverted. This usually means one of the ASC validations rejected the proof/event.",
    );
    throw error;
  }

  const buffered = (estimated * 140n) / 100n;
  const gasLimit = buffered > 900_000n ? buffered : 900_000n;

  console.log("Estimated gas:", estimated.toString());
  console.log("Gas limit:", gasLimit.toString());

  console.log("\n[5/6] Submitting proof to RevenueASC...");

  const response = await asc.execute(...args, { gasLimit });
  console.log("CC3 transaction:", response.hash);

  const receipt = await response.wait();

  if (!receipt || receipt.status !== 1) {
    throw new Error("RevenueASC transaction failed.");
  }

  console.log("✓ RevenueASC transaction mined in block", receipt.blockNumber);

  let consumedEvent = null;
  for (const log of receipt.logs) {
    try {
      const parsed = asc.interface.parseLog({
        topics: log.topics,
        data: log.data,
      });
      if (parsed?.name === "RevenueProofConsumed") {
        consumedEvent = parsed;
        break;
      }
    } catch {
      // Ignore other logs, including BlockProver and manager events.
    }
  }

  if (!consumedEvent) {
    throw new Error("RevenueProofConsumed event missing from successful tx.");
  }

  console.log("Query ID:", consumedEvent.args.queryId);

  console.log("\n[6/6] Reading Creditcoin state...");

  const after = await manager.verifiedRevenue(revenue.business);
  const expected = before + revenue.amount;

  console.log("Verified revenue after:", after.toString(), "raw USDC");

  if (after !== expected) {
    throw new Error(
      `State mismatch: expected ${expected}, got ${after}`,
    );
  }

  console.log("\n==============================================");
  console.log("✅ FIRST FLOWCRED REVENUE INGEST COMPLETE");
  console.log("==============================================");
  console.log(
    `${revenue.amount} raw USDC of Sepolia revenue is now recorded`,
  );
  console.log(
    `as cryptographically verified revenue for ${revenue.business}`,
  );
  console.log("inside RevenueCreditManager on Creditcoin CC3 Testnet.");
  console.log("CC3 tx:", response.hash);
}

main().catch((error) => {
  console.error("\n❌ FlowCred CC3 ingest failed");
  console.error(error instanceof Error ? error.stack ?? error.message : error);
  process.exit(1);
});
