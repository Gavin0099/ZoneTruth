#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENFORCE="${CLEAN_PILOT_ADMISSIBILITY_ENFORCE:-1}"
SUMMARY_OUT="artifacts/runtime/boundary-telemetry/clean_pilot_admissibility_smoke.json"
mkdir -p "$(dirname "$SUMMARY_OUT")"

json_output="$(python3 governance_tools/clean_pilot_admissibility.py \
  --repo . \
  --policy governance/fleet/cleaning_admissibility_policy.yaml \
  --format json)"

printf '%s\n' "$json_output" > "$SUMMARY_OUT"

admissible="$(python3 - <<'PY' "$SUMMARY_OUT"
import json, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    payload = json.load(fh)
print("true" if payload.get("clean_pilot_admissible", False) else "false")
PY
)"

if [[ "$admissible" != "true" ]]; then
  guard="not_admissible"
  echo "clean_pilot_admissibility_guard: ${guard}"
  echo "clean_pilot_admissibility_summary_file: ${SUMMARY_OUT}"
  if [[ "$ENFORCE" == "1" ]]; then
    echo "clean_pilot_admissibility_enforce: enabled"
    exit 1
  fi
  echo "clean_pilot_admissibility_enforce: disabled"
  exit 0
fi

echo "clean_pilot_admissibility_guard: passed"
echo "clean_pilot_admissibility_summary_file: ${SUMMARY_OUT}"
exit 0
