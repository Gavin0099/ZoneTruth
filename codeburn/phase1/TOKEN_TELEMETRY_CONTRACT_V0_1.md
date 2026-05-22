# Token Telemetry Contract v0.1

## Non-goals
Token telemetry must not be used to determine:

- correctness
- quality
- decision safety
- governance authority

Even when token provenance is `provider`, the result is still more trustworthy telemetry, not decision evidence.
Provider-backed token data may improve source credibility only. It must not elevate decision authority, gate eligibility, or release eligibility.

## Three-Line Token Model

### 1. Governance Authority
Token data must not directly enter gate, block, or release decisions.

### 2. Optimization Analytics
Token data may be used for efficiency comparison, but only when outcome parity is preserved.

### 3. System Health / Pressure Signal
Token data may act as an early warning proxy for context pressure even before outcome failure appears.

Examples of pressure-risk interpretations:

- truncation risk
- instruction dilution
- memory contamination
- reasoning fragmentation

## Core Principles

- `token = efficiency signal + pressure signal`
- `token != correctness signal`
- `token != authority signal`
- `provider_token = higher source credibility, not higher authority`
- `mixed estimated + provider must be disclosed, not flattened`

## Mixed-Source Disclosure Rules

When token telemetry combines estimated and provider-backed fields in the same reportable surface:

- it must not be silently presented as `step_level`
- the report must disclose `token_source_summary`
- the report must distinguish fully provider-backed totals from mixed provenance totals

Minimum disclosure shape:

- `token_source_summary: provider | estimated | mixed | unknown`

Interpretation rules:

- `provider` means all reported decision-relevant token fields are provider-backed
- `estimated` means all reported token fields are estimated or inferred
- `mixed` means at least one reported token field is provider-backed and at least one is estimated or inferred
- `unknown` means provenance cannot be determined

Guard rule:

- `mixed` must not be rendered as implicit `step_level`
- if a surface needs observability labeling, mixed provenance must remain disclosed as mixed and must not inherit provider authority by association
- mixed-source aggregate MAY retain `step_level` observability only when at least one provider-backed step-level token record exists
- every report or reviewer-facing surface for mixed-source step-level telemetry MUST disclose `token_source_summary`
- mixed-source `step_level` MUST NOT imply provider-only provenance
- mixed-source `step_level` MUST NOT imply decision authority

## Priority Resolution: Observability vs Provenance

The most implementation-critical ambiguity is the boundary between token observability and token provenance.

- `token_observability_level` answers how complete or granular token quantity capture is
- `token_source_summary` answers whether the reported token surface is provider-backed, estimated, mixed, or unknown
- these two fields are related but not interchangeable

Implementation rule:

- reports must not use `token_observability_level` as shorthand for provenance
- if a report surface shows `step_level`, and the provenance is not fully provider-backed, it must also show `token_source_summary`
- `token_source_summary = mixed` means the surface is still mixed even if some quantities are step-level or provider-backed
- mixed provenance remains disclosure-constrained telemetry, not provider-grade evidence
- mixed-source `step_level` surfaces MUST also carry an explicit provenance warning such as `provenance_warning = mixed_sources` or an equivalent reviewer-visible warning
- therefore the allowed aggregate combination is:
  - `token_observability_level = step_level`
  - `token_source_summary = mixed`
  - `decision_usage_allowed = false`

Conservative interpretation for downstream design:

- when there is conflict between observability optimism and provenance disclosure, downstream interpretation must follow provenance disclosure
- therefore `mixed` is semantically safer than flattening mixed data into provider-like step-level trust

## Normative Interpretation Examples

TRANSITIONAL READING NOTE:

This document defines the intended token telemetry semantics for v0.1, including
provenance disclosure such as `token_source_summary` and `provenance_warning`.

However, current Phase 1/2 runtime and report surfaces do NOT fully implement
these requirements.

In particular:

- `provenance_warning` is not yet available in current runtime/report output
- `token_source_summary` may be incomplete or absent in current runtime/report output
- `token_observability_level` MUST NOT be interpreted as provenance-complete in current runtime/report output

Until full implementation, all current token observability SHOULD be treated as
provenance-incomplete by default.

These examples are normative. If a report or reviewer-facing surface displays the following combinations, they MUST be interpreted as stated below.

### Case 1 - Provider-backed step-level
`token_observability_level: step_level`
`token_source_summary: provider`
`decision_usage_allowed: false`

Interpretation:

- Step-level token totals are available and fully provider-backed.
- This indicates high observability fidelity, but does NOT imply correctness or decision safety.

### Case 2 - Estimated-only coarse
`token_observability_level: coarse`
`token_source_summary: estimated`
`decision_usage_allowed: false`

Interpretation:

- Token values are estimated and may be imprecise.
- This data is suitable only for coarse observability and optimization analysis.
- It MUST NOT be used for decision-making or quality inference.

### Case 3 - Mixed-source step-level
`token_observability_level: step_level`
`token_source_summary: mixed(provider, estimated)`
`provenance_warning: mixed_sources`
`decision_usage_allowed: false`

Interpretation:

- Step-level token totals exist, but provenance is mixed.
- The presence of provider-backed data does NOT guarantee full provenance integrity.
- This MUST NOT be interpreted as equivalent to provider-only step-level data.
- Decision usage remains disallowed.

## Minimal Schema

### `token_efficiency_observability`
- `task_intent: string`
- `context_sources_used: string[]`
- `total_tokens: int | null`
- `token_source_summary: provider | estimated | mixed | unknown`
- `provenance_warning: mixed_sources | none`
- `retry_count: int`
- `outcome_status: pass | fail | partial | unknown`
- `evidence_complete: bool`
- `repair_turns: int`
- `followup_turns: int`

Use:

- decide whether the same outcome can be reached with fewer tokens

### `token_pressure_signal`
- `prompt_tokens: int | null`
- `completion_tokens: int | null`
- `total_tokens: int | null`
- `token_source_summary: provider | estimated | mixed | unknown`
- `provenance_warning: mixed_sources | none`
- `context_source_breakdown:`
  - `instruction_tokens: int | null`
  - `memory_tokens: int | null`
  - `file_tokens: int | null`
  - `history_tokens: int | null`
  - `tool_output_tokens: int | null`
- `retry_count: int`
- `truncation_detected: bool | null`
- `instruction_dilution_risk: low | medium | high | unknown`

Use:

- observe context pressure
- observe instruction dilution
- observe memory, file, history, or tool-output bloat

## Forbidden Uses
The following interpretations are explicitly forbidden:

- `token_high -> block execution`
- `token_low -> assume quality good`
- `provider_token -> auto decision safe`
- `provider_token -> higher decision authority`
- `estimated_token -> step_level decision evidence`
- `mixed estimated + provider -> silently step_level`
- `token_reduction -> claim improvement without outcome parity`

## Why `context_source_breakdown` Is The Anchor
`total_tokens` only answers "it increased".

`context_source_breakdown` answers why it increased:

- memory is too large
- history is too long
- file context is oversized
- instructions are duplicated
- tool output is too noisy

Without a breakdown, optimization can only cut blindly. With a breakdown, the system can identify which context layer is actually bloated.

## Final Principle

- do not optimize for more precise token numbers
- optimize for token usefulness at the correct semantic layer
- do not merely save tokens
- save the wrong context