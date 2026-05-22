# CodeBurn — Class D Epistemic Classification

> Status: **ACTIVE — effective from Copilot AI Credits admission**
> Written: 2026-05-21
> Prerequisite: `CODEBURN_COPILOT_AI_CREDITS_ADMISSION_GATE.md` (all 6 AG-Copilot answered)

---

## Definition

**Class D** is the epistemic class for billing-reported evidence:

> The observer did not observe token counts.
> The observer acquired billing-system ledger entries produced by converting token counts
> through pricing rates and plan-specific conditions.
> The original token counts are not recoverable without billing computation (IAF-4).

Class D evidence has greater observation distance than Class C.

---

## Class Comparison

| Dimension | Class C (Claude/Codex JSONL) | Class D (Copilot Billing CSV) |
|-----------|------------------------------|-------------------------------|
| Observation | JSONL session log | Billing ledger CSV |
| Token counts | Reconstructed from log | **Not available** (credits only) |
| Session identity | UUID from filename | **None** (daily aggregate) |
| Provenance depth | Line + offset | File + date only |
| Granularity | Per API turn | Per user / model / day |
| real_time_observed | 0 | 0 |
| analysis_safe_for_decision | 0 | 0 |
| provider_truthfulness_assumed | 0 | 0 |
| Billing computation | Forbidden | Forbidden |
| Cross-provider compare | Forbidden | Forbidden |
| Cross-class compare | N/A | **Forbidden** (Class D + Class C not comparable) |

---

## What Class D Does NOT Mean

- Class D does NOT mean "lower quality" in a general sense.
  It means the observation path is further from raw token counts.
- Class D does NOT unlock billing computation.
  `aic_gross_amount` remains categorically forbidden (C-1 + IAF-4).
- Class D does NOT enable cross-provider comparison.
  Class D + Class C → not comparable (FSP-3 applies across epistemic classes).
- Class D does NOT relax the structural incompleteness annotation.
  `completions_excluded = 1` is mandatory on every row regardless of class.

---

## Schema Binding

Class D evidence is stored in `copilot_billing_events`, never in `steps`.
The `acquisition_mode` for all Class D rows MUST be `'billing_report_daily_aggregate'`.
The `epistemic_class` for all Class D rows MUST be `'Class D'`.

`step_ingestion_provenance` is NOT used for Class D rows.
Class D provenance is embedded directly in `copilot_billing_events` columns.

---

## Future Class D Surfaces

If additional billing-ledger surfaces are admitted in the future, they require:
1. A surface research document (equivalent to `CODEBURN_GITHUB_COPILOT_AI_CREDITS_SURFACE_RESEARCH.md`)
2. A full six-question admission gate (equivalent to `CODEBURN_COPILOT_AI_CREDITS_ADMISSION_GATE.md`)
3. Class D classification confirmed
4. Separate table (never `copilot_billing_events` cross-pollinated with other surfaces)
