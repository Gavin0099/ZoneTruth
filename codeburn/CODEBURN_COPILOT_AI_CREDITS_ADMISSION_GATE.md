# CodeBurn — Copilot AI Credits Admission Gate

> Status: **ADMISSION GATE OPEN — Class D, billing_report_daily_aggregate**
> Written: 2026-05-21
> Prerequisite: `CODEBURN_GITHUB_COPILOT_AI_CREDITS_SURFACE_RESEARCH.md` (P6 research)
> Purpose: Answer all six AG-Copilot questions required before ingestion is permitted.
>
> All six answers below are binding constraints on the implementation.
> Any implementation that contradicts an answer below is non-compliant.

---

## AG-Copilot-1: Structural Absence of Code Completions

**Question:** How does the ingestor represent the structural absence of code completions?
Does it annotate that the surface is systematically incomplete?

**Answer:**

Every row written to `copilot_billing_events` carries a hard-coded column:

```sql
completions_excluded INTEGER NOT NULL DEFAULT 1 CHECK (completions_excluded = 1)
```

This column is:
- Non-nullable
- Always 1 (cannot be set to 0)
- Not overridable by any ingestor argument or caller parameter
- Present on every row regardless of model or report date

The column is not an advisory flag. It is a schema-enforced structural fact.
Any query that reads `copilot_billing_events` receives the annotation with every row.

The ingestor MUST also write a `copilot_surface_annotations` metadata row per CSV file
ingested, recording `completions_surface_present = 0` and
`completions_surface_reason = 'GitHub_billing_design: completions_do_not_consume_AI_Credits'`.

**Implementation gate:** The table DDL must be rejected by SQLite if `completions_excluded`
is set to any value other than 1. The constraint `CHECK (completions_excluded = 1)` enforces this.

---

## AG-Copilot-2: Provenance Identity Under Daily-Aggregate Granularity

**Question:** How does the daily-aggregate granularity affect provenance identity?
Is a "session" even a meaningful unit for this surface?

**Answer:**

**Session is not a meaningful unit for this surface. The unit is (user, model, date).**

The provenance identity model used for JSONL ingestion (artifact → line → offset → session_id)
partially applies, partially does not:

| Provenance field | JSONL (Class C) | Copilot CSV (Class D) | Notes |
|-----------------|-----------------|----------------------|-------|
| `source_artifact_path` | JSONL file path | CSV file path | **Applies** |
| `source_record_line` | Line number in JSONL | Row number in CSV | **Applies** |
| `source_record_offset` | Byte offset | NULL | **Not applicable** (CSV has no byte identity) |
| `session_id` | UUID from filename | NULL | **Not applicable** (no session in billing CSV) |
| `report_date` | Not applicable | YYYY-MM-DD | **New field: billing aggregate date** |
| `user_login` | Not applicable | GitHub username | **New field: user-level granularity** |

The `copilot_billing_events` table uses `(report_date, user_login, model, source_artifact_path)`
as the natural identity key. Duplicate ingestion is detected by this composite key.

`source_record_offset` MUST be NULL. `session_id` MUST NOT be stored.
Any attempt to synthesize a `session_id` from billing data is forbidden (CP-3).

---

## AG-Copilot-3: Preview vs. Actual Billing Ambiguity

**Question:** How does the ingestor handle the preview-vs-actual ambiguity?
Does it re-ingest corrected reports? What happens to records already in the DB?

**Answer:**

Every row in `copilot_billing_events` carries:
```sql
is_preview INTEGER NOT NULL DEFAULT 1 CHECK (is_preview IN (0, 1))
```

**Default is `is_preview = 1`** (conservative). GitHub has stated that preview reports
are directional signals, not precise billing. Any report ingested before GitHub confirms
it as final MUST be marked `is_preview = 1`.

**Re-ingestion handling:**

The ingestor supports a `--mark-final` flag that re-ingests a CSV with `is_preview = 0`
for rows that match the existing `(report_date, user_login, model, source_artifact_path)`.
This is a soft update, not a delete-and-reinsert, to preserve append semantics.

