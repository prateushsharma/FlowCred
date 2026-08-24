#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$ROOT" ]] || { echo "Run this inside the FlowCred git repository."; exit 1; }
cd "$ROOT"

[[ -f .env ]] || { echo "Missing .env in $ROOT"; exit 1; }

# Source local configuration, but deliberately export only what this read-only
# proof worker needs. PRIVATE_KEY is not exported to the Node process.
set +u
source .env
set -u

TX_HASH="${1:-0x52608de0beb87e16d67e009fbe943b5d9564b3610e68ee15b4c90d99d0d05042}"

: "${SEPOLIA_RPC_URL:?Missing SEPOLIA_RPC_URL in .env}"
: "${REGISTRY_ADDRESS:?Missing REGISTRY_ADDRESS in .env}"

export SEPOLIA_RPC_URL
export REGISTRY_ADDRESS
export BUSINESS_ADDRESS="${BUSINESS_ADDRESS:-}"
export PAYMENT_AMOUNT="${PAYMENT_AMOUNT:-}"

export CREDITCOIN_RPC_URL="${CREDITCOIN_RPC_URL:-https://rpc.cc3-testnet.creditcoin.network}"
export CREDITCOIN_PROOF_BUILDER_URL="${CREDITCOIN_PROOF_BUILDER_URL:-https://prover.cc3-testnet.creditcoin.network/}"
export SOURCE_CHAIN_KEY="${SOURCE_CHAIN_KEY:-1}"
export SOURCE_CHAIN_TXN_HASH="$TX_HASH"

echo
echo "[FlowCred] Revenue transaction: $SOURCE_CHAIN_TXN_HASH"
echo "[FlowCred] Creditcoin RPC: $CREDITCOIN_RPC_URL"
echo "[FlowCred] Proof Builder: $CREDITCOIN_PROOF_BUILDER_URL"
echo "[FlowCred] Source chainKey: $SOURCE_CHAIN_KEY"
echo

cd worker
npm run prove
