#!/usr/bin/env bash
# P1n Migration Gate – full condition verification.
# Usage: bash scripts/run_migration_gate.sh
# Output: artifacts/migration/migration_gate_report.json

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

REPORT_PATH="artifacts/migration/migration_gate_report.json"
mkdir -p artifacts/migration

echo "=== P1n Migration Gate Check ==="

# ── Check 1: primitive_snapshots_stable ──────────────────────────────────────
c1_status="pass"; c1_detail="null"
echo "  [1] primitive_snapshots_stable..."
if ! swift test --filter PrimitiveBuilder 2>/dev/null; then
  c1_status="fail"; c1_detail='"swift test PrimitiveBuilder failed"'
fi

# ── Check 2: observation_snapshots_stable ────────────────────────────────────
c2_status="pass"; c2_detail="null"
echo "  [2] observation_snapshots_stable..."
for filter in Zone2Observation VO2Observation StrengthObservation ActivityObservation; do
  if ! swift test --filter "$filter" 2>/dev/null; then
    c2_status="fail"; c2_detail="\"swift test ${filter} failed\""
    break
  fi
done

# ── Check 3: evaluation_snapshot_stable_or_annotated ─────────────────────────
c3_status="pass"; c3_detail="null"
echo "  [3] evaluation_snapshot_stable_or_annotated..."
if ! swift test --filter testWorkoutEvaluationSnapshotFixture 2>/dev/null; then
  # Snapshot test failed → require annotation
  latest_annotation="$(ls -1t artifacts/semantic_changes/SEM-*.json 2>/dev/null | grep -v TEMPLATE | head -n 1 || true)"
  if [[ -z "$latest_annotation" ]]; then
    c3_status="fail"
    c3_detail='"snapshot changed with no SEM annotation"'
  else
    c3_status="pass"
    c3_detail="\"annotated: $(basename "$latest_annotation")\""
  fi
fi

# ── Checks 4+5: in-process (shadow policy + fallback path) ───────────────────
c45_status="pass"; c45_detail="null"
echo "  [4+5] shadow_policy and fallback_path checks..."
if ! swift test --filter testMigrationGateFallbackChecksAllPass 2>/dev/null; then
  c45_status="fail"
  c45_detail='"testMigrationGateFallbackChecksAllPass failed — see swift test output"'
fi

echo ""

# ── Generate report ──────────────────────────────────────────────────────────
python3 - \
  "$c1_status" "$c1_detail" \
  "$c2_status" "$c2_detail" \
  "$c3_status" "$c3_detail" \
  "$c45_status" "$c45_detail" \
  "$REPORT_PATH" <<'PY'
import json, sys, datetime, os

args = sys.argv[1:]
(c1s, c1d, c2s, c2d, c3s, c3d, c45s, c45d, out_path) = args

def make_check(id_, status, detail_json):
    detail = json.loads(detail_json) if detail_json != "null" else None
    return {"id": id_, "status": status, "detail": detail}

checks = [
    make_check("primitive_snapshots_stable",              c1s,  c1d),
    make_check("observation_snapshots_stable",            c2s,  c2d),
    make_check("evaluation_snapshot_stable_or_annotated", c3s,  c3d),
    make_check("shadow_policy_and_fallback_path_checks",  c45s, c45d),
]

blocking = [c["id"] for c in checks if c["status"] == "fail"]
admissible = len(blocking) == 0

report = {
    "gate_version": "P1n-v1",
    "generated_at": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    "policy_primary_admissible": False,
    "policy_primary_admissible_for_discussion": admissible,
    "checks": checks,
    "blocking_reasons": blocking,
}

os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(report, f, indent=2, sort_keys=True)

print(f"policy_primary_admissible_for_discussion: {admissible}")
print("")
for c in checks:
    icon = "✓" if c["status"] == "pass" else "✗"
    line = f"  {icon} {c['id']}: {c['status']}"
    if c["detail"]:
        line += f" ({c['detail']})"
    print(line)

if blocking:
    print("")
    print(f"BLOCKING: {', '.join(blocking)}")
    sys.exit(1)
PY
