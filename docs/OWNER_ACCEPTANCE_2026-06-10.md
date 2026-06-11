---
audience: owner, local-tester, agent-runtime
authority: product-acceptance
status: local-owner-acceptance-candidate
last_updated: 2026-06-11
depends_on:
  - docs/OWNER_ACCEPTANCE_2026-06-05.md
  - docs/TEST_CANDIDATE_2026-06-04.md
  - docs/ZONE2_FEATURE_GATE_CHECKLIST.md
  - docs/TRAINING_ESTIMATOR_EVIDENCE_MAP.md
  - docs/APPLE_HEALTH_TRAINING_DATA_ROLE_MATRIX.md
  - docs/TRAINING_ANALYSIS_METADATA_CONTRACT.md
---

# Owner Acceptance 2026-06-10

Status: local owner acceptance candidate; no TestFlight build yet
Scope: VO2 max / Zone 2 / strength classification / Apple Health-backed metric metadata / sleep context / feedback persistence

## Purpose

This checklist is the current entry point for owner testing.

It answers whether the current local build is ready for a hands-on pass over:

- VO2 max estimate disclosure
- Zone 2 setup and claim-bounded ranges
- strength classification and strength metric disclosure
- Apple Health-backed metadata source-role disclosure
- Apple Health sleep context as supportive recovery context
- workout classification feedback save / duplicate behavior

It does not validate medical accuracy, lab equivalence, training plan adherence,
or App Store release readiness.

## Before Testing

Use the existing local app flow and sample data first. Use real Apple Health data
only after the sample path is stable.

Minimum setup:

- Build and launch the app locally.
- Confirm sample workouts are available, or import `SampleData/workouts.example.json`.
- If testing on device with Apple Health, grant the app-requested read permissions, including Sleep Analysis when prompted.
- Do not manually add unrelated HealthKit permissions outside the app-requested read set.
- Do not require Garmin, COROS, Strava live sync, TestFlight, or lab data.

## Local Smoke Commands

Recommended broad smoke:

```bash
bash scripts/meta_closeout.sh
```

Recommended product-targeted smoke:

```bash
swift test --filter 'testImportedVO2MaxEstimateAddsScalarMetadataWithoutReplacingIntervalQuality|testAppleHealthBackedMetricMetadataCarriesSourceRoleResolution|testMetricDisclosurePresenterRendersVO2MaxEstimateAsEstimate|testMetricDisclosurePresenterRendersStrengthMetricAsExerciseSpecificEstimate|testMetricDisclosurePresenterRendersHeartRateRecoveryAsBoundedContext|testMetricDisclosurePresenterRendersRunningPowerAsFieldEstimatorSupport|testMetricDisclosurePresenterRendersCyclingPowerAsFieldEstimatorSupport|testMetricDisclosurePresenterRendersWorkoutRouteAsTerrainContext|testWorkoutClassificationFeedbackRecorderSavesSuggestedTrainingModeRecord|testFileTrainingClassificationFeedbackStorePersistsRecordsAcrossInstances'
```

Recommended Zone 2 setup smoke:

```bash
swift test --filter 'testSettingsManagerPersistsRestingHeartRate|testSettingsManagerGeneratesAndAppliesRestingHeartRateSuggestion|testZone2ProfileStatusSummaryDoesNotShowPendingWhenSuggestionMatchesCurrentRange|testSettingsManagerResetsZone2BoundsToDefault|testRestingHeartRateImportAttemptsQueryWhenReadOnlyAuthorizationStatusIsDenied'
```

Recommended classification smoke:

```bash
swift test --filter 'testTrainingModeClassifierClassifiesStrengthHighHRAsConditioningLikeBeforeStrengthPattern|testTrainingModeClassifierClassifiesTypicalStrengthAsStrengthPattern|testTrainingModeClassifierDowngradesSwimmingZone2LikeClassification|testTrainingModeClassifierDowngradesSwimmingVO2LikeClassification'
```

Recommended sleep context smoke:

```bash
swift test --filter 'testHealthKitReadTypeIdentifiersIncludeVO2MaxAndRecovery|testHealthKitWorkoutRepositoryCarriesAppleSleepContext|testViewModelCarriesSleepContextIntoCurrentWeeklySummary|testWeeklyVisibleMissingEvidenceRemovesSleepWhenContextIsAvailable'
```

## Manual Test Checklist

### 1. Zone 2

1. Open Settings.
2. Confirm manual Zone 2 lower / upper bounds can be edited.
3. Confirm Resting HR can generate an initial Zone 2 reference range.
4. If current range equals suggested range, confirm the UI shows an already-applied state, not pending apply.
5. If current range differs from suggested range, confirm the UI offers to apply the reference range.
6. Open a Zone 2-like workout detail.
7. Confirm the detail view describes the current Zone 2 policy source.
8. Confirm the app does not present the range as exact, lab-verified, optimal, or medical-grade.

