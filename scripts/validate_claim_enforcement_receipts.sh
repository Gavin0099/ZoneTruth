#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export PYTHONPATH="$ROOT_DIR${PYTHONPATH:+:$PYTHONPATH}"

report_json="$(mktemp)"
cleanup() {
  rm -f "$report_json"
}
trap cleanup EXIT

if ! python3 -m governance_tools.claim_enforcement_receipt_validator --format json >"$report_json"; then
  echo "[claim-enforcement] FAIL validator crashed"
  exit 1
fi

python3 - "$report_json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))

file_present = report.get("file_present", False)
parse_errors = report.get("parse_errors", [])
invalid_rows = report.get("invalid_rows", [])
unreceipted = report.get("unreceipted_packets", [])
total_rows = report.get("total_rows", 0)
valid_rows = report.get("valid_rows", 0)
raw_roots = report.get("raw_packet_roots", [])

ok = file_present and not parse_errors and not invalid_rows and not unreceipted
status = "PASS" if ok else "FAIL"

print(f"[claim-enforcement] {status}")
print(f"  receipts file: {'present' if file_present else 'missing'}")
print(f"  raw roots: {len(raw_roots)}")
print(f"  total rows: {total_rows}")
print(f"  valid rows: {valid_rows}")
print(f"  parse errors: {len(parse_errors)}")
print(f"  invalid rows: {len(invalid_rows)}")
print(f"  unreceipted packets: {len(unreceipted)}")

if parse_errors:
    print("  parse error details:")
    for item in parse_errors:
        print(f"    - line {item['line_number']}: {item['error']}")

if invalid_rows:
    print("  invalid row details:")
    for row in invalid_rows:
        print(f"    - session={row['session_id']}")
        if row.get("missing_fields"):
            print(f"      missing_fields={row['missing_fields']}")
        if row.get("policy_deviations"):
            print(f"      policy_deviations={row['policy_deviations']}")
        if row.get("presence_mismatch"):
            print(
                "      presence_mismatch="
                f"receipt={row.get('receipt_claims_present')} disk={row.get('raw_packet_present')}"
            )

if unreceipted:
    print("  unreceipted packet sessions:")
    for sid in unreceipted:
        print(f"    - {sid}")

sys.exit(0 if ok else 1)
PY
