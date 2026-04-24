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
