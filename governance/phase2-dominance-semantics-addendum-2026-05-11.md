# Phase 2 Dominance Semantics Addendum (2026-05-11)

Status: normative addendum for observation interpretation  
Scope: `PHASE2_GATE_RUNBOOK.md` metric semantics only

## Purpose

Prevent dominance-ratio improvements that are achieved by synthetic/instrumental
session inflation rather than real workload diversification.

## Required Split

All Phase 2 dominance and distribution metrics MUST be reported in two tracks:

1. `natural_work_sessions`
2. `instrumental_sessions`

Both tracks must be shown for:

- total sessions
- distinct repos
- non-degenerate ratio
- dominant repo ratio

## Definitions

`natural_work_sessions`
- Sessions initiated by real engineering tasks with product or repository
  maintenance intent.
- Not created primarily to satisfy governance sample quotas.

`instrumental_sessions`
- Sessions initiated primarily to satisfy governance sampling, calibration,
  probe, or gate-readiness quotas.
- Includes explicit replay/probe-only runs without primary engineering delta.

## Reporting Rule

A Phase 2 readiness summary MUST include:

- combined metrics (`all_sessions`)
- natural-only metrics (`natural_only`)
- instrumental-only metrics (`instrumental_only`)

## Decision Rule

Dominance-risk relief cannot be claimed from `all_sessions` alone.

A downgrade from `risk_observed` to `risk_not_reobserved_yet` or
`closure_verified` requires that:

1. `natural_only.dominant_repo_ratio` trends down, and
2. `natural_only.distinct_repos` satisfies target coverage, and
3. no opposite movement is hidden by instrumental-session growth.

If these are not met, the window must remain at:

- `insufficient_closure_evidence`, or
- `risk_persists`

depending on observed evidence.

## Output Fields (minimum)

```yaml
session_mix:
  all_sessions: 44
  natural_work_sessions: 12
  instrumental_sessions: 32
metrics:
  all_sessions:
    dominant_repo_ratio: 0.72
    distinct_repos: 3
  natural_only:
    dominant_repo_ratio: 0.91
    distinct_repos: 2
  instrumental_only:
    dominant_repo_ratio: 0.40
    distinct_repos: 4
interpretation_guard:
  dominance_relief_claim_allowed: false
  reason: "natural_only dominance remains above threshold"
```

## Non-Claim

Lower `all_sessions.dominant_repo_ratio` by itself is not evidence of healthier
governance distribution.
