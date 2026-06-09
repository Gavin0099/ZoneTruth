# Long-Term Memory

This file is the main-session durable memory for ZoneTruth agents. Keep it
compact: durable project context, workflow preferences, and active constraints
only. Daily event logs belong in `memory/YYYY-MM-DD.md`.

## Durable Project Context

- ZoneTruth is an iOS/macOS fitness analysis app focused on Zone 2 training
  quality, VO2 interval context, strength-related signals, weekly adaptation
  signals, and bounded governance tooling.
- The current product direction uses route C for training classification:
  infer actual training mode from Apple Watch workout type plus heart-rate
  features. It does not require pre-declared workout intent.
- Training Classification v3.1 main line is complete:
  Swift Core classification object, rule-based classifier, descriptive weekly
  training-mode distribution, swimming data-quality floor, feedback data shape,
  App feedback persistence, saved-state display, and duplicate handling.
- Zone 2 feature-complete gate is closed through
  `docs/ZONE2_FEATURE_GATE_CHECKLIST.md`: manual bounds, Resting HR suggestion /
  apply / reset, single-detail policy source, weekly policy recomputation, and
  non-exact-threshold claim boundary are accepted for local product readiness.
- Governance adoption is synced to the framework snapshot recorded in
  `governance/framework.lock.json`. Follow repo-local governance in
  `governance/AGENT.md` for engineering execution.

## Durable Workflow Preferences

- Before file edits in this repo, define a narrow measurable `DONE = ...`
  condition and stop when that DONE is achieved.
- Commit and push completed implementation-session work, then append a compact
  daily memory entry with what changed, evidence, and next step.
- Do not stage or normalize unrelated drift. The recurring
  `artifacts/governance/version_compatibility.json` timestamp-only drift should
  be left alone unless explicitly scoped.
- Prefer product vertical slices over new governance surface. New governance work
  should be failure-driven.
- User prefers continuing implementation without being asked to manually test
  until the current plan line is complete.

## Active Boundaries

- Do not call `TrainingModeClassifier` directly from SwiftUI/App rendering;
  keep classification through Core/ViewModel facades.
- Do not reintroduce user-facing `本次意圖`, `目的符合度`, or legacy verdict
  language in workout detail surfaces.
- Weekly dashboard rendering is high risk. Avoid touching
  `WeeklyDashboardView.swift`, `WeeklySignals.swift`, or
  `WeeklyRenderingContractTests.swift` unless the DONE explicitly requires it.
- Feedback is calibration data, not original workout intent. It must not rewrite
  workout intent or mutate classifier output.
- Zone 2 ranges may be shown as configured bpm ranges, but must not be described
  as exact, lab-verified, optimal, or medical-grade thresholds.

## Current Next Step

- After this memory hygiene closeout, there is no remaining open Training
  Classification v3.1 implementation line in `plan.md`. The next work item
  should be defined as a fresh narrow DONE before edits begin.
