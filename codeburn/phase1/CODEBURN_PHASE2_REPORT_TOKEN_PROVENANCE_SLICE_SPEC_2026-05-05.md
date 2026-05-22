# CodeBurn Phase 2 Report Token Provenance Slice Spec (2026-05-05)

## Problem
The current highest-risk gap is not missing token math. It is human misinterpretation on the report surface.

`codeburn_report.py` currently exposes `token_observability_level` to reviewer-facing output, but it does not yet disclose provenance on that same surface.

This creates a specific semantic risk:

- reviewers may read `step_level` as high-trust or provider-only telemetry
- current runtime/report output does not yet expose `token_source_summary`
- current runtime/report output does not yet expose `provenance_warning`

As a result, the report surface can over-signal fidelity even when provenance is mixed or incomplete.

## Target Outcome
Land the smallest runtime slice that reduces human-facing provenance misinterpretation on the report surface without expanding decision authority.

This slice is successful when `codeburn_report.py` can disclose mixed provenance directly in reviewer-facing output while preserving the current advisory-only boundary.

## Scope
In scope:

- `codeburn/phase1/codeburn_report.py` only
- report JSON output
- report text output
- report-only provenance disclosure for token telemetry
- report tests needed to prove the new disclosure is present and decision posture is unchanged

## Non-goals
Out of scope:

- `codeburn_analyze.py`
- gate logic or gate policy changes
- schema migration
- decision authority changes
- `comparability_token` redesign
- provider coverage ratio
- new authority-granting machine interpretation

## Affected Surfaces
Primary implementation surface:

- `codeburn/phase1/codeburn_report.py`

Likely adjacent validation surfaces:

- `tests/test_codeburn_phase1_report.py`
- `codeburn/phase1/DATA_VALIDITY_CONTRACT.md` only if the runtime-valid report contract requires a narrow wording update
- `codeburn/phase1/TOKEN_TELEMETRY_CONTRACT_V0_1.md` only if the implemented field names must be reconciled with the current design contract language

## Boundary And API Considerations
Current local report truth:

- `build_report()` emits `token_observability_level`
- `build_report()` emits `decision_usage_allowed = False`
- `_print_text()` renders `Token observability level: ...`
- no provenance disclosure is currently emitted on either JSON or text surface

This slice must preserve the existing Phase 1/2 authority boundary:

- `decision_usage_allowed` remains `false`
- `analysis_safe_for_decision` remains `false`
- provenance disclosure increases truthfulness only; it does not increase machine authority

Proposed minimum runtime fields for the report surface:

- `token_source_summary`
- `provenance_warning`

Proposed minimum interpretation rule:

- if report surface shows `token_observability_level = step_level` and provenance is mixed, the same report surface must also show `token_source_summary = mixed(...)`
- mixed-source `step_level` must also show `provenance_warning = mixed_sources`
- absence of `provenance_warning` must not be reinterpreted as provider-only authority

## Failure Paths And Risk Points
Primary risk points for this slice:

- JSON output adds provenance fields but text output does not, leaving reviewer-facing ambiguity intact
- text output adds a generic warning but omits `token_source_summary`, forcing reviewers to infer provenance
- mixed-source report output is present but changes are mirrored into `analyze`, accidentally expanding machine interpretation scope
- implementation treats absence of provider data as authority downgrade logic instead of disclosure logic

Specific failure conditions for review:

- report can still display `step_level` without any provenance disclosure on a mixed-source session
- `decision_usage_allowed` changes from `false`
- new fields imply provider-only trust when provenance is mixed

## Evidence Plan
Minimum validation evidence for this slice:

- narrow report tests proving mixed-source step-level output includes `token_source_summary`
- narrow report tests proving mixed-source step-level output includes `provenance_warning = mixed_sources`
- narrow report tests proving `decision_usage_allowed` stays `false`
- narrow text-surface test proving reviewer-facing output shows the same provenance disclosure, not JSON-only disclosure

Suggested executable validation target:

- `pytest tests/test_codeburn_phase1_report.py`

If text rendering and JSON rendering are split in tests, both surfaces must be covered explicitly.

## Acceptance Criteria
This slice is complete only if all of the following are true:

1. Mixed + step-level report output displays `token_source_summary = mixed(...)`.
2. Mixed + step-level report output displays `provenance_warning = mixed_sources`.
3. `decision_usage_allowed` remains `false`.
4. Absence of `provenance_warning` is not treated as provider-only by the implemented report logic or reviewer-facing output.

## Implementation Tranche Recommendation
Recommended first tranche:

1. Add the smallest provenance summarization helper needed by `codeburn_report.py`.
2. Emit `token_source_summary` and `provenance_warning` in report JSON.
3. Render the same provenance disclosure in report text.
4. Add narrow tests for mixed-source step-level disclosure and unchanged decision boundary.

Explicit defer:

- do not modify `codeburn_analyze.py` in the same slice
- do not add schema-level provenance ratio fields in the same slice
- do not combine this slice with gate, policy, or authority work

## Why Report First
`analyze` is primarily a machine-consumable interpretation surface.

`report` is the reviewer-facing surface where the current highest-value fix lives, because the main risk is human shortcut reading:

- `step_level -> must be high trust`

Therefore the first runtime slice should reduce reviewer misinterpretation before it expands machine-readable telemetry semantics elsewhere.

## Status: IMPLEMENTED — Scope Lock

Implemented: 2026-05-05 (commit 7aa5761)

This slice is closed. The scope lock that must survive any future resumption:

> **Report provenance disclosure is human-facing only.**
> It is not a new decision input.

This means:

- `token_source_summary` and `provenance_warning` in report output are for reviewer interpretation only
- they must not be consumed by gate logic, decision authority checks, or automated policy enforcement
- adding these fields to `analyze` output would require a separate explicitly-scoped slice with its own evidence plan
- the current report surface increase in truthfulness does NOT change `decision_usage_allowed`, `analysis_safe_for_decision`, or any gate threshold

If a future slice needs to extend provenance disclosure to `codeburn_analyze.py`, it must open a new spec, not amend this one.

### Reverse Constraint

Report-level provenance fields (`token_source_summary`, `provenance_warning`) MUST NOT be consumed by any automated decision, analysis, or gating logic.

They are strictly human-facing disclosure artifacts.

Any machine-level use of provenance signals requires a separate contract and a dedicated machine surface (e.g., a future `analyze` provenance slice). Using report fields as a substitute for that surface — even transiently — is a boundary violation regardless of test pass status.

Rationale: the forward constraints above prevent this slice from expanding toward decision authority. The reverse constraint prevents other code from reading this slice's output as if it were decision authority. Both directions must be closed for the boundary to hold.