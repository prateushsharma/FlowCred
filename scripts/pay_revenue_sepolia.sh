#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

[[ -f .env ]] || { echo "Missing .env. Copy .env.example to .env and fill it."; exit 1; }
set -a
source .env
set +a

: "${SEPOLIA_RPC_URL:?Missing SEPOLIA_RPC_URL in .env}"
: "${PRIVATE_KEY:?Missing PRIVATE_KEY in .env}"
: "${REGISTRY_ADDRESS:?Missing REGISTRY_ADDRESS in .env}"
: "${BUSINESS_ADDRESS:?Missing BUSINESS_ADDRESS in .env}"
: "${PAYMENT_AMOUNT:?Missing PAYMENT_AMOUNT in .env}"
: "${PAYMENT_REF:?Missing PAYMENT_REF in .env}"

forge script script/PayRevenue.s.sol:PayRevenue \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --broadcast \
  -vv

BROADCAST="broadcast/PayRevenue.s.sol/11155111/run-latest.json"
[[ -f "$BROADCAST" ]] || { echo "Broadcast file not found: $BROADCAST"; exit 1; }

python3 - "$BROADCAST" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
txs = data.get("transactions", [])
if len(txs) < 2:
    raise SystemExit("Expected approve + payBusiness transactions.")

approve = txs[-2]
payment = txs[-1]

print("\n=== FlowCred revenue payment ===")
print("approve tx:", approve.get("hash"))
print("REVENUE TX FOR ATTESTCOIN:", payment.get("hash"))
print("\nKeep the second hash. Patch 003 will feed it to @gluwa/usc-sdk.")
PY
