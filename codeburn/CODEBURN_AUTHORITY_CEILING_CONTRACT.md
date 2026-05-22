# CodeBurn — Authority Ceiling Contract

> Written: 2026-05-20
> Status: **BINDING** — P0 constitutional freeze document, effective immediately
> Scope: all CodeBurn versions, all acquisition states, all epistemic classes
> Prerequisite for: any acquisition implementation that produces Class A or Class B evidence
> Depends on: CODEBURN_TOKEN_PROVENANCE_ONTOLOGY.md

---

## Why This Is the Most Critical P0 Document

The Provenance Ontology defines what token evidence IS.
The Comparability Boundary defines what comparisons are permitted.
This document defines what CodeBurn itself may BECOME as a result of acquisition.

The other two documents constrain data and its use.
This document constrains CodeBurn's epistemic position.

The distinction matters because the most dangerous authority escalation does not
come from misusing data — it comes from the system itself being reclassified.
Once CodeBurn is treated as a decision-support system, or a governance authority,
or a performance monitoring infrastructure, that reclassification shapes everything
that follows: what features get requested, what reports get generated, what
organizational workflows depend on it.

**This reclassification does not require a single deliberate decision.**
It occurs through gradual normalization of acquisition completeness as authority.

This document is the pre-positioned constraint against that normalization.

---

## The Authority Escalation Path

The specific drift pattern this document closes:

```
Stage 1: Acquisition Completeness
  "CodeBurn now receives Class A evidence from the Claude provider API"
  → Authorized: improved observability
  → Not yet at boundary

Stage 2: Trustworthiness Inference
  "The data is provider-grade, replay-stable, and provenance-verified"
  → This is true
  → Not yet at boundary — but the next step is the critical transition

Stage 3: Authority Inference (BOUNDARY)
  "Trustworthy data can be used to inform decisions"
  → This step is not authorized
  → Trustworthiness is a data quality attribute
  → Authority is a governance grant
  → These are not the same thing

Stage 4: Operational Integration (boundary already crossed)
  "CodeBurn token reports now feed the review queue prioritization"
  → CodeBurn is now a decision-influencing system
  → Authority was never granted; it was accumulated through workflow

Stage 5: Reclassification (boundary long since crossed)
  "CodeBurn is our AI efficiency monitoring platform"
  → Original epistemic position is no longer recoverable without explicit rollback
```

Stage 3 is where this document intervenes. The transition from Stage 2 to Stage 3
is the specific logical step that must be explicitly blocked, because it appears
epistemically reasonable — trustworthy data SHOULD be usable for decisions, in
most contexts. CodeBurn is the exception, and this document is the pre-positioned
record of why.

---

## The Core Principle

**Data quality does not confer authority.**

Authority requires a separate, explicit governance grant — a document that:
1. Names the specific authority being granted
2. Specifies the conditions under which it applies
3. Defines the oversight mechanism for that authority
4. Is written before any implementation depends on it

No such document exists for CodeBurn as of 2026-05-20. Therefore CodeBurn's
authority ceiling is: observational reporting only.

This ceiling holds at every acquisition stage.

---

## What Acquisition Completeness DOES Grant

To be precise: acquisition completeness is not without value. It legitimately grants:

| Acquisition stage | What is gained | What is NOT gained |
|---|---|---|
| Class D → Class A | Higher provenance quality | Any evaluative authority |
| Replay-stable | Audit-grade token records | Decision input legitimacy |
| Provider-integrated | Real-time session coverage | Runtime authority |
| Cross-session coverage | Historical observability | Comparative evaluation |
| Multi-provider | Broader coverage | Cross-provider comparability |

Each row represents a real improvement. None of them represents an authority upgrade.

The purpose of this table is to allow genuine progress to be acknowledged without
allowing that acknowledgment to be misread as authority escalation.

---

## Permanent Authority Ceilings

The following authority types are permanently outside CodeBurn's scope regardless
of acquisition completeness, data quality, or operational maturity:

