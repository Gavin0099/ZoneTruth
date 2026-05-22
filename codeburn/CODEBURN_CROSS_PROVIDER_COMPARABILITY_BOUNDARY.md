# CodeBurn — Cross-Provider Comparability Boundary

> Written: 2026-05-20
> Status: **BINDING** — P0 constitutional freeze document, effective immediately
> Scope: all CodeBurn versions, all provider combinations, all aggregation operations
> Prerequisite for: any multi-provider reporting, any cross-session analysis, any aggregate claim
> Depends on: CODEBURN_TOKEN_PROVENANCE_ONTOLOGY.md (epistemic class definitions)

---

## Why This Document Must Exist Before Multi-Provider Acquisition

The natural endpoint of a multi-provider token observability system is comparison.

Once CodeBurn can observe token counts from Claude, Codex, and potentially other
providers, the organizational pressure to compare them becomes very difficult to
resist technically. The data will be in the same database. The schema will have
the same fields. The reports will render them side by side.

At that point, comparison will feel inevitable — not because it is authorized,
but because it is structurally available.

**This document establishes that structural availability ≠ epistemic authorization.**

The comparability boundary must be defined before multi-provider acquisition exists,
for the same reason the consumption boundary was defined before acquisition legitimacy
was established: if the boundary is written after the data is present, it will appear
as a post-hoc restriction on already-available comparison surfaces.

Written before, it is a design constraint. Written after, it is a limitation.

---

## The Comparability Prerequisite

Comparison between two token counts is epistemically legitimate only when all of
the following conditions hold simultaneously:

**Condition 1 — Same epistemic class**
Both counts must belong to the same class in the Token Provenance Ontology
(Class A, B, C, or D). Cross-class comparison is prohibited regardless of
other conditions.

**Condition 2 — Same referent definition**
Both counts must measure the same thing. "Token" is not a universal unit —
providers define tokenization differently. A Claude token and a Codex token
are not the same referent. Comparison requires explicit confirmation that the
referents are equivalent, which is not currently achievable.

**Condition 3 — Same observation distance**
The acquisition mode must produce the same distance between observation and
the underlying computation for both counts. A Class A provider-reported count
and a Class B observer-derived count from the same provider are not at the same
observation distance.

**Condition 4 — Declared comparability scope**
The comparison must be accompanied by an explicit declaration of what is being
compared, under what conditions, and what the declared comparison does not imply.

**If any condition is not met, comparison is not permitted.**

No single condition is sufficient on its own. All four must hold simultaneously.
As of 2026-05-20, Condition 2 cannot be confirmed for any cross-provider pair.
This means cross-provider comparison is not currently achievable under any
acquisition configuration.

---

## Permanently Prohibited Comparisons

The following comparisons are prohibited regardless of acquisition completeness,
data quality, or organizational pressure to enable them:

### P1 — Cross-Provider Token Comparison

Comparing token counts between different AI providers.

```
Prohibited:
  Claude session: N tokens
  Codex session:  M tokens
  → "Claude used more tokens than Codex for equivalent work"
```

**Reason:** Condition 2 fails. Tokenization is provider-defined. "Token" is not
a cross-provider unit. There is no currently available mechanism to establish
referent equivalence across providers.

**Does not become permitted when:** acquisition chains for both providers are complete,
data quality improves, or both counts are Class A (provider-reported). Conditions 1
and 4 might be satisfiable; Condition 2 cannot be satisfied without explicit
provider-published tokenization equivalence documentation, which does not exist.

---

### P2 — Cross-Class Comparison

Comparing token counts from different epistemic classes, even from the same provider.

```
Prohibited:
  Session A: Class A (provider-reported) = N tokens
  Session B: Class D (user-asserted)      = M tokens
  → Any comparison or aggregate including both
```

**Reason:** Condition 1 fails. Different epistemic classes carry different claim
legitimacy. Mixing them without class declaration produces undefined provenance.

**Does not become permitted when:** both counts happen to match. Agreement between
Class A and Class D evidence does not upgrade Class D to Class A.

---

### P3 — Unlabeled Aggregation

Computing aggregate statistics (mean, median, total, percentile) across sessions
without declaring the epistemic class of each included count.

```
Prohibited:
  average_tokens_per_session = sum(all session tokens) / session_count
  → where sessions include mixed Class A, B, C, D evidence
```

**Reason:** Unlabeled aggregation conceals epistemic class mixing. The aggregate
inherits the least legitimate class of its inputs, but this inheritance is invisible
in the aggregate value. Condition 4 (declared scope) fails.

**Does not become permitted when:** the database enforces class labeling at storage
time. Aggregation without explicit class-scoped query is prohibited regardless of
how the underlying data is labeled.

---

### P4 — Normalization Across Providers

Applying a conversion factor, normalization function, or equivalence mapping to
make cross-provider token counts comparable.

```
Prohibited:
  normalized_tokens = claude_tokens * 0.8  # "approximate Codex equivalent"
  → then treating normalized_tokens as cross-provider comparable
```

**Reason:** Normalization does not establish referent equivalence — it asserts it.
The assertion is not epistemically grounded without provider-published equivalence
contracts, which do not exist. Normalization transforms a Condition 2 failure into
a hidden assumption, making the violation less visible, not more acceptable.

---

### P5 — Efficiency Inference Across Sessions

Using token counts to draw conclusions about relative efficiency between sessions,
agents, tasks, or providers — even within a single provider and single epistemic class.

