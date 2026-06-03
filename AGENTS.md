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

## Delivery Recovery Constraints

These constraints apply to implementation sessions in this repository. Their purpose is to prevent governance work from displacing product delivery.

### 1. Vertical Slice First

Before expanding governance surface, complete one usable end-to-end product slice.

Examples:
- `analyse workout → render weekly summary → user sees actionable signal`
- `HealthKit auth → load → dashboard`

No governance expansion before the vertical slice is usable unless triggered by an observed failure.

### 2. Failure-Driven Governance Only

New governance surface is allowed only after an observed failure.

Valid triggers:
- unsafe behavior
- irreversible failure
- false-positive / false-negative
- authority escalation
- replay inconsistency
- production ambiguity

Invalid triggers:
- future extensibility
- theoretical completeness
- semantic elegance
- might be useful later

### 3. Session Done Definition Required

Every implementation session must have a concrete DONE condition before file edits begin.

If the user provides DONE, use it directly.
If the user does not provide DONE, propose one measurable product outcome and wait for confirmation.

Format:

`DONE = <one measurable product outcome>`

Do not infer broad project direction as DONE. DONE must be narrow and testable.

### 4. Hard Stop After Done

When DONE is achieved, stop.

Do not add extra telemetry, readiness, qualification, runtime hooks, artifacts, or governance work unless there is an observed failure.

### 5. Result-First Final Report (reporting convention, not a gate)

Final reports should be result-first, not process-first.

Use this format:

1. Result: Done / Not done
2. Capability increased:
3. Changed files:
4. Validation:
5. Governance surface change: none / list
6. Remaining blocker:

## Repo-Specific Risk Levels
<!-- governance:key=risk_levels -->

- HIGH: any change to `WeeklyDashboardView.swift` rendering functions (`admissibleLabel`, `progressionBarLabel`, `WeeklyCTAPresenter`) — claim ceiling logic lives here; wrong output directly exposes clinical overclaiming
- HIGH: any change to `WeeklySignals.swift` classifier (`WeeklyInferenceClassifier`, `WeeklyAdaptationSignal.from`, `WeeklyTrainingStateSignal.from`) — classifier gates the rendering contract; wrong output bypasses the ceiling
- HIGH: any change to `WeeklyRenderingContractTests.swift` test assertions — these are the rendering contract lock; weakening tests silently allows overclaiming
- MEDIUM: any change to `WorkoutEvaluationAdapter` or `WorkoutEvaluationPolicyFactory` — semantic evaluation path; wrong output affects goal-fit scores and training tendency wording
- MEDIUM: any change to `BodyCompositionLedger` narrative or trend computation — narrative must not attribute long-term body composition changes to Zone 2 training
- LOW: documentation, memory files, plan updates, test fixture refreshes with no rendering-contract changes

## Must-Test Paths
<!-- governance:key=must_test_paths -->

- `WeeklyDashboardView.swift` `admissibleLabel(for:)` — any change requires `WeeklyRenderingContractTests` to remain green
- `TrainingState.progressionBarLabel` — changes require `testProgressionBarLabelSetContainsNoClinicalTerms` to remain green
- `WeeklyCTAPresenter.render(...)` — changes require `testCTAWordingBoundedByAuthorityTier` to remain green
- `WeeklyAdaptationSignal.from(...)` — changes require `testAdaptationResidualDefaultIsNoSignalNotMaintenance` to remain green
- Rendering contract tests (`WeeklyRenderingContractTests`) must remain green before any merge touching weekly dashboard rendering

## L1 → L2 Escalation Triggers
<!-- governance:key=escalation_triggers -->

- Any change to what counts as "admissible" rendering output (adding new positive direction labels to `.noSignal`, changing `admissibleLabel` output) — requires explicit evidence from code review that no existing test is weakened
- Any change to `WeeklyRenderingContractTests` assertions to make them less strict — requires human approval; softening contract tests is a semantic regression
- Any change that adds `localizedLabel` calls in place of `admissibleLabel` in view rendering — automatic escalation; this was the failure mode P3a was built to fix

## Repo-Specific Forbidden Behaviors
<!-- governance:key=forbidden_behaviors -->

- Do NOT call `TrainingState.localizedLabel` directly in SwiftUI view rendering — use `admissibleLabel(for:)` or `progressionBarLabel`; direct `localizedLabel` use was the P3a failure mode
- Do NOT attribute body composition changes (fat loss, muscle gain) to Zone 2 training in narrative text — `BodyCompositionLedger` comments explicitly forbid this causal claim
- Do NOT weaken `WeeklyRenderingContractTests` assertions to fix a build failure — if a test fails, fix the production code, not the test
- Do NOT expand the weekly dashboard rendering surface (new UI sections, new signal types) before the current rendering contract tests are green
- Do NOT use `.maintenance` as a fallback direction when evidence is insufficient — `.noSignal` is the correct residual; this was an explicit fix documented in commit history

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

