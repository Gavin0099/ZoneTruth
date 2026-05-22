# CodeBurn — Claude Artifact Ingestion Contract

> Written: 2026-05-20
> Status: **BINDING** — P3.0 spec document, authorizes schema extension and ingestion implementation
> Scope: Claude Code .jsonl session log artifacts, L1.5 acquisition surface only
> Depends on: CODEBURN_TOKEN_PROVENANCE_ONTOLOGY.md, CODEBURN_ACQUISITION_AUTHORITY_MODEL.md
> Authorizes: P3.1 schema extension, P3.2 ingestion parser, P3.3 provenance writer

---

## What This Document Authorizes

This document authorizes the implementation of L1.5 (post-hoc session log ingestion)
for Claude Code artifacts. It defines:

1. The admissible artifact format and record types
2. The epistemic class of evidence that ingestion may produce (Class C only)
3. The schema extensions required
4. The invariants that implementation must preserve
5. The negative-path specifications (what implementation must handle correctly)

Nothing in this document authorizes runtime observation, real-time capture,
or any acquisition mode other than post-hoc log ingestion.

---

## The Artifact: Claude Code `.jsonl` Session Files

Claude Code stores session logs as newline-delimited JSON files (`.jsonl`).
Each line is a self-contained JSON record. Files are stored at:

```
~/.claude/projects/<project-slug>/<session-uuid>.jsonl
```

### Observed Record Types

| Type | Contains token data | Admissible | Notes |
|------|---------------------|------------|-------|
| `assistant` | yes — `message.usage` | yes | Primary token evidence source |
| `user` | no | no — metadata only | Session scope context |
| `system` | no | no | Session initialization |
| `progress` | no | no | Streaming artifacts, not completed responses |
| `queue-operation` | no | no | Session queue management |
| `file-history-snapshot` | no | no | File tracking, not interaction data |

**Only `type=assistant` records are admissible for token extraction.**

All other record types are ignored during ingestion. They are not errors.
They are not quarantined. They are structurally not-applicable.

---

## The Token Evidence Structure (assistant records)

For `type=assistant` records, token data is at `message.usage`:

```json
{
  "type": "assistant",
  "sessionId": "...",
  "uuid": "...",
  "timestamp": "...",
  "message": {
    "role": "assistant",
    "usage": {
      "input_tokens": N,
      "output_tokens": M,
      "cache_creation_input_tokens": X,
      "cache_read_input_tokens": Y,
      "service_tier": "standard",
      "inference_geo": "not_available"
    }
  }
}
```

### Admissible Fields

| Field path | Admitted as | Notes |
|---|---|---|
| `message.usage.input_tokens` | `prompt_tokens` (Class C) | May be 0 when cache dominates |
| `message.usage.output_tokens` | `completion_tokens` (Class C) | Completion token count |
| `message.usage.cache_creation_input_tokens` | `cache_creation_tokens` (Class C) | New cache creation cost |
| `message.usage.cache_read_input_tokens` | `cache_read_tokens` (Class C) | Cache hit reads |
| `uuid` | `source_record_id` | Record identifier for provenance |
| `timestamp` | `source_record_timestamp` | Record timestamp for ordering |

### Inadmissible Fields (must not influence any CodeBurn claim)

| Field | Why inadmissible |
|---|---|
| `message.usage.service_tier` | Operational metadata — not a token quantity |
| `message.usage.inference_geo` | Geographic routing — not a token quantity |
| `message.usage.cache_creation.ephemeral_5m_input_tokens` | Sub-field of cache — not yet in scope |
| `message.usage.cache_creation.ephemeral_1h_input_tokens` | Sub-field of cache — not yet in scope |
| `message.model` | Model identity — not a token evidence field |
| `cwd` | Working directory — not a token evidence field |
| `version` | Client version — not a token evidence field |

**Inadmissible fields must not be stored in the token provenance table.**
Storing them as "additional context" without a separate authorization is
a scope expansion that this contract does not permit.

