#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FIXTURE_PATH="Tests/ZoneTruthAppTests/Fixtures/workout_evaluation_snapshot.json"
WEEKLY_FIXTURE_PATH="Tests/ZoneTruthCoreTests/Fixtures/weekly_load_policy_snapshot.json"
WEEKLY_UI_PATH="Sources/ZoneTruthApp/WeeklyDashboardView.swift"
BODY_UI_PATH="Sources/ZoneTruthApp/BodyCompositionView.swift"

semantic_guard="passed"
snapshot_fixture="matched"
weekly_snapshot="matched"
weekly_ui_guard="passed"
goal_alignment_guard="passed"
adaptation_28d_guard="passed"
interaction_structural_guard="passed"
inference_authority_guard="passed"
inference_core_contract_guard="passed"
working_tree_clean="yes"
ui_smoke="pending"
dual_run_review="not-found"
annotation_gate="not-required"
codeburn_render_guard="passed"

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

if ! swift test --filter testWeeklyLoadPolicySnapshotFixture; then
  weekly_snapshot="changed"
  echo "semantic_guard: ${semantic_guard}"
  echo "snapshot_fixture: ${snapshot_fixture}"
  echo "weekly_snapshot: ${weekly_snapshot}"
  echo "weekly_ui_guard: ${weekly_ui_guard}"
  echo "working_tree_clean: ${working_tree_clean}"
  echo "ui_smoke: ${ui_smoke}"
  exit 1
fi

if ! swift test --filter testWeeklyDashboardViewSmokeCompiles; then
  ui_smoke="failed"
  echo "semantic_guard: ${semantic_guard}"
  echo "snapshot_fixture: ${snapshot_fixture}"
  echo "weekly_snapshot: ${weekly_snapshot}"
  echo "weekly_ui_guard: ${weekly_ui_guard}"
  echo "working_tree_clean: ${working_tree_clean}"
  echo "ui_smoke: ${ui_smoke}"
  exit 1
fi
ui_smoke="passed"

if ! swift test --filter testBodyCompositionContextSectionSmokeCompiles; then
  ui_smoke="failed"
  echo "semantic_guard: ${semantic_guard}"
  echo "snapshot_fixture: ${snapshot_fixture}"
  echo "weekly_snapshot: ${weekly_snapshot}"
  echo "weekly_ui_guard: ${weekly_ui_guard}"
  echo "working_tree_clean: ${working_tree_clean}"
  echo "ui_smoke: ${ui_smoke}"
  exit 1
fi

if ! swift test --filter testBodyCompositionSeedLedgerHasExpectedCoverage; then
  semantic_guard="failed"
  echo "semantic_guard: ${semantic_guard}"
  echo "snapshot_fixture: ${snapshot_fixture}"
  echo "weekly_snapshot: ${weekly_snapshot}"
  echo "weekly_ui_guard: ${weekly_ui_guard}"
  echo "working_tree_clean: ${working_tree_clean}"
  echo "ui_smoke: ${ui_smoke}"
  exit 1
fi

if ! swift test --filter GoalAlignmentEngineTests; then
  goal_alignment_guard="failed"
  echo "goal_alignment_guard: ${goal_alignment_guard}"
  exit 1
fi

if ! swift test --filter testGoalAlignmentSurfaceLanguageContainsNoForbiddenAuthorityTerms; then
  goal_alignment_guard="failed"
  echo "goal_alignment_guard: ${goal_alignment_guard}"
  exit 1
fi

if ! swift test --filter testGoalAlignmentSurfaceLanguageSnapshotFixture; then
  goal_alignment_guard="failed"
  echo "goal_alignment_guard: ${goal_alignment_guard}"
  exit 1
fi

if ! swift test --filter testMultiWeekAdaptation; then
  adaptation_28d_guard="failed"
  echo "adaptation_28d_guard: ${adaptation_28d_guard}"
  exit 1
fi

