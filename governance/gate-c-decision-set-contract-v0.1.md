# Gate C Decision-Set Contract v0.1

Date: 2026-05-11
Status: draft-active
Scope: Copilot / Claude / ChatGPT lanes

## 1) Purpose

Define a stable decision boundary for Gate C when canonical logs include mixed-quality rows
(e.g., reconstructed rows with missing timestamps).

This contract prevents two failure modes:

1. Audit evidence deletion to force `pass`.
2. Permanent `provisional-pass` due to historical/null rows that are not decision-grade.

## 2) Two Data Surfaces

### 2.1 Canonical Surface (authority for audit completeness)

Canonical logs are append-only evidence surfaces:

- `docs/status/gate-c-review-log.ndjson`
- `docs/status/gate-c-rework-log.ndjson`
- `docs/status/gate-c-stability-log.ndjson`

Rules:

- Do not delete rows to improve metrics.
- Reconstructed or null-timestamp rows are allowed.
- Canonical preserves historical context and provenance.

### 2.2 Decision Set Surface (authority for Gate C verdict)

Decision set is a derived view for window verdict computation only.

Rules:

- Decision set MUST be derived from canonical, not manually authored.
- Decision set includes only rows meeting validity criteria (Section 3).
- Decision set is replaceable/recomputable from canonical + rules.

## 3) Validity Criteria (v0.1)

### 3.1 Review rows

A review row is decision-valid only if all are true:

- `window_id` matches target window
- `lane` is one of `copilot|claude|chatgpt`
- `review_start_utc` and `review_end_utc` are present and parseable ISO8601 UTC
- `review_end_utc >= review_start_utc`
- `review_minutes >= 0`

### 3.2 Rework rows

A rework row is decision-valid only if:

- `total_changes > 0`
- `reopen_count >= 0` and `revert_count >= 0`
- `reopen_revert_rate` is recomputable from counts/denominator

### 3.3 Stability rows

A stability row is decision-valid only if:

- `integration_stability` is `stable` or `degraded`
- `stability_note` is non-empty

## 4) Required Dual Output

Every Gate C run must emit two reports for the same window:

1. Canonical report
   - Uses full canonical logs
   - Shows completeness gaps and raw evidence conditions
2. Decision-set report
   - Uses derived decision-valid rows only
   - Produces verdict (`pass|provisional-pass|pause`) for rollout decision

Both reports must include:

- `window_id`
- `canonical_count` by lane and log type
- `decision_count` by lane and log type
- explicit explanation of filtered-out categories

## 5) Non-Goals

This contract does NOT:

- modify runtime behavior
- modify gate/block policy directly
- claim semantic correctness of reviewer judgment

It only defines reproducible decision inputs for Gate C.

## 6) Enforcement Boundary

- v0.1 is advisory-contract first.
- Violations raise `decision_contract_mismatch` advisory.
- No auto-block introduced in v0.1.

## 7) Reviewer Interpretation Guard

Decision-set `pass` means:

- Gate C decision inputs are sufficient and internally consistent for this window.

Decision-set `pass` does NOT mean:

- engineering correctness proven
- no future reopen risk
- governance system globally validated

## 8) Minimal Implementation Checklist

1. Add derived decision-set builder (canonical -> filtered rows).
2. Emit canonical + decision-set reports for same window.
3. Store decision-set report with explicit derivation metadata.
4. Keep canonical logs immutable under this workflow.

## 9) Traceability Field Additions (recommended)

For each decision-set run output:

- `decision_contract_version: gate-c-decision-set-v0.1`
- `decision_built_from_window_id`
- `canonical_review_count / decision_review_count`
- `canonical_rework_count / decision_rework_count`
- `canonical_stability_count / decision_stability_count`
- `filtered_reason_counts`

## 10) Upgrade Trigger to v0.2

Upgrade this contract when either occurs:

1. >20% rows consistently filtered for parser/format reasons across 2+ windows
2. Lane-specific schema drift requires per-lane validity rules
3. Reviewer workload indicates dual-report overhead is too high

