# CodeBurn Token Provenance — Controlled Exposure Guide (2026-05-05)

> Status: **ACTIVE — Controlled Exposure Phase**
> Scope: `codeburn_report.py` provenance disclosure fields only
> Base implementation: commit 7aa5761
> Spec: `CODEBURN_PHASE2_REPORT_TOKEN_PROVENANCE_SLICE_SPEC_2026-05-05.md`

---

## What This Is

This is a **controlled exposure**, not a rollout.

The distinction matters:

- **Rollout** = push to all repos, assume adoption is correct by default
- **Controlled exposure** = select a small number of repos, observe whether the semantics land correctly, and only widen after evidence confirms correct understanding

This phase exists because the highest risk right now is not a bug — it is **wrong adoption**. If repos start consuming `token_source_summary` or `provenance_warning` as machine inputs before the boundary is understood, the boundary is broken before it stabilizes.

---

## What Was Implemented

`codeburn_report.py` now emits two provenance disclosure fields on the report surface:

| Field | Purpose |
|-------|---------|
| `token_source_summary` | Summarizes the provenance of token data: `provider`, `estimated`, `mixed(...)`, or `unknown` |
| `provenance_warning` | Signals when provenance is not fully verified: `mixed_sources`, `provenance_unverified`, or `none` |

These fields appear in both JSON and text report output.

They are **strictly human-facing**. See the reverse constraint in the spec.

---

## Target Repo Criteria

Select 1–2 repos that meet **all** of the following:

1. A human reviewer actually reads the report output (not purely pipeline-consumed)
2. The repo has sessions with mixed or estimated token context (not all `unknown`)
3. The repo has retry, failure, or debug analysis use cases where provenance matters

Repos that produce only `token_source: unknown` will see only `provenance_warning: provenance_unverified` — this is correct but provides limited signal for the observation window.

---

## What To Do (Per Repo)

**Do:**

- Run `codeburn_report.py` as usual — the new fields appear automatically
- Read `token_source_summary` and `provenance_warning` as reviewer context
- Note whether the disclosure helps avoid misreading `step_level` as high-trust

**Do not:**

- Use `token_source_summary` or `provenance_warning` in any automated check, script, or gate condition
- Treat `token_source_summary = provider` as a trust signal that changes decision posture
- Add any code that reads these fields to make or influence a decision
- Attempt to extend this to `codeburn_analyze.py` — that requires a separate spec

---

## Inline Reminder (Recommended)

When introducing this to a repo, include the following note in the relevant runbook or session doc:

> **Token provenance fields are for human review only.**
> `token_source_summary` and `provenance_warning` describe data quality context.
> Do not use them for automated decisions, gate logic, or policy enforcement.

This reminder matters because it appears at **point of use**, not only in a contract document.

---

## Observation Window

Duration: **1–2 weeks** per exposed repo.

Observe the following:

| Signal | What To Look For |
|--------|-----------------|
| Reviewer use | Are reviewers actually reading `token_source_summary`? Is it useful? |
| Misinterpretation decrease | Are fewer reviewers treating `step_level` as provider-grade? |
| Misuse attempts | Is any repo code attempting to consume `token_source_summary` as a decision input? |
| False signal | Are any repos generating misleading `provenance_warning` due to data quality problems? |

If misuse is observed, stop the exposure and document the pattern before widening.

---

## What This Phase Is NOT For

This phase is not for:

- Gathering token efficiency data
- Establishing optimization baselines
- Feeding provenance signals into `codeburn_analyze.py`
- Proving decision-safety of any token surface

Those require a separate, explicitly-scoped slice with its own spec, evidence plan, and governance authority.

---

## Exit Criteria

This controlled exposure phase is complete when:

1. At least one reviewer has used `token_source_summary` correctly (as context, not as decision input)
2. No misuse of provenance fields as automated decision signals has been observed in the exposure window
3. The provenance disclosure is confirmed to be non-breaking (no existing report consumers broken)

After exit criteria are met, the exposure may be widened to additional repos.

---

## Boundary Summary

```
report fields      → human-facing disclosure only
                     not: gate input
                     not: decision signal
                     not: machine-consumable authority

analyze fields     → not yet extended (requires separate spec)

decision flags     → unchanged: decision_usage_allowed=false
                                analysis_safe_for_decision=false
```

Any deviation from this boundary during the exposure window must be documented and escalated before continuing.