### 2. VO2 Max

1. Open a workout with imported scalar VO2 max estimate data.
2. Confirm the visible metric is labeled as an estimate or product reference.
3. Confirm the source is visible when available, such as Apple Health VO2 max.
4. Confirm metric disclosure does not treat VO2 interval quality as scalar VO2 max.
5. Open a VO2 interval workout without scalar VO2 max data.
6. Confirm it is described as interval / stimulus context, not measured VO2 max.

### 3. Strength

1. Open a workout with structured strength metric data.
2. Confirm the value is exercise-specific, such as e1RM or a named lift metric.
3. Confirm the disclosure distinguishes direct / estimated strength data from heart-rate-only strength pattern.
4. Open a strength workout with heart-rate pattern only.
5. Confirm the primary result is about training mode or pattern, not whole-body strength measurement.
6. Confirm high-HR strength sessions can surface conditioning-like context rather than simply saying all strength workouts are typical strength.

### 4. Apple Health-Backed Metadata Disclosure

When Apple Health-backed fields are available, verify they are used as source-role
context, not as authority upgrades.

Check these fields when present:

- VO2 max
- 1-minute heart-rate recovery
- running power
- cycling power
- workout route
- sleep analysis

Expected behavior:

- VO2 max remains a product estimate unless direct lab provenance is present.
- Heart-rate recovery is recovery context, not a diagnosis.
- Running and cycling power are external-load context, not threshold proof.
- Workout route is terrain / context support, not a fitness verdict.
- Sleep analysis is supportive recovery context, not a recovery diagnosis or readiness verdict.
- Missing Apple Health fields are quiet absences, not full-workout failures.

### 5. Sleep Context

1. On device, grant Apple Health Sleep Analysis read access when prompted.
2. Open the weekly overview after Apple Health data refresh.
3. If recent sleep data exists, confirm the advanced section shows sleep context: nights covered, average sleep duration, and coverage ratio.
4. If recent sleep data exists, confirm provenance display no longer lists sleep as missing evidence.
5. Confirm the copy says sleep is recovery context only.
6. Confirm the copy does not diagnose recovery, readiness, sleep adequacy, illness, stress, or overtraining.
7. Confirm the copy does not prescribe training changes such as "do not train today."
8. If no recent sleep data exists, confirm the absence is shown as missing/insufficient context rather than a workout failure.

### 6. Feedback Persistence

1. Open a workout detail with a classification result.
2. Submit feedback as accurate.
3. Confirm the UI shows saved feedback.
4. Submit the same rating and suggested mode again.
5. Confirm duplicate handling prevents another identical record.
6. Submit inaccurate or somewhat-similar feedback with a suggested training mode.
7. Confirm the feedback is saved as calibration data only.
8. Confirm no UI says the feedback rewrites original workout intent.

## Claim Boundaries

Allowed:

- `VO2 max 估算`
- `初步 Zone 2 參考範圍`
- `初步估算，尚未驗證`
- `肌力訓練型態`
- `偏高密度循環訓練`
- `心率恢復脈絡`
- `睡眠脈絡`
- `恢復脈絡參考`
- `外部負荷脈絡`
- `路線脈絡`
- `回饋已保存`

Forbidden:

- `VO2 max 實測`
- `true VO2 max`
- `lab-equivalent`
- `精準 Zone 2`
- `exact Zone 2`
- `最佳 Zone 2`
- `optimal Zone 2`
- `已量測 LT1`
- `已量測 VT1`
- `全身肌力診斷`
- `臨床肌力診斷`
- `恢復診斷`
- `readiness verdict`
- `睡眠不足，所以今天不要練`
- `睡眠資料證明你已恢復`
- `目的符合度`
- `本次意圖`
- `未達標`

## Acceptance Notes Format

Use this compact format after testing:

```text
Zone 2: pass / concern / fail
VO2 max: pass / concern / fail
Strength: pass / concern / fail
Apple Health metadata: pass / concern / fail
Sleep context: pass / concern / fail
Feedback persistence: pass / concern / fail
Overclaim check: pass / concern / fail
Most confusing screen:
Next fix:
```

## Exit Criteria

This owner acceptance pass is useful when it can answer:

- Can the owner understand what the app thinks happened in the workout?
- Does the detail view disclose evidence/source limits without becoming unreadable?
- Do Apple Health fields improve context without upgrading claim authority?
- Does sleep context appear as supportive recovery context without becoming a diagnosis or prescription?
- Does Zone 2 setup feel consistent after Resting HR import, suggestion, apply, and reset?
- Does feedback save as calibration data without becoming workout intent?

## Out Of Scope

This pass does not require:

- TestFlight build
- App Store readiness
- SwiftUI sections beyond the current sleep context surface
- weekly classifier or coaching changes
- HealthKit permissions beyond the current app-requested read set
- new classifier logic
- Garmin / COROS / Strava expansion
- clinical or lab-grade validation
