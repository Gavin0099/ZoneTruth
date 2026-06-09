---
audience: owner, agent-runtime
authority: product-acceptance
status: accepted
last_updated: 2026-06-09
---

# Zone 2 Feature Gate Checklist

This checklist closes the minimum Zone 2 feature-complete gate for local product
acceptance. It is an acceptance contract, not a new product surface.

## Scope

Zone 2 is feature-complete for the current release candidate when these paths are
present and covered:

- Manual Zone 2 lower / upper bounds can be saved and used by analysis policy.
- Resting HR can be stored, used to generate heuristic Zone 2 bounds, and applied.
- Resting HR suggestion offsets can be adjusted before applying the suggestion.
- Zone 2 bounds can be reset to the default policy.
- Single workout detail can show which Zone 2 policy source is currently used.
- Weekly zone distribution recomputes from the current Zone 2 policy.
- Resetting Zone 2 bounds restores the weekly distribution to default-policy behavior.

## Claim Boundary

Allowed wording:

- `Zone 2`
- `Zone 2 心率範圍`
- `預設界線`
- `自訂界線`
- `Resting HR 建議已套用`
- `非驗證閾值`

Forbidden wording:

- `精準 Zone 2`
- `exact Zone 2`
- `最佳區間`
- `optimal Zone 2`
- `已量測 LT1`
- `lab-equivalent`

The current app may display the configured bpm range, but it must not claim that
the range is a lab-verified or exact physiological threshold.

## Evidence

Existing automated coverage:

- `testSettingsManagerPersistsRestingHeartRate`
- `testSettingsManagerGeneratesAndAppliesRestingHeartRateSuggestion`
- `testSettingsManagerGeneratesSuggestionFromCustomRestingHeartRateOffsets`
- `testZone2ProfileStatusSummaryTracksSettingsState`
- `testSettingsManagerResetsZone2BoundsToDefault`
- `testWeeklySummaryRecomputesZoneDistributionFromCustomPolicy`
- `testWeeklySummaryReturnsToDefaultPolicyAfterReset`
- `testWorkoutDetailZoneContextSummaryTracksPolicySource`
- `testWorkoutAnalysisDisclosureItemsRespectMetricSpecificClaimProfiles`

Manual owner acceptance coverage:

- `docs/OWNER_ACCEPTANCE_2026-06-05.md`, section `Zone 2`

## Out Of Scope

This gate does not add:

- new classifier behavior
- new SwiftUI sections
- weekly dashboard rendering changes
- training plan / target compliance language
- exact threshold or medical-grade claims
