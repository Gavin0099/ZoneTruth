# Knowledge Base

## Gotchas

- Record troubleshooting notes, anti-patterns, and fixes here.
- The latest PLAN.md narrows MVP scope to Zone 2 judgment plus basic activity review.
- VO2 / Interval and Strength are intentionally deferred because heart rate alone is not trusted enough for first-pass verdicts.
- The useful core signals for MVP are zone distribution, Zone 3 leakage, HR stability, and HR drift.
- Analysis should stay session-level and explainable; avoid pretending heart rate is ground truth.
- This environment does have a usable Swift toolchain, but `swift test` may need to run outside the sandbox because SwiftPM and clang cache directories are not writable inside the default sandbox.
- `SampleWorkoutCases` now acts as a labeled validation dataset, not just mock workouts, and is safe to reuse in both tests and preview UI.
- Real sample import currently lives in the app adapter layer through `JSONWorkoutRepository`, which reads `SampleData/workouts.json` and falls back cleanly to mock data on missing or invalid files.
- HealthKit integration is now split into `HealthKitWorkoutStore` and `HealthKitWorkoutRepository`; native access remains isolated in the store, while the repository only maps authorized snapshots into domain inputs.
- The app-side repository flow now supports async refresh, and `WorkoutListView` triggers a refresh task so authorized HealthKit data can replace fallback data later without changing the screen structure.
- `SystemHealthKitWorkoutStore.fetchRecentWorkouts(limit:)` now uses `HKSampleQuery` wrappers to load recent workouts and then fetch heart-rate quantity samples in each workout time window before mapping them into `HealthKitWorkoutSnapshot`.
- Repository loading now returns `WorkoutLoadResult`, which carries both workouts and source/status metadata so fallback behavior is visible in the UI instead of being silent.
- Health access requests now flow through the same repository boundary (`requestHealthAccess`) so UI code can trigger authorization without importing or depending on HealthKit types.
- Strava now has a parallel adapter boundary (`StravaClient`, `StravaSessionStore`, `StravaActivityRepository`) and reads an optional `SampleData/strava-session.json` session file, but network fetching is still intentionally unimplemented.
- Strava OAuth specifics are now modeled explicitly with `StravaOAuthConfiguration`, `StravaAuthorizationParser`, and token exchange request/response types, using the official short-lived token + refresh token flow.
- `WeeklyObservationBuilder.build(..., policy:)` must receive `settingsManager.policy` if weekly charts are expected to reflect user-customized Zone 2 bounds; otherwise the dashboard silently stays on `AnalysisPolicy.default`.
- Large SwiftUI setting screens can trigger "compiler is unable to type-check this expression in reasonable time"; the reliable fix here is to split the `body` into smaller computed subviews/bindings instead of trying to tweak the expression inline.
- The current Resting HR personalization heuristic is intentionally bounded and non-verified: `zone2Lower = restingHR + 55`, `zone2Upper = restingHR + 70`, with upper-zone gaps preserved forward for Zone 4/5 thresholds. Treat it as a starting suggestion, not a validated physiological threshold.
## Refine analyzer logic for sparse HR data and strength training classification.
- Captured: 2026-04-28T10:36:04.239225+00:00
- Approved by: governance-auto
- Risk: low
- Oversight: auto
- Summary: Refine analyzer logic for sparse HR data and strength training classification.

## Refine analyzer logic for sparse HR data and strength training classification.
- Captured: 2026-04-28T10:41:09.161990+00:00
- Approved by: governance-auto
- Risk: low
- Oversight: auto
- Summary: Refine analyzer logic for sparse HR data and strength training classification.

## Refine analyzer logic for sparse HR data and strength training classification.
- Captured: 2026-04-28T10:41:44.148848+00:00
- Approved by: governance-auto
- Risk: low
- Oversight: auto
- Summary: Refine analyzer logic for sparse HR data and strength training classification.

## Implement Automatic Threshold Calibration (Phase 5) and finalize governance verification.
- Captured: 2026-04-29T03:08:35.926045+00:00
- Approved by: governance-auto
- Risk: low
- Oversight: auto
- Summary: Implement Automatic Threshold Calibration (Phase 5) and finalize governance verification.
