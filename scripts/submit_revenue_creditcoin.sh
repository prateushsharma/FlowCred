#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$ROOT" ]] || { echo "Run inside FlowCred repository."; exit 1; }
cd "$ROOT"

[[ -f .env ]] || { echo "Missing .env"; exit 1; }

set +u
source .env
set -u

TX_HASH="${1:-0xe3273f418e1bea1f14c838608f4286e121a6a5059e627666041cfa3efef937d9}"

KEY="${CREDITCOIN_PRIVATE_KEY:-${PRIVATE_KEY:-}}"

: "${SEPOLIA_RPC_URL:?Missing SEPOLIA_RPC_URL}"
: "${REGISTRY_ADDRESS:?Missing REGISTRY_ADDRESS}"
: "${REVENUE_ASC_ADDRESS:?Run ./scripts/deploy_creditcoin.sh first}"
: "${CREDIT_MANAGER_ADDRESS:?Run ./scripts/deploy_creditcoin.sh first}"
: "${KEY:?Set CREDITCOIN_PRIVATE_KEY or PRIVATE_KEY}"

export SEPOLIA_RPC_URL
export REGISTRY_ADDRESS
export REVENUE_ASC_ADDRESS
export CREDIT_MANAGER_ADDRESS
export CREDITCOIN_PRIVATE_KEY="$KEY"

export CREDITCOIN_RPC_URL="${CREDITCOIN_RPC_URL:-https://rpc.cc3-testnet.creditcoin.network}"
export CREDITCOIN_PROOF_BUILDER_URL="${CREDITCOIN_PROOF_BUILDER_URL:-https://prover.cc3-testnet.creditcoin.network/}"
export SOURCE_CHAIN_KEY="${SOURCE_CHAIN_KEY:-1}"
export SOURCE_CHAIN_TXN_HASH="$TX_HASH"

cd worker
node submit-revenue.mjs