---

## Token Count Interpretation: The Cache Problem

Claude Code token accounting includes cache fields that make the total token
picture more complex than `input_tokens + output_tokens`:

```
total_billed_tokens ≈ input_tokens + output_tokens + cache_creation_input_tokens
                      (cache_read_input_tokens typically billed at reduced rate)
```

**This contract does not authorize total billing computation.**

Reasons:
1. Cache billing rates are provider-defined and may change
2. `cache_creation_input_tokens` represents a different cost than regular input
3. Computing billing from token fields would cross from observation into cost governance
4. Cost governance requires a separate contract (currently prohibited by AC3)

**What ingestion may record:** individual field values, as observed in the log.
**What ingestion may NOT compute:** totals, aggregates, billing estimates, cost-per-session.

---

## The Epistemic Class: Class C (Observer-Reconstructed)

All token evidence produced by this ingestion is Class C.

**It is Class C because:**
- CodeBurn arrives after the interaction completes
- Evidence is reconstructed from log artifacts, not observed in real-time
- Log completeness is not guaranteed (logs may be truncated, partial, or corrupt)
- The log records what was reported to the log writer, not what the provider computed

**This class assignment is permanent and unconditional.**

It does not change if:
- All records are present and valid
- Token counts are internally consistent
- The same session is ingested multiple times with identical results
- The provider API is verified as the originator of the session

Consistency and completeness do not upgrade Class C to Class A or Class B.
The temporal distance (post-hoc) is what determines the class, not the data quality.

---

## Invariants: What Implementation Must Preserve

The following invariants must hold for every ingestion path:

### I1 — Class C Assignment Is Unconditional

```
provenance_class = "C"
real_time_observed = False
```

These values must be set at record creation and must not be modifiable by ingestion logic.
They are not defaults with override paths. They are structural constants.

### I2 — Missing Token Fields ≠ Zero Usage

If `message.usage` is absent from an assistant record, or if individual fields
within `message.usage` are absent:

```
CORRECT:  token field = NULL (typed null, incomplete evidence)
WRONG:    token field = 0    (implies zero usage, which is not the same as absence)
```

`NULL` means "not present in log artifact."
`0` means "recorded as zero."
These are epistemically different states. `NULL` must not be collapsed to `0`.

### I3 — Malformed Records Are Quarantined, Not Dropped

If a line in the `.jsonl` file cannot be parsed as valid JSON, or if a parsed
record has a structure that does not match the expected schema:

```
CORRECT:  quarantine the record — store source_artifact_path + line_number +
          raw_content + failure_reason; do not write token evidence
WRONG:    silently skip the line
WRONG:    log a warning and continue without persisting the failure
WRONG:    write partial evidence from a partially-parsed record
```

Quarantine means: **the failure is persisted and traceable**. Silent drops are
not acceptable because they make ingestion completeness unverifiable.

### I4 — Source Artifact Path and Line Number Are Required

Every token evidence record must carry:

```
source_artifact_path  — absolute path to the .jsonl file
source_artifact_line  — 1-indexed line number of the source record
```

Without these, the evidence is not reconstructable or auditable. Records without
source provenance must not be written.

### I5 — No Authority Upgrade Through Ingestion

Ingestion must not set or imply:

```
token_source = 'provider'   ← Class A only
real_time_observed = True   ← false for all Class C
analysis_safe_for_decision = True  ← permanently false per Authority Ceiling Contract
```

These values must not appear in any ingestion output, default, or fallback path.

### I6 — Reconstruction Gap Must Be Declared

Every ingestion record must carry:

```
reconstruction_gap_declared = True
```

This is not an opt-in field. It is a required assertion that the ingester
acknowledges the temporal distance between the original interaction and this
record.

---

## Schema Extension Authorization

This contract authorizes the following schema additions to `schema.sql`:

### New Table: `step_ingestion_provenance`

