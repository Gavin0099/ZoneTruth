#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BOUNDARY_PATTERN_JSON="scripts/closeout_boundary_patterns.json"
BOUNDARY_PATTERN_SCHEMA="schemas/closeout_boundary_patterns.schema.json"
if [[ ! -f "$BOUNDARY_PATTERN_JSON" ]]; then
  echo "test_boundary_guard: missing_boundary_pattern_config"
  exit 1
fi
if [[ ! -f "$BOUNDARY_PATTERN_SCHEMA" ]]; then
  echo "test_boundary_guard: missing_boundary_pattern_schema"
  exit 1
fi

if ! python - "$BOUNDARY_PATTERN_JSON" "$BOUNDARY_PATTERN_SCHEMA" <<'PY'
import json, sys

config_path, schema_path = sys.argv[1], sys.argv[2]
try:
    with open(config_path, "r", encoding="utf-8") as fh:
        cfg = json.load(fh)
    with open(schema_path, "r", encoding="utf-8") as fh:
        schema = json.load(fh)
except Exception as exc:
    print(f"boundary_schema_validation_error: {exc}")
    sys.exit(1)

if schema.get("type") != "object":
    print("boundary_schema_validation_error: unsupported_schema_type")
    sys.exit(1)

required = schema.get("required", [])
props = schema.get("properties", {})
allow_extra = not (schema.get("additionalProperties") is False)

for key in required:
    if key not in cfg:
        print(f"boundary_schema_validation_error: missing_required_key:{key}")
        sys.exit(1)

if not allow_extra:
    extra = [k for k in cfg.keys() if k not in props]
    if extra:
        print(f"boundary_schema_validation_error: unexpected_keys:{','.join(sorted(extra))}")
        sys.exit(1)

for key, rule in props.items():
    if key not in cfg:
        continue
    val = cfg[key]
    if rule.get("type") == "string":
        if not isinstance(val, str):
            print(f"boundary_schema_validation_error: type_mismatch:{key}")
            sys.exit(1)
        if len(val) < int(rule.get("minLength", 0)):
            print(f"boundary_schema_validation_error: min_length_violation:{key}")
            sys.exit(1)
    if rule.get("type") == "array":
        if not isinstance(val, list):
            print(f"boundary_schema_validation_error: type_mismatch:{key}")
            sys.exit(1)
        if len(val) < int(rule.get("minItems", 0)):
            print(f"boundary_schema_validation_error: min_items_violation:{key}")
            sys.exit(1)
        item_rule = rule.get("items", {})
        item_required = item_rule.get("required", [])
        item_props = item_rule.get("properties", {})
        item_allow_extra = not (item_rule.get("additionalProperties") is False)
        for idx, item in enumerate(val):
            if not isinstance(item, dict):
                print(f"boundary_schema_validation_error: array_item_type_mismatch:{key}:{idx}")
                sys.exit(1)
            for req_key in item_required:
                if req_key not in item:
                    print(f"boundary_schema_validation_error: array_item_missing_required:{key}:{idx}:{req_key}")
                    sys.exit(1)
            if not item_allow_extra:
                extra = [k for k in item.keys() if k not in item_props]
                if extra:
                    print(f"boundary_schema_validation_error: array_item_unexpected_keys:{key}:{idx}:{','.join(sorted(extra))}")
                    sys.exit(1)
            for item_key, item_prop_rule in item_props.items():
                if item_key not in item:
                    continue
                item_val = item[item_key]
                if item_prop_rule.get("type") == "string":
                    if not isinstance(item_val, str):
                        print(f"boundary_schema_validation_error: array_item_type_mismatch:{key}:{idx}:{item_key}")
                        sys.exit(1)
                    if len(item_val) < int(item_prop_rule.get("minLength", 0)):
                        print(f"boundary_schema_validation_error: array_item_min_length_violation:{key}:{idx}:{item_key}")
                        sys.exit(1)

print("boundary_schema_validation: ok")
PY
then
  echo "test_boundary_guard: invalid_boundary_pattern_schema_or_config"
  exit 1
fi

readarray -t boundary_patterns < <(python - "$BOUNDARY_PATTERN_JSON" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    payload = json.load(fh)
for key in ("comment_filter_regex",):
    value = payload.get(key)
    if not isinstance(value, str) or not value:
        print("")
    else:
        print(value)
PY
)

BOUNDARY_COMMENT_FILTER_REGEX="${boundary_patterns[0]:-}"
if [[ -z "$BOUNDARY_COMMENT_FILTER_REGEX" ]]; then
  echo "test_boundary_guard: invalid_boundary_pattern_config"
  exit 1
fi