```
Prohibited:
  Session A (500 tokens) was more efficient than Session B (1200 tokens)
```

**Reason:** Token count does not measure task equivalence. Sessions with different
task complexity, context size, retry patterns, and output requirements are not
comparable on token grounds even if all other conditions are met. This prohibition
is inherited from the Consumption Boundary and applies at the comparability layer.

---

## Conditionally Permitted Comparisons

The following are permitted when the stated conditions are fully satisfied:

### CP1 — Same-Session, Same-Class Step Aggregation

Summing token counts across steps within a single session, when all steps have
the same epistemic class.

```
Permitted when:
  - All steps in the session share the same epistemic class
  - The class is declared in the report
  - The aggregate is labeled as "session total (Class X)"
```

**What this does not authorize:** comparing the session total to any other session,
or drawing efficiency conclusions from the total.

---

### CP2 — Same-Provider, Same-Class, Declared-Scope Trend Observation

Observing token count trends across sessions from the same provider with the same
acquisition mode, when the scope is explicitly declared.

```
Permitted when:
  - All sessions use the same provider
  - All sessions use the same acquisition mode (same epistemic class)
  - The report declares: "provider: X, acquisition: Y, class: Z"
  - The trend is described as observation only, not as efficiency signal
```

**What this does not authorize:** drawing optimization conclusions from the trend,
or extending the trend observation to sessions outside the declared scope.

---

### CP3 — Data Quality Comparison

Comparing the epistemic class distribution across sessions or providers as a
data quality observation (not as a token usage observation).

```
Permitted:
  "Session A has Class A evidence; Session B has Class D evidence.
   Session A has higher provenance quality."
```

**What this does not authorize:** using provenance quality as a proxy for session
quality, or ranking sessions by provenance quality as an evaluative signal.

---

## The Normalization Trap

The most common path to Condition 2 failure is normalization presented as a
technical solution rather than an epistemic assumption.

The pattern:

```
Step 1: Cross-provider comparison is identified as desirable
Step 2: "Tokens are just numbers" — referent equivalence assumed
Step 3: Conversion factor proposed ("Claude tokens ≈ X Codex tokens")
Step 4: Normalization implemented as a utility function
Step 5: Normalized counts enter reports as if Condition 2 were satisfied
Step 6: Cross-provider comparison becomes standard practice
```

No individual step is an explicit violation. The boundary crossing occurs when
Step 4 is treated as satisfying Condition 2 rather than as an assertion that
bypasses it.

**This document is the pre-positioned reference for identifying Step 3 → Step 4
as a Condition 2 bypass before it becomes implemented infrastructure.**

If a normalization function is proposed for cross-provider token counts, that
proposal is attempting to bypass the comparability prerequisite. Reject it at
the design stage. The correct response is not "we need a better conversion factor"
but "referent equivalence requires provider-published equivalence contracts."

---

## Comparability Scope Declaration Format

When a permitted comparison (CP1, CP2, or CP3) is included in a report, the
declaration must include:

```yaml
comparability_scope:
  provider: [provider name, e.g. "claude" or "same-provider-only"]
  acquisition_mode: [e.g. "provider-api-response", "session-log-ingestion"]
  epistemic_class: [A / B / C / D]
  comparison_type: [step-aggregation / trend-observation / quality-comparison]
  what_this_does_not_claim:
    - [explicit list of prohibited inferences]
```

The `what_this_does_not_claim` field is not optional. A comparability scope
declaration without explicit prohibited inference listing is incomplete.

---

## Cross-Provider Acquisition State Does Not Change This Boundary

When CodeBurn successfully acquires Class A evidence from both Claude and Codex,
the following remain unchanged:

- Cross-provider token comparison remains prohibited (Condition 2 unsatisfied)
- The normalization trap remains a boundary crossing, not a technical solution
- Aggregate statistics across providers remain unlabeled aggregation violations
- Efficiency inference across providers remains prohibited

Acquisition completeness moves token evidence from Class D to Class A.
It does not move Condition 2 from unsatisfied to satisfied.

**The comparability boundary is not a temporary restriction pending better data.
It is a permanent epistemic constraint on what token counts can legitimately claim.**

---

## Relationship to Other Boundary Documents

| Document | Layer | Constraint |
|---|---|---|
| CODEBURN_TOKEN_PROVENANCE_ONTOLOGY.md | Type system | Defines epistemic classes |
| This document | Comparison surface | Defines what comparisons are permitted |
| CODEBURN_TOKEN_OBSERVABILITY_CONSUMPTION_BOUNDARY.md | Downstream use | Defines what consumers may do |
| CODEBURN_PHASE1_ANALYSIS_CONTRACT.md | Output claims | Defines what CodeBurn may say |

These documents form a layered constraint surface. A use that passes one layer
may still be prohibited by another. All layers apply simultaneously.

---

## Amendment Process

The permanently prohibited comparison list (P1–P5) may be narrowed only if:

1. A provider publishes explicit tokenization equivalence documentation that
   satisfies Condition 2 for a specific cross-provider pair
2. The specific pair is named, and the equivalence scope is documented
3. The amendment is committed before any comparison implementation that depends on it
4. The `what_this_does_not_claim` field for any comparison using the amendment
   explicitly names the remaining prohibited inferences

Amending P1 for one provider pair does not amend it for any other pair.

---

*Structural availability of data is not epistemic authorization to compare it.*
*Acquisition completeness does not satisfy the comparability prerequisite.*
*Cross-provider token counts are not the same kind of evidence.*
