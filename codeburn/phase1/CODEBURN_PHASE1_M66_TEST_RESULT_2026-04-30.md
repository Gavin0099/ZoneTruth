# CodeBurn v2 Phase 1 - M6.6 Test Result (2026-04-30)

## Scope
- Repo: `E:\BackUp\Git_EE\ai-governance-framework`
- Target: deterministic analysis output

## Deterministic Rules Applied
1. Stable query ordering:
- `steps`: `ORDER BY started_at ASC, step_id ASC`
- `changed_files`: `ORDER BY file_path ASC`
- `signals`: `ORDER BY id ASC, step_id ASC`
- `latest` resolution: `ORDER BY created_at DESC, session_id DESC`

2. No unstable runtime fields:
- analysis output does not include current timestamp
- no extra alias-resolution text in output payload

## Test Added
- `tests/test_codeburn_phase1_analyze_deterministic.py`
- Contract:
  - same session id
  - run `codeburn_analyze.py --format json` twice
  - assert `output1 == output2` (byte-for-byte)

## Execution Boundary
test execution degraded; validator gate passed; not equivalent to full pytest pass

## Verdict
- M6.6 status: **PASS (deterministic contract implemented)**
