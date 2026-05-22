# CodeBurn v1.1 — Architecture Freeze Snapshot

> Status: **FROZEN BASELINE**
> Written: 2026-05-22
> Phases completed: P0 – P6 (admission research through observability tooling)
> Purpose: Capture the governed architecture baseline before any new ingestion or
>          analytics work begins. This document defines what the system IS,
>          what it is NOT, and what convergence paths are permanently forbidden.
>
> This document does not authorize new work.
> It is a precise record of what was built and why the boundaries are where they are.

---

## 1. What Was Built

**CodeBurn v1.1 is a multi-provider evidence acquisition architecture.**

It is not a multi-provider analytics platform.

The distinction is load-bearing:

| Evidence Acquisition Architecture | Analytics Platform |
|-----------------------------------|--------------------|
| Acquires evidence from multiple providers | Aggregates data from multiple providers |
| Preserves provenance identity per record | Blends records into unified views |
| Enforces epistemic class per source | Normalizes to a common unit |
| Forbids cross-class comparison | Enables cross-source dashboards |
| authority_flags = all false permanently | Presents evidence as decision input |

CodeBurn is the first column. It will not become the second column without a formal
epistemic upgrade process that does not currently exist.

---

## 2. Supported Evidence Classes

### Class C — Observer-Reconstructed Session Evidence

> The observer read a session log written by the provider's client software.
> Token counts are reconstructed from log entries, not directly measured.
> The observer cannot verify provider truthfulness.

| Field | Value |
|-------|-------|
| `epistemic_class` | `Class C` |
| `real_time_observed` | `0` (permanently) |
| `analysis_safe_for_decision` | `0` (permanently) |
| `provider_truthfulness_assumed` | `0` (permanently) |
| Granularity | Per API turn (JSONL line) |
| Provenance identity | source_artifact_path + line + offset |
| Token counts | Reconstructed from `input_tokens` + `output_tokens` |
| Rate-limit tokens | `input + cache_creation + cache_read` (display only, rate limit estimation) |

### Class D — Billing-Reported Evidence

> The observer acquired billing-system ledger entries produced by converting
> token counts through pricing rates and plan-specific conditions.
> The original token counts are not recoverable without billing computation (IAF-4).

| Field | Value |
|-------|-------|
| `epistemic_class` | `Class D` |
| `real_time_observed` | `0` (permanently) |
| `analysis_safe_for_decision` | `0` (permanently) |
| `provider_truthfulness_assumed` | `0` (permanently) |
| Granularity | Per user / model / day (billing aggregate) |
| Provenance identity | source_artifact_path + CSV row line |
| Token counts | **Not available** — `aic_quantity` (credits) only |
| Session identity | **None** — daily aggregate has no session UUID |

**Class D is weaker than Class C.** The observation distance is greater.
Class D + Class C → NOT comparable (FSP-3 applies across classes).

---

## 3. Provider → Evidence Class Mapping

| Provider | Surface | Class | Table | Admission Gate |
|----------|---------|-------|-------|----------------|
| Claude (Anthropic) | Session JSONL (`~/.claude/projects/**/*.jsonl`) | C | `steps` + `step_ingestion_provenance` | P3 (original design) |
| Codex (OpenAI) | Session JSONL + rate_limits payload | C | `steps` + `step_ingestion_provenance` | P5 admission gate |
| GitHub Copilot | AI Credits billing CSV (2026-06-01+) | D | `copilot_billing_events` + `copilot_surface_annotations` | Copilot admission gate (AG-Copilot-1..6) |

**Any new provider requires a full admission gate before any ingestion work begins.**
The admission gate minimum requirements are defined in Section 6.

---

## 4. Non-Transferable Semantics (Frozen)

The following field-level semantic equivalences are **permanently forbidden**:

### NST-1: Token Fields Are Not Cross-Provider Comparable

`Claude.input_tokens ≠ Codex.input_tokens`

Both fields are named identically and both are integers. They are not the same thing:
- Claude `input_tokens` counts tokens in the Anthropic tokenizer after prompt construction
- Codex `input_tokens` counts tokens in the OpenAI tokenizer after prompt construction

Different tokenizers, different models, different context construction strategies.
The numeric values cannot be compared, averaged, or aggregated across providers.

### NST-2: AI Credits Are Not Token Counts

`aic_quantity ≠ input_tokens` (in either direction, for any provider)

