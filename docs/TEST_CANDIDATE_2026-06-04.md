# Test Candidate 2026-06-04

Status: ready for developer/local testing
Base commit: `2843372`
Audience: owner / local tester

## Short Answer

You can start testing the current `main` now for single-workout analysis,
personalized Zone 2 settings, and metadata disclosure.

This is not yet a TestFlight/App Store release candidate. It is a local test
candidate for validating user-visible behavior and claim boundaries.

## What Is Testable Now

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

- `TC-2 weekly disclosure`: add minimal weekly metadata disclosure under the
  existing weekly rendering guard.
- `TC-2 release packaging`: prepare an installable device/TestFlight build
  checklist and version bump.
