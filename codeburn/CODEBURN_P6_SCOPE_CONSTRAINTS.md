# CodeBurn P6 Scope Constraints

> Status: **PRE-ADMISSION CONSTRAINT DOCUMENT**
> Written: 2026-05-21
> Purpose: Define what P6 is and is not permitted to build, before any implementation begins.
>
> This document is a prerequisite for any P6 phase opening.
> P6 may not begin without explicit answers to all six constraint questions below.

---

## Context: Why This Document Exists

P0–P5 successfully bounded the acquisition layer:
- Multi-provider ingestion (Claude + Codex)
- Class C provenance for all evidence
- Semantic freeze preventing field equivalence claims
- Admission-gated provider expansion
- Replay-stable provenance identity

The primary drift risk for P6 is no longer **acquisition drift**.

It is **interpretation layer drift**:

> The acquisition system produces Class C, observer-reconstructed evidence.
> An interpretation layer that treats this evidence as more authoritative
> than Class C constitutes implicit epistemic promotion.

The six questions below define the constraint boundary before any P6 scope is proposed.

---

## Constraint Question 1: Aggregate Analytics

**Question:** Is P6 permitted to build aggregate analytics across sessions or turns?

**Answer: CONDITIONALLY RESTRICTED.**

Same-provider, single-session aggregation (e.g., total tokens across turns within one session)
is a **reconstruction operation**, not an analytic promotion — permitted with epistemic annotation.

Cross-session aggregation (e.g., weekly token totals across multiple sessions) is:
- Permitted for **display** as Class C reconstruction summary
- Forbidden for **use** as decision input, efficiency signal, or optimization basis

Cross-provider aggregation is **categorically forbidden** by FSP-3:
> Class C + Class C →/ comparability

Aggregation does not change the epistemic class of the underlying evidence.
An aggregate of Class C rows is still Class C. Any display that omits this is
an authority inflation surface.

**Constraint (A-1):** All aggregate outputs must carry `epistemic_class = Class C`
and `analysis_safe_for_decision = 0` in their provenance annotation.
Aggregates must not be labeled as "usage", "consumption", or "cost" without
explicit Class C qualification.

---

## Constraint Question 2: Same-Provider Trend Analysis

**Question:** Is P6 permitted to analyze trends within a single provider over time?

**Answer: PERMITTED FOR OBSERVATION, FORBIDDEN FOR INFERENCE.**

Observing that a provider's reconstructed token counts changed over time is
a Class C reconstruction of log data — permitted.

Inferring from that trend any of the following is **forbidden**:
- Efficiency change
- Model behavior change
- Cost change
- Performance regression or improvement
- Optimization opportunity

The Temporal Non-Promotion Rule (TNP) applies directly:

> Replay stability / persistence / historical consistency MUST NOT upgrade
> provider equivalence, field equivalence, or aggregation admissibility.

A consistent upward trend in token counts over 30 days does not become
"measurement" by virtue of persistence. It remains reconstruction.

**Constraint (T-1):** Trend displays must include explicit epistemic annotation:
`observer-reconstructed trend — not provider-measured`. Trend data must not be
used as input to any optimization, ranking, or allocation decision path.

---

## Constraint Question 3: Cost Estimation

**Question:** Is P6 permitted to build cost estimation features?

**Answer: FORBIDDEN.**

Cost estimation is explicitly banned by IAF-4 (billing computation forbidden)
and by the architectural decision to exclude `cached_input_tokens` from all
acquisition paths. The exclusion of cached tokens was precisely because cached
tokens affect billing calculations — and billing computation is outside the
epistemic boundary of this system.

Cost estimation requires:
- Provider billing rates (external, not acquired)
- Accurate token counts (Class C, not verified)
- Cache behavior (IAF-4, excluded from acquisition)
- Reasoning token scope (IAF-2, excluded from acquisition)

None of these are available at sufficient epistemic authority for billing computation.

**Constraint (C-1):** P6 must not implement any cost estimation, cost projection,
billing approximation, or spend tracking feature. Any feature that multiplies
token counts by a price rate is categorically out of scope.

---

## Constraint Question 4: Replay-Derived Metrics

**Question:** Is P6 permitted to derive metrics from replay-stable sessions?

**Answer: FORBIDDEN AS METRICS, PERMITTED AS RECONSTRUCTION DOCUMENTATION.**

A replay-derived value (e.g., "average tokens per turn across 5 replays") is
a Class C reconstruction artifact. It is not a metric in the measurement sense.

The distinction:
- **Reconstruction documentation**: "Session replay produced consistent token counts across N runs" — permitted, with Class C annotation
- **Metric**: "Average tokens per turn = 847" presented as a measurement — forbidden, implies measurement authority

The Anti-Collapse Axiom applies:
> Stable reconstruction does not collapse observation distance.

