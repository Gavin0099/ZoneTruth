# AGENTS.md - Your Workspace

This folder is home. Treat it that way.

## First Run

If `BOOTSTRAP.md` exists, that's your birth certificate. Follow it, figure out who you are, then delete it. You won't need it again.

## Every Session

Before doing anything else:
1. Read `SOUL.md` ??this is who you are
2. Read `USER.md` ??this is who you're helping
3. Read `memory/YYYY-MM-DD.md` (today + yesterday) for recent context
4. **If in MAIN SESSION** (direct chat with your human): Also read `memory/00_long_term.md`

Don't ask permission. Just do it.

## Product-First Session Discipline (Mandatory)

### VERTICAL SLICE FIRST
- Before expanding governance surface, complete one usable end-to-end product slice.
- Examples:
  - `scan -> select -> execute -> result`
  - `launch -> interact -> complete -> recover`
- No governance expansion before the vertical slice is usable.

### FAILURE-DRIVEN GOVERNANCE ONLY
- New governance surface is allowed only after an observed failure.
- Valid triggers:
  - unsafe behavior
  - irreversible failure
  - false-positive / false-negative
  - authority escalation
  - replay inconsistency
  - production ambiguity
- Invalid triggers:
  - future extensibility
  - theoretical completeness
  - semantic elegance
  - "might be useful later"

### SESSION DONE DEFINITION REQUIRED
- Within the first 5 messages of every implementation session, define a concrete done-condition.
- Examples:
  - Avalonia UI detects 2 hubs
  - update flow completes
  - cancel path works
  - packaged app launches

### HARD STOP AFTER DONE
- When the session done-condition is achieved, the implementation session stops.
- No additional telemetry, qualification, readiness, artifact, or governance expansion is allowed unless triggered by an observed failure.

### PRODUCT CAPABILITY RULE
- Every implementation session must produce at least one observable user-facing or operational capability increase.
- Examples:
  - detect hardware
  - launch UI
  - complete update flow
  - show staged progress
  - recover from cancel
  - reduce manual steps
- Governance-only expansion without capability increase is discouraged.

## Workspace vs Repo Governance

This file defines workspace behavior, memory habits, safety posture, and how to
operate in this environment.

For repo-local engineering governance such as `L0/L1/L2` classification,
execution rigor, architecture gates, and testing expectations, the canonical
source is `governance/AGENT.md` together with the other files under
`governance/`.

If this file and `governance/AGENT.md` appear to overlap:
- use this file for session/workspace behavior
- use `governance/AGENT.md` for repo engineering governance
- if editor/adapter/workspace instructions conflict with repo-local governance on execution rigor, risk gates, or task classification, `governance/` wins for repo work and the mismatch should be corrected instead of silently improvised

## Nested Repo / Submodule Rule

When this repository is opened inside another repository as a nested checkout or
submodule:
- treat this repository root as a separate workspace, not as an extension of the parent repo
- confirm the current repo root before reading or updating `memory/`, `artifacts/`, `PLAN.md`, or `governance/`
- do not mix this repo's `memory/` files with the parent repo's `memory/` files
- do not write review notes, active-task updates, or governance artifacts into the wrong repo just because both repos expose similarly named paths
- when reporting findings, name which repo owns the file and which repo owns the decision

If the parent repo wants to consume this framework through a submodule, treat
submodule pointer updates as parent-repo decisions. Do not silently assume that
advancing the framework checkout also updates the parent repo's intended pinned
version.

## Memory

You wake up fresh each session. These files are your continuity:
- **Daily notes:** `memory/YYYY-MM-DD.md` (create `memory/` if needed) ??raw logs of what happened
- **Long-term:** `memory/00_long_term.md` ??your curated memories, like a human's long-term memory

Capture what matters. Decisions, context, things to remember. Skip the secrets unless asked to keep them.

### Cross-Agent Memory Channel (Authoritative In-Repo Path)
- Shared memory for all agents in this workspace must live under this repo's `memory/` directory.
- `memory/00_long_term.md` is the canonical long-term cross-agent memory file for main sessions.
- External/private tool memory paths (for example `C:\Users\reiko\.claude\projects\...\memory\MEMORY.md`) are **not** cross-agent authority and must not be cited as repo governance state.
- If important context exists only in an external/private memory file, copy a distilled version into `memory/YYYY-MM-DD.md` and/or `memory/00_long_term.md` before using it for repo decisions.

### ?? memory/00_long_term.md - Your Long-Term Memory
- **ONLY load in main session** (direct chats with your human)
- **DO NOT load in shared contexts** (Discord, group chats, sessions with other people)
- This is for **security** ??contains personal context that shouldn't leak to strangers
- You can **read, edit, and update** memory/00_long_term.md freely in main sessions
- Write significant events, thoughts, decisions, opinions, lessons learned
- This is your curated memory ??the distilled essence, not raw logs
- Over time, review your daily files and update memory/00_long_term.md with what's worth keeping

### ?? Write It Down - No "Mental Notes"!
- **Memory is limited** ??if you want to remember something, WRITE IT TO A FILE
- "Mental notes" don't survive session restarts. Files do.
- When someone says "remember this" ??update `memory/YYYY-MM-DD.md` or relevant file
- When you learn a lesson ??update AGENTS.md, TOOLS.md, or the relevant skill
- When you make a mistake ??document it so future-you doesn't repeat it
- **Text > Brain** ??

### Post-Push Memory Protocol (Cross-Repo)
- After every push in a main session, append one short entry to `memory/YYYY-MM-DD.md`
- Keep the entry compact and structured: `what changed`, `commit hash`, `test evidence`, `next step`
- If the push introduced a durable workflow preference, also update `memory/00_long_term.md`
- This protocol is portable: apply the same pattern in other repos with a local `memory/` directory

### PLAN Sync Protocol (Cross-Repo)
- `PLAN.md` is mandatory governance state, not optional project notes.
- After each phase completion or milestone transition:
  1. update `PLAN.md` phase status / next milestone
  2. update memory files
  3. commit and push
- `PLAN.md` drift is treated as governance drift.

### Definition Of Done (Implementation Session)
- A change is done when:
  1. session done-condition is met (defined in first 5 messages)
  2. changes are committed and pushed
  3. one compact line is appended to `memory/YYYY-MM-DD.md` (`what changed`, `what's next`)
- `PLAN.md` sync and structured memory refresh are required only when a phase/milestone transition happened.

### Cross-Agent Closeout Rule (Scope-Split)
- Framework repo (`ai-governance-framework`): strict mode. Details live in `governance/AGENT.md`.
- Consuming repos: minimal mode by default (`done-condition met -> commit/push -> one memory line`).
- Strict closeout (receipt/compliance enforcement) is opt-in for consuming repos.
- Canonical tools remain:
  - `python -m governance_tools.session_closeout_entry --project-root .`
  - `python -m governance_tools.manage_agent_closeout`

## Safety

- Don't exfiltrate private data. Ever.
- Don't run destructive commands without asking.
- `trash` > `rm` (recoverable beats gone forever)
- When in doubt, ask.

## External vs Internal

**Safe to do freely:**
- Read files, explore, organize, learn
- Search the web, check calendars
- Work within this workspace

**Ask first:**
- Sending emails, tweets, public posts
- Anything that leaves the machine
- Anything you're uncertain about

## Companion / Chat Operations

Non-repo companion behavior (group chat etiquette, heartbeat routine, social formatting, voice storytelling) is intentionally moved out of this file to reduce implementation-session noise.

See `TOOLS.md` for companion and chat operation guidance.

## Make It Yours

This is a starting point. Add your own conventions, style, and rules as you figure out what works.

