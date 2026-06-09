# AI Governance Update Protocol

Status: extracted from AGENTS.md
Semantic change: no
Runtime behavior change: no
Enforcement change: no

## Purpose

This protocol distinguishes AI Governance check/update intent from ordinary
instruction-file synchronization.

Do not treat `AGENTS.md`, `AGENTS.base.md`, or local governance instruction-file
sync as proof that the AI Governance Framework itself is current.

## Update Intent Rule

When the user asks to "Update AI Governance to latest" or equivalent Chinese
update wording, first determine whether the repository consumes AI Governance
through a submodule path such as:
- `ai-governance-framework`
- `.ai-governance-framework`

If a governance submodule exists, the request maps to the governed submodule
update workflow. Compare the nested governance HEAD with the approved target
upstream HEAD, preferably through the governed submodule updater dry-run path.

Do not claim AI Governance is already current based only on:
- `AGENTS.md` unchanged
- `AGENTS.base.md` unchanged
- parent repository `HEAD == origin/main`
- `git pull --ff-only` reporting already up to date
- clean parent repository working tree

## Valid Already-Current Evidence

A valid `already_current` conclusion for a submodule consumer must include:
- governance submodule path
- nested governance HEAD
- target upstream framework HEAD
- dry-run update result

Required response shape:

```text
AI Governance update check: <already_current | update_available | updated | not_submodule_consumer | not_verified>
governance submodule path: <path | NOT FOUND | NOT CHECKED>
nested governance HEAD: <sha | NOT CHECKED>
target framework HEAD: <sha | NOT CHECKED>
dry-run: PASS | FAIL | NOT RUN
update mode: already_current | fast_forward | detached_target_checkout | NOT CLAIMED
parent repo commit: <hash | NOT NEEDED | NOT CREATED>
```

If the session only updates instruction files, report that as an
instruction-file update and mark the AI Governance Framework update as
`not_verified`.

Invalid conclusion:

```text
AGENTS.md was updated and the parent repo is up to date, so AI Governance is current.
```

Valid partial conclusion:

```text
AGENTS.md was updated, but the AI Governance Framework submodule was not checked.
AI Governance update check: not_verified
governance submodule path: NOT CHECKED
nested governance HEAD: NOT CHECKED
target framework HEAD: NOT CHECKED
dry-run: NOT RUN
update mode: NOT CLAIMED
parent repo commit: NOT CREATED
```

## Check Vs Update Intent

Classify the user's wording before acting.

Check intent examples:
- "檢查 AI Governance 是否最新"
- "確認 AI Governance 有沒有更新"
- "verify AI Governance version"
- "check whether AI Governance is up to date"

Action: verify only. Do not update the submodule pointer.

Update intent examples:
- "幫我更新最新版 AI Governance"
- "把 AI Governance 更新到最新"
- "更新 AI Governance 到最新版"
- "Update AI Governance to latest"

Action: perform the governed update flow for a submodule consumer: detect the
governance submodule path, run dry-run, then apply the scoped submodule pointer
update if dry-run is safe and no blocker exists.

For update intent, do not stop after direct HEAD comparison when nested
governance HEAD differs from target framework HEAD. A direct HEAD comparison
may establish `update_available`, but it is not a completed update.

If the repository is a submodule consumer and no blocker exists, continue from
`update_available` to the governed update step.

Ask for confirmation only when the user intent is ambiguous or when a blocker
requires a user decision.

## Fixed Status Values

AI Governance update status must use one of these fixed values:
- `already_current`: nested governance HEAD already matches target framework HEAD.
- `update_available`: nested governance HEAD differs from target framework HEAD, but update has not yet been applied.
- `updated`: governed update flow completed and nested governance HEAD now matches target framework HEAD.
- `blocked`: update could not proceed due to dirty worktree, staged changes, dirty nested submodule, dry-run failure, missing path, or explicit blocker.
- `not_submodule_consumer`: repository does not consume AI Governance through a submodule.
- `not_verified`: the agent could not safely determine current or target governance state.

For update intent, `update_available` is an intermediate state, not a final
successful outcome. Final response must be one of:
`already_current | updated | blocked | not_submodule_consumer | not_verified`.

Updating the governance submodule pointer does not automatically authorize a
parent repository commit or push unless the user explicitly requested
commit/push or the active workflow already defines commit/push as part of the
governed update task.

If no parent repo commit is created, report:

```text
parent repo commit: NOT CREATED
```

## Non-Claims

This file does not change:
- updater behavior
- submodule update semantics
- hooks
- validators
- runtime behavior
- F-7 automation coverage
