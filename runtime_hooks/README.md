# Runtime Hooks

This directory contains the runtime governance layer.

Core hooks:

- `core/session_start.py`
- `core/pre_task_check.py`
- `core/post_task_check.py`
- `core/session_end.py`

Adapters:

- `adapters/claude_code/pre_task.py`
- `adapters/claude_code/post_task.py`
- `adapters/claude_code/normalize_event.py`
- `adapters/codex/pre_task.py`
- `adapters/codex/post_task.py`
- `adapters/codex/normalize_event.py`
- `adapters/gemini/pre_task.py`
- `adapters/gemini/post_task.py`
- `adapters/gemini/normalize_event.py`

Design rule:

- Keep tool-specific event mapping in adapters.
- Keep governance decisions in `core/`.
- Keep adapter behavior aligned with `ADAPTER_CONTRACT.md`.

Shared payload contract:

- `event_contract.md`
- `event_schema.json`

Normalization flow:

- native harness payload
- `adapters/<harness>/normalize_event.py`
- shared event shape
- `core/pre_task_check.py` or `core/post_task_check.py`
- shared governance startup can also use `session_start` directly through `dispatcher.py` or `smoke_test.py`
- shared adapter runner now accepts `session_start` as well, so startup context can be exercised through the same adapter path

Active rule injection:

- `pre_task_check.py` now returns both rule-pack selection metadata and loaded active rule content
- active rules are loaded from `governance/rules/<pack>/*.md`
- `pre_task_check.py`, `session_start.py`, and `post_task_check.py` now also accept `--contract <path/to/contract.yaml>`
- external `contract.yaml` files can contribute additional `documents`, `rule_roots`, and `validators` without hardcoding repo coupling
- when `--contract` is omitted, runtime hooks now resolve contracts in this order:
  - explicit `--contract`
  - `AI_GOVERNANCE_CONTRACT`
  - upward discovery from `project_root` or evidence file paths
- upward discovery is bounded on purpose: stop at `.git` or after ascending 3 levels
- if multiple contract candidates are found, the runtime emits a warning and continues in generic mode instead of auto-picking one
- `session_start.py` now performs validator preflight so broken external validators fail early in startup context
- runtime consumers should treat this payload as governance context, not as a general-purpose rule DSL
- runtime human output now follows a reviewer-first pattern:
  - the first compact `summary=...` line should expose the highest-signal decision context first
  - contract-aware runs should surface `contract=<domain>/<risk_tier>` when available
  - detailed fields remain below the summary line for operator drill-down
- current seed packs include `common`, `python`, `cpp`, `refactor`, `csharp`, `swift`, `avalonia`, `kernel-driver`
- pack categories distinguish `scope`, `language`, `framework`, and `platform`
- `pre_task_check.py` also exposes advisory `rule_pack_suggestions` so runtime entrypoints can see the same language/framework suggestions as `state_generator.py`
- when a high-confidence suggestion is missing from the active contract, `pre_task_check.py` emits advisory warnings without mutating `RULES`
- `suggested_rules_preview` is included to reduce operator friction when adopting the suggested pack set
- human output from `pre_task_check.py` now prints `suggested_rules_preview=...` directly
- `pre_task_check.py` can now attach `architecture_impact_preview` when `--impact-before/--impact-after` files are supplied
- if the impact preview recommends stricter `risk` or `oversight`, `pre_task_check.py` emits advisory warnings but does not mutate the contract

Test-result handoff:

- `governance_tools/test_result_ingestor.py` converts runner output into normalized `checks`
- recommended flow: test runner output -> `test_result_ingestor.py` -> runtime `checks.errors / checks.warnings / checks.summary`
- supported evidence kinds now include `pytest-text`, `junit-xml`, `sdv-text`, `msbuild-warning-text`, `sarif`, and `wdk-analysis-text`

Public API handoff:

- `governance_tools/public_api_diff_checker.py` can be passed into `post_task_check.py` with `--api-before` and `--api-after`
- this is currently used as a lightweight interface-stability signal for `refactor` tasks
- `session_end.py` now preserves public API diff evidence in runtime summaries and curated artifacts
- human output from `post_task_check.py` now includes compact evidence summary lines such as `public_api_ok=...` and `refactor_evidence_ok=...`
- refactor runs can now also require structured `error_path_inventory` and `error_behavior_diff` payloads through the same `checks-file`
- the runtime validates coverage and reviewer-note completeness, but does not prove that the error-case list is exhaustive

Kernel-driver evidence handoff:

- `governance_tools/driver_evidence_validator.py` is applied by `post_task_check.py` when `RULES` contains `kernel-driver`
- preferred evidence sources are external analysis and compiler diagnostics such as SDV / SAL / WDK outputs, merged into normalized `checks`

