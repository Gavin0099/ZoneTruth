# Runtime Event Contract

This contract defines the shared payload shape that all harness adapters should normalize to before calling runtime governance core logic.

The goal is portability:

- Claude Code
- Codex
- Gemini
- future harnesses

must all map their native hook/event payloads into the same structure.

## Session-Start Event

```json
{
  "event_type": "session_start",
  "project_root": ".",
  "plan_path": "PLAN.md",
  "task": "Refactor Avalonia boundary",
  "rules": ["common", "refactor"],
  "risk": "medium",
  "oversight": "review-required",
  "memory_mode": "candidate",
  "impact_before_files": ["before.cs"],
  "impact_after_files": ["after.cs"],
  "metadata": {
    "harness": "shared",
    "session_id": "2026-03-12-00"
  }
}
```

Required fields:

- `event_type`
- `project_root`
- `risk`
- `oversight`
- `memory_mode`

## Pre-Task Event

```json
{
  "event_type": "pre_task",
  "project_root": ".",
  "task": "Runtime governance",
  "rules": ["common", "python"],
  "risk": "medium",
  "oversight": "review-required",
  "memory_mode": "candidate",
  "response_file": null,
  "metadata": {
    "harness": "codex",
    "session_id": "2026-03-12-01"
  }
}
```

Required fields:

- `event_type`
- `project_root`
- `rules`
- `risk`
- `oversight`
- `memory_mode`

## Post-Task Event

```json
{
  "event_type": "post_task",
  "project_root": ".",
  "task": "Runtime governance",
  "rules": ["common", "python"],
  "risk": "medium",
  "oversight": "review-required",
  "memory_mode": "candidate",
  "response_file": "ai_response.txt",
  "checks_file": "checks.json",
  "create_snapshot": true,
  "snapshot_summary": "Candidate memory from task output",
  "metadata": {
    "harness": "gemini",
    "session_id": "2026-03-12-01"
  }
}
```

Required fields:

- `event_type`
- `project_root`
- `risk`
- `oversight`
- `memory_mode`

Additional rule:

- `response_file` is required for `post_task` unless the adapter provides response text directly through another wrapper layer.
- `checks_file` is optional, but recommended when the post-task flow should replay structured evidence (test results, diff-derived checks, SARIF-like warnings, domain fixtures) instead of only the raw assistant response.

## Adapter Rule

Adapters may transform native payloads into this shape, but they must not reinterpret governance policy.

`session_start` is currently a shared-governance event intended for startup context and handoff flows; native harness adapters may adopt it later.
