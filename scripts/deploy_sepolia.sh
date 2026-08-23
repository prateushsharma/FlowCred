#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

[[ -f .env ]] || { echo "Missing .env. Copy .env.example to .env and fill it."; exit 1; }
set -a
source .env
set +a

: "${SEPOLIA_RPC_URL:?Missing SEPOLIA_RPC_URL in .env}"
: "${PRIVATE_KEY:?Missing PRIVATE_KEY in .env}"

forge script script/DeploySource.s.sol:DeploySource \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --broadcast \
  -vv

BROADCAST="broadcast/DeploySource.s.sol/11155111/run-latest.json"
[[ -f "$BROADCAST" ]] || { echo "Broadcast file not found: $BROADCAST"; exit 1; }

python3 - "$BROADCAST" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
txs = data.get("transactions", [])
if not txs:
    raise SystemExit("No deployment transaction found.")
tx = txs[-1]
print("\n=== FlowCred Sepolia deployment ===")
print("txHash:", tx.get("hash"))
print("RevenueRegistry:", tx.get("contractAddress"))
print("Save REGISTRY_ADDRESS in your .env.")
PY
