# Test Candidate 2026-06-04

Status: local product acceptance candidate; no TestFlight build yet
Base commit: pending current Strength slice commit
Audience: owner / local tester

## Short Answer

The three scoped product pillars now have minimum user-visible vertical slices.

This checkpoint is suitable for local owner acceptance testing after the current
Strength slice commit is pushed. It is still not a TestFlight/App Store release
candidate.

- VO2 max
- Zone 2
- Strength

## What Is Testable Now

- Single-workout analysis detail view.
- Zone 2 / VO2 interval / Strength reasons and recommendations.
- Training metric disclosure in single-workout analysis:
  - estimate / measured status
  - method label
  - confidence reason
  - recommended validation direction
- Scalar VO2 max estimate display when an imported workout includes a VO2 max
  value:
  - source labeling
  - estimate-only disclosure for product / field estimates
  - no lab-equivalent claim unless source is direct CPET/GXT gas analysis
- Personalized Zone 2 settings:
  - manual Zone 2 bounds
  - Resting HR suggestion
  - apply suggestion
  - reset to default bounds
  - policy source shown in single-workout and weekly summary context
- Structured Strength metric display when an imported workout includes direct
  1RM / e1RM style data:
  - exercise-specific value display
  - source labeling
  - measured / estimate disclosure by method
  - no whole-body or clinical strength diagnosis claim
- Weekly dashboard existing behavior.
- HealthKit / Strava / JSON import paths already validated earlier in Phase E.

## Feature-Complete Test Gate

Formal product testing should start only after all three pillars below have a
user-visible vertical slice.

### VO2 Max

Required before formal testing:

- A user-visible VO2 max estimate/import surface.
- Clear source labeling: lab-measured, product estimate, field estimate, or
  unknown provenance.
- Metadata disclosure showing method tier, confidence, and claim ceiling.
- Trend or latest-value rendering that never claims lab-equivalent truth unless
  the source is direct CPET/GXT gas analysis.

Current status:

- Feature-complete for the minimum imported scalar estimate slice.
- JSON import can carry `vo2MaxEstimate`.
- Single-workout UI can show the imported VO2 max estimate and claim-bounded
  disclosure.
- Existing VO2 interval path remains `vo2_interval_quality`; it is not reused as
  scalar VO2 max.
- Trend rendering is still intentionally minimal.

### Zone 2

Required before formal testing:

- Manual Zone 2 bounds.
- Resting HR suggestion / apply / reset.
- Single-workout analysis uses the selected policy.
- Weekly summary uses the selected policy.
- User-visible disclosure explains estimate / starting-point status.

Current status:

- Feature-complete for heuristic / personalized bounds.
- Still must not claim exact LT1/VT1 threshold unless validated by a threshold
  source.

### Strength

Required before formal testing:

- A user-visible strength metric surface beyond heart-rate session pattern.
- At minimum, support direct 1RM, e1RM, or structured strength-log input with
  exercise/protocol context.
- Metadata disclosure showing method, confidence, and claim ceiling.
- UI must distinguish strength-session pattern from measured strength.

Current status:

- Feature-complete for the minimum structured metric slice.
- JSON import can carry `strengthMetrics`.
- Single-workout UI can show an exercise-specific direct 1RM / e1RM style value.
- Analysis disclosure distinguishes structured strength metrics from
  heart-rate-based strength-session pattern.

## What Is Not Claimed Yet

- No TestFlight build has been produced by this checkpoint.
- No App Store release readiness claim.
- No VO2 max lab-equivalent claim for product / field / unknown estimates.
- No exact Zone 2 threshold measurement.
- No whole-body strength diagnosis or clinical strength interpretation.
- No weekly metadata disclosure UI yet.
- No Garmin integration.

## Claim Ceiling

The current app can say:

- "This workout analysis used these metric metadata assumptions."
- "This output is an estimate / starting point / observation depending on method."
- "Imported VO2 max values are estimates unless the source is direct CPET/GXT
  gas analysis."
- "Current VO2 interval path describes interval quality, not VO2 max."
- "Imported Strength metrics are exercise-specific measurements or estimates,
  depending on method."
- "Current heart-rate-only Strength path describes session pattern, not strength
  output."

The current app must not say:

- "VO2 max measured."
- "Lab-equivalent."
- "Exact Zone 2."
- "Optimal Zone 2."
- "Whole-body strength diagnosed."
- "Clinical strength diagnosis."

## Recommended Local Smoke Test

Run:

```bash
swift test --filter 'testJSONWorkoutRepositoryLoadsImportedWorkouts|testImportedVO2MaxEstimateAddsScalarMetadataWithoutReplacingIntervalQuality|testMetricDisclosurePresenterRendersVO2MaxEstimateAsEstimate|testStructuredStrengthMetricAddsMeasurementMetadataWithoutReplacingHeartRatePattern|testMetricDisclosurePresenterRendersStrengthMetricAsExerciseSpecificEstimate|testValidationDatasetMatchesExpectedVerdicts'
```

Optional broader guard:

```bash
bash scripts/meta_closeout.sh
```

## Manual Test Checklist

1. Launch the app from Xcode or SwiftPM-supported host target.
2. For JSON-import testing, place `SampleData/workouts.example.json` into the
   app container Documents path as `workouts.json`; it contains Zone 2, VO2 max
   estimate, and Strength e1RM sample workouts.
3. Open a Zone 2 workout.
4. Confirm the detail view shows "分析依據揭露".
5. Confirm Zone 2 disclosure says it is a starting reference / estimate, not exact.
6. Open a workout with imported VO2 max estimate data and confirm the metrics
   grid says "VO2 max 估算".
7. Confirm disclosure says "最大攝氧量估算" with source and estimate wording,
   not VO2 max measurement.
8. Open a VO2 interval workout without scalar VO2 max data.
9. Confirm disclosure says "VO2 間歇型態", not VO2 max measurement.
10. Open a Strength workout.
11. Confirm a workout with imported strength metric data shows an
    exercise-specific value such as "Back Squat e1RM".
12. Confirm disclosure says "肌力指標" and uses estimate / measured wording by
    source.
13. Confirm a heart-rate-only Strength workout still says "肌力訓練型態" rather
    than strength measurement.
14. Change Zone 2 bounds manually and verify single-workout analysis uses the updated bounds.
15. Generate/apply/reset Resting HR suggestion and confirm the policy source text updates.
16. Open weekly dashboard and confirm existing weekly rendering still loads.

## Exit Criteria For First Tester Feedback

This candidate is useful if the tester can answer:

- Are the disclosure labels understandable?
- Does the app avoid sounding like it measured VO2 max / exact Zone 2 / whole-body strength?
- Does personalized Zone 2 setup feel discoverable?
- Does the detail view feel too crowded after adding disclosure?
- Does weekly dashboard still feel stable and unchanged?

## Next Step

- Run the recommended local smoke test and then decide whether to produce an
  installable local/TestFlight candidate.
