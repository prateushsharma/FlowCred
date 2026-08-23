import {
  blockProver,
  chainInfo,
  proofProvider,
} from "@gluwa/usc-sdk";
import {
  Interface,
  JsonRpcProvider,
  getAddress,
  isHexString,
} from "ethers";
import fs from "node:fs/promises";
import path from "node:path";

const REQUIRED = [
  "SEPOLIA_RPC_URL",
  "CREDITCOIN_RPC_URL",
  "CREDITCOIN_PROOF_BUILDER_URL",
  "SOURCE_CHAIN_TXN_HASH",
  "REGISTRY_ADDRESS",
];

function env(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function bigintReplacer(_key, value) {
  return typeof value === "bigint" ? value.toString() : value;
}

function short(value) {
  if (typeof value !== "string" || value.length < 18) return value;
  return `${value.slice(0, 10)}…${value.slice(-8)}`;
}

async function main() {
  for (const name of REQUIRED) env(name);

  const sourceRpc = env("SEPOLIA_RPC_URL");
  const creditcoinRpc = env("CREDITCOIN_RPC_URL");
  const proofBuilderUrl = env("CREDITCOIN_PROOF_BUILDER_URL");
  const txHash = env("SOURCE_CHAIN_TXN_HASH");
  const registryAddress = getAddress(env("REGISTRY_ADDRESS"));
  const chainKey = Number(process.env.SOURCE_CHAIN_KEY ?? "1");

  if (!Number.isSafeInteger(chainKey) || chainKey <= 0) {
    throw new Error(`Invalid SOURCE_CHAIN_KEY: ${process.env.SOURCE_CHAIN_KEY}`);
  }
  if (!isHexString(txHash, 32)) {
    throw new Error(`Invalid transaction hash: ${txHash}`);
  }

  const sourceProvider = new JsonRpcProvider(sourceRpc);
  const creditcoinProvider = new JsonRpcProvider(creditcoinRpc);

  console.log("\n=== FlowCred Attestcoin Proof Flow ===");
  console.log("Source chain: Ethereum Sepolia");
  console.log("Attestcoin chainKey:", chainKey);
  console.log("Revenue tx:", txHash);
  console.log("RevenueRegistry:", registryAddress);

  // ---------------------------------------------------------------------------
  // 1. Validate the source-chain transaction before asking Attestcoin to prove it.
  // ---------------------------------------------------------------------------
  console.log("\n[1/5] Reading Sepolia transaction + receipt...");

  const [tx, receipt] = await Promise.all([
    sourceProvider.getTransaction(txHash),
    sourceProvider.getTransactionReceipt(txHash),
  ]);

  if (!tx) throw new Error("Source transaction was not found.");
  if (!receipt) throw new Error("Source transaction receipt was not found.");
  if (receipt.status !== 1) {
    throw new Error(
      `Revenue transaction failed on Sepolia (receipt status=${receipt.status}).`,
    );
  }

  if (!tx.to || getAddress(tx.to) !== registryAddress) {
    throw new Error(
      `Transaction target mismatch. Expected RevenueRegistry ${registryAddress}, got ${tx.to}`,
    );
  }

  console.log("✓ tx exists");
  console.log("✓ receipt status = SUCCESS");
  console.log("Block:", receipt.blockNumber);
  console.log("Tx target:", tx.to);

  // ---------------------------------------------------------------------------
  // 2. Confirm our canonical RevenuePaymentForCredit event exists.
  //    This is a local sanity check. The future RevenueASC will enforce these
  //    validations on Creditcoin after proof verification.
  // ---------------------------------------------------------------------------
  console.log("\n[2/5] Decoding RevenuePaymentForCredit event...");

  const revenueInterface = new Interface([
    "event RevenuePaymentForCredit(address indexed business,address indexed payer,bytes32 indexed paymentId,address token,uint256 amount)",
  ]);

  let revenueEvent = null;

  for (const log of receipt.logs) {
    if (getAddress(log.address) !== registryAddress) continue;

    try {
      const parsed = revenueInterface.parseLog({
        topics: log.topics,
        data: log.data,
      });

      if (parsed?.name === "RevenuePaymentForCredit") {
        revenueEvent = parsed;
        break;
      }
    } catch {
      // Not our event.
    }
  }

  if (!revenueEvent) {
    throw new Error(
      "RevenuePaymentForCredit event not found in the proven transaction receipt.",
    );
  }

  const eventData = {
    business: revenueEvent.args.business,
    payer: revenueEvent.args.payer,
    paymentId: revenueEvent.args.paymentId,
    token: revenueEvent.args.token,
    amount: revenueEvent.args.amount,
  };

  console.log("✓ RevenuePaymentForCredit found");
  console.log("Business:", eventData.business);
  console.log("Payer:", eventData.payer);
  console.log("Token:", eventData.token);
  console.log("Amount (raw USDC):", eventData.amount.toString());
  console.log("Payment ID:", eventData.paymentId);

  const expectedBusiness = process.env.BUSINESS_ADDRESS;
  if (
    expectedBusiness &&
    expectedBusiness !== "0x0000000000000000000000000000000000000000" &&
    getAddress(expectedBusiness) !== getAddress(eventData.business)
  ) {
    throw new Error(
      `Business mismatch. Expected ${expectedBusiness}, event contains ${eventData.business}`,
    );
  }

  const expectedAmount = process.env.PAYMENT_AMOUNT;
  if (expectedAmount && BigInt(expectedAmount) !== eventData.amount) {
    throw new Error(
      `Amount mismatch. Expected ${expectedAmount}, event contains ${eventData.amount}`,
    );
  }

  // ---------------------------------------------------------------------------
  // 3. Ask Creditcoin which source chains are supported and wait for the
  //    source block to be attested.
  // ---------------------------------------------------------------------------
  console.log("\n[3/5] Waiting for Creditcoin attestation...");

  const chainInfoProvider =
    new chainInfo.PrecompileChainInfoProvider(creditcoinProvider);

  try {
    const supported = await chainInfoProvider.getSupportedChains();
    const selected = supported.find(
      (entry) => Number(entry.chainKey) === chainKey,
    );

    if (!selected) {
      throw new Error(
        `chainKey ${chainKey} is not supported by this Creditcoin environment.`,
      );
    }

    console.log(
      `✓ chainKey ${chainKey}: ${selected.chainName ?? "supported source chain"} (chainId ${selected.chainId ?? "unknown"})`,
    );
  } catch (error) {
    // getSupportedChains is diagnostic; waiting below is authoritative.
    console.warn(
      "Could not print supported-chain metadata; continuing to attestation check:",
      error instanceof Error ? error.message : String(error),
    );
  }

  console.log(
    `Waiting until Sepolia block ${receipt.blockNumber} is attested on Creditcoin...`,
  );

  await chainInfoProvider.waitUntilHeightAttested(
    chainKey,
    receipt.blockNumber,
  );

  console.log("✓ block is attested");

  // ---------------------------------------------------------------------------
  // 4. Fetch Merkle + continuity proofs from the official Proof Builder.
  // ---------------------------------------------------------------------------
  console.log("\n[4/5] Generating Attestcoin proof...");

  const proofBuilder = new proofProvider.service.ProofBuilder(
    chainKey,
    proofBuilderUrl,
  );

  const result = await proofBuilder.getProof(txHash);

  if (!result.success || !result.data) {
    throw new Error(`Proof generation failed: ${result.error ?? "unknown error"}`);
  }

  const proof = result.data;

  console.log("✓ proof generated");
  console.log("Proof chainKey:", proof.chainKey);
  console.log("Header number:", proof.headerNumber);
  console.log("txBytes:", short(proof.txBytes));
  console.log(
    "Merkle siblings:",
    Array.isArray(proof.merkleProof?.siblings)
      ? proof.merkleProof.siblings.length
      : "unknown",
  );
  console.log(
    "Continuity roots:",
    Array.isArray(proof.continuityProof?.roots)
      ? proof.continuityProof.roots.length
      : "unknown",
  );

  // Save only as a local ignored artifact for inspection/debugging.
  const artifactsDir = path.resolve(".artifacts");
  await fs.mkdir(artifactsDir, { recursive: true });
  const proofPath = path.join(
    artifactsDir,
    `revenue-proof-${txHash.slice(2, 12)}.json`,
  );
  await fs.writeFile(
    proofPath,
    `${JSON.stringify(proof, bigintReplacer, 2)}\n`,
    "utf8",
  );

  console.log("Saved proof artifact:", proofPath);

  // ---------------------------------------------------------------------------
  // 5. Verify the proof through Creditcoin's native Block Prover precompile.
  // ---------------------------------------------------------------------------
  console.log("\n[5/5] Verifying proof on Creditcoin...");

  const prover = new blockProver.PrecompileBlockProver(creditcoinProvider);

  const verified = await prover.verifySingle(
    proof.chainKey,
    proof.headerNumber,
    proof.txBytes,
    proof.merkleProof,
    proof.continuityProof,
  );

  if (!verified) {
    throw new Error("Creditcoin Block Prover returned FAILED.");
  }

  console.log("\n==============================================");
  console.log("✅ ATTESTCOIN PROOF VERIFIED");
  console.log("==============================================");
  console.log(`Sepolia tx ${txHash}`);
  console.log("is cryptographically verifiable on Creditcoin.");
  console.log("");
  console.log("Next milestone:");
  console.log(
    "RevenueASC.sol will verify this proof, validate the receipt/event on-chain,",
  );
  console.log(
    "then call FlowCred's Creditcoin-side business logic with the verified revenue.",
  );
}

main().catch((error) => {
  console.error("\n❌ FlowCred proof flow failed");
  console.error(error instanceof Error ? error.stack ?? error.message : error);
  process.exit(1);
});