Domain validator handoff:

- `governance_tools/validator_interface.py` defines the shared `DomainValidator` / `ValidatorResult` interface
- `governance_tools/domain_validator_loader.py` performs validator discovery, import isolation, preflight checks, and advisory execution routing
- `post_task_check.py` now merges domain-validator findings as advisory warnings by default, while treating matched `hard_stop_rules` as runtime policy input that can still stop the task
- validator import or execution failures are wrapped into structured runtime errors instead of crashing the governance engine

Dispatcher:

- `dispatcher.py` routes a shared event JSON payload directly to `pre_task_check` or `post_task_check`
- `dispatcher.py` also routes `session_start` into the agent-start context builder
- `smoke_test.py` runs documented native example payloads end-to-end, including `session_start`
- human output from `smoke_test.py --event-type session_start` now surfaces the startup handoff summary, including expected validators and required evidence
- `smoke_test.py` can now also write machine-readable JSON envelopes with `--json-output`
- `smoke_test.py` now also accepts `--contract`, `--project-root`, and `--plan-path`, so the documented example payloads can be replayed against a real external contract repo without editing the example JSON files first
- when only `--contract` is supplied, `smoke_test.py` now defaults `project_root` and `plan_path` from the contract repo only if that contract root also contains `PLAN.md`; otherwise it preserves the example payload's original root/plan
- when a contract is supplied, smoke-test human output also surfaces `contract_source`, `contract_path`, and `domain_contract`
- `../scripts/run-runtime-governance.sh` is the shared enforcement entrypoint for hooks and CI
- `../scripts/run-runtime-governance.sh` now also forwards `--contract`, `--project-root`, and `--plan-path` into its smoke flows, so the shared shell wrapper can replay the built-in runtime examples against an external contract repo too
- `dispatcher.py` now also accepts the same `--contract`, `--project-root`, and `--plan-path` overrides, so shared event JSON files can be replayed against an external contract repo without editing the event payload first
- when only `--contract` is supplied, `dispatcher.py` now uses the contract repo as `project_root` and defaults `plan_path` to `<contract-root>/PLAN.md` only when that contract root actually contains `PLAN.md`
- when a contract is supplied, dispatcher human output also surfaces `contract_source`, `contract_path`, and `domain_contract`
- both `smoke_test.py` and `dispatcher.py` now also accept `--response-file` and `--checks-file`, so shared post-task examples can replay file-based evidence fixtures instead of only the bundled raw response text

Session close:

- `core/session_end.py` closes a session into runtime audit artifacts
- emits `artifacts/runtime/candidates/<session_id>.json`
- emits `artifacts/runtime/summaries/<session_id>.json`
- creates candidate memory snapshots and applies conservative promotion policy
- `--impact-preview-file` can now attach proposal-time `architecture_impact_preview` into the same audit trail
- `--proposal-summary-file` can now attach `proposal_summary` so proposal-time guidance is preserved into summary and curated artifacts

Session start:

- `core/session_start.py` builds an agent-start context from `state_generator.py` plus `pre_task_check.py`
- it packages suggested rules, suggested skills, suggested agent, proposal guidance, and a full `change_proposal` artifact into one startup artifact
- when `--contract` is supplied, startup context also includes discovered domain documents, extra rule roots, and validator metadata
- when a contract is resolved, human output now also shows `contract_source=...` and `contract_path=...`
- startup human output now also surfaces validator preflight status and per-validator readiness

External domain contract:

```yaml
name: usb-hub-firmware
documents:
  - docs/start_session.md
rule_roots:
  - rules
validators:
  - validators/firmware_validator.py
```

- document and validator paths are resolved relative to `contract.yaml`
- external rule packs are merged with the built-in `governance/rules/` packs
- current validator execution remains advisory-first by default, but `contract.yaml` can now declare `hard_stop_rules` so selected domain-validator violations are reclassified by the runtime policy layer instead of directly switching outcome inside the validator merge path

Examples:

- `examples/claude_code/*.native.json`
- `examples/codex/*.native.json`
- `examples/gemini/*.native.json`
- `examples/shared/*.shared.json`
- `examples/shared/session_start.shared.json`

Enforcement:

- local `pre-push` runs `scripts/run-runtime-governance.sh --mode enforce`
- CI runs the same script with `--mode ci`
- this keeps smoke coverage and focused runtime tests on the same execution path
- CI also uploads `artifacts/runtime/smoke/` so session-start handoff summaries can be reviewed after a run
- shared enforcement now also derives `change_control_summary` artifacts from the saved session-start JSON envelopes
