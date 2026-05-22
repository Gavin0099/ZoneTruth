# CodeBurn -- Codex Log Ingestor Spec (P5.0)

> Written: 2026-05-21
> Status: P5.0 -- spec before implementation
> Scope: Codex CLI session JSONL ingestion
> Depends on:
>   CODEBURN_CODEX_ARTIFACT_CONTRACT.md (field admissibility)
>   CODEBURN_PROVIDER2_ADMISSION_SIGNOFF_CODEX.md (gate clearance)
>   CODEBURN_ACQUISITION_SEMANTIC_FREEZE.md (semantic constraints + TNP)
>   CODEBURN_CROSS_PROVIDER_COMPARABILITY_BOUNDARY.md (aggregation prohibition)
> Implementation: codeburn/phase2/codex_log_ingestor.py (P5.3)
> Tests: tests/test_codeburn_codex_negative.py (P5.1)

---

## Purpose

Ingest Codex CLI session JSONL logs as Class C (observer-reconstructed) evidence.

The purpose is NOT to make Codex data comparable with Claude.
The purpose IS to acquire Codex token observation records under the same epistemic
constraints as Claude, independently labeled, into the same DB.

---

## Non-Goals (Explicit)

이 ingestor 가 절대 하지 않는 것:

1. **cross-provider aggregation**: Codex rows + Claude rows 합산 금지
2. **billing computation**: 어떤 형태의 비용 계산도 금지
3. **reasoning token characterization**: `reasoning_output_tokens` 저장, 계산, 분석 금지
4. **provider efficiency ranking**: "Codex is cheaper than Claude" 유형의 추론 생성 금지
5. **comparability assertion**: Codex `output_tokens` ≠ Claude `output_tokens` (NST-1)
6. **total_tokens storage**: Codex log 가 `total_tokens` 를 제공하더라도 NULL 유지

---

## Admissible Record Selection

Only records matching ALL of the following conditions:

```python
record["type"] == "event_msg"
record["payload"]["type"] == "token_count"
record["payload"]["info"]["last_token_usage"] exists
```

All other records: **skip** (not quarantine -- they are structurally valid, just non-token).

Exception: if `type == "event_msg"` AND `payload.type == "token_count"` BUT
`payload.info.last_token_usage` is absent → **quarantine** (malformed token_count record).

---

## Admissible Field Extraction

From a selected record, extract ONLY:

| Source path | Stored as | Notes |
|---|---|---|
| `timestamp` (record top-level) | `started_at` in steps | ISO8601 |
| `payload.info.last_token_usage.input_tokens` | `prompt_tokens` | NULL if absent |
| `payload.info.last_token_usage.output_tokens` | `completion_tokens` | NULL if absent; reasoning EXCLUDED |
| session UUID (from filename or session_meta) | `session_id` | see Session Identity below |

All other fields: **not extracted, not stored, not passed to any downstream layer**.

---

## IAF Enforcement (Inadmissible Field Categories)

These MUST be enforced at code level, not just policy.

### IAF-1: total_token_usage.* (ALL sub-fields)

```
total_token_usage.input_tokens    → NEVER stored as prompt_tokens
total_token_usage.output_tokens   → NEVER stored as completion_tokens
total_token_usage.cached_input_tokens → never stored
total_token_usage.reasoning_output_tokens → never stored
total_token_usage.total_tokens    → never stored
```

Reason: `total_token_usage` is a cumulative session total.
On turn 1, `total_token_usage == last_token_usage` -- this is the camouflage window (AR-1b).
Storing `total_token_usage` as per-turn data produces correct values on turn 1
and silently wrong values on all subsequent turns.

Implementation requirement: do NOT read from `payload.info.total_token_usage` at all.
The key `total_token_usage` must be absent from any extraction code path.

### IAF-2: reasoning_output_tokens (from both last_ and total_)

```
last_token_usage.reasoning_output_tokens  → NEVER stored
total_token_usage.reasoning_output_tokens → NEVER stored (see IAF-1)
```

Reason: Reasoning Separation Principle. No Claude equivalent.
`completion_tokens` = `last_token_usage.output_tokens` (which already excludes reasoning).
No new column for reasoning tokens is authorized.

### IAF-3: total_tokens (from both last_ and total_)

```
last_token_usage.total_tokens  → NEVER stored (total_tokens column = NULL always)
total_token_usage.total_tokens → NEVER stored (see IAF-1)
```

Reason: billing computation forbidden. The `total_tokens = NULL` policy
applies to Codex identically to Claude.
The fact that Codex explicitly provides `total_tokens` in the log does NOT
authorize storage or use. (AG-6 Output 3, item 5 of P5-admission.3)

### IAF-4: cached_input_tokens (from both last_ and total_)

```
last_token_usage.cached_input_tokens  → NEVER stored
total_token_usage.cached_input_tokens → NEVER stored (see IAF-1)
```

Reason: billing computation forbidden. Same policy as Claude's
`cache_read_input_tokens` exclusion.

### IAF-5: model_context_window

```
payload.info.model_context_window → NEVER stored
```

Reason: operational metadata.

### IAF-6: rate_limits.* (ALL sub-fields)

```
payload.rate_limits.* → NEVER stored
```

Reason: operational metadata (used_percent, resets_at, etc.).

### IAF-7: session_meta operational fields

```
session_meta.payload.cwd          → NEVER stored
session_meta.payload.cli_version  → NEVER stored
session_meta.payload.source       → NEVER stored
session_meta.payload.model_provider → NEVER stored
session_meta.payload.originator   → NEVER stored
```

Reason: operational metadata.

### IAF-8: SQLite surface