AI Credits are a billing construct. They are produced by:
```
tokens → model pricing rate → plan multiplier → AI Credits
```
The original token count is not recoverable from AI Credits without billing computation.
Treating `aic_quantity` as a token count is a CP-1 violation.

### NST-3: Rate-Limit Tokens Are Not Billing Tokens

`rate_limit_tokens ≠ billable_tokens`

`rate_limit_tokens` (input + cache_creation + cache_read) is the total token volume
sent to the API, used for rate limit estimation. It differs from billable tokens because:
- Cache reads are charged at a discounted rate (billing perspective)
- But cache reads count fully toward rate limits (consumption perspective)

`rate_limit_tokens` is stored for rate limit observability only. It must not be used
in any cost or billing context.

---

## 5. Admission Gate Requirements (for any new provider)

Before any new provider may be ingested, the following must exist as committed documents:

1. **Surface Research Document** (equivalent to P6 admission research):
   - What is the surface? What does it actually contain?
   - What are the structural gaps? (What is systematically absent?)
   - What is the observation distance? (How many transforms from raw signal?)

2. **Admission Gate Document** answering at minimum:
   - AG-N-1: How is structural incompleteness represented? (schema-enforced annotation)
   - AG-N-2: What is the provenance identity model? (line-level or aggregate?)
   - AG-N-3: How are corrections / retroactive changes handled?
   - AG-N-4: How is billing computation prevented? (column exclusions + schema guards)
   - AG-N-5: How is cross-provider comparison prevented? (query-level contracts)
   - AG-N-6: What adversarial re-interpretation attempts were tested?

3. **Epistemic class confirmed** (Class C or Class D, or new class if warranted)

4. **Separate table** if Class D or below (never `steps` or Class C tables)

5. **Semantic freeze updated** with new provider's non-transferable semantics

---

## 6. Frozen Invariants

These invariants cannot be relaxed by implementation convenience or scope pressure.

### Anti-Collapse Axiom
> Stable reconstruction does not collapse observation distance.
>
> 100 consistent replays of a session = reconstruction method is stable.
> 100 consistent replays ≠ the reconstructed values are measurements.

### Field Semantic Permanence (FSP-3)
> The semantic meaning of a field is determined at acquisition time and is permanent.
> No accumulation of data, no historical consistency, no cross-provider co-occurrence
> changes the semantic type of a field.

### Temporal Non-Promotion Rule (TNP)
> Replay stability / persistence / historical consistency MUST NOT upgrade
> provider equivalence, field equivalence, or aggregation admissibility.

### IAF-4: Billing Computation Forbidden
> `cached_input_tokens` (for billing) and `aic_gross_amount` (Copilot) must not be stored.
> Any feature that multiplies token counts by a price rate is out of scope.
> `rate_limit_tokens` is the only permitted use of cache token data, and it is
> annotated for rate-limit estimation only, not for billing computation.

---

## 7. Closeout Obligations

Every phase must produce a closeout document before the next phase opens.
The closeout document must confirm:

- [ ] All evidence admitted in this phase is Class C or Class D
- [ ] `real_time_observed = 0` on all rows
- [ ] `analysis_safe_for_decision = 0` on all rows
- [ ] `provider_truthfulness_assumed = 0` on all rows
- [ ] No cross-provider aggregation introduced
- [ ] No cost estimation introduced
- [ ] Semantic freeze not violated

Closeout documents are **append-only** records. A closed phase cannot be reopened
by overwriting its closeout document.

---

## 8. Forbidden Convergence Paths

The following convergence paths are permanently forbidden. They are listed explicitly
because they are the natural drift direction of any system that acquires multi-provider data.

### FCP-1: The Normalization Slide
```
tokens (Claude) + credits (Copilot) + tokens (Codex)
  → normalize to common unit
  → unified usage aggregate
  → "total AI consumption" dashboard
```
**Why forbidden:** The normalization step requires asserting cross-class, cross-provider
comparability that does not exist. Any common unit is fabricated.
The output would present fabricated comparability as measurement.

### FCP-2: The Cost Efficiency Ranking
```
session token counts
  → multiply by provider pricing rate
  → cost per session
  → rank sessions / prompts by cost efficiency
  → optimization recommendations
```
**Why forbidden:** Billing computation (IAF-4). Token counts are Class C reconstructions,
not measurements. Cost efficiency claims on Class C data are authority inflation.

### FCP-3: The Historical Calibration Drift
```
provider X has been stable for N months
  → "we have enough history to calibrate"
  → treat historical mean as ground truth
  → reduce epistemic disclaimers
  → begin using as decision input
```
**Why forbidden:** TNP (Temporal Non-Promotion Rule). Historical consistency does not
upgrade the epistemic class of reconstructed evidence. N months of consistent Class C
evidence is still Class C evidence.

