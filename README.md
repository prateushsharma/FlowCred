# FlowCred

**Cross-chain cash-flow credit powered by Attestcoin.**

FlowCred lets businesses borrow on Creditcoin against revenue that is cryptographically verified
from another chain. The first source chain is Ethereum Sepolia.

## Patch 001: source revenue registry

This slice implements:

- `RevenueRegistry.sol` — minimal payment contract wired to **official Circle USDC on Sepolia**.
- `MockUSDC.sol` — local unit-test fixture only; it is **not deployed to Sepolia**.
- Foundry tests, including event verification and basic invalid-payment cases.
- Sepolia deployment and real testnet-USDC payment scripts.

## Setup

```bash
cp .env.example .env
# Edit PRIVATE_KEY and SEPOLIA_RPC_URL.

forge build
forge test -vvv
```

## Deploy to Sepolia

```bash
source .env
forge script script/DeploySource.s.sol:DeploySource \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --broadcast
```

Copy the printed `RevenueRegistry` address into `.env`.

Acquire Circle testnet USDC on Sepolia (for example through a faucet or a Sepolia DEX swap), then set `BUSINESS_ADDRESS` to a different Sepolia address.

## Emit one revenue event

```bash
source .env
forge script script/PayRevenue.s.sol:PayRevenue \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --broadcast -vvvv
```

From the broadcast output, copy the transaction hash and inspect it:

```bash
cast receipt <TX_HASH> --rpc-url "$SEPOLIA_RPC_URL"
```

You should see the `RevenuePaymentForCredit` log. That exact transaction hash becomes the input to
Patch 002, where `@gluwa/usc-sdk` will wait for attestation, build the proof, and verify it against
Creditcoin CC3 Testnet.

## Canonical event

```solidity
event RevenuePaymentForCredit(
    address indexed business,
    address indexed payer,
    bytes32 indexed paymentId,
    address token,
    uint256 amount
);
```

We intentionally do **not** use the generic ERC-20 `Transfer` event as FlowCred's cross-chain
trigger.