# Goal alignment wording must never contain achievement/predictive language.
# Keep this scoped to overclaim verbs; generic "診斷" appears in bounded disclaimers elsewhere.
if grep -E -q '目標達成|將會達到|已達成|必定|保證|預測|必然' "$WEEKLY_UI_PATH"; then
  goal_alignment_guard="forbidden_goal_claim_detected"
  echo "weekly_ui_guard: ${weekly_ui_guard}"
  echo "goal_alignment_guard: ${goal_alignment_guard}"
  exit 1
fi

if ! bash scripts/run_codeburn_render_test.sh; then
  codeburn_render_guard="failed"
  echo "semantic_guard: ${semantic_guard}"
  echo "snapshot_fixture: ${snapshot_fixture}"
  echo "weekly_snapshot: ${weekly_snapshot}"
  echo "weekly_ui_guard: ${weekly_ui_guard}"
  echo "annotation_gate: ${annotation_gate}"
  echo "codeburn_render_guard: ${codeburn_render_guard}"
  echo "working_tree_clean: ${working_tree_clean}"
  echo "ui_smoke: ${ui_smoke}"
  exit 1
fi

if grep -E -q '過度訓練|overtraining|休息不足' "$WEEKLY_UI_PATH"; then
  weekly_ui_guard="forbidden_term_detected"
  echo "semantic_guard: ${semantic_guard}"
  echo "snapshot_fixture: ${snapshot_fixture}"
  echo "weekly_snapshot: ${weekly_snapshot}"
  echo "weekly_ui_guard: ${weekly_ui_guard}"
  echo "working_tree_clean: ${working_tree_clean}"
  echo "ui_smoke: ${ui_smoke}"
  exit 1
fi

# Interaction authority guard:
# forbid authority-compressing interaction patterns, not just forbidden words.
if grep -E -q 'readiness|Readiness|Recovery score|恢復分數|today recommendation|Recommended workout today|你應該休息|你今天不適合高強度' "$WEEKLY_UI_PATH"; then
  interaction_structural_guard="forbidden_interaction_authority_pattern"
  echo "interaction_structural_guard: ${interaction_structural_guard}"
  exit 1
fi

# Inference authority guard:
# ensure inference governance artifacts exist and upstream language does not inflate authority.
if [[ ! -f "docs/INFERENCE_POLICY.md" ]]; then
  inference_authority_guard="missing_inference_policy"
  echo "inference_authority_guard: ${inference_authority_guard}"
  exit 1
fi

if [[ ! -f "schemas/inference_provenance.schema.json" ]]; then
  inference_authority_guard="missing_inference_provenance_schema"
  echo "inference_authority_guard: ${inference_authority_guard}"
  exit 1
fi

if ! grep -q 'non_interventional' "docs/INFERENCE_POLICY.md"; then
  inference_authority_guard="missing_non_interventional_authority_ceiling"
  echo "inference_authority_guard: ${inference_authority_guard}"
  exit 1
fi

if ! grep -q '"authority_ceiling"' "schemas/inference_provenance.schema.json"; then
  inference_authority_guard="schema_missing_authority_ceiling"
  echo "inference_authority_guard: ${inference_authority_guard}"
  exit 1
fi

if ! grep -q '"missing_evidence"' "schemas/inference_provenance.schema.json"; then
  inference_authority_guard="schema_missing_missing_evidence"
  echo "inference_authority_guard: ${inference_authority_guard}"
  exit 1
fi

if grep -R -E -q 'strongly suggests reduced intensity|you should rest today|Recommended workout today|today recommendation|must rest|不適合高強度|必須休息|建議休息' Sources; then
  inference_authority_guard="forbidden_inference_escalation_phrase_detected"
  echo "inference_authority_guard: ${inference_authority_guard}"
  exit 1
fi

# App boundary guard: WeeklyDashboardView must render Core-provided provenance only.
if grep -E -q 'InferenceProvenanceFactory\.weekly|InferenceAuthorityCeiling|MissingEvidence\.sleep|MissingEvidence\.hrv' "$WEEKLY_UI_PATH"; then
  inference_core_contract_guard="ui_reintroduced_inference_contract_logic"
  echo "inference_core_contract_guard: ${inference_core_contract_guard}"
  exit 1
