# CodeBurn — Verification Substrate Observations — 2026-05-20

Status: observation record — not a constraint, not a policy document
Scope: governance substrate failure mode analysis; exemplified by Phase 2 state
Origin: discussion during Phase 2 status review, 2026-05-20 session
Authority: none — observations only; no operational consequence

---

## Purpose

This document records governance failure mode patterns identified during analysis
of CodeBurn Phase 2 verification state. The patterns are named here so they can
be recognized and cited in future decision contexts.

The observation-before-modification principle applies: no structural change is
authorized by this document. It provides vocabulary, not prescription.

---

## 1. Verification laundering — the named pattern

**Definition**: The organizational memory rewrite that converts "verification failed"
into "feature basically done, environment has issues."

**The pattern:**

```
Step 1: Feature implemented (code written, runtime smoke passes)
Step 2: Formal verification fails (pytest permission-denied — cannot run test suite)
Step 3: Organizational memory records: "feature complete, pytest env degraded"
Step 4: Future reference: "Phase 2 token observability: implementation_landed"
Step 5 (risk): "implementation_landed" ≈ "verified" in downstream reasoning
```

**The launder point is Step 3 → Step 4**: the failure state is preserved in words
("environment degraded") but encoded in a status field ("implementation_landed")
that does not carry the failure signal. Future readers see the status, not the words.

**Codeburn Phase 2 current state:**

`CODEBURN_PHASE2_TOKEN_OBSERVABILITY_SLICE_CLOSEOUT_2026-04-30.md` records:
- `status: implementation_landed`
- pytest environment: permission-denied failures (cannot run full test suite)
- Verification closure: NOT available

The code is present and structurally correct. The test suite cannot confirm it.
`implementation_landed` ≠ `verification_complete`.

**Anti-laundering artifact already present:**

The closeout document explicitly records this distinction. The failure mode is not
yet instantiated — the laundering risk exists if future reasoning treats the
status field as sufficient evidence without reading the prose.

---

## 2. Verification substrate fragility — governance substrate concern

**Definition**: Test environment failures are not infrastructure noise when the
test suite is the verification substrate for a governance claim.

**The distinction:**

| Framing | Implication | Correct? |
|---------|------------|---------|
| "pytest env is degraded — tech debt" | fix when convenient; feature is done | No |
| "pytest env permission-denied = verification closure unavailable" | governance substrate concern; feature status is uncertain | Yes |

**Why the distinction matters:**

Phase 2 token observability is claimed as `implementation_landed`. The claim
depends on the implementation being verifiable. If the test substrate cannot run,
the verification gap is indeterminate — we cannot tell whether the claim is
correct or incorrect. The feature exists in an epistemically unverifiable state.

**Structural property:**

A governance system that cannot verify its own claims is not producing governance —
it is producing the appearance of governance backed by implementation optimism.
The pytest failure is not a blocker to fix; it is a signal that the current
verification posture is not adequate for the governance claims being made.

**Codeburn current state:**

- Phase 1: verified (runtime smoke passes; M1–M8 confirmed)
- Phase 2 token observability: code present, pytest substrate broken
- Phase 2 token provenance: spec written, not implemented

The honest statement: Phase 2 observability code exists but is not
verified by the system's own test substrate.

---

## 3. Asymmetrical evolution — the architectural freeze constraint

**The asymmetry:**

| Axis | Can evolve? | Authority required? |
|------|------------|---------------------|
| Observability capability | Yes (Phase 2, 3, ...) | New observability contract per slice |
| `analysis_safe_for_decision` | Must remain `false` | CODEBURN_DECISION_AUTHORITY_CONTRACT.md (not written) |
| `decision_usage_allowed` | Must remain `false` | Same authority contract |

**Why this asymmetry is architecturally correct:**

Observability and decision authority have different governance prerequisites.
Observability requires: new contract, additive fields, Phase 1 invariants preserved.
Decision authority requires: proof standard, authority certification, scope definition,
enforcement validator — none of which currently exist.

