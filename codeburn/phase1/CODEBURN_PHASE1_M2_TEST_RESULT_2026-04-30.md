# CodeBurn v2 Phase 1 - M2 Test Result (2026-04-30)

## Scope
- Repo: `E:\BackUp\Git_EE\ai-governance-framework`
- Target: M2.1~M2.6
  - run wrapper
  - step minimal required fields
  - stdout/stderr bytes, exit_code, duration_ms
  - git status before/after snapshot
  - changed_files from `git diff --name-only`
  - validator checks for steps/changed_files contracts

## Implementation Check
- `codeburn/phase1/codeburn_run.py`
  - writes step row with required fields
  - records `git_status_before`, `git_status_after`
  - records `stdout_bytes`, `stderr_bytes`, `exit_code`, `duration_ms`
  - writes `changed_files` with normalized `/` path
  - on start failure:
    - `exit_code = null`
    - `duration_ms = null`
    - `stderr_bytes > 0`
    - marks session `data_quality = partial`
- `codeburn/phase1/validate_phase1_data.py`
  - enforces launched command contract
  - enforces failed-start contract
  - enforces git snapshot non-null
  - validates changed_files path not empty and no `\`

## Runtime Smoke Evidence
Commands executed:
```powershell
python codeburn/phase1/codeburn_session.py --db codeburn/phase1/examples/m2_run.db --schema codeburn/phase1/schema.sql --repo . session-start --task "m2 smoke" --open-session-action auto_close_previous
python codeburn/phase1/codeburn_run.py --db codeburn/phase1/examples/m2_run.db --schema codeburn/phase1/schema.sql --repo . --step-kind planning --provider local --token-source unknown -- python -c "print('m2-ok')"
python codeburn/phase1/validate_phase1_data.py --db codeburn/phase1/examples/m2_run.db --format json
```

Start-failure contract path (forced via monkeypatch) result:
- `launched=false`
- `exit_code=null`
- `duration_ms=null`
- `stderr_bytes=23`
- validator remained `ok=true`

Validator result:
- `ok=true`
- `finding_count=0`

## Test File Added
- `tests/test_codeburn_phase1_run.py`
  - success path
  - start-failure contract path
  - changed_files normalization check

Note:
- `test execution degraded`: in this environment, `pytest` temp/cache directories are permission-blocked, so direct `pytest` execution is currently not reliable.
- `validator gate passed`: runtime smoke + validator evidence above passed and is the executable gate record for this run.
- This is not equivalent to a full pytest pass.

## Verdict
- M2 implementation status: **PASS**
- M2 hard rules status: **PASS**

## Next Step
1. M3.5: complete Session Recovery + Data Validity integration tests (`auto_close_previous`, `resume_previous`, `abort_start`, `idle_timeout`).
2. M4: add `codeburn report` CLI with explicit observability boundary section.
3. M5: add retry signal generator and hard validation (`advisory_only=true`, `can_block=false`).
