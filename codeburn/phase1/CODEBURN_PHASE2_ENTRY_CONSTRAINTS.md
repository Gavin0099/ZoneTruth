# CodeBurn Phase 2 — Entry Constraints

> Written: 2026-04-30
> Authority: Phase 1 closeout (`CODEBURN_PHASE1_FINAL_CLOSEOUT_2026-04-30.md`)
> Status: **BINDING** — must be read before any Phase 2 code is written

---

## Purpose

This document defines what Phase 2 is NOT allowed to do, before any Phase 2
design begins. It is not a Phase 2 spec. It is a pre-entry constraint record.

Constraints defined here take precedence over Phase 2 feature requirements.
If a Phase 2 feature conflicts with a constraint below, the constraint wins.
To override a constraint, create a separate decision-authority contract
(see §3) and get it reviewed before writing code.

---

## 1. Preserved Phase 1 Invariants

The following fields MUST remain `false` in all Phase 2 analysis and report output:

```json
"analysis_safe_for_decision": false
"decision_usage_allowed": false
```

Phase 2 may add token observability, new signals, cross-session comparison,
or any other analytical capability.

**Phase 2 may NOT change these two fields to any value other than `false`
unless a decision-authority contract is created, enforced, and reviewed.**

Rationale: Phase 1 established that CodeBurn output is observational and not
a basis for optimization or correctness decisions. Phase 2 extends observability.
Extending observability does not automatically make the system decision-safe.
Decision authority requires its own governance layer.

---

## 2. Phase 1 Contract Preservation

`CODEBURN_PHASE1_ANALYSIS_CONTRACT.md` (v1.0.0) remains in force.

Phase 2 extensions that touch Phase 1 analysis output MUST:
1. Follow the §7 amendment process (name the change, state the new guarantee,
   record evidence, bump version, reference in test result)
2. NOT silently override Phase 1 contract sections
3. NOT remove or weaken the boundary footer, observability limits, or non-claims

Phase 2 may add new contract sections or extend existing ones with additive
guarantees. Removing or weakening a Phase 1 guarantee requires an explicit
amendment with documented rationale.

---

## 3. Decision-Authority Contract Requirement

If Phase 2 (or any later phase) needs to enable decision usage, it must:

1. **Create** `CODEBURN_DECISION_AUTHORITY_CONTRACT.md` defining:
   - What decisions are permitted (scope)
   - What observability conditions must be met (preconditions)
   - What makes analysis "decision-safe" (proof standard)
   - Who may certify decision-readiness (authority)

2. **Implement** enforcement:
   - A new validator that checks decision-readiness conditions
   - `analysis_safe_for_decision` and `decision_usage_allowed` may only
     become `true` if the validator passes

3. **Review** the contract before changing any guard field value

Changing `analysis_safe_for_decision` or `decision_usage_allowed` without
completing steps 1–3 = Phase 1 invariant violation, regardless of test pass status.

---

## 4. Phase 2 Entry Prerequisites

From `CODEBURN_PHASE1_FINAL_CLOSEOUT_2026-04-30.md` §5:

- **P1** — pytest environment unblocked: 7 test files must pass fully
- **P2** — forbidden phrase scanner (L1) resolved before semantic validation expansion
- **P3** — all Phase 2 extensions reference §7 amendment process
- **P4** — `validate_phase1_data.py --include-analysis` is the standard CI gate

Phase 2 work must not begin on any feature that requires P1–P4 to be satisfied
if those conditions are not yet met.

---

## 5. Permitted Phase 2 Scope

Within the constraints above, Phase 2 may:

- Add token observability (with new observability contract)
  - first slice must be observability-level only:
    - `token_observability_level: none | coarse | step_level`
  - this slice must not introduce waste/efficiency/correctness judgment
  - this slice must preserve:
    - `"analysis_safe_for_decision": false`
    - `"decision_usage_allowed": false`
- Add cross-session comparison (with explicit comparability conditions)
- Add new signal types (must document in §3.3 or Phase 2 signal extension)
- Add new analysis output fields (must not conflict with Phase 1 non-claims)
- Resolve L1 (phrase scanner metadata exclusion)
- Unblock pytest execution path

Phase 2 may NOT:
- Claim waste detection, efficiency measurement, or correctness evaluation
  without a Phase 3+ semantic contract
- Add `"recommendation"` or `"action"` fields to analysis output
- Remove `analysis_safe_for_decision` or `decision_usage_allowed` fields
- Skip the §7 amendment process when modifying Phase 1 contract sections

---

*This constraint document is binding from the point of first Phase 2 commit.*
*It may be amended only by creating a new version with documented rationale.*