When `is_preview` changes from 1 → 0, a `copilot_surface_annotations` row is written
recording the correction event with a `correction_timestamp`.

**Aggregation restriction:**

Any query that reads `copilot_billing_events` MUST filter on `is_preview`.
Mixed-preview aggregation (combining `is_preview = 0` and `is_preview = 1` rows
for the same date range) is forbidden at the query layer.
The schema does not enforce this; it is a query contract.

---

## AG-Copilot-4: Preventing Back-Calculation from aic_quantity to Tokens (CP-1)

**Question:** How does CP-1 prevent back-calculation from `aic_quantity` to tokens?
What schema constraints enforce this?

**Answer:**

Three enforcement layers:

**Layer 1: Column exclusion.**
`aic_gross_amount` is NOT a column in `copilot_billing_events`. The column is never
ingested, never stored, never displayed. Its absence makes cost computation impossible
from DB data alone.

**Layer 2: No `token_count` column.**
The table has `aic_quantity` (REAL) and no `prompt_tokens`, `completion_tokens`, or
`total_tokens` columns. The normal token columns from the `steps` table do not exist here.
Any JOIN attempt between `copilot_billing_events` and `steps` on token columns will find
no columns to JOIN on.

**Layer 3: Schema documentation hard constraint.**
The column comment for `aic_quantity` reads:
```sql
-- aic_quantity: billing credits only. NOT a token count.
-- Back-calculation to tokens is FORBIDDEN (CP-1, IAF-4).
-- No pricing rate may be applied to this value.
```

The ingestor enforces: if any caller passes a `model_pricing_rate` argument, it raises
`ValueError("CP-1 violation: pricing rate application forbidden")`.

---

## AG-Copilot-5: Preventing Cross-Model Credit Comparison (CP-2)

**Question:** How does CP-2 prevent cross-model credit comparison in reports and
visualizations? What query-level guards enforce this?

**Answer:**

**Schema-level:** `copilot_billing_events` has a `model` column. Credits are stored
per-model (as the CSV provides). This means cross-model data exists in the table.

**Query-level guard (not schema, but documented contract):**
Any query that aggregates `aic_quantity` across multiple models is forbidden.
This includes:
- `SUM(aic_quantity) GROUP BY user_login` (aggregates across models for a user)
- `AVG(aic_quantity)` without `WHERE model = ?` filter

The only permitted `aic_quantity` aggregation: `SUM(aic_quantity) WHERE model = ? AND report_date = ?`
(same model, same date — this is reconstruction of the daily total for one model for one user).

**Display-level:** Any display of `aic_quantity` MUST include the `model` field in the
same row. Displaying a total without model context is forbidden.

**Reason documented in schema:**
```sql
-- Cross-model comparison of aic_quantity is FORBIDDEN (CP-2).
-- Credits embed pricing decisions. Claude Opus ≠ GPT-4o credits even if quantity equals.
-- model column MUST appear in any query that reads aic_quantity.
```

---

## AG-Copilot-6: Adversarial Re-Interpretation Attempts

**Question:** What adversarial re-interpretation attempts were made, and which
existing invariants blocked them? (AG-6 requirement)

**Answer: Six adversarial attempts tested. All blocked.**

### Attempt A6-1: "Normalize credits to tokens using public pricing"

> *Claim: GitHub publishes model pricing (e.g., Claude Haiku = 0.25x, GPT-4o = 1x).
> We can divide aic_quantity by the published rate to recover token counts.*

**Blocked by:** CP-1 + IAF-4 (billing computation forbidden).
The rate applied at billing time may differ from the published rate (plan multipliers,
promotional rates, retroactive corrections). The public rate is not the actual rate used.
Even if rates matched, recovering token counts from billing data is billing computation.

### Attempt A6-2: "aic_quantity is just a unit change from tokens"

> *Claim: 1 AI Credit = $0.01, and pricing is per million tokens, so credits and tokens
> are proportional within a single model. It's just a unit conversion.*

