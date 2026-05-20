# Active Task

## Current Status

- Reframed the project around the latest PLAN.md.
- Built the first Zone 2 judgment core around explainable session-level signals.
- Kept the SwiftUI skeleton as a mock-data shell, but reduced MVP logic to Zone 2 and Activity / Skill review.
- Added a labeled validation dataset for pass / warning / fail / activity-review cases and verified it with `swift test`.
- Added an app-side JSON import adapter with fallback to mock data so real samples can be fed into the existing analyzer without changing domain logic.
- Added a HealthKit adapter skeleton in the app layer so future Apple Health reads can map into `WorkoutInput` without leaking native types into the core.
- Added async HealthKit authorization / refresh boundaries so the app now has the right shape for real Apple Health queries.
- Implemented the first real HealthKit query path for recent workouts and time-bounded heart-rate samples inside the adapter boundary.
- Added source-aware loading metadata so the UI can show whether data came from Apple Health, imported JSON, or preview samples.
- Added an explicit Apple Health authorization action so the app can request permission instead of only waiting for passive refresh.
- Added a Strava adapter skeleton with session-file loading, activity snapshot mapping, and repository integration, while keeping OAuth/network work deferred.
- Added Strava OAuth contract models for authorization URLs, callback parsing, and token exchange/refresh payloads so the integration boundary is now shaped around the official flow.
- Implemented real `SystemStravaOAuthClient` with URLSession token exchange/refresh, added `saveSession(_:)` to `StravaSessionStore`/`FileStravaSessionStore`, and made `StravaTokenExchangeResponse.athlete` optional to unify exchange and refresh response types.
- Added `StravaCallbackHandler` (URL parse → exchange → save), shared `FileStravaSessionStore` instance in `AppEnvironment`, and wired `.onOpenURL` in `ZoneTruthApp` to call `refreshWorkouts()` on success.
- Added session auto-refresh inside `SystemStravaClient.fetchRecentActivities`: expired token calls `refreshToken`, carries over `athleteID`, writes new session, then continues.
- Implemented real `fetchRecentActivities`: activity list + per-activity heart-rate streams, sport_type mapping, graceful fallback to empty HR when stream unavailable.
- Added README.md covering architecture, data sources, analysis policy, Strava setup, and JSON import format.
- Added "Connect Strava" button in the banner: `AppEnvironment.stravaAuthorizationURL` → `WorkoutListViewModel.canConnectStrava` → `WorkoutSourceBannerView` opens OAuth URL via `@Environment(\.openURL)`.
- Sparse HR early return in `Zone2QualityAnalyzer`: no misleading stability/drift analysis when sample count too low; returns clear "too low" reason instead.
- Added 3 edge-case labeled samples (sparse HR, high drift low leakage, unstable but Zone 2) and 3 matching core tests.
- Created `Info.plist` with `zonetruth://` URL scheme and HealthKit usage strings; `Package.swift` excludes it from SPM processing (Xcode picks it up automatically).
- Added `WorkoutEvaluation` model and adapter mapping from legacy `AnalysisResult` to semantic-first output (`primaryIntent` baseline, `trainingTendency`, `goalFitScore`, split confidences).
- Wired `WorkoutEvaluation` into ViewModel/UI with legacy pass/fail downgraded to secondary detail.
- Added semantic consistency guard tests to ensure tendency/action coherence, non-harsh failure tone, confidence separation, and finding priority.
- Added `WorkoutEvaluation` snapshot fixture coverage for five canonical scenarios and fixture refresh path via `UPDATE_WORKOUT_EVAL_FIXTURE=1`.
- Completed P1a Observation/Policy boundary guard:
  - Observation shape now excludes verdict/reason/recommendation fields.
  - Policy layer owns tendency/goal-fit/next-action generation.
  - Added boundary guard tests to prevent semantic backsliding.
- Completed P1b minimum parallel path:
  - Added `Zone2ObservationAnalyzer` with observation-only output (`zoneDistribution`, `driftRatio`, `stabilityStandardDeviation`, `sampleQuality`).
  - Analyzer explicitly avoids pass/fail, recommendation, and user-facing judgment fields.
- Completed P1c observation fixture baseline:
  - Added `Tests/ZoneTruthCoreTests/Fixtures/zone2_observation_snapshot.json`.
  - Added independent update flag `UPDATE_ZONE2_OBSERVATION_FIXTURE=1`.
- Completed P1d VO2 observation parallel path:
  - Added `VO2ObservationAnalyzer` with observation-only output (`zoneDistribution`, `highIntensityRatio`, `peakZoneRatio`, `intervalPatternHint`, `sampleQuality`).
  - Added `Tests/ZoneTruthCoreTests/Fixtures/vo2_observation_snapshot.json`.
  - Added independent update flag `UPDATE_VO2_OBSERVATION_FIXTURE=1`.

## Next Steps

- Open Package.swift in Xcode and verify Info.plist is picked up; run on real device with Strava credentials.
- Consider adding VO2/Interval and Strength analysis paths beyond the current "outside MVP scope" placeholder.
- Add personalized zone bounds via user settings (Resting HR, Zone 2 lower/upper bound inputs).
- Validate the HealthKit query path on-device and decide how to handle workouts with sparse or missing heart-rate samples.
- Expand the labeled case dataset with more edge cases near drift and leakage thresholds.
- Validate the HealthKit query path on-device and decide how to handle workouts with sparse or missing heart-rate samples.
- Expand the labeled case dataset with more edge cases near drift and leakage thresholds.
- [x] Promoted memory: Refine analyzer logic for sparse HR data and strength training classification.
- [x] Promoted memory: Refine analyzer logic for sparse HR data and strength training classification.
- [x] Promoted memory: Refine analyzer logic for sparse HR data and strength training classification.
- [x] Promoted memory: Implement Automatic Threshold Calibration (Phase 5) and finalize governance verification.
- Refactored `ZoneTruthApp` to a library and created `ZoneTruthHost` Xcode project wrapper to enable proper HealthKit capability signing on physical iOS devices, integrating it into the repository structure.
- Garmin status: not yet integrated; current sources remain HealthKit + Strava + JSON import. Garmin deferred until post-MVP semantic/model stabilization.
