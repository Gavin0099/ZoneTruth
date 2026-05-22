# CodeBurn — Acquisition Authority Model

> Written: 2026-05-20
> Status: **BINDING** — P2 governance decision, effective immediately
> Scope: all CodeBurn provider integrations, all acquisition implementations
> Decision: L1.5 / Class C (observer-reconstructed) is the acquisition authority ceiling
> Depends on: CODEBURN_TOKEN_PROVENANCE_ONTOLOGY.md, CODEBURN_AUTHORITY_CEILING_CONTRACT.md

---

## The Decision

**CodeBurn selects L1.5 (post-hoc session log ingestion) as the initial and maximum
acquisition authority level for all provider integrations.**

This is a governance constraint, not a technical limitation.

L1 (runtime command wrapper) is technically feasible. It is not selected because
it changes the system's epistemic topology in ways that are incompatible with
CodeBurn's governance trajectory.

**L1 is deferred indefinitely, not as a temporary measure pending maturity,
but as a principled boundary on how close CodeBurn approaches provider runtime.**

---

## The Deferred Runtime Authority Principle

> CodeBurn intentionally selects post-hoc reconstructed acquisition as the initial
> provider integration surface in order to preserve explicit observation distance
> and prevent premature runtime authority centralization.

This principle encodes three decisions simultaneously:

**1. "Intentionally selects"** — the choice is active, not forced by capability gap.
The absence of L1 is not an implementation debt. It is a design decision.

**2. "Initial and maximum"** — L1.5 is not a stepping stone toward L1. L1 requires
a separate authority elevation process (see Amendment Process below).

**3. "Prevent premature runtime authority centralization"** — the primary risk
being avoided is not token acquisition failure. It is Runtime Centralization Drift.

---

## Runtime Centralization Drift — The Risk Pattern

The specific failure mode that L1 opens and L1.5 avoids:

```
Stage 1: Runtime Wrapper Introduced
  "just wrapping the command for token capture"
  → architectural change: CodeBurn now sits between caller and runtime

Stage 2: Wrapper Controls Invocation
  "wrapper already intercepts the call"
  → natural extension: add pre-flight checks
  → CodeBurn is now an invocation gate

Stage 3: Wrapper Can Inspect Runtime
  "wrapper has runtime context"
  → natural extension: read runtime state for richer observability
  → CodeBurn is now a runtime inspector

Stage 4: Wrapper Can Mutate Runtime
  "wrapper already modifies invocation"
  → natural extension: add enforcement hooks
  → CodeBurn is now an execution authority layer

Stage 5: Operational Dependency
  "no CodeBurn → no runtime"
  → CodeBurn's epistemic posture is now enforcement posture
  → authority has fully transferred through implementation gravity
```

No individual step is an explicit violation. Each step feels like a natural
extension of the previous one. The transition from observer to authority layer
occurs through accumulated implementation decisions, not through a single
deliberate choice.

**L1.5 blocks this drift at Stage 1 by never introducing the runtime wrapper.**

---

## Why L1.5 Preserves Epistemic Honesty

L1.5 (observer-reconstructed) has a structural property that L1 (observer-derived)
does not: it carries an inherent, non-negotiable observation distance.

```
L1 topology:
  runtime → [wrapper observes] → artifacts

L1.5 topology:
  runtime → artifacts → [CodeBurn reconstructs]
```

In L1, CodeBurn is present during the interaction.
In L1.5, CodeBurn arrives after the interaction.

This temporal asymmetry is not a deficiency — it is a governance feature.

It enforces honesty about what CodeBurn can legitimately claim:

| Claim | L1 | L1.5 |
|---|---|---|
| "I observed this in real-time" | possible (technically) | impossible (structurally) |
| "I reconstructed this from artifacts" | misleading | accurate |
| "This count may be incomplete" | understated | inherent |
| "Replay may differ from original" | obscured | required to acknowledge |

**L1.5 makes the right epistemic claims structurally unavoidable.**
The reconstruction gap cannot be hidden because the architecture makes it visible.

This aligns with CodeBurn's broader trajectory:

- Null Ontology: absence of data is a valid epistemic state
- Typed provenance: different acquisition modes produce different evidence types
- Fail-closed admissibility: missing data does not default to optimistic assumptions
- Analysis-safe-for-decision = false: permanent until explicitly contracted otherwise

L1.5 produces Class C evidence. Class C evidence is honest about:
- Reconstruction gap (temporal distance)
- Replay incompleteness (logs may be partial)
- Provider opacity (what the provider computed vs. what it reported)
- Acquisition non-equivalence (Class C ≠ Class A)

These admissions are not weaknesses. They are the foundation for defensible
observability.

---

## What L1.5 Means in Practice (Claude Code Acquisition)

For Claude Code as the first provider integration target:

**Acquisition mode:** Session log ingestion from Claude Code `.jsonl` session files