fi

# Core contract guard: provenance is an inference contract in ZoneTruthCore,
# not a UI-only disclosure artifact.
if ! grep -q 'public struct InferenceProvenance' "Sources/ZoneTruthCore/Models.swift"; then
  inference_core_contract_guard="missing_core_inference_provenance_struct"
  echo "inference_core_contract_guard: ${inference_core_contract_guard}"
  exit 1
fi

if ! grep -q 'public enum InferenceType' "Sources/ZoneTruthCore/Models.swift"; then
  inference_core_contract_guard="missing_core_inference_type"
  echo "inference_core_contract_guard: ${inference_core_contract_guard}"
  exit 1
fi

if ! grep -q 'public enum InferenceAuthorityCeiling' "Sources/ZoneTruthCore/Models.swift"; then
  inference_core_contract_guard="missing_core_authority_ceiling"
  echo "inference_core_contract_guard: ${inference_core_contract_guard}"
  exit 1
fi

if ! grep -q 'public enum MissingEvidence' "Sources/ZoneTruthCore/Models.swift"; then
  inference_core_contract_guard="missing_core_missing_evidence"
  echo "inference_core_contract_guard: ${inference_core_contract_guard}"
  exit 1
fi

if ! grep -q 'public enum DerivedFromSignal' "Sources/ZoneTruthCore/Models.swift"; then
  inference_core_contract_guard="missing_core_derived_from_signal"
  echo "inference_core_contract_guard: ${inference_core_contract_guard}"
  exit 1
fi

if ! grep -q 'inferenceType' "Sources/ZoneTruthCore/Models.swift" || \
   ! grep -q 'derivedFrom' "Sources/ZoneTruthCore/Models.swift" || \
   ! grep -q 'missingEvidence' "Sources/ZoneTruthCore/Models.swift" || \
   ! grep -q 'authorityCeiling' "Sources/ZoneTruthCore/Models.swift"; then
  inference_core_contract_guard="core_inference_provenance_fields_missing"
  echo "inference_core_contract_guard: ${inference_core_contract_guard}"
  exit 1
fi

# Required structural order in root composition:
# Overview (bounded interpretation context) -> override coverage insight -> advanced evidence surface
overview_call_line="$(grep -n 'WeeklyOverviewCard(' "$WEEKLY_UI_PATH" | head -n 1 | cut -d: -f1 || true)"
coverage_call_line="$(grep -n 'WeeklyOverrideInsightCard(' "$WEEKLY_UI_PATH" | head -n 1 | cut -d: -f1 || true)"
advanced_call_line="$(grep -n 'WeeklyAdvancedCard(' "$WEEKLY_UI_PATH" | head -n 1 | cut -d: -f1 || true)"

if [[ -z "$overview_call_line" || -z "$coverage_call_line" || -z "$advanced_call_line" ]]; then
  interaction_structural_guard="missing_required_interaction_surface"
  echo "interaction_structural_guard: ${interaction_structural_guard}"
  exit 1
fi

if ! [[ "$overview_call_line" -lt "$coverage_call_line" && "$coverage_call_line" -lt "$advanced_call_line" ]]; then
  interaction_structural_guard="invalid_interaction_order"
  echo "interaction_structural_guard: ${interaction_structural_guard}"
  echo "overview_call_line: ${overview_call_line}"
  echo "coverage_call_line: ${coverage_call_line}"
  echo "advanced_call_line: ${advanced_call_line}"
  exit 1
fi

if ! grep -q 'Text("恢復觀察")' "$WEEKLY_UI_PATH"; then
  weekly_ui_guard="missing_recovery_observation_label"
  echo "semantic_guard: ${semantic_guard}"
  echo "snapshot_fixture: ${snapshot_fixture}"
  echo "weekly_snapshot: ${weekly_snapshot}"
  echo "weekly_ui_guard: ${weekly_ui_guard}"
  echo "working_tree_clean: ${working_tree_clean}"
  echo "ui_smoke: ${ui_smoke}"
  exit 1
