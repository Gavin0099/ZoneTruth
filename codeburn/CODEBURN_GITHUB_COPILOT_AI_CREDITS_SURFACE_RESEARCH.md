# CodeBurn — GitHub Copilot AI Credits Surface Research

> Status: **P6 ADMISSION RESEARCH — NOT YET ADMITTED**
> Written: 2026-05-21
> Purpose: Analyze GitHub Copilot AI Credits as a potential CodeBurn acquisition surface
>          before any ingestion path is proposed.
>
> This document does NOT authorize ingestion.
> It defines what the surface IS and what boundaries MUST be locked before any P7+ work.

---

## 1. Surface Description

GitHub Copilot transitions to usage-based billing on **2026-06-01**.
The billing unit is the **AI Credit**: 1 AI Credit = $0.01 USD.

Token consumption is converted to AI Credits via model-specific pricing rates.
A usage report CSV is available (one row per user, per model, per day) with fields:
- `aic_quantity` — AI Credits consumed
- `aic_gross_amount` — Estimated USD cost

Source: https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing

---

## 2. What This Surface Actually Is

**The CSV report is not a token log. It is a billing ledger.**

The conversion path is:

```
raw token counts (provider-internal)
  → model-specific pricing rate ($/million tokens)
  → AI Credits (aic_quantity)
  → estimated USD (aic_gross_amount)
```

By the time the data reaches the CSV report, it has passed through:
1. Provider token counting (unverifiable by observer)
2. Model-specific pricing conversion
3. GitHub billing platform aggregation (daily, not session)
4. Optional plan-specific multipliers (annual vs. monthly subscribers differ)

CodeBurn acquires data at the observation boundary.
The AI Credits CSV is already three transformations removed from that boundary.

---

## 3. Critical Acquisition Gaps

### Gap 1: Code Completions Are Absent

> Code completions and Next Edit Suggestions do NOT consume AI Credits.

The most common Copilot usage pattern — inline code completion while typing — is
**entirely invisible** to the AI Credits surface. Any "total Copilot usage" metric
derived from AI Credits is structurally incomplete. It systematically excludes the
highest-frequency, lowest-friction use case.

**Implication for CodeBurn:** An AI Credits acquisition surface produces a dataset
with an unknown and unquantifiable completions-shaped hole. Aggregates over this
data misrepresent actual AI compute consumed by Copilot users.

### Gap 2: No Session-Level Granularity

The report granularity is **one row per user, per model, per day**.

There is no session UUID, no conversation ID, no provenance identity.
Provenance identity — the principle that each ingested record can be traced to
a specific artifact at a specific offset — does not exist in this surface.

This is a fundamental break from P3/P4 acquisition design, which was built on
JSONL line-level provenance.

### Gap 3: Preview ≠ Actual Billing

GitHub explicitly states that preview reports are "directional signals," not
precise billing predictions. Known inaccuracies:
- ~2% of 0x-model usage from April 1–24 missing
- Some code review entries missing AI credit estimations
- May 14, 2026 correction: April preview showed credits higher than expected

**Implication:** Even the billing ledger itself is subject to retrospective correction.
An ingestor that trusts `aic_quantity` as ground truth ingests a value that GitHub
itself disclaims as an estimate.

### Gap 4: Organization Credit Pooling

Credits are pooled at the billing-entity level, not per-user buckets.
Individual developer attribution requires additional assumptions about how pooled
credits are divided — assumptions that GitHub does not provide algorithmically.

---

## 4. Three Non-Negotiable Boundaries

These boundaries must be locked before any ingestion path for Copilot AI Credits
is proposed. They may not be relaxed in P7 or later.

### Boundary CP-1: AI Credits ≠ Raw Token Truth

```
AI Credits = f(tokens, model_pricing_rate, plan_multiplier)
```

AI Credits are a pricing-converted aggregate. The mapping is:
- Non-invertible without knowing the exact billing rate applied at the time
- Model-dependent (Claude Opus rates differ from GPT-4o rates by 27x in annual plans)
- Plan-dependent (monthly vs. annual subscribers have different multipliers)
- Platform-opaque (billing system may apply corrections after the fact)

**Locked rule:** `aic_quantity` MUST NOT be treated as a token count.
Back-calculation from credits to tokens requires billing computation,
which is forbidden by C-1 (cost estimation) and IAF-4 (billing computation forbidden).

### Boundary CP-2: AI Credits ≠ Provider Efficiency Signal

AI Credits embed pricing decisions made by GitHub and its model providers.
A session using Claude Opus 4.7 costs 27x more credits than a comparable session
using a 0x-model — not because Claude used more tokens, but because GitHub priced
it higher for annual subscribers.

Credit comparison across models is pricing comparison, not capability comparison.
Credit comparison across time is pricing-tier comparison, not usage comparison.

**Locked rule:** AI Credits MUST NOT be used to compare efficiency, cost-effectiveness,
or output quality across models or providers. Such comparison requires FSP-3
(cross-provider) violation AND C-1 (cost) violation simultaneously.

