# CodeBurn v2 Phase 1 - M6 Test Result (2026-04-30)

## Scope
- Repo: `E:\BackUp\Git_EE\ai-governance-framework`
- Target: M6 post-job auto analysis
  - `codeburn_analyze.py`
  - auto analysis on `session-end` (default enabled)
  - `--no-analyze` opt-out path

## Implementation
- Added `codeburn/phase1/codeburn_analyze.py`:
  - summarizes session/step execution
  - reports slowest step
  - shows step breakdown
  - shows git-visible changed files
  - shows advisory signals
  - shows observability limits
- Updated `codeburn/phase1/codeburn_session.py`:
  - `session-end` now runs post-job analysis by default
  - `session-end --no-analyze` disables analysis output

## Runtime Smoke Evidence
Commands executed:
```powershell
python codeburn/phase1/codeburn_session.py --db codeburn/phase1/examples/m6_demo.db --schema codeburn/phase1/schema.sql --repo . session-start --task "m6 demo" --open-session-action auto_close_previous
python codeburn/phase1/codeburn_run.py --db codeburn/phase1/examples/m6_demo.db --schema codeburn/phase1/schema.sql --repo . --step-kind planning --provider local --token-source unknown -- cmd /c exit 0
python codeburn/phase1/codeburn_run.py --db codeburn/phase1/examples/m6_demo.db --schema codeburn/phase1/schema.sql --repo . --step-kind test --provider local --token-source unknown -- cmd /c exit 1
python codeburn/phase1/codeburn_run.py --db codeburn/phase1/examples/m6_demo.db --schema codeburn/phase1/schema.sql --repo . --step-kind test --provider local --token-source unknown -- cmd /c exit 1
python codeburn/phase1/codeburn_session.py --db codeburn/phase1/examples/m6_demo.db --schema codeburn/phase1/schema.sql --repo . session-end
python codeburn/phase1/codeburn_session.py --db codeburn/phase1/examples/m6_demo.db --schema codeburn/phase1/schema.sql --repo . session-end --no-analyze
```

Observed:
- `session-end` prints `CodeBurn Post-Job Analysis` block by default.
- `session-end --no-analyze` suppresses analysis block.
- Output remains observational only; no waste/enforcement claims.
- Analysis includes explicit boundary footer and signal traceability (`derived_from_steps`).

## Test File Added
- `tests/test_codeburn_phase1_analyze.py`

## Execution Boundary
test execution degraded; validator gate passed; not equivalent to full pytest pass

## Verdict
- M6 status: **PASS (runtime smoke)**