fi

if ! grep -q '部分訓練心率樣本不足，數據僅供參考' "$WEEKLY_UI_PATH"; then
  weekly_ui_guard="missing_sparse_confidence_warning"
  echo "semantic_guard: ${semantic_guard}"
  echo "snapshot_fixture: ${snapshot_fixture}"
  echo "weekly_snapshot: ${weekly_snapshot}"
  echo "weekly_ui_guard: ${weekly_ui_guard}"
  echo "working_tree_clean: ${working_tree_clean}"
  echo "ui_smoke: ${ui_smoke}"
  exit 1
fi

if ! grep -q 'Text("身體組成脈絡")' "$WEEKLY_UI_PATH"; then
  weekly_ui_guard="missing_body_composition_context_label"
  echo "semantic_guard: ${semantic_guard}"
  echo "snapshot_fixture: ${snapshot_fixture}"
  echo "weekly_snapshot: ${weekly_snapshot}"
  echo "weekly_ui_guard: ${weekly_ui_guard}"
  echo "working_tree_clean: ${working_tree_clean}"
  echo "ui_smoke: ${ui_smoke}"
  exit 1
fi

if grep -E -q '神經疲勞|肌肥大效果|必須|可診斷|診斷結果|確定診斷' "$BODY_UI_PATH"; then
  weekly_ui_guard="body_composition_forbidden_term_detected"
  echo "semantic_guard: ${semantic_guard}"
  echo "snapshot_fixture: ${snapshot_fixture}"
  echo "weekly_snapshot: ${weekly_snapshot}"
  echo "weekly_ui_guard: ${weekly_ui_guard}"
  echo "working_tree_clean: ${working_tree_clean}"
  echo "ui_smoke: ${ui_smoke}"
  exit 1
fi

if grep -q -E 'recommendationEmphasisOpacity\(for:[[:space:]]*policy\.confidence\)' "$WEEKLY_UI_PATH" || grep -q -E 'recommendationStrokeOpacity\(for:[[:space:]]*policy\.confidence\)' "$WEEKLY_UI_PATH"; then
  weekly_ui_guard="visual_authority_bypass_detected"
  echo "semantic_guard: ${semantic_guard}"
  echo "snapshot_fixture: ${snapshot_fixture}"
  echo "weekly_snapshot: ${weekly_snapshot}"
  echo "weekly_ui_guard: ${weekly_ui_guard}"
  echo "working_tree_clean: ${working_tree_clean}"
  echo "ui_smoke: ${ui_smoke}"
  exit 1
fi

if ! git diff --quiet -- "$FIXTURE_PATH" || ! git diff --quiet --cached -- "$FIXTURE_PATH"; then
  snapshot_fixture="changed"
fi

if ! git diff --quiet -- "$WEEKLY_FIXTURE_PATH" || ! git diff --quiet --cached -- "$WEEKLY_FIXTURE_PATH"; then
  weekly_snapshot="changed"
fi

if ! git diff --quiet -- Tests/ZoneTruthCoreTests/Fixtures || ! git diff --quiet --cached -- Tests/ZoneTruthCoreTests/Fixtures; then
  snapshot_fixture="changed"
  weekly_snapshot="changed"
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
echo "weekly_snapshot: ${weekly_snapshot}"
echo "weekly_ui_guard: ${weekly_ui_guard}"
echo "goal_alignment_guard: ${goal_alignment_guard}"
echo "adaptation_28d_guard: ${adaptation_28d_guard}"
echo "interaction_structural_guard: ${interaction_structural_guard}"
echo "inference_authority_guard: ${inference_authority_guard}"
echo "inference_core_contract_guard: ${inference_core_contract_guard}"
echo "annotation_gate: ${annotation_gate}"
echo "codeburn_render_guard: ${codeburn_render_guard}"
echo "working_tree_clean: ${working_tree_clean}"
echo "ui_smoke: ${ui_smoke}"
echo "dual_run_review: ${dual_run_review}"
