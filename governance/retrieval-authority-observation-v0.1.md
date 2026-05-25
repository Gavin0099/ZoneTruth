# Retrieval Authority Observation v0.1

Status: Draft-for-implementation  
Mode: Observation only

## Scope Boundary (Locked)
- Observation only.
- No retrieval modification.
- No prompt injection.
- No ranking/scoring.
- No gate/block/escalation in v0.1.

## Purpose
Provide advisory telemetry for retrieval-time authority correctness signals:
- whether canonical/candidate/superseded memory appears in a response
- whether candidate appears to override canonical

This v0.1 observer is intentionally conservative:
- pattern-based and citation-based only
- does not claim semantic correctness
- does not attempt to enforce behavior

## Output Contract
The observer must emit an advisory payload with:
- `advisory_only: true` (always)
- `used_canonical: bool`
- `used_candidate: bool`
- `used_superseded: bool`
- `explicit_candidate_context: bool`
- `authority_conflict: bool`
- `authority_evidence_level: none|weak|explicit`
- `needs_human_review: bool`
- `missed_active_memory: unknown` (reserved field in v0.1)

## Conflict Semantics (v0.1)
- `used_candidate=true` is not automatically a conflict.
- Candidate usage is acceptable when response explicitly frames it as candidate context.
- `authority_conflict=true` only when candidate appears to override canonical authority.
- `used_superseded=true` always sets `needs_human_review=true`.

## Evidence Level
- `explicit`: structured citations provided in payload (`memory_refs`) and used in observation.
- `weak`: usage inferred by response text patterns only.
- `none`: no usage signals found.

## Runtime Integration
v0.1 integration target:
- advisory artifact only
- no change to runtime gate decision

Expected output path convention:
- `artifacts/runtime/advisory/retrieval-authority-<session_id>.json`

