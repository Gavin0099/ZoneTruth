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

## Next Steps

- Expand the labeled case dataset with more edge cases near drift and leakage thresholds.
- Define the first user-facing import contract from exported workout data into `WorkoutInput`.
- Validate the HealthKit query path on-device and decide how to handle workouts with sparse or missing heart-rate samples.
- Add a richer post-authorization experience, such as showing why Apple Health access failed or linking users to system settings when access is denied.
- Implement real Strava OAuth and API calls on top of the new adapter boundary.
- Add session persistence writes and real URLSession-based token exchange for Strava.
- Add HealthKit adapters only after Zone 2 judgment feels trustworthy on fixed cases.
