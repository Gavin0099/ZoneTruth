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
