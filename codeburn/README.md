# CodeBurn — Agent Navigation

> Phase 1: **CLOSED** (2026-04-30)
> Next: Phase 2 Token Observability Upgrade (entry criteria below)

---

## Entry Points (Phase 1)

| Purpose | File |
|---|---|
| Start here | `phase1/CODEBURN_PHASE1_STATUS.md` |
| Create smoke fixture | `python phase1/create_distribution_smoke_fixture.py --db <db>` |
| Run analysis | `python phase1/codeburn_analyze.py --db <db>` |
| Run report | `powershell -ExecutionPolicy Bypass -File phase1/run_report.ps1 -DatabasePath <db>` |
| Full gate | `python phase1/validate_phase1_data.py --db <db> --include-analysis` |
| Contract | `phase1/CODEBURN_PHASE1_ANALYSIS_CONTRACT.md` (v1.0.0) |
| Phase 2 limits | `phase1/CODEBURN_PHASE2_ENTRY_CONSTRAINTS.md` |
| Final closeout | `phase1/CODEBURN_PHASE1_FINAL_CLOSEOUT_2026-04-30.md` |

---

## Distribution Smoke v0.1

Goal: a user does not need to understand `PYTHONPATH`, package layout, or helper imports.
If they follow the documented commands, they should get the same Phase 1 report whether they run from repo root or from outside the repo.

### Minimal Flow

From repo root:

```powershell
python codeburn/phase1/create_distribution_smoke_fixture.py --db codeburn/phase1/examples/distribution_smoke.db
python codeburn/phase1/codeburn_analyze.py --db codeburn/phase1/examples/distribution_smoke.db --session distribution-smoke-session --format json
powershell -ExecutionPolicy Bypass -File codeburn/phase1/run_report.ps1 -DatabasePath codeburn/phase1/examples/distribution_smoke.db -SessionId distribution-smoke-session -Format json
```

From outside repo:

```powershell
python E:\BackUp\Git_EE\ai-governance-framework\codeburn\phase1\create_distribution_smoke_fixture.py --db E:\BackUp\Git_EE\ai-governance-framework\codeburn\phase1\examples\distribution_smoke.db
python E:\BackUp\Git_EE\ai-governance-framework\codeburn\phase1\codeburn_analyze.py --db E:\BackUp\Git_EE\ai-governance-framework\codeburn\phase1\examples\distribution_smoke.db --session distribution-smoke-session --format json
powershell -ExecutionPolicy Bypass -File E:\BackUp\Git_EE\ai-governance-framework\codeburn\phase1\run_report.ps1 -DatabasePath E:\BackUp\Git_EE\ai-governance-framework\codeburn\phase1\examples\distribution_smoke.db -SessionId distribution-smoke-session -Format json
```

### Smoke Assertions

Expected report fields:

```json
"token_observability_level": "step_level"
"token_source_summary": "mixed(provider, estimated)"
"decision_usage_allowed": false
"analysis_safe_for_decision": false
```

Forbidden output in smoke runs:

```text
WRONG_MODULE
WRONG_HEADER
```

`run_report.ps1` intentionally clears `PYTHONPATH` for the child process before invoking `codeburn_report.py`.
This keeps the distribution surface stable even if the caller environment is polluted.
This distribution smoke contract validates the main repo CodeBurn Phase 1 surface only.
Embedded copy synchronization is intentionally out of scope for this slice.

---

## What Phase 1 Can and Cannot Do

**Can observe:**
- Command execution lifecycle (start / end / step / recovery)
- Git-visible file changes per step
- Retry patterns (advisory signals only)
- Post-job analysis summary

**Cannot claim:**
- Waste detection or redundancy
- Token usage (unknown)
- Correctness or effectiveness judgment
- Optimization recommendations

---

## Permanent Phase 1 Invariants

These two fields are **always `false`** in all Phase 1 JSON output.
Do not change them without creating `CODEBURN_DECISION_AUTHORITY_CONTRACT.md`.

```json
"analysis_safe_for_decision": false
"decision_usage_allowed": false
```

Every CLI prints this to stderr on invocation:
```
CodeBurn Phase 1 | Status: CLOSED | Decision usage: NOT ALLOWED (analysis_safe_for_decision=false)
```

---

## Analysis Contract Summary (v1.0.0)

| § | Layer | Core Rule |
|---|---|---|
| 2 | Semantics | Observation-only; boundary footer mandatory |
| 3 | Signal | `derived_from_steps` required; advisory-only, no blocking |
| 4 | Determinism | Byte-for-byte; 4 ORDER BY rules; no runtime timestamp |
| 5 | Observability | `token_usage/file_reads/file_activity` declared in every output |
| 6 | Non-Claims | No waste/efficiency/correctness/cross-session claims |
| 7 | Amendment | Name + version + evidence; silent change = violation |

Enforcement (`codeburn_validate_analysis.py`) is fail-closed: exit 1 on any violation.

---

## Phase 2 Entry Criteria

All four must be satisfied before Phase 2 work begins:

- **P1** — 7 pytest test files pass in a clean environment
- **P2** — Forbidden phrase scanner excludes user metadata fields (L1 fix)
- **P3** — All Phase 2 extensions follow §7 amendment process
- **P4** — `validate_phase1_data.py --include-analysis` is the CI gate

Phase 2 may NOT change guard fields or add decision/recommendation output
without first creating a decision-authority contract.
See `phase1/CODEBURN_PHASE2_ENTRY_CONSTRAINTS.md` for full constraints.

---

## Phase 3 — Deliberately Prohibited (as of 2026-04-27)

Phase 3 (Trigger Design: dynamic threshold, trend_direction, cross-repo correlation) is
technically unblocked but **deliberately prohibited for now**.

Reason: E2 must produce initial verifiable results before Phase 3 trigger design begins.
Phase 2.5 semantic locks remain fully in effect (observation-only, no interpretive-class keys).

Phase 3 entry requires explicit Phase 2 → Phase 3 gate passage and reviewer sign-off.

This prohibition is currently enforced at documentation level only.
Runtime enforcement is not yet implemented.