**The risk: capability-authority conflation**

As observability grows (token provenance, cross-session comparison, step-level
breakdown), the data richness increases. Rich observational data creates pressure
toward decision use through:
- "advisory prioritization" (not a formal decision)
- "confidence-weighted ranking" (uses token data as signal)
- "review acceleration" (treats high-token sessions as review targets)

None of these require changing `analysis_safe_for_decision` from `false`.
All of them constitute decision authority use without authorization.

**The constitutional boundary:**

`analysis_safe_for_decision = false` is not a placeholder. It is the
architectural boundary between observability and decision authority.
The asymmetry is intentional: observability can be extended; decision
authority requires a separate governance track that does not yet exist.

---

## 4. Operational dependency creep — the most dangerous drift path

**Definition**: Decision authority is used in practice through workflow integration,
even when schema invariants remain unchanged.

**Why it is more dangerous than direct schema change:**

| Path | Detection | Reversibility |
|------|-----------|--------------|
| Direct: change `analysis_safe_for_decision = true` | Easy — schema diff | Hard — requires revert + governance review |
| Indirect: integrate Codeburn output into review workflow | Hard — behavioral change | Very hard — organizational habit |

**The mechanism:**

```
Codeburn report is added to review template (observational, permitted)
→ reviewer looks at token counts before deciding scope (informed by data)
→ reviewer mentions token count in review notes (becomes reference point)
→ next reviewer looks for token count signal to calibrate (pattern established)
→ high token count → extended review (implicit decision criterion)
→ token count is now a de facto decision signal (schema unchanged; governance bypassed)
```

**Why this is hard to prevent:**

The mechanism is individually legitimate at each step. Adding observational
data to a template is permitted. A reviewer using data to inform judgment is
not prohibited. The governance violation is in the aggregate pattern, not any
individual step. It is the semantic leakage problem applied to workflow integration.

**Observable precursors (not yet observed in this system):**

- Codeburn output referenced in review comments
- Review decisions correlated with token observability level
- Team norms that treat high-token sessions as requiring more review
- SLA differentiation based on Codeburn step count

None of these involve changing any governance document. The invariant `false`
fields remain. The authority boundary has been operationally bypassed.

---

## 5. Verification substrate recovery — what is needed

This section records what would be needed to close the verification gap,
without prescribing when or whether to do it.

**P1 prerequisite (from Phase 1 Final Closeout):**

> pytest environment unblocked: 7 test files must pass fully

**Current state:**

Permission-denied errors in pytest temporary directories prevent the test
suite from running. Root cause: Windows filesystem permission issue in
`examples/pytest_tmp*` directories.

**What resolution provides:**

- Verification closure for Phase 2 token observability slice
- `implementation_landed` → `runtime_verified` status upgrade possible
- Unblocking of Phase 3+ entry (Phase 2 P1 prerequisite satisfied)

**What resolution does NOT provide:**

- Authorization to change `analysis_safe_for_decision` (that requires DECISION_AUTHORITY_CONTRACT)
- Cross-session comparability (requires Phase 2 comparability slice)
- Decision authority (requires separate governance track)

**Governance note:**

Fixing the pytest environment is not a governance decision — it is a maintenance
action with governance prerequisites as a consequence. It should be treated as
infrastructure work, not as a governance boundary modification.

---

## Document status

Observation record. Carries no enforcement authority.
Does not modify any Phase 1 or Phase 2 constraint.
Does not authorize any change to `analysis_safe_for_decision` or `decision_usage_allowed`.
Does not prescribe when to fix the pytest environment.

**Function**: provide named vocabulary for recognizing these patterns when they
appear in actual system evolution decisions.

**Trigger condition for revisiting:**

If a concrete instance of verification laundering, operational dependency creep,
or capability-authority conflation is identified in actual Codeburn usage or
integration, that instance becomes the evidence base for targeted constraint addition.