**Blocked by:** CP-1. Proportionality holds only if:
(a) The exact rate used at billing time is known (it is not — platform applies corrections).
(b) The plan multiplier is known (monthly vs. annual subscribers differ).
(c) No promotional or trial-rate adjustment applied.
All three conditions are unverifiable by the observer. Proportionality claim fails.

### Attempt A6-3: "Code completions are negligible — omit the annotation"

> *Claim: Code completions are low-token interactions. The gap is small enough
> to ignore in aggregate analysis.*

**Blocked by:** AG-Copilot-1 structural annotation requirement + A-1.
Code completions are the **highest-frequency** Copilot usage pattern.
Frequency, not token size per call, determines aggregate significance.
The gap is unquantifiable — "small" cannot be asserted without measuring completions,
which the surface does not expose. The annotation is mandatory regardless of assumed magnitude.

### Attempt A6-4: "Store aic_quantity as total_tokens for unified querying"

> *Claim: The steps table has total_tokens = NULL by policy anyway. We could store
> aic_quantity there to make reporting simpler.*

**Blocked by:** CP-3 + NST-1 (Non-Transferable Semantics Theorem).
`total_tokens` in the steps table has a specific semantic: observer-reconstructed
sum of provider-reported token counts. `aic_quantity` is a billing credit quantity.
These are different quantities. Storing `aic_quantity` in `total_tokens` would create
a field whose semantic is false for Copilot rows.
`copilot_billing_events` is a separate table precisely to prevent this.

### Attempt A6-5: "Preview data is close enough — skip the is_preview flag"

> *Claim: GitHub's preview reports are usually within 5% of final billing.
> The is_preview flag adds complexity for minimal gain.*

**Blocked by:** AG-Copilot-3 answer + Class D epistemic definition.
GitHub explicitly documented a May 14, 2026 correction where April preview showed
credits higher than expected. "Usually within 5%" is a probabilistic claim that
cannot be verified before correction arrives. The `is_preview` flag is mandatory.
Default `is_preview = 1` ensures conservative handling; re-ingestion corrects.

### Attempt A6-6: "Cross-provider comparison is fine if we label it 'approximate'"

> *Claim: Comparing Copilot AI Credits with direct Claude API costs is useful
> if we add a disclaimer that values are approximate.*

**Blocked by:** FSP-3 (Field Semantic Permanence) + CP-2.
A disclaimer does not change the epistemic class of the underlying data.
Class D (Copilot billing-reported) + Class C (Claude observer-reconstructed) →
not comparable regardless of labeling. The comparison would require asserting
a common unit of measurement that does not exist between the two surfaces.
The prohibition is categorical, not annotation-resolvable.

---

## Admission Gate Decision

All six AG-Copilot questions have been answered. All six adversarial attempts are blocked
by existing invariants plus the new CP-1, CP-2, CP-3 constraints.

**Copilot AI Credits may be admitted as a Class D acquisition surface under the following
conditions (all mandatory):**

1. Stored in `copilot_billing_events` table only — never in `steps` or `step_ingestion_provenance`
2. `completions_excluded = 1` on every row (schema-enforced)
3. `aic_gross_amount` never ingested (C-1)
4. `is_preview` default 1; `--mark-final` re-ingestion required for confirmed data
5. No `token_count` columns in the table (CP-1)
6. Cross-model `aic_quantity` aggregation forbidden at query layer (CP-2)
7. `acquisition_mode = 'billing_report_daily_aggregate'` on every provenance row (CP-3)
8. `epistemic_class = 'Class D'` on every provenance row
9. Class D evidence MUST NOT be joined with or aggregated against Class C evidence

---

## Document Status

- Admission gate: **OPEN**
- Implementation: See `codeburn/phase2/copilot_billing_ingestor.py`
- Schema extension: See `codeburn/phase1/schema.sql` (copilot_billing_events table)
- Class D definition: See `CODEBURN_CLASS_D_EPISTEMIC_CLASSIFICATION.md`