### Boundary CP-3: Billing Report ≠ Session Provenance

The AI Credits CSV has no session UUID, no conversation identity, no line-level
offset, no acquisition timestamp for individual turns. It is a billing summary,
not an observation log.

The P3/P4 provenance identity model (artifact → line → offset → session_id)
cannot be applied to a daily-aggregated billing report. Any ingestion path that
claims session-level provenance from a daily aggregate is making a false claim.

**Locked rule:** AI Credits data MUST be labeled with `acquisition_mode = "billing_report_daily_aggregate"`,
NOT `acquisition_mode = "session_log_ingestion"`. Provenance identity fields
(source_artifact_line, source_artifact_offset) MUST be NULL or absent.

---

## 5. Proposed Epistemic Classification

If admitted in a future phase, Copilot AI Credits evidence would require a new
epistemic class:

| Dimension | Claude (P4) | Codex (P5) | Copilot AI Credits (proposed) |
|-----------|------------|------------|-------------------------------|
| Source | Session JSONL | Session JSONL | Billing report CSV |
| Granularity | Per turn | Per turn | Per user / model / day |
| Token counts | Reconstructed | Reconstructed | **Not available** (credits only) |
| Session identity | UUID (from filename) | UUID (from filename) | **None** |
| Provenance depth | Line + offset | Line + offset | **File + date only** |
| Epistemic class | Class C | Class C | **Class D** (proposed) |
| real_time_observed | 0 | 0 | 0 |
| analysis_safe_for_decision | 0 | 0 | 0 |
| provider_truthfulness_assumed | 0 | 0 | 0 |
| Billing computation | Forbidden | Forbidden | Forbidden (aic_gross_amount) |
| Cross-provider compare | Forbidden | Forbidden | Forbidden |

**Class D** is proposed as a new epistemic class for billing-reported evidence:
> Observer did not observe token counts. Observer acquired billing-system ledger entries
> that were produced by converting token counts through pricing rates and plan conditions.
> The original token counts are not recoverable without billing computation.

Class D is weaker than Class C. The observation distance is greater.
Class D + Class C → NOT comparable (FSP-3 applies across classes as well as providers).

---

## 6. What a Future Admission Gate Would Need to Answer

Any P7+ proposal to ingest Copilot AI Credits must address:

**AG-Copilot-1:** How does the ingestor represent the structural absence of
code completions? Does it annotate that the surface is systematically incomplete?

**AG-Copilot-2:** How does the daily-aggregate granularity affect provenance identity?
Is a "session" even a meaningful unit for this surface?

**AG-Copilot-3:** How does the ingestor handle the preview-vs-actual ambiguity?
Does it re-ingest corrected reports? What happens to records already in the DB?

**AG-Copilot-4:** How does CP-1 prevent back-calculation from `aic_quantity` to tokens?
What schema constraints enforce this?

**AG-Copilot-5:** How does CP-2 prevent cross-model credit comparison in reports
and visualizations? What query-level guards enforce this?

**AG-Copilot-6:** What adversarial re-interpretation attempts were made, and which
existing invariants blocked them? (AG-6 requirement)

---

## 7. What Is Not Permitted Under P6 Constraints

Per `CODEBURN_P6_SCOPE_CONSTRAINTS.md`:

- `aic_gross_amount` ingestion → **C-1 violation** (cost estimation forbidden)
- Credit-to-model comparison visualization → **V-1 + C-1 violation**
- "Total Copilot spend this week" → **C-1 + O-1 violation**
- Trend analysis of credits over time → **T-1 constraint applies** (annotation required)
- Cross-provider credit comparison (Copilot vs. direct Claude) → **FSP-3 + CP-2 violation**

---

## 8. What Is Permitted Under P6 (Observability Only)

- Documenting that this surface exists (this document)
- Documenting the gap (completions absent) as a structural acquisition limitation
- Noting that `aic_quantity` represents billing-converted evidence, not token evidence
- Proposing a Class D epistemic classification for future admission discussion

---

## 9. Recommendation

**Do not admit Copilot AI Credits as an acquisition surface in P6.**

Reasons:
1. The surface is structurally incomplete (completions absent — unquantifiable gap)
2. No session-level provenance identity (daily aggregate only)
3. `aic_quantity` is already a billing construct, not a token observation
4. Class D evidence would require new schema extension, new epistemic class definition,
   and new adversarial review — all of which are P7+ admission work
5. The preview-vs-actual ambiguity creates a retroactive correction risk that
   CodeBurn's append-only ingestion model does not currently handle

**If admitted later:** Copilot AI Credits evidence must be stored in a separate
table (`copilot_billing_events` or similar), never joined with `steps` rows,
and never used in the same aggregate as Class C evidence.

---

## Document Status

- Surface research: COMPLETE
- Admission gate: NOT YET OPENED
- Next required step before P7 can propose ingestion:
  All six AG-Copilot questions must be answered in an adversarial review document.
