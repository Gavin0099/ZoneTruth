# CodeBurn — Token Observability Consumption Boundary

> Written: 2026-05-20
> Status: **BINDING** — forward constraint, effective immediately
> Scope: all versions of CodeBurn, all acquisition states
> Authority: written before acquisition legitimacy is established — intentionally

---

## Why This Document Exists Now

This document is written before CodeBurn's token acquisition chain is complete.

That timing is deliberate.

The organizational pressure to use token observability data for evaluative purposes
does not emerge from bad intent — it emerges from data trustworthiness. Once token
data is provider-integrated, replay-stable, and provenance-verified, the argument
"why can't we use this for optimization?" becomes very difficult to counter technically.

**The consumption boundary must be established before acquisition legitimacy is
established.** If this document is written after acquisition is complete, it will
appear as a post-hoc limitation on trusted data. Written before, it is a design
principle that acquisition must not violate.

Anti-inversion rule: **this boundary governs acquisition design, not the reverse.**

If a future acquisition implementation creates pressure to revise the consumption
boundary, that is implementation gravity. Resolve it by constraining the
implementation, not this document.

---

## The Core Epistemic Constraint

**Data verification ≠ evaluative authority.**

Token count is a proxy for computational cost.
Computational cost is not a proxy for reasoning quality.
Reasoning quality is not a proxy for session value.

The inference chain from:

> `verified token count`

to:

> `this session was efficient / wasteful / optimal / suboptimal`

crosses multiple boundaries that CodeBurn has not authorized and cannot authorize.
This holds regardless of:

- How accurate the token count is
- How trusted the data provenance is
- How complete the acquisition chain is
- How long the system has been operational

**Provider-grade, replay-stable, provenance-verified token data does not acquire
evaluative authority. Acquisition legitimacy ≠ evaluative legitimacy.**

---

## Permitted Uses of Token Observability Data

| Use | Allowed | Notes |
|-----|---------|-------|
| Human reviewer reading token counts as session scope context | yes | observational; no comparison implied |
| Understanding provenance quality of a session's data | yes | `provenance_warning` is for this purpose |
| Historical audit of data quality across sessions | yes | quality of data, not quality of sessions |
| Understanding what observability level was achieved | yes | `token_observability_level` is for this |
| Investigating whether acquisition chain is functioning | yes | technical health check |
| Providing context for human review of a specific session | yes | as context, not as signal |

---

## Prohibited Uses (regardless of acquisition completeness)

| Use | Prohibited | Reason |
|-----|-----------|--------|
| Session quality scoring based on token counts | prohibited | token count does not measure session quality |
| Ranking sessions by token usage | prohibited | ranking implies comparative evaluation not authorized |
| Agent or contributor efficiency comparison | prohibited | token observability is not a performance instrument |
| Automated review prioritization based on token counts | prohibited | creates evaluative hierarchy without authorization |
| Optimization pressure ("this session used too many tokens") | prohibited | waste judgment is explicitly out of scope (Phase 1 contract §2.1) |
| Cost governance that treats token counts as waste signals | prohibited | waste detection requires Phase 3+ semantic contract |
| Anomaly scoring that implies sessions require behavioral correction | prohibited | anomaly ≠ normative deviation |
| Input to any gate, threshold, or automated decision | prohibited | `decision_usage_allowed = false` is permanent |

**Rationale:**

These uses are prohibited not because the data is inaccurate, but because
the inferential steps required to produce evaluative conclusions from token
counts are not authorized by any CodeBurn governance contract.

The chain `token count → efficiency inference → optimization pressure` does not
become legitimate when the data becomes trustworthy. The authorization gap is
epistemic, not technical.

---

## Drift Signal Vocabulary

The following phrases, when appearing in documentation, review notes, team
discussion, or tooling that references CodeBurn token data, indicate that the
consumption boundary is being approached or crossed:

| Phrase pattern | Why it signals drift |
|---------------|---------------------|
| "high token density" | reframes token count as evaluative signal |
| "token-efficient session" | implies comparative evaluation |
| "attention routing based on token usage" | decision influence through observational data |
| "anomaly surfacing" (applied to token counts) | implies token count is a normative baseline |
| "review prioritization" based on observability data | evaluative hierarchy through workflow |
| "this agent uses more tokens than average" | comparative evaluation not authorized |
| "token cost governance" | cost framing of observational data |
| any sentence comparing session A and session B on token grounds | cross-session evaluative comparison |

**If a future feature request includes phrases like these, that request is
attempting to cross this boundary. Reject it at the design stage.**

This is the same drift signal principle as the Hearth Gap Consumption Boundary
(2026-05-17): if the language of a request implies evaluative use, the request
crosses the boundary regardless of how the technical implementation is framed.

---

## The Specific Risk: Indirect Escalation

The most dangerous form of boundary crossing does not require schema change.

It occurs through operational workflow:

