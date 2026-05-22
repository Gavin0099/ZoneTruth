# CodeBurn v2 Phase 1 - M7 Test Result (2026-04-30)

## Scope
- Repo: `E:\BackUp\Git_EE\ai-governance-framework`
- Target: M7 Analysis Contract Enforcement (fail-closed)
  - `codeburn_validate_analysis.py` — standalone enforcement CLI
  - `validate_phase1_data.py --include-analysis` — merged mode

## Implementation
Added `codeburn/phase1/codeburn_validate_analysis.py`:
- (A) `boundary_structure` check: `analysis_boundary.claims=False`, `analysis_type=observation`,
  `interpretation_level=low`, all three `observability_limits` values declared
- (B) `forbidden_phrases` check: renders text output and scans for
  `waste / inefficient / unnecessary / should optimize / should reduce` (case-insensitive)
- (C) `traceability` check: `retry_pattern_detected` / `retry_pattern_inferred` must
  carry non-empty `derived_from_steps`

Updated `codeburn/phase1/validate_phase1_data.py`:
- Added `--include-analysis` flag (calls `validate_analysis()`)
- Added `--session` argument (default: `latest`)
- On analysis violation: sets `ok=False`, injects `analysis_contract_violation:*` into `findings[]`

Added `tests/test_codeburn_phase1_validate_analysis.py`.

## Runtime Smoke Evidence
Commands executed:

```powershell
# Clean session — all 3 checks pass
python codeburn/phase1/codeburn_validate_analysis.py --db codeburn/phase1/examples/m6_demo.db
# → ok=true, violation_count=0, all checks pass

# Missing session — fail-closed
python codeburn/phase1/codeburn_validate_analysis.py --db codeburn/phase1/examples/m6_demo.db --session nonexistent
# → ok=false, exit_code=1, violations=["session_not_found"]

# Merged mode
python codeburn/phase1/validate_phase1_data.py --db codeburn/phase1/examples/m6_demo.db --include-analysis
# → ok=true, analysis_contract.ok=true, finding_count=0
```

## Contract Enforcement Guarantees

| Check | Trigger | Contract Section |
|---|---|---|
| `boundary_structure` | `claims≠False` / `analysis_type≠observation` / missing observability_limits | §2.2, §5.1 |
| `forbidden_phrases` | rendered output contains waste/efficiency/correctness claims | §2.1, §6 |
| `traceability` | retry signal without `derived_from_steps` | §3.1 |

## Execution Boundary
test execution degraded; validator gate passed; not equivalent to full pytest pass

## Verdict
- M7 status: **PASS (runtime smoke — fail-closed enforcement operative)**

## Known Limitation
Forbidden phrase scanner (B) operates on full rendered text including user-supplied `task` name.
If a task name contains a forbidden word (e.g., "reduce noise"), the check will trigger.
Future amendment (Phase 2): exclude user-metadata fields from phrase scan scope.
This limitation is documented in `test_task_name_with_neutral_word_does_not_trigger`.
