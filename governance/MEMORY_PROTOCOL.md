# Memory Protocol

Status: extracted from AGENTS.md
Semantic change: no
Runtime behavior change: no
Enforcement change: no

## Purpose

This protocol defines repo-local memory authority, canonical memory writing,
post-push memory, PLAN sync, and memory interpretation rules.

## Memory Surfaces

You wake up fresh each session. These files are continuity:
- Daily notes: `memory/YYYY-MM-DD.md` (create `memory/` if needed).
- Long-term memory: `memory/00_long_term.md`.

Capture decisions, durable context, and lessons. Skip secrets unless the user
explicitly asks to keep them.

## Cross-Agent Memory Channel

- Shared memory for all agents in this workspace must live under this repo's
  `memory/` directory.
- `memory/00_long_term.md` is the canonical long-term cross-agent memory file
  for main sessions.
- External/private tool memory paths are not cross-agent authority and must not
  be cited as repo governance state.
- If important context exists only in an external/private memory file, copy a
  distilled version into `memory/YYYY-MM-DD.md` and/or `memory/00_long_term.md`
  before using it for repo decisions.

## Long-Term Memory

- Load `memory/00_long_term.md` only in main sessions with the user.
- Do not load it in shared contexts.
- It can contain personal context and must not leak to strangers.
- In main sessions, it may be read, edited, and updated when durable context
  should persist.

## Write It Down

- Memory does not survive as "mental notes"; durable context must be written.
- When the user says to remember something, update `memory/YYYY-MM-DD.md` or the
  relevant repo memory file.
- When a durable lesson is learned, update the appropriate governance doc,
  tool doc, or skill.
- When a mistake is found, document it so future sessions do not repeat it.

## Canonical Memory Writer Rule

Any entry claiming `memory_type: session-derived` must be written via
`governance_tools.memory_record`, not by direct markdown append.

Canonical path:

```powershell
python -m governance_tools.memory_record `
  --what-changed "..." `
  --commit <git-sha> `
  --session-id <session-id> `
  --test-evidence "..." `
  --next-step "..." `
  --project-root .
```

All new session-derived memory entries must use the canonical writer CLI.
Direct markdown append in `- what changed:` or `- what_changed:` format is
prohibited for new entries.

The guard flags direct-format entries in files dated `>= 2026-05-01` as
`old_format_entry_after_canonical_writer_cutoff`.

Violation code: `non_canonical_writer` warning in `memory_authority_guard`.
Historical violations before the cutoff are not to be backfilled unless a
separate scoped cleanup is approved.

## Post-Push Memory Protocol

- After every push in a main session, append one short entry to
  `memory/YYYY-MM-DD.md`.
- Use the canonical writer CLI for all new entries.
- If the push introduced a durable workflow preference, also update
  `memory/00_long_term.md`.
- This protocol is portable to other repos with a local `memory/` directory.

## Memory State Trace Consistency

Memory entries must not mix completed and pending state.

`next_step` must describe the next unfinished action, not repeat an action
already recorded as completed in the same memory entry.

If a `commit` or `commit_hash` is recorded, commit state for that scope must be
treated as completed unless the entry explicitly marks the commit as failed,
local-only, or not pushed.

If push status is unknown, write `verify remote push state` instead of
`commit and push`.

If push is confirmed, `next_step` must name the next unfinished slice rather
than repeat commit or push for the completed scope.

When correcting ambiguous historical memory state, prefer adding a new
canonical corrective memory entry over rewriting historical entries.

## Memory State Interpretation Rule

Memory entries are state evidence of prior work, not authorization for current
action.

A retrieved `memory.next_step` is a candidate continuation signal only. It does
not grant permission to modify files, commit, push, close issues, upgrade
claims, or bypass current workspace checks.

Current user instruction, current workspace state, dirty-tree status, and
applicable governance rules always supersede memory content. Before acting on
any memory-derived next step, revalidate the current repo state and authority
boundary.

## PLAN Sync Protocol

- `PLAN.md` is mandatory governance state, not optional project notes.
- After each phase completion or milestone transition:
  1. update `PLAN.md` phase status or next milestone;
  2. update memory files;
  3. commit and push.
- `PLAN.md` drift is treated as governance drift.

## Definition Of Done

A change is done when:
1. session done-condition is met;
2. changes are committed and pushed;
3. one canonical memory entry is appended to `memory/YYYY-MM-DD.md`.

`PLAN.md` sync and structured memory refresh are required when a phase or
milestone transition happened.

## Cross-Agent Closeout Rule

- Framework repo (`ai-governance-framework`): strict mode. Details live in
  `governance/AGENT.md`.
- Consuming repos: minimal mode by default (`done-condition met -> commit/push
  -> one memory entry`).
- Strict closeout is opt-in for consuming repos.

Canonical tools:

```powershell
python -m governance_tools.session_closeout_entry --project-root .
python -m governance_tools.manage_agent_closeout
```

## Non-Claims

This file does not change:
- memory writer schema
- runtime hooks
- validators
- enforcement level
- #17 threshold
- historical violation disposition