```
Step 1: CodeBurn report added to review template (observational — permitted)
Step 2: Reviewer looks at token counts before deciding scope (informed — permitted)
Step 3: Reviewer mentions token count in review notes (reference — permitted)
Step 4: Next reviewer looks for token count signal to calibrate (pattern — unclear)
Step 5: High token count → extended review (implicit criterion — not permitted)
Step 6: Token count is now a de facto review decision signal (boundary crossed)
```

No individual step is a clear violation. The boundary crossing occurs at the
aggregate operational pattern level. No one will have changed `decision_usage_allowed`.

**This document is the pre-positioned reference for identifying Step 5 → Step 6
as a boundary crossing before it becomes an established norm.**

---

## What Verified Acquisition Does NOT Change

When CodeBurn's acquisition chain is complete — provider-integrated, replay-stable,
provenance-verified — the following remain unchanged:

- `analysis_safe_for_decision = false`
- `decision_usage_allowed = false`
- The prohibition on waste, efficiency, and optimization claims
- The prohibition on recommendation and action fields
- This consumption boundary in its entirety

Verification of data does not confer evaluative authority. The Phase 2 entry
constraints document (`CODEBURN_PHASE2_ENTRY_CONSTRAINTS.md`) established that
`analysis_safe_for_decision` requires a separate `CODEBURN_DECISION_AUTHORITY_CONTRACT.md`
that does not yet exist. Completion of the acquisition chain does not substitute
for that contract.

**Acquisition completeness moves CodeBurn from declarative instrumentation to
runtime-coupled instrumentation. It does not move CodeBurn toward
telemetry authority or evaluative authority.**

---

## Relationship to Phase 1 Analysis Contract

This document extends the consumption constraint surface established in
`CODEBURN_PHASE1_ANALYSIS_CONTRACT.md`.

The Phase 1 contract constrains **output** (what CodeBurn may claim in its reports).
This document constrains **downstream consumption** (what users of CodeBurn output
may do with the data).

These are complementary, not redundant:

| Layer | Document | Constraint type |
|-------|----------|----------------|
| Output claims | CODEBURN_PHASE1_ANALYSIS_CONTRACT.md | what CodeBurn may say |
| Schema fields | Phase 2 entry constraints | what fields may hold |
| Downstream use | This document | what consumers may do |

---

## Known Limitation and True Function

**What this document cannot detect:**

Pre-linguistic workflow adaptation — when token observability data becomes an
organizational attention attractor without explicit language. When review queues
silently shift, managerial instincts quietly form, and operational habits stabilize
without anyone saying "high token density" or "attention-worthy session," this
document cannot detect it. Linguistic surveillance depends on language. The deepest
form of semantic drift eventually operates below the language threshold.

At that stage: schema validation sees nothing, forbidden phrase detection sees
nothing, drift vocabulary surveillance sees nothing. The only visible signal is
that the workflow feels "natural" — which is precisely how governance drift looks
from the inside when it has completed.

**What this document provides instead:**

A reference frame for retroactive recognition, not real-time prevention.

If pre-linguistic drift has occurred, this document enables a future reviewer to
say: "This describes exactly what happened. The inferential transition that produced
this outcome was named non-neutral in 2026-05-20, before it became invisible."

**The actual governance function:**

This document does not claim to stabilize the social meaning of token observability
data. Social meaning is not permanently stable — it shifts with organizational
incentives, scale changes, management turnover, cost pressure, and incident response.

The function served is narrower and more durable:

> **Preserve the contestability of meaning.**

As long as this document exists as a living constraint, the interpretation "token
observability naturally implies optimization authority" cannot become uncontested
organizational common sense without an explicit act of revision. Someone can always
point to this document and say: "This was contested. It is still being contested."

**The failure condition for this document:**

Not: the boundary is explicitly violated.

But: the document begins to be treated as a historical artifact — interesting
background, but no longer an active constraint. When that happens, the boundary
has ended without any schema change, without any forbidden phrase appearing, and
without anyone deciding to abandon it.

This is why the Amendment Process below requires explicit authorization steps.
Not to prevent revision, but to ensure revision is **intentional** — that it does
not happen through gradual normalization of the document's irrelevance.

---

## Amendment Process

This document may be amended only if:

1. A `CODEBURN_DECISION_AUTHORITY_CONTRACT.md` is created and reviewed
2. The specific prohibited use being unlocked is explicitly named
3. The epistemic justification for evaluative authority is documented
4. The amendment is committed before any implementation that depends on it

Amending this document without completing steps 1–3 = consumption boundary violation,
regardless of whether the data being used is technically accurate.

---

*This boundary is written before acquisition legitimacy is established.*
*Its purpose is to survive acquisition legitimacy intact.*
*If organizational pressure to revise it intensifies as data becomes trustworthy,*
*that pressure is evidence that the boundary is working correctly.*
