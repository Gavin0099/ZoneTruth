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

- Not feature-complete.
- Existing VO2 path is `vo2_interval_quality`, not scalar VO2 max.

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
- No scalar VO2 max estimate or import flow.
- No exact Zone 2 threshold measurement.
- No 1RM, e1RM, force output, or validated strength measurement.
- No weekly metadata disclosure UI yet.
- No Garmin integration.

## Claim Ceiling

The current app can say:

- "This workout analysis used these metric metadata assumptions."
- "This output is an estimate / starting point / observation depending on method."
- "Current VO2 path describes interval quality, not VO2 max."
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
swift test --filter 'testMetricDisclosurePresenterRendersBoundedEstimateLanguage|testMetricDisclosurePresenterUsesMetricSpecificClaimProfiles|testMetricDisclosureCardViewSmokeCompiles|testWeeklyRenderingContainsNoMetricMeasurementClaims|testWeeklyDashboardViewSmokeCompiles|testValidationDatasetMatchesExpectedVerdicts'
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
5. Open a VO2 interval workout.
6. Confirm disclosure says "VO2 間歇型態", not VO2 max measurement.
7. Open a Strength workout.
8. Confirm disclosure describes heart-rate pattern, not 1RM or strength measurement.
9. Change Zone 2 bounds manually and verify single-workout analysis uses the updated bounds.
10. Generate/apply/reset Resting HR suggestion and confirm the policy source text updates.
11. Open weekly dashboard and confirm existing weekly rendering still loads.

## Exit Criteria For First Tester Feedback

This candidate is useful if the tester can answer:

- Are the disclosure labels understandable?
- Does the app avoid sounding like it measured VO2 max / exact Zone 2 / strength?
- Does personalized Zone 2 setup feel discoverable?
- Does the detail view feel too crowded after adding disclosure?
- Does weekly dashboard still feel stable and unchanged?

## Next Candidate

The next test candidate should be one of:

- `TC-2 VO2 max vertical slice`: add scalar VO2 max estimate/import surface with
  claim-bounded disclosure.
- `TC-2 Strength vertical slice`: add structured strength metric input/display
  with claim-bounded disclosure.
- `TC-2 Zone 2 completion polish`: only if Zone 2 needs final wording or weekly
  disclosure before formal testing.