Replay consistency across N runs does not upgrade the reconstructed value to
a measured value. 100 consistent replays = reconstruction method stable.
100 consistent replays ≠ measurement.

**Constraint (R-1):** Replay-derived outputs must be labeled `reconstruction artifact`
not `metric`. They must not be consumed by ranking, optimization, or decision systems.

---

## Constraint Question 5: Provider-Specific Optimization

**Question:** Is P6 permitted to implement provider-specific optimization recommendations?

**Answer: FORBIDDEN.**

Optimization implies using evidence to make decisions. The epistemic contract
of this system permanently sets `analysis_safe_for_decision = 0` for all
Class C evidence. This is not a runtime configuration — it is a constitutional constraint.

Provider-specific optimization would require:
- Treating token counts as measurements (they are reconstructions)
- Using Class C evidence as decision inputs (forbidden by AC4)
- Implicitly claiming provider truthfulness (forbidden, provider_truthfulness_assumed = 0)

This is the most dangerous form of authority inflation because it appears
to be a natural extension of "having the data":

> "We already track Codex tokens → we can tell you which prompts are cheaper"

This inference chain is categorically blocked. Having acquisition data does not
authorize optimization use of that data.

**Constraint (O-1):** P6 must not implement optimization recommendations, prompt
efficiency rankings, provider cost comparisons, or any feature that uses
Class C evidence as decision authority. Such features would require a separate
epistemic upgrade process — not an implicit P6 scope expansion.

---

## Constraint Question 6: Visualizations That Cause Authority Inflation

**Question:** Which visualizations are out of scope because they implicitly inflate authority?

**Answer:** The following visualization patterns are **forbidden** without explicit
epistemic guardrails:

| Visualization Type | Why It Inflates Authority |
|-------------------|--------------------------|
| Bar chart: "Token Usage by Provider" | Implies cross-provider comparability (FSP-3 violation) |
| Line chart: "Token Trend Over Time" without Class C label | Implies measurement, not reconstruction |
| Pie chart: "Cost Breakdown by Provider" | Implies billing computation (IAF-4 violation) |
| Table: "Efficiency Ranking by Prompt" | Implies optimization authority (O-1 violation) |
| Dashboard: "Total Spend This Week" | Implies cost estimation (C-1 violation) |
| Any chart comparing Claude vs Codex values | Implies NST-1 violation (non-transferable semantics) |

The following visualization patterns are **permitted** with required annotation:

| Visualization Type | Required Annotation |
|-------------------|---------------------|
| Same-provider session token counts | `Class C — observer-reconstructed` |
| Same-provider turn-count timeline | `Class C — not provider-measured` |
| Quarantine rate per session | `Class C — structural observation only` |
| Admission/skip/quarantine breakdown | `Class C — acquisition surface statistics` |

**Constraint (V-1):** All P6 visualizations must carry explicit epistemic class annotation.
Any visualization that presents Class C data without `observer-reconstructed, Class C,
not decision-authoritative` labeling is an authority inflation surface and is out of scope.

---

## Summary: The Six Constraints

| ID | Domain | Ruling |
|----|--------|--------|
| A-1 | Aggregate analytics | Permitted for observation, forbidden for decision input |
| T-1 | Trend analysis | Permitted for reconstruction display, forbidden for inference |
| C-1 | Cost estimation | **Categorically forbidden** |
| R-1 | Replay-derived metrics | Permitted as reconstruction documentation, not as metrics |
| O-1 | Optimization recommendations | **Categorically forbidden** |
| V-1 | Visualizations | Permitted only with explicit Class C annotation |

---

## What P6 Is Permitted To Build

Within the constraints above, P6 may explore:

- **Acquisition surface statistics**: counts of admitted, skipped, quarantined records
  (structural observation, not measurement)
- **Session provenance display**: surfacing existing provenance fields for human review
  (display of already-bound Class C evidence)
- **Replay consistency documentation**: displaying that replay produced consistent
  reconstructions (stability documentation, not metric)
- **Quarantine inspection**: tooling to inspect quarantined records and understand
  why they were excluded (structural audit, not analytics)

---

## What P6 Is NOT Permitted To Build

The following are outside P6 scope regardless of implementation effort:

- Cost estimation or billing approximation of any kind
- Cross-provider comparison of any token field
- Optimization recommendations based on token data
- Efficiency rankings or prompt scoring
- Trend-based decision inputs
- Any feature that treats Class C evidence as measurement-grade data

---

## P6 Opening Condition

P6 may not open a phase document until:

1. This constraint document is committed and acknowledged
2. The proposed P6 scope is checked against all six constraints (A-1, T-1, C-1, R-1, O-1, V-1)
3. Any proposed P6 feature that touches a "FORBIDDEN" constraint is explicitly removed
   from scope before implementation begins

The purpose of P6 is to build **observability tooling** for Class C evidence —
not to upgrade that evidence to a higher epistemic class through the back door
of visualization and analytics.
