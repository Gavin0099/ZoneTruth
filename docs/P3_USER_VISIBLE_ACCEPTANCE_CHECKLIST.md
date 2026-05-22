# P3 User-Visible Acceptance Checklist (P3d/P3e)

Last updated: 2026-05-22
Owner: ZoneTruth Product + Core
Status: Accepted

## Scope

This checklist validates user-visible behavior for:

- P3d Authority Rendering System
- P3e Training State Machine

## A) Weekly Home Surface

- [x] Primary surface still prioritizes readiness/load/recovery guidance.
- [x] Weekly summary wording uses guidance tone, not authoritative commands.
- [x] No forbidden semantics appear in user-visible weekly cards:
- overtraining / 過度訓練 / 休息不足 / 必須 / 診斷式語氣

## B) Authority Rendering (Visual + Semantic)

- [x] `WeeklyDecisionAuthority` maps correctly from confidence + freshness:
- fresh/high confidence -> observational
- fresh/mid confidence -> bounded inference
- low confidence or stale/missing freshness -> weak inference
- [x] Low-evidence states reduce recommendation prominence:
- lower emphasis background opacity
- lower stroke opacity
- [x] Card-surface opacity is monotonic by authority:
- observational > bounded > weak
- [x] Weak-evidence cards do not present high-authority visual intensity.

## C) Freshness and Evidence Labels

- [x] Freshness chip renders one of: Data fresh / Data partial / Data stale / Data missing.
- [x] Inference chip renders one of: Bounded inference / Weak inference / Unsupported speculation.
- [x] Evidence gaps are visible inline when inference is weak/unsupported.

## D) Training State Machine (Non-binary)

- [x] Weekly training state renders within allowed state set:
- recovered / accumulating_load / functional_fatigue / possible_under_recovery / recovery_normalizing
- [x] Stale or missing evidence downgrades state rendering to `recovery_normalizing`.
- [x] Training state text avoids binary verdict framing (good/bad).
- [x] Internal `functional_fatigue` does not render as clinical certainty phrase.

## E) Adaptation Direction Guard

- [x] Adaptation direction renders with authority-bounded phrasing.
- [x] `noSignal` always renders as explicit evidence gap label.
- [x] 7d/28d temporal chips render correctly (`7d signal`, `28d unavailable`).

## F) Body Composition Context (Weekly Advanced)

- [x] Weekly Advanced card includes `BodyCompositionContextSection`.
- [x] If ledger exists, detailed per-measurement rows are viewable.
- [x] If ledger missing, user sees explicit data-unavailable guidance.
- [x] Body composition wording stays observational and non-diagnostic.

## G) Regression / Guard Scripts

- [x] `swift test` passes relevant app and core guard tests.
- [x] `bash scripts/closeout_workout_evaluation.sh` passes:
- semantic guard
- weekly UI guard
- UI smoke / compile guard
- codeburn render guard

## H) Release Gate

Ship P3d/P3e user-visible changes only when all checklist items above are complete.

Execution evidence (2026-05-22):

- `bash scripts/closeout_p3_user_visible.sh` -> passed
- `bash scripts/closeout_workout_evaluation.sh` -> passed (`codeburn_render_guard: passed`)

## Execution Command

Run:

`bash scripts/closeout_p3_user_visible.sh`

Expected final lines:

- `p3_user_visible_guard: passed`
- `authority_tests: passed`
- `freshness_tests: passed`
- `state_machine_tests: passed`
- `adaptation_guard_tests: passed`
- `body_context_tests: passed`
- `forbidden_semantics_guard: passed`