### FCP-4: The Dashboard Authority Inflation
```
Class C data displayed in a chart
  → chart looks authoritative
  → users make decisions from chart
  → system implicitly accepts decision use
  → "analysis_safe_for_decision" becomes effectively 1 through practice
```
**Why forbidden:** V-1 (Visualization constraint). All visualizations must carry explicit
`observer-reconstructed, Class C, not decision-authoritative` annotation.
Display design that omits this annotation is an authority inflation surface.

### FCP-5: The Billing-to-Token Inversion
```
aic_quantity (Copilot AI Credits)
  → divide by published GitHub pricing rate
  → estimate token counts
  → store as token evidence
  → compare with Claude/Codex token evidence
```
**Why forbidden:** CP-1 violation. The published rate may differ from the rate actually
applied at billing time (plan multipliers, promotional rates, retroactive corrections).
The inversion is non-invertible without knowing the exact billing rate used.

---

## 9. What the System Is Not (and Will Not Become Without Formal Upgrade)

| Category | Status |
|----------|--------|
| Token measurement system | NOT — all counts are Class C reconstructions |
| Cost tracking system | NOT — IAF-4 permanently forbids billing computation |
| Cross-provider comparison system | NOT — FSP-3 + NST-1 permanently forbid this |
| Optimization recommendation system | NOT — O-1 permanently forbids this |
| Decision-support system | NOT — `analysis_safe_for_decision = 0` permanently |
| Billing approximation system | NOT — C-1 permanently forbids this |

Upgrading any of these would require:
1. A new epistemic class definition (above Class C)
2. A formal claim that provider data meets the bar for that class
3. Adversarial review of that claim
4. Formal amendment to this freeze document

This process does not currently exist. It cannot be triggered by implementation alone.

---

## 10. Rate Limit Observation Posture (Unverified Boundary)

CodeBurn's session display includes an advisory warning based on `rate_limit_tokens`
(input + cache_creation + cache_read) compared against a user-set threshold.

**This boundary is NOT verified.** The following is explicitly unresolved:

### Unresolved: cache_read accounting regime

One calibration observation was made:
> At 95% session usage (Claude.ai), cache-inclusive 5h tokens ≈ 18.4M

This is a single observation, not a verified Anthropic quota boundary.

The following accounting regimes may differ for `cache_read_input_tokens`:
- **Claude.ai session limit**: tracks some measure of window consumption
- **Anthropic API rate limit** (`anthropic-ratelimit-tokens-*` headers): per-minute API quota
- **Claude Code subscription accounting**: how Pro subscription counts session usage
- **Billing**: cache reads charged at discounted rate vs. full rate for new tokens

`cache_read_input_tokens` appears in the JSONL. Its semantic meaning within Anthropic's
quota accounting system has not been confirmed against any official documentation.

**This is NST-1 applied to internal accounting systems:**
> `cache_read_input_tokens` (JSONL field)
> ≠ confirmed quota unit in Anthropic's session limit accounting

### Permitted posture

The threshold variable is named `CODEBURN_CLAUDE_5H_ADVISORY_WARN_THRESHOLD` (not `WARN_TOKENS`)
to signal its epistemic status. The display explicitly says:
- `"Observed saturation heuristic — NOT verified Anthropic quota boundary"`
- `"cache_read accounting regime not confirmed"`

This posture permits: advisory warning, usage anomaly observation.
This posture forbids: "X% of Anthropic limit" claims, decision authority.

---

## 11. Freeze Confirmation

This snapshot confirms the governed architecture baseline as of CodeBurn v1.1 (2026-05-22).

| Component | Status |
|-----------|--------|
| Claude ingestion (Class C) | COMPLETE — smoke + replay stable |
| Codex ingestion (Class C) | COMPLETE — smoke + replay stable |
| Copilot billing ingestion (Class D) | COMPLETE — admission gate answered |
| Semantic freeze | ACTIVE — NST-1..3, FSP-3, Anti-Collapse, TNP |
| P6 scope constraints | ACTIVE — A-1, T-1, C-1, R-1, O-1, V-1 |
| Closeout recognition | STABLE — canonical path valid |
| Forbidden convergence paths | DOCUMENTED — FCP-1..5 |
| Architecture type | Multi-provider evidence acquisition (NOT analytics platform) |
