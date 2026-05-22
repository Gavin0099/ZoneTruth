# CodeBurn v2 Phase 1 - M3.5 + M4 Test Result (2026-04-30)

## Scope
- Repo: `E:\BackUp\Git_EE\ai-governance-framework`
- Target:
  - M3.5 Session Recovery tests
  - M4 Report fixed output contract

## Code Changes
- Session end preserves existing quality state (no forced overwrite to `complete`):
  - `codeburn/phase1/codeburn_session.py`
- Added report CLI:
  - `codeburn/phase1/codeburn_report.py`
- Added tests:
  - `tests/test_codeburn_phase1_session_recovery.py`
  - `tests/test_codeburn_phase1_report.py`

## M3.5 Runtime Smoke Evidence
### 1) open session + auto_close_previous
- DB: `codeburn/phase1/examples/m35_auto_close.db`
- Result:
  - previous session (`s1`) closed with `ended_by=auto_close_previous`
  - previous session `data_quality=recovered`
  - `recovery_events.action_taken=auto_close_previous`

### 2) open session + resume_previous
- DB: `codeburn/phase1/examples/m35_resume.db`
- Result:
  - no new session created
  - existing session remains open
  - existing session `data_quality=recovered`
  - `recovery_events.action_taken=resume_previous`

### 3) open session + abort_start
- DB: `codeburn/phase1/examples/m35_abort.db`
- Result:
  - command returns `open_session_exists`
  - no new session created
  - `recovery_events.action_taken=abort_start`

### 4) idle_timeout exceeded
- DB: `codeburn/phase1/examples/m35_idle.db`
- Args: `--idle-timeout-minutes 0`
- Result:
  - previous session closed with `ended_by=idle_timeout`
  - previous session `data_quality=partial`
  - `recovery_events.reason` includes `idle-timeout-0m`

## M4 Report Contract Evidence
Command:
```powershell
python codeburn/phase1/codeburn_report.py --db codeburn/phase1/examples/m35_auto_close.db --format text
```

Observed fixed lines:
- `Data quality: complete / partial / recovered / invalid` (current sample output: `complete`)
- `Token comparability: true / false` (current sample output: `false`)
- `File activity: git-visible only`
- `File reads: unsupported`

## Test Execution Status
- `test execution degraded`: environment blocks pytest temp/cache paths.
- `validator gate passed`: runtime behavior is validated through executable smoke evidence.
- Not equivalent to full pytest pass.

## Verdict
- M3.5 status: **PASS (runtime smoke)**
- M4 status: **PASS (fixed report fields present)**

## Next Step
1. Stabilize local test permission path so `tests/test_codeburn_phase1_session_recovery.py` and `tests/test_codeburn_phase1_report.py` can run in full pytest mode.
2. After pytest path is unblocked, run:
   - `python -m pytest tests/test_codeburn_phase1_session_recovery.py tests/test_codeburn_phase1_report.py -q`
3. Then proceed to M5 retry signal with clean session-boundary confidence.