```
state_5.sqlite (threads.tokens_used) → NEVER used as acquisition source
logs_2.sqlite                        → NEVER used as acquisition source
```

Reason: Dual Acquisition Surface Rule. JSONL is the sole acquisition surface.
SQLite is inadmissible not because it is unreliable, but because it is a
different acquisition path. Using both paths for the same evidence would
violate the provenance identity contract.

Implementation requirement: `ingest_codex_session()` accepts a JSONL file path.
No SQLite path parameter exists or is accepted.

---

## Session Identity

Codex JSONL filename: `rollout-{ISO8601_timestamp}-{UUID_v7}.jsonl`

Session UUID: extracted from the filename (UUID portion) or from the
`session_meta` record's `payload.id` field (whichever is present first).

The session_id written to the `sessions` table uses this UUID.

If no UUID can be extracted: the session is quarantined entirely
(session_id cannot be fabricated).

---

## Malformed Record Handling

A record is **malformed** if any of the following:
- JSON parse failure
- `type == "event_msg"` AND `payload.type == "token_count"` BUT `payload.info` absent
- `type == "event_msg"` AND `payload.type == "token_count"` AND `payload.info` present
  BUT `payload.info.last_token_usage` absent
- Partial record (truncated write -- detected by missing closing brace)

Malformed records → `quarantined_records` table, NOT silently dropped.

Records of other types (`response_item`, `turn_context`, `session_meta`)
that are skipped are NOT quarantined -- they are valid records, just non-token.

### Empty session handling

A session JSONL with NO `token_count` records produces:
- Zero rows in `steps` for this session
- The `sessions` row still written (to record the session's existence)
- NOT a "zero-token" row in `steps`

```
zero token_count records = no token observation for this session
zero token_count records != input_tokens=0, completion_tokens=0
```

The absence is the observation. It must not be coerced into zero.

---

## Schema

Uses **existing tables only**. No new tables. No new columns.

| Table | Usage |
|---|---|
| `sessions` | One row per Codex session (JSONL file) |
| `steps` | One row per admissible `token_count` record |
| `step_ingestion_provenance` | One row per `steps` row (provenance identity) |
| `quarantined_records` | Malformed records |

Column mapping for `steps`:

| Column | Value | Note |
|---|---|---|
| `provider` | `'codex'` | distinguishes from `'claude'` |
| `prompt_tokens` | `last_token_usage.input_tokens` | NULL if absent |
| `completion_tokens` | `last_token_usage.output_tokens` | NULL if absent; reasoning excluded |
| `total_tokens` | `NULL` | always NULL -- IAF-3 |
| `token_source` | `'estimated'` | Class C is always reconstructed |
| `step_kind` | `'other'` | no semantic mapping to Claude step kinds |

No new columns added for:
- `reasoning_output_tokens` (IAF-2)
- `cached_input_tokens` (IAF-4)
- Any `total_token_usage.*` field (IAF-1)

---

## Epistemic Invariants (Hard-coded, Not Configurable)

```python
_PROVIDER                    = "codex"
_EPISTEMIC_CLASS             = "Class C"
_ACQUISITION_MODE            = "session_log_ingestion"
_REAL_TIME_OBSERVED          = 0  # schema CHECK enforces this
_ANALYSIS_SAFE_FOR_DECISION  = 0  # schema CHECK enforces this
_PROVIDER_TRUTHFULNESS_ASSUMED = 0  # schema CHECK enforces this
```

These values are identical to Claude's epistemic constants.
Identity of class does NOT imply comparability (FSP-3, AG-2).

---

## Provenance Identity

Every `steps` row written has a corresponding `step_ingestion_provenance` row:

```
source_artifact_path = absolute resolved path of the JSONL file
source_record_line   = 1-indexed line number of the token_count record
source_record_offset = byte offset of the token_count record
```

These follow the P4 provenance identity pattern
(CODEBURN_CLAUDE_REPLAY_PROVENANCE_CONTRACT.md) applied to Codex.

Replay stability: re-ingesting the same JSONL produces the same
(source_artifact_path, source_record_line, source_record_offset) pairs.
Replay stability does NOT collapse observation distance (Anti-Collapse Axiom).
Replay stability does NOT upgrade epistemic class (TNP).

---

## What This Ingestor Cannot Do

These are intentional constraints, not capability gaps:

```
Cannot: determine if Codex computed tokens correctly (FSP-4)
Cannot: produce billing-safe totals (IAF-3, AC4)
Cannot: compare output_tokens with Claude output_tokens (NST-1)
Cannot: characterize reasoning behavior (IAF-2)
Cannot: verify JSONL completeness against runtime (FSP-2)
Cannot: combine Codex and Claude token counts (P1 prohibition)
Cannot: upgrade evidence from Class C to Class A/B (CODEBURN_ACQUISITION_SEMANTIC_FREEZE.md)
Cannot: use SQLite as a corroborating acquisition surface (IAF-8)
Cannot: treat temporal consistency as epistemic upgrade (TNP)
```

---

## Implementation Tranche Order

```
P5.0 (this document): spec
P5.1: negative-path tests (written before implementation -- lock invariants first)
P5.2: schema extension review (confirm no new columns needed)
P5.3: parser + provenance writer
P5.4: smoke command
P5.5: replay/provenance verification
```

P5.3 may only begin after P5.1 tests are written and confirmed as XFAIL.
P5.3 is complete when all P5.1 tests pass.

---

*This spec exists to ensure Codex enters the system without eroding P0--P4 boundaries.*
*The ordering (spec → tests → implementation) is the boundary enforcement mechanism.*
