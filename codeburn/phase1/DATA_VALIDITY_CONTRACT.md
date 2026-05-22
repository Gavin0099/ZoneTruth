# CodeBurn v2 Phase 1 Data Validity Contract

## Goal
Define deterministic validity rules so Phase 2 can trust Phase 1 telemetry.

## Session Recovery Rules
When `session start` detects an open session:
- must record one `recovery_events` row
- allowed `action_taken`:
  - `auto_close_previous`
  - `resume_previous`
  - `abort_start`

Required fields in `recovery_events`:
- `previous_session_id`
- `action_taken`
- `reason`
- `created_at`

Idle timeout policy:
- `session_idle_timeout_minutes = 60`
- timeout close must set:
  - `ended_by = idle_timeout`
  - `data_quality = partial`

## Required Fields
### sessions
Required:
- `session_id`
- `task`
- `created_at`
- `data_quality`

Nullable:
- `ended_at`

### steps
Required:
- `step_id`
- `session_id`
- `step_kind`
- `command`
- `started_at`

Nullable:
- `exit_code` only when command did not start

## Data Quality States
- `complete`: normal start/run/end flow observed
- `partial`: timeout or interrupted flow
- `recovered`: session continuity restored by explicit recovery action
- `invalid`: required fields or chronology violated

## Invalid Conditions (minimum)
A record must be marked `invalid` when any of the following is true:
- missing any required field listed above
- `ended_at < created_at`
- step references missing `session_id`
- `signals.can_block = 1` (Phase 1 hard rule violation)
- `signals.advisory_only = 0` (Phase 1 hard rule violation)

## Observability Boundary Disclosure
Reports must state:
- file reads: `unsupported`
- git-visible changes: `supported`
- untracked files: `supported via git status`
- rename detail: `partial`

## Comparability Guard
Never assume token comparability when provider data is absent.

Rule:
- if `token_source != provider` -> `comparability_token = 0`
- only `token_source = provider` may set `comparability_token = 1`

## Token Observability Guard
Token observability and token comparability are not the same contract.

NOTE: `TOKEN_TELEMETRY_CONTRACT_V0_1.md` defines provenance disclosure requirements
(for example `token_source_summary` and `provenance_warning`) that are NOT currently
enforced in the Phase 1/2 runtime or current report surfaces.

Current Phase 1/2 runtime MUST NOT be assumed to provide provenance-complete token
observability, even when `token_observability_level` is reported as `step_level`.

Consumers MUST treat all current token observability as provenance-incomplete unless
explicit provenance disclosure is present.

Rule:
- `token_observability_level = step_level` only when provider-backed token totals are present
- `token_observability_level = coarse` when token totals are estimated, or when provider provenance exists without step-level totals
- `token_observability_level = none` when no token quantity is present
- `token_observability_level = coarse` does not authorize decision use and does not imply `comparability_token = 1`

`comparability_duration` and `comparability_change` are tracked separately.

## Transitional Rule
Until `provenance_warning` is implemented in runtime and report surfaces, any
`token_observability_level = step_level` MUST be treated as provenance-unverified and
MUST NOT be interpreted as provider-only.

Absence of `provenance_warning` MUST NOT be interpreted as absence of mixed sources.

## Retry Signal Noise Control
If retry rule triggers (`>= 3` consecutive retry steps):
- default confidence: `medium`
- downgrade to `low` when any retry step has `changed_files > 0`

Hard rule:
- `advisory_only = true`
- `can_block = false`
