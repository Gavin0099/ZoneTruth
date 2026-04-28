# AGENTS.md
<!-- governance-baseline: overridable -->
<!-- baseline_version: 1.0.0 -->
<!-- This file is repo-specific. Edit freely. -->
<!-- DO NOT edit AGENTS.base.md — it is a protected framework file. -->

This file extends `AGENTS.base.md`.
All rules in `AGENTS.base.md` are non-negotiable and apply to this repo unconditionally.

Add repo-specific rules below.
Fill in each section below, or write `N/A` if the section is not applicable to this repo.

Quick start:

1. Start with the top 1-3 risky paths in this repo, not a full policy rewrite.
2. If you already have a checklist / runbook / test convention, copy that wording here instead of inventing new terms.
3. If a section truly does not apply, keep `N/A` and move on.

---

## Repo-Specific Risk Levels
<!-- governance:key=risk_levels -->

- **HIGH**: Any change to `Analyzers.swift` core logic or `AnalysisPolicy` thresholds. These affect the primary verdict (Pass/Fail) and are critical to the app's correctness.
- **MEDIUM**: Adding new workout intents or modifying `RecommendationEngine.swift` logic.
- **LOW**: UI styling, layout tweaks, or documentation-only changes.

## Must-Test Paths
<!-- governance:key=must_test_paths -->

- `Sources/ZoneTruthCore/Analyzers.swift`: Any change must be verified against the full `SampleWorkoutCases` suite.
- `Sources/ZoneTruthCore/RecommendationEngine.swift`: Must ensure recommendations align with the analyzer's output reasons.

## L1 → L2 Escalation Triggers
<!-- governance:key=escalation_triggers -->

- Modifying `AGENTS.base.md` or any "protected" file listed in `.governance/baseline.yaml`.
- Changing the analysis core in a way that significantly deviates from the original `plan.md` intent.
- Introducing external dependencies to the `ZoneTruthCore` package.

## Repo-Specific Forbidden Behaviors
<!-- governance:key=forbidden_behaviors -->

- Do not introduce Apple-specific frameworks (HealthKit, SwiftUI) into the `ZoneTruthCore` directory.
- Do not modify `SampleWorkoutCases.swift` without also updating the corresponding tests in `ZoneTruthCoreTests.swift`.
