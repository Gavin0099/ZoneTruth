#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ $# -lt 1 ]]; then
  echo "usage: bash scripts/write_claim_enforcement_receipt.sh <session_id> [recorded_at]"
  exit 2
fi

SESSION_ID="$1"
RECORDED_AT="${2:-}"

export PYTHONPATH="$ROOT_DIR${PYTHONPATH:+:$PYTHONPATH}"

writer_cmd=(
  python3 -m governance_tools.claim_enforcement_receipt_writer
  --repo-root "$ROOT_DIR"
  --session-id "$SESSION_ID"
)

if [[ -n "$RECORDED_AT" ]]; then
  writer_cmd+=(--recorded-at "$RECORDED_AT")
fi

echo "[claim-enforcement] WRITE session_id=${SESSION_ID}"
"${writer_cmd[@]}"

echo "[claim-enforcement] VALIDATE"
bash scripts/validate_claim_enforcement_receipts.sh
