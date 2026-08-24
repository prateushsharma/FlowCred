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
DEPLOY_KEY="${CREDITCOIN_PRIVATE_KEY:-${PRIVATE_KEY:-}}"

: "${DEPLOY_KEY:?Set CREDITCOIN_PRIVATE_KEY or PRIVATE_KEY in .env}"
: "${REGISTRY_ADDRESS:?Missing REGISTRY_ADDRESS in .env}"

SOURCE_USDC="0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238"
EXPECTED_CHAIN_ID="102031"
DECODER_SOURCE="worker/node_modules/@gluwa/usc-contracts/contracts/decoding/EvmV1Decoder.sol"
DECODER_TARGET="${DECODER_SOURCE}:EvmV1Decoder"

chain_id="$(cast chain-id --rpc-url "$CREDITCOIN_RPC_URL")"
if [[ "$chain_id" != "$EXPECTED_CHAIN_ID" ]]; then
  echo "Refusing deployment: expected CC3 Testnet chainId $EXPECTED_CHAIN_ID, got $chain_id"
  exit 1
fi

DEPLOYER="$(cast wallet address --private-key "$DEPLOY_KEY")"
BALANCE="$(cast balance "$DEPLOYER" --rpc-url "$CREDITCOIN_RPC_URL")"

echo
echo "=== FlowCred CC3 deployment ==="
echo "RPC:      $CREDITCOIN_RPC_URL"
echo "Chain ID: $chain_id"
echo "Deployer: $DEPLOYER"
echo "Balance:  $BALANCE wei tCTC"
echo

if [[ "$BALANCE" == "0" ]]; then
  echo "The deployer has no tCTC."
  echo "Fund $DEPLOYER from the Creditcoin CC3 Testnet faucet, then rerun."
  exit 1
fi

extract_address() {
  sed -n 's/.*Deployed to:[[:space:]]*\(0x[0-9a-fA-F]\{40\}\).*/\1/p' | tail -n1
}

deploy_and_capture() {
  local label="$1"
  shift

  local out
  echo >&2
  echo "[FlowCred] Deploying $label..." >&2

  # Do not use `forge script` for this sequence. Creditcoin's official
  # custom-contract tutorial uses forge create for the decoder + linked ASC.
  out="$("$@" 2>&1)"
  printf '%s\n' "$out" >&2

  local addr
  addr="$(printf '%s\n' "$out" | extract_address)"
  [[ -n "$addr" ]] || {
    echo "Could not parse deployed address for $label." >&2
    return 1
  }

  printf '%s' "$addr"
}

DECODER_ADDRESS="$(deploy_and_capture \
  "EvmV1Decoder" \
  forge create \
    --broadcast \
    --rpc-url "$CREDITCOIN_RPC_URL" \
    --private-key "$DEPLOY_KEY" \
    "$DECODER_TARGET")"

MANAGER_ADDRESS="$(deploy_and_capture \
  "RevenueCreditManager" \
  forge create \
    --broadcast \
    --rpc-url "$CREDITCOIN_RPC_URL" \
    --private-key "$DEPLOY_KEY" \
    src/creditcoin/RevenueCreditManager.sol:RevenueCreditManager \
    --constructor-args "$DEPLOYER")"

ASC_ADDRESS="$(deploy_and_capture \
  "RevenueASC" \
  forge create \
    --broadcast \
    --rpc-url "$CREDITCOIN_RPC_URL" \
    --private-key "$DEPLOY_KEY" \
    --libraries "${DECODER_SOURCE}:EvmV1Decoder:${DECODER_ADDRESS}" \
    src/creditcoin/RevenueASC.sol:RevenueASC \
    --constructor-args \
      "$REGISTRY_ADDRESS" \
      "$SOURCE_USDC" \
      "$MANAGER_ADDRESS")"

echo
echo "[FlowCred] Authorizing RevenueASC in RevenueCreditManager..."

SET_ASC_TX="$(
  cast send \
    --rpc-url "$CREDITCOIN_RPC_URL" \
    --private-key "$DEPLOY_KEY" \
    "$MANAGER_ADDRESS" \
    "setASC(address)" \
    "$ASC_ADDRESS" \
    --json \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["transactionHash"])'
)"

AUTHORIZED_ASC="$(
  cast call \
    --rpc-url "$CREDITCOIN_RPC_URL" \
    "$MANAGER_ADDRESS" \
    "asc()(address)"
)"

if [[ "${AUTHORIZED_ASC,,}" != "${ASC_ADDRESS,,}" ]]; then
  echo "ASC authorization verification failed."
  echo "Expected: $ASC_ADDRESS"
  echo "On-chain: $AUTHORIZED_ASC"
  exit 1
fi

cat > deployments/cc3-testnet.json <<JSON
{
  "network": "Creditcoin CC3 Testnet",
  "chainId": 102031,
  "rpc": "$CREDITCOIN_RPC_URL",
  "deployer": "$DEPLOYER",
  "source": {
    "network": "Ethereum Sepolia",
    "chainKey": 1,
    "revenueRegistry": "$REGISTRY_ADDRESS",
    "usdc": "$SOURCE_USDC"
  },
  "creditcoin": {
    "evmV1Decoder": "$DECODER_ADDRESS",
    "revenueCreditManager": "$MANAGER_ADDRESS",
    "revenueASC": "$ASC_ADDRESS"
  },
  "transactions": {
    "authorizeASC": "$SET_ASC_TX"
  }
}
JSON

# Update local .env without exposing the key.
python3 - "$DECODER_ADDRESS" "$MANAGER_ADDRESS" "$ASC_ADDRESS" <<'PY'
from pathlib import Path
import sys

decoder, manager, asc = sys.argv[1:]
p = Path(".env")
lines = p.read_text().splitlines()

updates = {
    "CREDITCOIN_DECODER_ADDRESS": decoder,
    "CREDIT_MANAGER_ADDRESS": manager,
    "REVENUE_ASC_ADDRESS": asc,
}

seen = set()
out = []
for line in lines:
    if "=" in line and not line.lstrip().startswith("#"):
        key = line.split("=", 1)[0].strip()
        if key in updates:
            out.append(f"{key}={updates[key]}")
            seen.add(key)
            continue
    out.append(line)

if out and out[-1] != "":
    out.append("")

for key, value in updates.items():
    if key not in seen:
        out.append(f"{key}={value}")

p.write_text("\n".join(out) + "\n")
PY

echo
echo "=============================================="
echo "✅ FLOWCRED CONTRACTS LIVE ON CC3 TESTNET"
echo "=============================================="
echo "EvmV1Decoder:        $DECODER_ADDRESS"
echo "RevenueCreditManager:$MANAGER_ADDRESS"
echo "RevenueASC:           $ASC_ADDRESS"
echo "ASC authorization tx: $SET_ASC_TX"
echo
echo "Saved: deployments/cc3-testnet.json"
echo
echo "NOTE: ASC configuration is intentionally NOT permanently locked yet."
echo "We will lock it after the first real proof is successfully ingested."
