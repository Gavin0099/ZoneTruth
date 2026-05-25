# Semantic Run Completion Protocol (v1.0)

Purpose: define when a semantic run is considered **completed and auditable**.

This protocol is repository-agnostic and can be applied to runtime-active repos such as `gl_electron_tool`.

## Completion Definition
A run is complete only when all four layers are satisfied:

1. Semantic slice exists
- A bounded change exists with a commit hash.

2. Same-repo closeout exists
- A closeout session is generated in the same repo immediately after the slice.
- `artifacts/session-index.ndjson` contains a new row with `closeout_status=valid`.

3. Intent linkage exists
- The closeout `task_intent` clearly references the semantic slice purpose.
- Session timestamp is later than commit timestamp.

4. Ledger mapping exists
- `docs/ab-v1.2-run-ledger.md` includes:
  - `commit_hash`
  - `session_id`
  - `closeout_covered: yes`
  - `mapping_confidence: high`

If any of the four is missing, treat the run as **incomplete**.

## Minimal Execution Flow
1. Create semantic slice commit.
2. Update closeout source text for this slice (task intent aligned).
3. Run session closeout hook in the same repo.
4. Verify session-index append with `valid` status.
5. Backfill ledger row as high-confidence mapping.
6. Verify no forbidden artifact contamination in source commit.

## High-Confidence Mapping Criteria
- Temporal order: `commit_time < session.closed_at`.
- Intent order: session task intent matches the slice objective.
- Scope order: no contradictory out-of-scope edits for the mapped slice.
- Evidence order: run record can be reconstructed from commit + session artifact.

## Common Failure Modes
- Closeout generated, ledger not backfilled.
- Ledger backfilled with guessed session_id (fabricated linkage).
- Session exists but task_intent is generic/manual and not slice-specific.
- Multiple slices mapped to one ambiguous closeout without explicit note.

## Recommended Counters
Track these per repo:
- `semantic_runs_total`
- `closeout_valid_total`
- `ledger_mapped_high_total`
- `closeout_coverage_ratio = ledger_mapped_high_total / semantic_runs_total`

Interpretation:
- rising valid sessions with flat mapped_high indicates governance observability gap.
- mapped_high growth indicates auditability quality improving, not just activity volume.
