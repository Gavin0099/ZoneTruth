# CodeBurn v2 Phase 1 Test Plan (7-Day)

## Scope
Validate Phase 1 observability wrapper can produce boundary-clear and trustable telemetry.

## Day 0 Setup
1. Initialize DB with schema:
```powershell
sqlite3 codeburn_phase1.db ".read codeburn/phase1/schema.sql"
```
2. Confirm schema exists:
```powershell
sqlite3 codeburn_phase1.db ".tables"
```

## Daily Loop (Day 1-7)
Run at least one complete session envelope:
1. `session start`
2. `run planning/execution/test` steps
3. `session end`
4. `report`

Capture artifacts:
- session row
- step rows
- changed_files rows
- signals rows
- recovery_events rows (if any)

## Daily Validation Checklist
- session required fields present
- step required fields present
- no `ended_at < created_at`
- all signals satisfy:
  - `advisory_only = 1`
  - `can_block = 0`
- token comparability guard respected
- git visibility boundary disclosure present in report

## Activation Coverage Checklist
Within 7 days, must observe at least once:
- retry signal path (`>=3` retry sequence)
- confidence downgrade path (`changed_files > 0` during retry sequence)
- session recovery path (`auto_close_previous` OR `resume_previous` OR `abort_start`)
- idle-timeout closure path (`ended_by=idle_timeout`, `data_quality=partial`)

## Exit Criteria
Phase 1 is acceptable when:
- all daily validation checks pass for 7 days
- no invalid rows are generated
- retry signal remains advisory-only in all cases
- observability boundary is consistently disclosed

## Notes
Phase 1 does not claim waste/correctness/governance enforcement.
It only claims stable observability with explicit boundary semantics.