```sql
CREATE TABLE IF NOT EXISTS step_ingestion_provenance (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  step_id TEXT NOT NULL,
  provenance_class TEXT NOT NULL CHECK (provenance_class IN ('A', 'B', 'C', 'D', 'E')),
  real_time_observed INTEGER NOT NULL DEFAULT 0 CHECK (real_time_observed IN (0, 1)),
  reconstruction_gap_declared INTEGER NOT NULL DEFAULT 1 CHECK (reconstruction_gap_declared IN (0, 1)),
  source_artifact_path TEXT NOT NULL,
  source_artifact_line INTEGER NOT NULL,
  source_record_id TEXT,
  source_record_timestamp TEXT,
  ingested_at TEXT NOT NULL,
  FOREIGN KEY(step_id) REFERENCES steps(step_id)
);
```

### New Table: `quarantined_records`

```sql
CREATE TABLE IF NOT EXISTS quarantined_records (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source_artifact_path TEXT NOT NULL,
  source_artifact_line INTEGER NOT NULL,
  raw_content TEXT,
  failure_reason TEXT NOT NULL,
  quarantined_at TEXT NOT NULL
);
```

### New Fields in `steps` Table

None. Token values are already stored in the existing `steps` table via
`prompt_tokens`, `completion_tokens`, `total_tokens`, `token_source`.

The `step_ingestion_provenance` table provides the Class C metadata without
modifying the existing schema.

---

## Negative-Path Specifications

These are the test contracts that implementation must satisfy:

### NP1 — Valid Record → Class C Evidence Written

**Input:** Valid `type=assistant` record with complete `message.usage`
**Expected:** `steps` row written with `token_source='estimated'`; `step_ingestion_provenance` row written with `provenance_class='C'`, `real_time_observed=0`, `reconstruction_gap_declared=1`
**Fail if:** `provenance_class` is anything other than `C`; `real_time_observed` is 1; `token_source` is `provider`

### NP2 — Missing Usage → Typed Null Written

**Input:** Valid `type=assistant` record where `message.usage` is absent
**Expected:** `steps` row written with token fields as `NULL` (not 0); `step_ingestion_provenance` row written with `provenance_class='C'`
**Fail if:** token fields are written as 0; record is silently dropped; no `step_ingestion_provenance` row

### NP3 — Malformed JSON → Quarantine Record Written

**Input:** `.jsonl` file line that is not valid JSON
**Expected:** `quarantined_records` row written with source path, line number, raw content, failure reason; no `steps` row; no `step_ingestion_provenance` row
**Fail if:** line is silently skipped; partial `steps` row is written; failure is only logged (not persisted)

### NP4 — Inadmissible Fields → Not Stored

**Input:** Valid `type=assistant` record with `service_tier` and `inference_geo` in usage
**Expected:** `step_ingestion_provenance` row contains no `service_tier` or `inference_geo` column
**Fail if:** any inadmissible field is stored in any table as "context"

### NP5 — Cache Tokens → Individual Fields, No Total Computed

**Input:** Valid record with `input_tokens=3`, `cache_creation_input_tokens=5808`, `cache_read_input_tokens=9364`
**Expected:** individual fields stored as-is; no `total_tokens` computed from these fields; `steps.total_tokens` is `NULL` or the sum of `input_tokens + output_tokens` only (not cache fields)
**Fail if:** a cost estimate or billed total is computed and stored

---

## What This Contract Does NOT Authorize

- Real-time token capture from Claude Code API responses
- Modification of any existing record after ingestion
- Cross-session aggregation of ingested token counts
- Comparison of ingested counts to any other source
- Using `inference_geo` or `service_tier` for any purpose
- Treating successful ingestion as evidence that logs are complete

---

*Ingestion reads artifacts that already exist.*
*It does not observe. It reconstructs.*
*The reconstruction is always partial. The partiality must be acknowledged in every record.*