readarray -t app_test_boundary_rules < <(python - "$BOUNDARY_PATTERN_JSON" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    payload = json.load(fh)
rules = payload.get("app_test_boundary_rules", [])
for rule in rules:
    rid = rule.get("id", "")
    regex = rule.get("regex", "")
    rationale = rule.get("rationale", "")
    if isinstance(rid, str) and rid and isinstance(regex, str) and regex and isinstance(rationale, str) and rationale:
        print(f"{rid}\t{regex}\t{rationale}")
PY
)

if [[ ${#app_test_boundary_rules[@]} -eq 0 ]]; then
  echo "test_boundary_guard: invalid_boundary_pattern_config"
  exit 1
fi

readarray -t app_source_boundary_rules < <(python - "$BOUNDARY_PATTERN_JSON" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    payload = json.load(fh)
rules = payload.get("app_source_boundary_rules", [])
for rule in rules:
    rid = rule.get("id", "")
    regex = rule.get("regex", "")
    rationale = rule.get("rationale", "")
    if isinstance(rid, str) and rid and isinstance(regex, str) and regex and isinstance(rationale, str) and rationale:
        print(f"{rid}\t{regex}\t{rationale}")
PY
)

if [[ ${#app_source_boundary_rules[@]} -eq 0 ]]; then
  echo "test_boundary_guard: invalid_boundary_pattern_config"
  exit 1
fi

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
test_boundary_guard="passed"
app_source_boundary_guard="passed"
working_tree_clean="yes"
ui_smoke="pending"
dual_run_review="not-found"
annotation_gate="not-required"
codeburn_render_guard="passed"
boundary_telemetry_status="passed"
boundary_telemetry_dir="artifacts/runtime/boundary-telemetry"
mkdir -p "$boundary_telemetry_dir"
boundary_telemetry_file="$boundary_telemetry_dir/boundary_telemetry_$(date -u +"%Y%m%dT%H%M%SZ").json"
boundary_trend_summary_file="$boundary_telemetry_dir/summary_latest.json"
boundary_trend_gate="passed"
boundary_trend_window="${BOUNDARY_TREND_WINDOW:-20}"
boundary_trend_max_failure_events="${BOUNDARY_TREND_MAX_FAILURE_EVENTS:-2}"
boundary_trend_max_rule_hits="${BOUNDARY_TREND_MAX_RULE_HITS:-2}"
app_test_boundary_hit_count=0
app_source_boundary_hit_count=0
app_test_boundary_rule_total=${#app_test_boundary_rules[@]}
app_source_boundary_rule_total=${#app_source_boundary_rules[@]}
app_test_boundary_rule_hit_count=0
app_source_boundary_rule_hit_count=0
app_test_boundary_rule_hits=""
app_source_boundary_rule_hits=""

line_count() {
  local value="$1"
  if [[ -z "$value" ]]; then
    echo 0
  else
    printf '%s' "$value" | awk 'NF{c++} END{print c+0}'
  fi
}

write_boundary_telemetry() {
  python - "$boundary_telemetry_file" <<'PY'
import json, os, sys

path = sys.argv[1]
payload = {
    "generated_at_utc": os.environ.get("BOUNDARY_TELEMETRY_TS", ""),
    "status": os.environ.get("BOUNDARY_TELEMETRY_STATUS", "unknown"),
    "app_test_boundary_rule_total": int(os.environ.get("APP_TEST_BOUNDARY_RULE_TOTAL", "0")),
    "app_test_boundary_rule_hit_count": int(os.environ.get("APP_TEST_BOUNDARY_RULE_HIT_COUNT", "0")),
    "app_test_boundary_hit_count": int(os.environ.get("APP_TEST_BOUNDARY_HIT_COUNT", "0")),
    "app_source_boundary_rule_total": int(os.environ.get("APP_SOURCE_BOUNDARY_RULE_TOTAL", "0")),
    "app_source_boundary_rule_hit_count": int(os.environ.get("APP_SOURCE_BOUNDARY_RULE_HIT_COUNT", "0")),
    "app_source_boundary_hit_count": int(os.environ.get("APP_SOURCE_BOUNDARY_HIT_COUNT", "0")),
    "app_test_boundary_hits": [line for line in os.environ.get("APP_TEST_BOUNDARY_HITS", "").splitlines() if line.strip()],
    "app_source_boundary_hits": [line for line in os.environ.get("APP_SOURCE_BOUNDARY_HITS", "").splitlines() if line.strip()],
}
with open(path, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
PY
}

evaluate_boundary_trend_gate() {
  local summarize_rc=0
  python3 scripts/summarize_boundary_telemetry.py \
    --telemetry-dir "$boundary_telemetry_dir" \
    --limit "$boundary_trend_window" \
    --max-failure-events "$boundary_trend_max_failure_events" \
    --max-rule-hits "$boundary_trend_max_rule_hits" \
    --output "$boundary_trend_summary_file" >/dev/null 2>&1 || summarize_rc=$?
  if [[ ! -f "$boundary_trend_summary_file" ]]; then
    boundary_trend_gate="missing_summary"
    echo "boundary_trend_gate: ${boundary_trend_gate}"
    return 1
  fi

  local failure_events=0 hottest_rule_hits=0 gate_reason="unknown" gate_verdict="unknown"
  read -r failure_events hottest_rule_hits gate_verdict gate_reason < <(python3 - "$boundary_trend_summary_file" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    payload = json.load(fh)
gate = payload.get("trendGate", {})
print(f"{int(gate.get('failureEvents', 0))} {int(gate.get('hottestRuleHits', 0))} {gate.get('verdict', 'unknown')} {gate.get('reason', 'unknown')}")
PY
)

  if [[ "$summarize_rc" -ne 0 || "$gate_verdict" == "fail" ]]; then
    boundary_trend_gate="${gate_reason}"
    echo "boundary_trend_gate: ${boundary_trend_gate}"
    echo "boundary_trend_window: ${boundary_trend_window}"
    echo "boundary_trend_failure_events: ${failure_events}"
    echo "boundary_trend_max_failure_events: ${boundary_trend_max_failure_events}"
    echo "boundary_trend_hottest_rule_hits: ${hottest_rule_hits}"
    echo "boundary_trend_max_rule_hits: ${boundary_trend_max_rule_hits}"
    return 1
  fi

  boundary_trend_gate="passed"
  return 0
}

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

# Test responsibility boundary guard:
# App tests must not re-test core inference semantics.
if [[ ! -f "docs/TEST_RESPONSIBILITY_BOUNDARY.md" ]]; then
  test_boundary_guard="missing_test_responsibility_boundary_doc"
  echo "test_boundary_guard: ${test_boundary_guard}"
  exit 1
fi

if ! grep -q 'Core tests verify inference truth' "docs/TEST_RESPONSIBILITY_BOUNDARY.md" || \
   ! grep -q 'App tests verify rendering safety' "docs/TEST_RESPONSIBILITY_BOUNDARY.md" || \
   ! grep -q 'Closeout guards verify boundary drift' "docs/TEST_RESPONSIBILITY_BOUNDARY.md"; then
  test_boundary_guard="incomplete_test_responsibility_boundary_doc"
  echo "test_boundary_guard: ${test_boundary_guard}"
  exit 1
fi

# Expand to entire app-test directory and report concrete hits.
# Basic false-positive reduction: ignore comment-only lines.
app_test_boundary_hits=""
for rule_line in "${app_test_boundary_rules[@]}"; do
  IFS=$'\t' read -r rule_id rule_regex rule_rationale <<< "$rule_line"
  if [[ -z "${rule_id:-}" || -z "${rule_regex:-}" ]]; then
    continue
  fi
  rule_hits="$(
    grep -RIn --include="*.swift" -E "$rule_regex" Tests/ZoneTruthAppTests \
    | grep -Ev "$BOUNDARY_COMMENT_FILTER_REGEX" || true
  )"
  if [[ -n "$rule_hits" ]]; then
    app_test_boundary_rule_hit_count=$((app_test_boundary_rule_hit_count + 1))
    while IFS= read -r hit_line; do
      [[ -z "$hit_line" ]] && continue
      app_test_boundary_hits+="$rule_id|$rule_rationale|$hit_line"$'\n'
    done <<< "$rule_hits"
  fi
done
app_test_boundary_hit_count="$(line_count "$app_test_boundary_hits")"
app_test_boundary_rule_hits="$app_test_boundary_hits"
if [[ -n "$app_test_boundary_hits" ]]; then
  boundary_telemetry_status="failed_app_test_boundary"
  BOUNDARY_TELEMETRY_TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  BOUNDARY_TELEMETRY_STATUS="$boundary_telemetry_status" \
  APP_TEST_BOUNDARY_RULE_TOTAL="$app_test_boundary_rule_total" \
  APP_TEST_BOUNDARY_RULE_HIT_COUNT="$app_test_boundary_rule_hit_count" \
  APP_TEST_BOUNDARY_HIT_COUNT="$app_test_boundary_hit_count" \
  APP_SOURCE_BOUNDARY_RULE_TOTAL="$app_source_boundary_rule_total" \
  APP_SOURCE_BOUNDARY_RULE_HIT_COUNT="$app_source_boundary_rule_hit_count" \
  APP_SOURCE_BOUNDARY_HIT_COUNT="$app_source_boundary_hit_count" \
  APP_TEST_BOUNDARY_HITS="$app_test_boundary_rule_hits" \
  APP_SOURCE_BOUNDARY_HITS="$app_source_boundary_rule_hits" \
  write_boundary_telemetry
  test_boundary_guard="app_tests_retesting_core_inference_semantics"
  echo "test_boundary_guard: ${test_boundary_guard}"
  echo "test_boundary_hits:"
  printf '%s' "$app_test_boundary_hits"
  exit 1
fi

# App source boundary guard:
# App layer must not create or classify inference authority.
app_source_boundary_hits=""
for rule_line in "${app_source_boundary_rules[@]}"; do
  IFS=$'\t' read -r rule_id rule_regex rule_rationale <<< "$rule_line"
  if [[ -z "${rule_id:-}" || -z "${rule_regex:-}" ]]; then
    continue
  fi
  rule_hits="$(
    grep -RIn --include="*.swift" -E \
    "$rule_regex" \
    Sources/ZoneTruthApp \
    | grep -Ev "$BOUNDARY_COMMENT_FILTER_REGEX" || true
  )"
  if [[ -n "$rule_hits" ]]; then
    app_source_boundary_rule_hit_count=$((app_source_boundary_rule_hit_count + 1))
    while IFS= read -r hit_line; do
      [[ -z "$hit_line" ]] && continue
      app_source_boundary_hits+="$rule_id|$rule_rationale|$hit_line"$'\n'
    done <<< "$rule_hits"
  fi
done
app_source_boundary_hit_count="$(line_count "$app_source_boundary_hits")"
app_source_boundary_rule_hits="$app_source_boundary_hits"

if [[ -n "$app_source_boundary_hits" ]]; then
  boundary_telemetry_status="failed_app_source_boundary"
  BOUNDARY_TELEMETRY_TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  BOUNDARY_TELEMETRY_STATUS="$boundary_telemetry_status" \
  APP_TEST_BOUNDARY_RULE_TOTAL="$app_test_boundary_rule_total" \
  APP_TEST_BOUNDARY_RULE_HIT_COUNT="$app_test_boundary_rule_hit_count" \
  APP_TEST_BOUNDARY_HIT_COUNT="$app_test_boundary_hit_count" \
  APP_SOURCE_BOUNDARY_RULE_TOTAL="$app_source_boundary_rule_total" \
  APP_SOURCE_BOUNDARY_RULE_HIT_COUNT="$app_source_boundary_rule_hit_count" \
  APP_SOURCE_BOUNDARY_HIT_COUNT="$app_source_boundary_hit_count" \
  APP_TEST_BOUNDARY_HITS="$app_test_boundary_rule_hits" \
  APP_SOURCE_BOUNDARY_HITS="$app_source_boundary_rule_hits" \
  write_boundary_telemetry
  app_source_boundary_guard="app_source_reintroduced_inference_authority_logic"
  echo "app_source_boundary_guard: ${app_source_boundary_guard}"
  echo "app_source_boundary_hits:"
  printf '%s' "$app_source_boundary_hits"
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

BOUNDARY_TELEMETRY_TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
BOUNDARY_TELEMETRY_STATUS="$boundary_telemetry_status" \
APP_TEST_BOUNDARY_RULE_TOTAL="$app_test_boundary_rule_total" \
APP_TEST_BOUNDARY_RULE_HIT_COUNT="$app_test_boundary_rule_hit_count" \
APP_TEST_BOUNDARY_HIT_COUNT="$app_test_boundary_hit_count" \
APP_SOURCE_BOUNDARY_RULE_TOTAL="$app_source_boundary_rule_total" \
APP_SOURCE_BOUNDARY_RULE_HIT_COUNT="$app_source_boundary_rule_hit_count" \
APP_SOURCE_BOUNDARY_HIT_COUNT="$app_source_boundary_hit_count" \
APP_TEST_BOUNDARY_HITS="$app_test_boundary_rule_hits" \
APP_SOURCE_BOUNDARY_HITS="$app_source_boundary_rule_hits" \
write_boundary_telemetry
if ! evaluate_boundary_trend_gate; then
  exit 1
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
echo "test_boundary_guard: ${test_boundary_guard}"
echo "app_source_boundary_guard: ${app_source_boundary_guard}"
echo "annotation_gate: ${annotation_gate}"
echo "codeburn_render_guard: ${codeburn_render_guard}"
echo "working_tree_clean: ${working_tree_clean}"
echo "ui_smoke: ${ui_smoke}"
echo "dual_run_review: ${dual_run_review}"
echo "boundary_telemetry_file: ${boundary_telemetry_file}"
echo "boundary_trend_summary_file: ${boundary_trend_summary_file}"
echo "boundary_trend_gate: ${boundary_trend_gate}"
