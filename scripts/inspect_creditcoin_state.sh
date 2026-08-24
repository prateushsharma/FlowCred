#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$ROOT" ]] || { echo "Run inside FlowCred repository."; exit 1; }
cd "$ROOT"

[[ -f .env ]] || { echo "Missing .env"; exit 1; }

set +u
source .env
set -u

CREDITCOIN_RPC_URL="${CREDITCOIN_RPC_URL:-https://rpc.cc3-testnet.creditcoin.network}"

: "${CREDIT_MANAGER_ADDRESS:?Missing CREDIT_MANAGER_ADDRESS}"
: "${BUSINESS_ADDRESS:?Missing BUSINESS_ADDRESS}"

RAW="$(
  cast call \
    --rpc-url "$CREDITCOIN_RPC_URL" \
    "$CREDIT_MANAGER_ADDRESS" \
    "verifiedRevenue(address)(uint256)" \
    "$BUSINESS_ADDRESS"
)"

echo "Business:         $BUSINESS_ADDRESS"
echo "Verified revenue: $RAW raw USDC"
echo
echo "USDC has 6 decimals: 1,000,000 raw units = 1 USDC."
