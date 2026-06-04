# Test Candidate 2026-06-04

Status: developer checkpoint only; formal testing deferred until feature-complete
Base commit: `2843372`
Audience: owner / local tester

## Short Answer

Do not start formal product testing from this checkpoint.

This checkpoint is useful for developer verification only. Formal testing should
start after the three product pillars are feature-complete:

- VO2 max
- Zone 2
- Strength

This is not a TestFlight/App Store release candidate.

## What Is Testable Now

This section is for developer smoke only, not formal tester rollout.

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
- Trend rendering is still intentionally minimal; formal testing remains
  blocked by the Strength pillar.

### Zone 2

Required before formal testing:

- Manual Zone 2 bounds.
- Resting HR suggestion / apply / reset.
- Single-workout analysis uses the selected policy.
- Weekly summary uses the selected policy.
- User-visible disclosure explains estimate / starting-point status.

Current status:

- Mostly feature-complete for heuristic / personalized bounds.
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

- Not feature-complete.
- Existing Strength path describes heart-rate-based session pattern only.

## What Is Not Claimed Yet

- No TestFlight build has been produced by this checkpoint.
- No App Store release readiness claim.
- No VO2 max lab-equivalent claim for product / field / unknown estimates.
- No exact Zone 2 threshold measurement.
- No 1RM, e1RM, force output, or validated strength measurement.
- No weekly metadata disclosure UI yet.
- No Garmin integration.

## Claim Ceiling

The current app can say:

- "This workout analysis used these metric metadata assumptions."
- "This output is an estimate / starting point / observation depending on method."
- "Imported VO2 max values are estimates unless the source is direct CPET/GXT
  gas analysis."
- "Current VO2 interval path describes interval quality, not VO2 max."
- "Current Strength path describes heart-rate session pattern, not strength output."

The current app must not say:

- "VO2 max measured."
- "Lab-equivalent."
- "Exact Zone 2."
- "Optimal Zone 2."
- "1RM measured."
- "Strength measured."

## Recommended Local Smoke Test

Run:

```bash
swift test --filter 'testJSONWorkoutRepositoryLoadsImportedWorkouts|testImportedVO2MaxEstimateAddsScalarMetadataWithoutReplacingIntervalQuality|testMetricDisclosurePresenterRendersVO2MaxEstimateAsEstimate|testMetricDisclosurePresenterRendersBoundedEstimateLanguage|testValidationDatasetMatchesExpectedVerdicts'
```

Optional broader guard:

```bash
bash scripts/meta_closeout.sh
```

## Manual Test Checklist

1. Launch the app from Xcode or SwiftPM-supported host target.
2. Open a Zone 2 workout.
3. Confirm the detail view shows "分析依據揭露".
4. Confirm Zone 2 disclosure says it is a starting reference / estimate, not exact.
5. Open a workout with imported VO2 max estimate data and confirm the metrics
   grid says "VO2 max 估算".
6. Confirm disclosure says "最大攝氧量估算" with source and estimate wording,
   not VO2 max measurement.
7. Open a VO2 interval workout without scalar VO2 max data.
8. Confirm disclosure says "VO2 間歇型態", not VO2 max measurement.
9. Open a Strength workout.
10. Confirm disclosure describes heart-rate pattern, not 1RM or strength measurement.
11. Change Zone 2 bounds manually and verify single-workout analysis uses the updated bounds.
12. Generate/apply/reset Resting HR suggestion and confirm the policy source text updates.
13. Open weekly dashboard and confirm existing weekly rendering still loads.

## Exit Criteria For First Tester Feedback

This candidate is useful if the tester can answer:

- Are the disclosure labels understandable?
- Does the app avoid sounding like it measured VO2 max / exact Zone 2 / strength?
- Does personalized Zone 2 setup feel discoverable?
- Does the detail view feel too crowded after adding disclosure?
- Does weekly dashboard still feel stable and unchanged?

## Next Candidate

The next test candidate should be:

- `TC-2 Strength vertical slice`: add structured strength metric input/display
  with claim-bounded disclosure.
