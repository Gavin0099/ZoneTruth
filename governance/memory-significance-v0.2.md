# Memory Significance v0.2

Status: Draft-for-implementation
Scope: organizational memory governance

## Purpose
Canonical memory is not intended to maximize historical completeness.
Its purpose is to preserve high-reuse organizational semantics.

This contract separates:
- Audit Artifact: execution evidence (run-record/scorecard/diff/session-index)
- Memory Candidate: machine-generated memory proposal (non-authoritative)
- Canonical Memory: promoted organizational knowledge (authoritative)

## Authority Model
Observation does not equal authority.
- Audit artifacts and candidates MAY challenge canonical memory.
- They MUST NOT overwrite canonical conclusions directly.
- Challenge output is `canonical_review_required` only.

## Event Significance Classification

### Levels
- L3 (must-log): architecture and governance-significant events with future dependency
- L2 (should-log): reusable process or cross-file semantic alignment
- L1 (optional): low-impact local changes

### L3 enum (closed set)
L3 event types MUST use this enum only. Custom strings are forbidden.

- architecture_contract_change
- enforcement_semantic_change
- external_behavior_change
- reviewer_override
- incident_root_cause

Validation rule:
- If `significance_level=L3` and `event_type` not in enum => invalid candidate.

## Lifecycle
1. closeout completes
2. candidate generation
3. significance classifier
4. advisory report
5. optional promotion to canonical memory

Current phase policy:
- No pre-push hard gate in v0.2 rollout.
- Use advisory + escalation only.

## Supersedence Model (Canonical Memory)
Canonical entries are not append-only truth. They can be replaced.

Required fields for L3 canonical entries:
- memory_id
- validity_state: active | deprecated | superseded
- supersedes: list[memory_id]
- superseded_by: list[memory_id]

## Retrieval Contract

### Retrieval layers (authority order)
1. Canonical memory
2. Promoted candidate index (if present)
3. Audit artifacts

### Conflict handling
If canonical entries conflict:
1. Prefer `active` over `deprecated` over `superseded`
2. If same validity_state, prefer newer entry
3. If timestamps are close or ambiguous, prefer entry with stronger evidence linkage
4. Emit `canonical_conflict_detected` advisory

If non-canonical evidence conflicts with canonical:
- Emit `canonical_review_required`
- Do not auto-rewrite canonical entry

## Advisory Outputs
Minimum advisory classes:
- canonical_review_required
- canonical_conflict_detected
- invalid_l3_event_type
- missing_l3_memory_linkage

## Metrics (observability, not KPI gaming)

Primary:
- memory_significance_hit_rate
- historical_reference_frequency

Secondary:
- candidate_promotion_ratio (observational only)
- memory_duplication_rate
- memory_noise_ratio (supplementary only)

Policy note:
- High promotion ratio is NOT automatically good.
- Candidate discard is expected behavior.

## Enforcement Boundary
v0.2 enforcement is soft:
- closeout -> candidate generation -> classifier -> advisory report
- repeated L3 misses may escalate
- no hard push block in this phase

## Minimum Candidate Contract
See: `templates/memory-candidate-template.yaml`
