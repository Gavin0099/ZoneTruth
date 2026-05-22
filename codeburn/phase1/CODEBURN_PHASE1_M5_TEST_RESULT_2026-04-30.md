# CodeBurn v2 Phase 1 - M5 Test Result (2026-04-30)

## Scope
- Repo: `E:\BackUp\Git_EE\ai-governance-framework`
- Target: `retry_pattern_detected`
  - signal generation
  - advisory-only hard rule
  - confidence denoise rule
  - validator hard-rule coverage
  - fallback inference for implicit retries (`retry_pattern_inferred`)

## Implementation
- `codeburn/phase1/codeburn_run.py`
  - added retry detection on step ingest
  - emits signal when consecutive retry streak reaches exactly 3
  - retry condition:
    - `step_kind == retry`
    - or `retry_of != null`
  - signal payload:
    - `signal=retry_pattern_detected`
    - `type=cost_risk`
    - `advisory_only=1`
    - `can_block=0`
    - `source=phase1_heuristic`
  - confidence rule:
    - `low` if any `changed_files > 0` in the 3-step retry streak
    - else `medium`
  - fallback rule (`retry_pattern_inferred`):
    - trigger when consecutive implicit retry-like steps reach 3:
      - step kind fixed in `{execution, test}`
      - same command
      - non-zero exit code
      - no changed files
      - no explicit retry marker (`step_kind!=retry` and `retry_of` empty)
    - payload fixed to:
      - `type=cost_risk`
      - `advisory_only=1`
      - `can_block=0`
      - `confidence=low`
      - `source=phase1_fallback`

- `codeburn/phase1/validate_phase1_data.py`
  - added retry signal contract validation:
    - `type` must be `cost_risk`
    - `source` must be `phase1_heuristic`
    - `confidence` in `{low, medium}`
    - `advisory_only=1`
    - `can_block=0`
  - added inferred retry contract validation:
    - `signal=retry_pattern_inferred`
    - `type=cost_risk`
    - `source=phase1_fallback`
    - `confidence=low`
    - `advisory_only=1`
    - `can_block=0`

- Tests added:
  - `tests/test_codeburn_phase1_retry_signal.py`
    - medium confidence path (no changed files)
    - low confidence path (changed files present)
    - `retry_of` sequence support
    - implicit execution retry inference path

## Runtime Smoke Evidence
Commands:
```powershell
python codeburn/phase1/codeburn_session.py --db codeburn/phase1/examples/m5_run.db --schema codeburn/phase1/schema.sql --repo . session-start --task "m5 smoke" --open-session-action auto_close_previous
python codeburn/phase1/codeburn_run.py --db codeburn/phase1/examples/m5_run.db --schema codeburn/phase1/schema.sql --repo . --step-kind retry --provider local --token-source unknown -- python -c "import sys; sys.exit(1)"
python codeburn/phase1/codeburn_run.py --db codeburn/phase1/examples/m5_run.db --schema codeburn/phase1/schema.sql --repo . --step-kind retry --provider local --token-source unknown -- python -c "import sys; sys.exit(1)"
python codeburn/phase1/codeburn_run.py --db codeburn/phase1/examples/m5_run.db --schema codeburn/phase1/schema.sql --repo . --step-kind retry --provider local --token-source unknown -- python -c "import sys; sys.exit(1)"
python codeburn/phase1/validate_phase1_data.py --db codeburn/phase1/examples/m5_run.db --format json
```

Observed signal:
```json
["retry_pattern_detected", "cost_risk", 1, 0, "low", "phase1_heuristic"]
```

Observed fallback signal (clean repo smoke):
```json
["retry_pattern_inferred", "cost_risk", 1, 0, "low", "phase1_fallback"]
```

Validator:
- `ok=true`
- `finding_count=0`

## Test Execution Status
- `test execution degraded`: pytest temp/cache permission issues remain in this environment.
- `validator gate passed`: runtime smoke + validator checks passed.
- Not equivalent to full pytest pass.

## Verdict
- M5 status: **PASS (runtime smoke + validator gate)**
