#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FIXTURE_PATH="Tests/ZoneTruthAppTests/Fixtures/workout_evaluation_snapshot.json"

semantic_guard="passed"
snapshot_fixture="matched"
working_tree_clean="yes"
ui_smoke="skipped/manual-required"
dual_run_review="not-found"
annotation_gate="not-required"

if ! swift test; then
  semantic_guard="failed"
  echo "semantic_guard: ${semantic_guard}"
  echo "snapshot_fixture: ${snapshot_fixture}"
  echo "working_tree_clean: ${working_tree_clean}"
  echo "ui_smoke: ${ui_smoke}"
  exit 1
fi

if ! swift test --filter PrimitiveBuilder; then
  semantic_guard="failed"
  echo "semantic_guard: ${semantic_guard}"
  echo "snapshot_fixture: ${snapshot_fixture}"
  echo "working_tree_clean: ${working_tree_clean}"
  echo "ui_smoke: ${ui_smoke}"
  exit 1
fi

if ! swift test --filter Zone2Observation; then
  semantic_guard="failed"
  echo "semantic_guard: ${semantic_guard}"
  echo "snapshot_fixture: ${snapshot_fixture}"
  echo "working_tree_clean: ${working_tree_clean}"
  echo "ui_smoke: ${ui_smoke}"
  exit 1
fi

if ! swift test --filter VO2Observation; then
  semantic_guard="failed"
  echo "semantic_guard: ${semantic_guard}"
  echo "snapshot_fixture: ${snapshot_fixture}"
  echo "working_tree_clean: ${working_tree_clean}"
  echo "ui_smoke: ${ui_smoke}"
  exit 1
fi

if ! swift test --filter StrengthObservation; then
  semantic_guard="failed"
  echo "semantic_guard: ${semantic_guard}"
  echo "snapshot_fixture: ${snapshot_fixture}"
  echo "working_tree_clean: ${working_tree_clean}"
  echo "ui_smoke: ${ui_smoke}"
  exit 1
fi

if ! swift test --filter ActivityObservation; then
  semantic_guard="failed"
  echo "semantic_guard: ${semantic_guard}"
  echo "snapshot_fixture: ${snapshot_fixture}"
  echo "working_tree_clean: ${working_tree_clean}"
  echo "ui_smoke: ${ui_smoke}"
  exit 1
fi

if ! swift test --filter testWorkoutEvaluationSnapshotFixture; then
  snapshot_fixture="changed"
  echo "semantic_guard: ${semantic_guard}"
  echo "snapshot_fixture: ${snapshot_fixture}"
  echo "working_tree_clean: ${working_tree_clean}"
  echo "ui_smoke: ${ui_smoke}"
  exit 1
fi

if ! git diff --quiet -- "$FIXTURE_PATH" || ! git diff --quiet --cached -- "$FIXTURE_PATH"; then
  snapshot_fixture="changed"
fi

if ! git diff --quiet -- Tests/ZoneTruthCoreTests/Fixtures || ! git diff --quiet --cached -- Tests/ZoneTruthCoreTests/Fixtures; then
  snapshot_fixture="changed"
fi

# P1m annotation gate: any snapshot change requires a SEM-*.json annotation.
# blocking_drift additionally requires admissibility == "intentional_semantic_change".
if [[ "$snapshot_fixture" == "changed" ]]; then
  annotation_gate="required"
  latest_annotation="$(ls -1t artifacts/semantic_changes/SEM-*.json 2>/dev/null | grep -v TEMPLATE | head -n 1 || true)"
  if [[ -z "$latest_annotation" ]]; then
    annotation_gate="missing_annotation"
    echo "semantic_guard: ${semantic_guard}"
    echo "snapshot_fixture: ${snapshot_fixture}"
    echo "annotation_gate: ${annotation_gate}"
    echo "working_tree_clean: ${working_tree_clean}"
    echo "ui_smoke: ${ui_smoke}"
    exit 1
  fi
  annotation_gate="$(python - "$latest_annotation" "$dual_run_review" <<'PY'
import json, sys

path, drift_status = sys.argv[1], sys.argv[2]
try:
    with open(path, "r", encoding="utf-8") as fh:
        ann = json.load(fh)
except Exception as e:
    print(f"invalid_annotation: {e}")
    sys.exit(0)

required_fields = ["change_id", "reason", "affected_fixtures", "expected_behavior_change", "reviewed_by", "admissibility"]
for field in required_fields:
    if not ann.get(field):
        print(f"invalid_annotation: missing {field}")
        sys.exit(0)

if drift_status == "blocking_drift" and ann["admissibility"] != "intentional_semantic_change":
    print("blocked_by_admissibility")
    sys.exit(0)

print("valid")
PY
)"
  if [[ "$annotation_gate" != "valid" ]]; then
    echo "semantic_guard: ${semantic_guard}"
    echo "snapshot_fixture: ${snapshot_fixture}"
    echo "annotation_gate: ${annotation_gate}"
    echo "working_tree_clean: ${working_tree_clean}"
    echo "ui_smoke: ${ui_smoke}"
    exit 1
  fi
  annotation_gate="valid"
fi

latest_dual_run_file="$(ls -1t artifacts/migration/dual_run_*.json 2>/dev/null | head -n 1 || true)"
if [[ -n "$latest_dual_run_file" ]]; then
  dual_run_review="$(python - "$latest_dual_run_file" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    payload = json.load(fh)
print(payload.get("reviewStatus", "unknown"))
PY
)"
  if [[ "$dual_run_review" == "blocking_drift" || "$dual_run_review" == "invalid_report" ]]; then
    echo "semantic_guard: ${semantic_guard}"
    echo "snapshot_fixture: ${snapshot_fixture}"
    echo "working_tree_clean: ${working_tree_clean}"
    echo "ui_smoke: ${ui_smoke}"
    echo "dual_run_review: ${dual_run_review}"
    exit 1
  fi
fi

if ! git diff --quiet || ! git diff --quiet --cached; then
  working_tree_clean="no"
fi

echo "semantic_guard: ${semantic_guard}"
echo "snapshot_fixture: ${snapshot_fixture}"
echo "annotation_gate: ${annotation_gate}"
echo "working_tree_clean: ${working_tree_clean}"
echo "ui_smoke: ${ui_smoke}"
echo "dual_run_review: ${dual_run_review}"
