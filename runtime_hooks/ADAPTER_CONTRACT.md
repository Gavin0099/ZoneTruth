# Runtime Adapter Contract

The runtime governance layer is harness-agnostic.

`runtime_hooks/core/` contains governance decisions.
`runtime_hooks/adapters/` contains harness-specific wrappers only.

## Required rule

Adapters must not embed governance policy.

They may only:

- map harness event payloads into CLI arguments or Python function inputs
- normalize native payloads into the shared shape defined by `event_contract.md` / `event_schema.json`
- read harness-specific input locations
- forward results back to the harness in its expected format

They must not:

- redefine risk rules
- redefine oversight rules
- bypass contract validation
- bypass memory-mode restrictions

## Current adapter families

- `claude_code/`
- `codex/`
- `gemini/`

## Minimum adapter surface

Each harness should expose wrappers for:

- `pre_task`
- `post_task`
- `normalize_event`

Future optional wrappers:

- `pre_compact`
- `session_end`

## Shared payload contract

Adapters should target the shared runtime event shape documented in:

- `runtime_hooks/event_contract.md`
- `runtime_hooks/event_schema.json`
