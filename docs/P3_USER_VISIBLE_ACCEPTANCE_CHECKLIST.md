# P3 User-Visible Acceptance Checklist (P3d/P3e)

Last updated: 2026-05-22
Owner: ZoneTruth Product + Core
Status: Active

## Scope

This checklist validates user-visible behavior for:

- P3d Authority Rendering System
- P3e Training State Machine

## A) Weekly Home Surface

- [ ] Primary surface still prioritizes readiness/load/recovery guidance.
- [ ] Weekly summary wording uses guidance tone, not authoritative commands.
- [ ] No forbidden semantics appear in user-visible weekly cards:
- overtraining / 過度訓練 / 休息不足 / 必須 / 診斷式語氣

## B) Authority Rendering (Visual + Semantic)

- [ ] `WeeklyDecisionAuthority` maps correctly from confidence + freshness:
- fresh/high confidence -> observational
- fresh/mid confidence -> bounded inference
- low confidence or stale/missing freshness -> weak inference
- [ ] Low-evidence states reduce recommendation prominence:
- lower emphasis background opacity
- lower stroke opacity
- [ ] Card-surface opacity is monotonic by authority:
- observational > bounded > weak
- [ ] Weak-evidence cards do not present high-authority visual intensity.

## C) Freshness and Evidence Labels

- [ ] Freshness chip renders one of: Data fresh / Data partial / Data stale / Data missing.
- [ ] Inference chip renders one of: Bounded inference / Weak inference / Unsupported speculation.
- [ ] Evidence gaps are visible inline when inference is weak/unsupported.

## D) Training State Machine (Non-binary)

- [ ] Weekly training state renders within allowed state set:
- recovered / accumulating_load / functional_fatigue / possible_under_recovery / recovery_normalizing
- [ ] Stale or missing evidence downgrades state rendering to `recovery_normalizing`.
- [ ] Training state text avoids binary verdict framing (good/bad).
- [ ] Internal `functional_fatigue` does not render as clinical certainty phrase.

## E) Adaptation Direction Guard

- [ ] Adaptation direction renders with authority-bounded phrasing.
- [ ] `noSignal` always renders as explicit evidence gap label.
- [ ] 7d/28d temporal chips render correctly (`7d signal`, `28d unavailable`).

## F) Body Composition Context (Weekly Advanced)

- [ ] Weekly Advanced card includes `BodyCompositionContextSection`.
- [ ] If ledger exists, detailed per-measurement rows are viewable.
- [ ] If ledger missing, user sees explicit data-unavailable guidance.
- [ ] Body composition wording stays observational and non-diagnostic.

## G) Regression / Guard Scripts

- [ ] `swift test` passes relevant app and core guard tests.
- [ ] `bash scripts/closeout_workout_evaluation.sh` passes:
- semantic guard
- weekly UI guard
- UI smoke / compile guard

## H) Release Gate

Ship P3d/P3e user-visible changes only when all checklist items above are complete.
