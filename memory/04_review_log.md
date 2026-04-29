# Review Log

## Entries

- Append review summaries and validation history here.
- 2026-04-24: Reviewed PLAN.md and aligned implementation to the stated product boundary.
- 2026-04-24: Replaced broader multi-intent analyzer logic with a Zone 2-first core using policy-based sample sanitization, Zone 3 leakage, HR stability, and HR drift.
- 2026-04-24: Added `SampleWorkoutCases` and revised unit tests to cover pass, warning, fail, activity review, and sample sanitization behavior.
- 2026-04-24: Updated SwiftUI mock app to consume the new `WorkoutInput` and `AnalysisResult` model while keeping UI scope non-authoritative.
- 2026-04-24: Upgraded `SampleWorkoutCases` into labeled validation cases, wired preview UI to reuse them, fixed package compile issues (`WorkoutInput: Hashable`, cross-platform SwiftUI background colors), and confirmed `swift test` passes with 7/7 tests.
- 2026-04-24: Added `JSONWorkoutRepository` and `FallbackWorkoutRepository` in the app layer, introduced `SampleData/workouts.example.json` as the first import contract example, added app-level import tests, and confirmed `swift test` passes with 10/10 tests.
- 2026-04-24: Added `HealthKitWorkoutStore`, `SystemHealthKitWorkoutStore`, and `HealthKitWorkoutRepository` as the first Apple Health adapter skeleton, switched app environment loading to a composite source chain (HealthKit -> JSON -> mock), added adapter tests, and confirmed `swift test` passes with 12/12 tests.
- 2026-04-24: Extended the HealthKit adapter with async authorization and refresh boundaries, updated the view model and root view to support refresh-driven loading, added async adapter tests, and confirmed `swift test` passes with 13/13 tests.
- 2026-04-24: Replaced the HealthKit fetch placeholder with real `HKSampleQuery`-based workout and heart-rate loading helpers, added workout activity type mapping into domain types, and confirmed `swift test` still passes with 13/13 tests.
- 2026-04-24: Added source-aware load metadata (`WorkoutLoadResult`), updated repositories to report fallback reasons, surfaced the active source in the list UI, expanded tests for source/status behavior, and confirmed `swift test` still passes with 13/13 tests.
- 2026-04-24: Added an explicit Apple Health access action wired through repository capabilities, updated the banner UI to request authorization, added authorization-flow tests across HealthKit/composite/view model paths, and confirmed `swift test` passes with 16/16 tests.
- 2026-04-24: Added a first-pass Strava adapter skeleton (`StravaClient`, `StravaSessionStore`, `StravaActivityRepository`), wired it into app environment fallback order, introduced a sample session file contract, added Strava repository tests, and confirmed `swift test` passes with 18/18 tests.
- 2026-04-24: Added Strava OAuth contract models and parsers for mobile authorization URLs, callback handling, and token exchange payloads, added contract-focused tests, and confirmed `swift test` passes with 22/22 tests.
- 2026-04-24: Implemented real `SystemStravaOAuthClient` (URLSession POST to `/oauth/v3/token`, form-encoded body, HTTP error surfacing). Added `saveSession(_:)` to `StravaSessionStore` protocol and implemented it in `FileStravaSessionStore` (atomic write via `JSONEncoder.zoneTruth`). Made `StravaTokenExchangeResponse.athlete` optional so the same type handles both exchange and refresh responses. Build passes.
- 2026-04-24: Added `StravaCallbackHandler` to coordinate URL parsing → token exchange → session persistence. Wired `AppEnvironment` to share a single `FileStravaSessionStore` between `SystemStravaClient` and the handler. Added `.onOpenURL` in `ZoneTruthApp` that calls `refreshWorkouts()` on success. `swift test` passes with 27/27 tests.
- 2026-04-24: Added session auto-refresh to `SystemStravaClient`: expired token triggers `refreshToken` call, preserves `athleteID` from old session, writes new session atomically, then continues fetch. Three new tests cover: auto-refresh success, no refresh token, no configuration. `swift test` passes with 30/30 tests.
- 2026-04-24: Implemented real `fetchRecentActivities`: GET `/api/v3/athlete/activities`, then per-activity GET `/api/v3/activities/{id}/streams` for heart-rate. Added `StravaActivitySummary`, `StravaActivityStreams` decoders. Added sport_type → WorkoutType mapping covering Run/Ride/Swim/Walk/Hike/WeightTraining/Crossfit etc. Added README.md. `swift test` passes with 31/31 tests.
- 2026-04-24: Added "Connect Strava" button to the banner UI. `AppEnvironment` exposes `stravaAuthorizationURL`; `WorkoutListViewModel` gains `stravaAuthorizationURL` + `canConnectStrava`; `WorkoutSourceBannerView` opens the OAuth URL via `@Environment(\.openURL)`. Button hidden when Strava is already the active source. `swift test` passes with 33/33 tests.
- 2026-04-24: Sparse HR early return in `Zone2QualityAnalyzer` (no misleading stability/drift analysis when sample count too low). Added 3 edge-case labeled samples: sparse_hr_cycling, high_drift_zone2_ride, unstable_zone2_run. Added Info.plist with zonetruth:// URL scheme + HealthKit usage strings; Package.swift excludes it from SPM processing. `swift test` passes with 36/36 tests.
## Promotion: Refine analyzer logic for sparse HR data and strength training classification.
- Approved by: governance-auto
- Candidate: /Users/gavin_wu/Desktop/ZoneTruth/memory/candidates/session_20260428T103604Z.json
- Risk: low
- Oversight: auto

## Promotion: Refine analyzer logic for sparse HR data and strength training classification.
- Approved by: governance-auto
- Candidate: /Users/gavin_wu/Desktop/ZoneTruth/memory/candidates/session_20260428T104109Z.json
- Risk: low
- Oversight: auto

## Promotion: Refine analyzer logic for sparse HR data and strength training classification.
- Approved by: governance-auto
- Candidate: /Users/gavin_wu/Desktop/ZoneTruth/memory/candidates/session_20260428T104144Z.json
- Risk: low
- Oversight: auto

## Promotion: Implement Automatic Threshold Calibration (Phase 5) and finalize governance verification.
- Approved by: governance-auto
- Candidate: /Users/gavin_wu/Desktop/ZoneTruth/memory/candidates/session_20260429T030835Z.json
- Risk: low
- Oversight: auto

