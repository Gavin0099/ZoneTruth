# Active Task

## Current Status

- Reframed the project around the latest PLAN.md.
- Built the first Zone 2 judgment core around explainable session-level signals.
- Kept the SwiftUI skeleton as a mock-data shell, but reduced MVP logic to Zone 2 and Activity / Skill review.
- Added a labeled validation dataset for pass / warning / fail / activity-review cases and verified it with `swift test`.
- Added an app-side JSON import adapter with fallback to mock data so real samples can be fed into the existing analyzer without changing domain logic.
- Added a HealthKit adapter skeleton in the app layer so future Apple Health reads can map into `WorkoutInput` without leaking native types into the core.
- Added async HealthKit authorization / refresh boundaries so the app now has the right shape for real Apple Health queries.

## Next Steps

- Expand the labeled case dataset with more edge cases near drift and leakage thresholds.
- Define the first user-facing import contract from exported workout data into `WorkoutInput`.
- Implement real `HKWorkout` and heart-rate sample queries inside `SystemHealthKitWorkoutStore.fetchRecentWorkouts(limit:)`.
- Add HealthKit adapters only after Zone 2 judgment feels trustworthy on fixed cases.
