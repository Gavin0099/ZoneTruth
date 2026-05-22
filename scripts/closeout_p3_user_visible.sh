#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

WEEKLY_UI_PATH="Sources/ZoneTruthApp/WeeklyDashboardView.swift"
CHECKLIST_PATH="docs/P3_USER_VISIBLE_ACCEPTANCE_CHECKLIST.md"

p3_user_visible_guard="passed"
authority_tests="passed"
freshness_tests="passed"
state_machine_tests="passed"
adaptation_guard_tests="passed"
body_context_tests="passed"
forbidden_semantics_guard="passed"
base_closeout="passed"

fail() {
  echo "p3_user_visible_guard: ${p3_user_visible_guard}"
  echo "base_closeout: ${base_closeout}"
  echo "authority_tests: ${authority_tests}"
  echo "freshness_tests: ${freshness_tests}"
  echo "state_machine_tests: ${state_machine_tests}"
  echo "adaptation_guard_tests: ${adaptation_guard_tests}"
  echo "body_context_tests: ${body_context_tests}"
  echo "forbidden_semantics_guard: ${forbidden_semantics_guard}"
  exit 1
}

if ! test -f "$CHECKLIST_PATH"; then
  p3_user_visible_guard="missing_checklist_doc"
  fail
fi

if ! bash scripts/closeout_workout_evaluation.sh >/tmp/zonetruth_p3_base_closeout.log; then
  base_closeout="failed"
  p3_user_visible_guard="base_closeout_failed"
  cat /tmp/zonetruth_p3_base_closeout.log
  fail
fi

if ! swift test --filter testWeeklyAuthorityRenderingDowngradesUnderLowConfidence; then
  authority_tests="failed"
  p3_user_visible_guard="authority_tests_failed"
  fail
fi

if ! swift test --filter testLowEvidenceCannotRenderHighAuthorityVisuals; then
  authority_tests="failed"
  p3_user_visible_guard="authority_tests_failed"
  fail
fi

if ! swift test --filter testCardSurfaceOpacityMonotonicByAuthority; then
  authority_tests="failed"
  p3_user_visible_guard="authority_tests_failed"
  fail
fi

if ! swift test --filter testWeeklyFreshnessSignalClassifiesFreshPartialStaleMissing; then
  freshness_tests="failed"
  p3_user_visible_guard="freshness_tests_failed"
  fail
fi

if ! swift test --filter testWeeklyInferenceClassifierReturnsUnsupportedWhenEvidenceMissing; then
  freshness_tests="failed"
  p3_user_visible_guard="freshness_tests_failed"
  fail
fi

if ! swift test --filter testWeeklyTrainingStateSignalCoversStateProgression; then
  state_machine_tests="failed"
  p3_user_visible_guard="state_machine_tests_failed"
  fail
fi

if ! swift test --filter testWeeklyTrainingStateSignalDowngradesUnderStaleOrMissingEvidence; then
  state_machine_tests="failed"
  p3_user_visible_guard="state_machine_tests_failed"
  fail
fi

if ! swift test --filter testTrainingStateRenderingAvoidsBinaryGoodBadTerms; then
  state_machine_tests="failed"
  p3_user_visible_guard="state_machine_tests_failed"
  fail
fi

if ! swift test --filter testNoSignalDirectionAlwaysRendersEvidenceGapLabel; then
  adaptation_guard_tests="failed"
  p3_user_visible_guard="adaptation_guard_tests_failed"
  fail
fi

if ! swift test --filter testWeeklyAdaptationSignalUsesBoundedDirectionClasses; then
  adaptation_guard_tests="failed"
  p3_user_visible_guard="adaptation_guard_tests_failed"
  fail
fi

if ! swift test --filter testBodyCompositionContextSectionSmokeCompiles; then
  body_context_tests="failed"
  p3_user_visible_guard="body_context_tests_failed"
  fail
fi

if ! swift test --filter testBodyCompositionSeedLedgerHasExpectedCoverage; then
  body_context_tests="failed"
  p3_user_visible_guard="body_context_tests_failed"
  fail
fi

if grep -E -q '過度訓練|overtraining|休息不足|神經疲勞|肌肥大效果|今天必須休息|你不適合高強度' "$WEEKLY_UI_PATH"; then
  forbidden_semantics_guard="failed"
  p3_user_visible_guard="forbidden_semantics_detected"
  fail
fi

echo "p3_user_visible_guard: ${p3_user_visible_guard}"
echo "base_closeout: ${base_closeout}"
echo "authority_tests: ${authority_tests}"
echo "freshness_tests: ${freshness_tests}"
echo "state_machine_tests: ${state_machine_tests}"
echo "adaptation_guard_tests: ${adaptation_guard_tests}"
echo "body_context_tests: ${body_context_tests}"
echo "forbidden_semantics_guard: ${forbidden_semantics_guard}"