**What this captures:**
- Token counts as logged in session artifacts (if present in log format)
- Session timing and step boundaries from log records
- Tool use sequences from log entries
- Exit status and completion signals from log events

**What this explicitly does NOT capture:**
- Real-time token streaming data
- Live API response objects
- Provider-side computation details
- Anything not present in the post-session log artifact

**Epistemic class produced:** Class C (observer-reconstructed)

**Token source field:** `estimated` (with reconstruction gap declaration)

**What CodeBurn may claim from Class C evidence:**
- "The session log recorded N tokens for this session segment"
- "Token data is post-hoc reconstructed from session artifacts"
- "Log completeness is not guaranteed"

**What CodeBurn may NOT claim from Class C evidence:**
- "N tokens were consumed" (reconstruction ≠ original observation)
- "This count is provider-grade" (Class C ≠ Class A)
- "The session used fewer/more tokens than average" (efficiency inference prohibited)

---

## Boundary Between L1.5 and L1

The boundary between L1.5 and L1 is not a performance or completeness threshold.
It is an architectural topology test:

**L1.5:** CodeBurn reads artifacts that already exist after the AI interaction completes.
**L1:** CodeBurn is present during the AI interaction through a wrapper or hook.

Tests for boundary crossing:
- Does CodeBurn need to be invoked before or during the AI interaction? → L1 territory
- Does CodeBurn intercept, wrap, or modify the AI invocation? → L1 territory
- Does CodeBurn read log files, export artifacts, or session summaries after completion? → L1.5
- Does CodeBurn process data that only exists because CodeBurn created it during invocation? → L1 territory

**If an acquisition implementation requires CodeBurn to be present at runtime,
it is an L1 implementation regardless of how it is described.**

---

## What L1 Would Require to Be Reconsidered

L1 is not permanently prohibited. It requires a separate governance process:

1. A `CODEBURN_RUNTIME_WRAPPER_AUTHORITY_CONTRACT.md` must be created that:
   - Names the specific runtime authority being accepted
   - Documents the Runtime Centralization Drift mitigations in place
   - Defines the operational dependency limit (what happens when CodeBurn fails)
   - Specifies who holds authority over the wrapper's enforcement scope

2. The contract must be reviewed by a party independent of the L1 implementation

3. The contract must be committed before any L1 implementation begins

4. The Deferred Runtime Authority Principle in this document remains the governing
   statement until the contract explicitly supersedes it

**Building an L1 wrapper before this contract exists = Runtime Centralization
Drift at Stage 1 onset. The drift pattern begins at implementation, not at
governance violation.**

---

## Acquisition Authority Level Reference

For all future acquisition implementation decisions:

| Level | Label | Architecture | Max epistemic class | Authority status |
|-------|-------|--------------|---------------------|-----------------|
| L0 | Passive recorder | Human-provided data | D (user-asserted) | Current state |
| L1.5 | Session log ingestion | Post-hoc artifact read | C (reconstructed) | **Selected ceiling** |
| L1 | Runtime wrapper | Present at invocation | B (observer-derived) | Deferred — requires contract |
| L2 | Direct API hook | In API response path | A (provider-originated) | Deferred — requires contract |
| L3 | Traffic substrate | All provider traffic | A (provider-originated) | Permanently deferred |

CodeBurn may move from L0 to L1.5 through implementation.
CodeBurn may NOT move from L1.5 to L1 or above without `CODEBURN_RUNTIME_WRAPPER_AUTHORITY_CONTRACT.md`.

---

## Relationship to Existing Boundary Documents

| Document | Relationship |
|---|---|
| Provenance Ontology | Defines Class C; this document selects it as the ceiling |
| Authority Ceiling Contract | Defines what CodeBurn may not become; this document applies those ceilings to the acquisition architecture |
| Consumption Boundary | Constrains downstream use; this document constrains upstream architecture |
| Comparability Boundary | Constrains cross-provider comparison; this document establishes that Class C is the maximum evidence class for first integration |

---

## Current Acquisition State (2026-05-20)

```
Current level:                L0 (passive recorder)
Selected ceiling:             L1.5 (session log ingestion)
Next implementation target:   L1.5 — Claude Code session log ingestion
L1 status:                    Deferred — requires CODEBURN_RUNTIME_WRAPPER_AUTHORITY_CONTRACT.md
L2+ status:                   Permanently deferred

Deferred Runtime Authority Principle: ACTIVE
Runtime Centralization Drift posture: MONITORED
```

The move from L0 to L1.5 is the scope of Phase 3 (Claude-only acquisition closure).
That implementation is separate from this document.
This document governs the boundary, not the implementation.

---

*The absence of a runtime wrapper is not a capability gap.*
*It is a governance constraint that preserves observation distance.*
*CodeBurn arrives after the interaction. That temporal asymmetry is the design.*