### AC1 — Runtime Authority

CodeBurn may not make, block, trigger, or influence automated runtime decisions.

**What this prohibits:**
- Gates that check CodeBurn data before allowing a session to proceed
- Thresholds that trigger automated actions based on token counts
- Alerts that interrupt AI agent workflows based on token observability signals
- Any mechanism where CodeBurn output changes system behavior without human intermediary

**What this permits:**
- Human reviewer reads CodeBurn report and makes a decision
- CodeBurn report is available as context for human review

The distinction: human in the loop = permitted. System-to-system without human = prohibited.

**Does not become permitted when:** acquisition is complete, data is Class A, or
the automated action is "minor." No automated runtime action is authorized.

---

### AC2 — Governance Authority

CodeBurn may not issue governance decisions, compliance verdicts, or policy enforcement
based on token observability data.

**What this prohibits:**
- "Session X failed governance review because token usage exceeded threshold"
- Automated promotion blocking based on token signals
- Compliance scoring that includes token count as a governance factor
- Policy enforcement that treats token anomalies as violations

**What this permits:**
- Governance reviewers may read CodeBurn reports as observational context
- CodeBurn signals (e.g., `retry_pattern_detected`) are advisory, never blocking

**Note:** CodeBurn signals carry `advisory_only = 1, can_block = 0` in the schema.
This schema constraint is the runtime encoding of AC2. Schema changes that set
`can_block = 1` for token-related signals are prohibited without a separate
governance contract.

---

### AC3 — Evaluative Authority

CodeBurn may not evaluate, score, rank, or rate sessions, agents, contributors,
or providers based on token observability data.

**What this prohibits:**
- Session quality scores derived from token counts
- Agent performance metrics that include token usage
- Contributor efficiency rankings based on token data
- Provider quality assessments based on reported token counts

**What this permits:**
- Describing token count as a session property (observational)
- Reporting token provenance quality (data quality, not session quality)

**Inherited from:** Consumption Boundary §Prohibited Uses. This ceiling applies
to CodeBurn's own output generation, not only to downstream consumers.

---

### AC4 — Decision Safety Certification

CodeBurn may not certify that its output is safe for use in automated decision systems.

**What this prohibits:**
- Setting `analysis_safe_for_decision = true` without a separate
  `CODEBURN_DECISION_AUTHORITY_CONTRACT.md` being created and reviewed
- Any report field that implies output can safely feed a decision system
- Schema changes that introduce decision-support fields without the above contract

**What this permits:**
- Current state: `analysis_safe_for_decision = false` (permanent default)
- This default survives all acquisition milestones unchanged

**The specific field:** `analysis_safe_for_decision` in `codeburn_analyze.py` is
hard-coded to `False`. That hard-coding is not a placeholder. It is the runtime
implementation of AC4. Changing it requires `CODEBURN_DECISION_AUTHORITY_CONTRACT.md`.

---

### AC5 — Provider Truthfulness Certification

CodeBurn may not certify the accuracy or truthfulness of provider-reported token counts.

**What this prohibits:**
- "Provider-grade evidence means the count is accurate"
- Using Class A evidence to validate provider billing claims
- Treating consistent Class A counts as confirmed provider truthfulness

**What this permits:**
- "The provider reported N tokens for this request"
- "Token source is Class A (provider-originated)"

**Reason:** CodeBurn observes what providers report, not what providers compute.
Provider reporting and provider computation are not the same thing. This boundary
may seem minor but is critical if token data is ever considered for cost auditing.

---

## The Trustworthiness Inference — Why It Must Be Explicitly Blocked

The Authority Escalation Path passes through Stage 2 → Stage 3 via what appears
to be a reasonable inference:

> "The data is trustworthy, therefore it can inform decisions."

This inference is valid in most epistemic contexts. It is specifically invalid for
CodeBurn token observability because:

**1. The inference assumes authority follows from data quality.**
Authority is a governance grant, not a data property. Trustworthy data without
authority grant = trustworthy observational data. Nothing more.

**2. The inference ignores the inferential gap.**
`token count → session quality → decision relevance` crosses boundaries that
are not authorized by any CodeBurn governance contract. The data being trustworthy
does not close the inferential gap.

**3. The inference inverts the authority model.**
In the correct model: governance contract → authority → data can be used for X.
In the inverted model: data quality → data can be used for X → authority is implied.
CodeBurn's governance model is the correct model. The inference runs in the wrong direction.

**This document is the explicit record that this inference does not apply to
CodeBurn token observability, regardless of acquisition stage.**

---

## Authority Drift Detection Signals

The following patterns, when observed in CodeBurn-related documentation, discussion,
or tooling, indicate that authority escalation is occurring or has occurred:

| Pattern | Authority ceiling being crossed |
|---|---|
| "CodeBurn flagged this session" (as if it blocked something) | AC1 runtime authority |
| "Token usage triggered a review" (automated trigger) | AC1 runtime authority |
| "Session failed CodeBurn governance check" | AC2 governance authority |
| "CodeBurn score" or "CodeBurn rating" | AC3 evaluative authority |
| "High-token sessions require extended review" | AC3 + AC1 combined |
| "We use CodeBurn to monitor agent efficiency" | AC3 evaluative authority |
| "CodeBurn-verified token counts" (implying decision safety) | AC4 decision safety |
| "Provider accuracy confirmed by CodeBurn" | AC5 provider truthfulness |
| Any sentence treating CodeBurn as a performance monitoring system | All ceilings |

**If any of these patterns appears in a feature request, report template, or operational
workflow, that is evidence of authority escalation. The correct response is not
"we need to add safeguards to this feature" — it is "this feature crosses the
authority ceiling."**

---

## Relationship to Other Boundary Documents

| Document | What it constrains | How it relates to this document |
|---|---|---|
| Provenance Ontology | What token evidence IS | Defines the evidence that is subject to this contract |
| Comparability Boundary | What comparisons are permitted | Constrains data use at comparison layer |
| Consumption Boundary | What consumers may do with output | Constrains downstream use (this contract constrains CodeBurn itself) |
| Phase 1 Analysis Contract | What CodeBurn output may claim | Constrains output text; this contract constrains system position |

The consumption boundary constrains external actors.
This contract constrains CodeBurn's epistemic position as a system.

A system that respects the consumption boundary but exceeds this contract has still
undergone authority escalation — the escalation happens at the system identity level,
not at the data use level.

---

## What Elevating the Authority Ceiling Requires

Any authority ceiling (AC1–AC5) may be elevated only through:

1. A dedicated governance contract document named for the specific authority being granted
   (e.g., `CODEBURN_DECISION_AUTHORITY_CONTRACT.md` for AC4)
2. The contract must name the specific authority, the conditions, and the oversight mechanism
3. The contract must be committed before any implementation that depends on the elevated ceiling
4. The contract must not be created by the same actor who requests the authority elevation
   (separation of roles)

No acquisition milestone, data quality improvement, or operational maturity achievement
substitutes for this process.

The authority ceiling is not a temporary restriction pending better infrastructure.
It is a permanent constraint pending explicit governance authorization.

---

## Current Authority State (2026-05-20)

```
AC1 runtime authority:        NOT GRANTED
AC2 governance authority:     NOT GRANTED
AC3 evaluative authority:     NOT GRANTED
AC4 decision safety:          NOT GRANTED (analysis_safe_for_decision = false)
AC5 provider truthfulness:    NOT GRANTED

CodeBurn epistemic position:  observational reporting only
Authority ceiling:            advisory signals, human-facing reports
```

This state is the baseline. All future acquisition work begins from this baseline.
Completion of acquisition chains does not modify this state.

---

*Trustworthy data is still just data.*
*Authority is a governance grant, not a data property.*
*This ceiling survives every acquisition milestone.*
