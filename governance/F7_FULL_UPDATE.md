# F-7 Full Update

Status: extracted from AGENTS.md
Semantic change: no
Runtime behavior change: no
Enforcement change: no

## Purpose

F-7 is the AI Governance Full Update workflow. A governed submodule pointer
update is Stage 1 of F-7, not the whole workflow.

When the user asks to update or adopt the latest AI Governance through F-7, F-7
must execute the full adoption/update workflow or explicitly report a blocker.

A submodule pointer update alone is insufficient and must be reported as
`partially_updated`, not completed.

## Required Stages

1. framework pointer update
2. repo-local instruction refresh
3. memory writer coverage check
4. hook / validator coverage check
5. existing memory normalization status check
6. final adoption status report

## Layered Status Fields

```text
framework_pointer: updated | already_current | blocked | not_present | not_verified
repo_local_instruction: updated | already_current | blocked | missing | not_verified
memory_writer_coverage: verified | updated | blocked | missing | not_applicable | not_verified
hook_validator_enforcement: verified | updated | blocked | missing | not_applicable | not_verified
existing_memory_normalization: completed | needed | blocked | not_applicable | not_verified
final_status: full_update_completed | already_current | partially_updated | blocked | not_submodule_consumer | not_verified
```

`full_update_completed` may be used only when every required stage is
`updated`, `already_current`, `verified`, `completed`, or `not_applicable`.

If any required surface is `missing`, `needed`, `blocked`, or `not_verified`,
the final status must not be `full_update_completed`.

## Non-Claims

This protocol defines the required F-7 reporting contract. It does not by
itself implement updater automation for all stages.

Not claimed unless separately implemented and validated:
- updater automation performs all F-7 stages
- hooks changed
- validators changed
- artifact schema changed
- existing memory was normalized
