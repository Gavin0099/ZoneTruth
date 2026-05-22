# CodeBurn P7 — Advisory Threshold Governance

> Status: **BINDING** — effective from date of commitment
> Written: 2026-05-22
> Scope: all advisory thresholds in CodeBurn, current and future
> Operationalizes: CODEBURN_V1_1_ARCHITECTURE_FREEZE.md §10
> Does NOT modify: the architecture freeze
> Depends on:
>   CODEBURN_V1_1_ARCHITECTURE_FREEZE.md §10 (Unverified Boundary)
>   CODEBURN_ACQUISITION_SEMANTIC_FREEZE.md (TNP, Anti-Collapse Axiom)
>   CODEBURN_TOKEN_PROVENANCE_ONTOLOGY.md (epistemic class definitions)

---

## 0. Purpose and Scope

The architecture freeze documented one advisory threshold in §10 and described it as
"unverified." It did not define:

- What "unverified" means as a governance category
- What evidence would change that status
- How a threshold in this epistemic state must be represented in downstream artifacts
  (env vars, session display, closeout documents)

P7 closes that gap.

**P7 does not govern verified boundaries** — those do not exist in CodeBurn yet.
P7 governs values that are: empirically derived, single-observation, not sourced from
official provider documentation, and used operationally as heuristics.

**P7 does not imply that advisory thresholds are acceptable indefinitely.**
The primary risk is not the unverified status itself but the downstream drift where
an advisory threshold gets treated in practice as if it were verified.
P7 governs that drift surface.

---

## 1. Definition — Advisory Threshold vs. Verified Boundary

| Dimension | Advisory Threshold | Verified Boundary |
|---|---|---|
| Source | Empirical observation (one or more sessions) | Official provider documentation or API contract |
| Observation count minimum | Any (one is sufficient to create the advisory) | Not applicable — source authority replaces observation count |
| Observation authority | Observer-derived (CodeBurn acquisition observer) | External authority: named Anthropic document, rate-limit API contract |
| Accounting regime confirmed | No | Yes — specific context (API rate limit, session limit, billing) must be named |
| Permitted use | Advisory warning, usage anomaly observation | Threshold comparison, rate planning (if separately authorized) |
| Closeout representation | "advisory threshold — not verified" | "verified boundary — source: [named document]" |
| Subject to AT rules | Yes — all AT rules apply | No — AT rules do not apply once verified |

### What "source authority" means for a verified boundary

A verified boundary requires:

1. A **named, addressable external document** (Anthropic API reference, official changelog,
   rate-limit policy page) that specifies the accounting unit, accounting scope, and
   numeric value.
2. **Confirmed accounting regime** — which accounting system (API rate limits, session
   limits, subscription limits, billing) uses the value, and in what way.

The following are **NOT** source authority for a verified boundary:

- A different observer seeing the same number
- The same threshold working without incident for N consecutive months
- Multiple observations of an unverified referent (Anti-Collapse Axiom applies)

### The NST-1 generalization applies here

`cache_read_input_tokens` (JSONL field) is not a confirmed quota unit in Anthropic's
session limit accounting. The Architecture Freeze §10 states this explicitly. Any
advisory threshold derived from `rate_limit_tokens` (which includes `cache_read_input_tokens`)
inherits this unconfirmed status. A verified boundary requires confirming not just
the numeric value but the accounting treatment of each field in the formula.

---

## 2. Rule AT-1 — Naming Convention

**Env variable names, config keys, and code constants that identify advisory thresholds
must encode their epistemic status in the identifier itself.**

### Format requirement

The token `ADVISORY` must appear as a segment in the identifier. It must not be:
- Abbreviated (`ADV_`)
- Implied by context
- Omitted in favor of shorter names

### Prohibited tokens in advisory threshold identifiers

An advisory threshold identifier must NOT include the following unless `ADVISORY`
precedes or qualifies them:

| Prohibited token | Reason |
|---|---|
| `LIMIT` | Implies a known, authoritative boundary |
| `QUOTA` | Implies provider-confirmed accounting |
| `BOUNDARY` | Implies verification |
| `VERIFIED` | Explicitly false for advisory thresholds |
| `RATE` (standalone) | `RATE_LIMIT` implies the limit is known |

`ADVISORY_WARN` is permitted alongside `RATE` when `ADVISORY` comes first:
`CODEBURN_CLAUDE_5H_ADVISORY_WARN_THRESHOLD` — compliant.

### Examples

**Compliant (existing):**
- `CODEBURN_CLAUDE_5H_ADVISORY_WARN_THRESHOLD` — contains `ADVISORY`, no boundary claim
- `CODEBURN_CODEX_5H_ADVISORY_WARN_THRESHOLD` — same pattern

**Non-compliant (historical, now corrected):**
- `CODEBURN_CLAUDE_5H_WARN_TOKENS` — implied a known token quantity; renamed
- `CODEBURN_CLAUDE_5H_RATE_LIMIT_THRESHOLD` — implies rate limit boundary is known
- `CODEBURN_CLAUDE_SESSION_LIMIT` — implies the limit is authoritative
- `CODEBURN_CLAUDE_5H_QUOTA_THRESHOLD` — `QUOTA` implies provider-confirmed accounting

### Motivating case

The rename from `CODEBURN_CLAUDE_5H_WARN_TOKENS` to `CODEBURN_CLAUDE_5H_ADVISORY_WARN_THRESHOLD`
(commit `816966a`) is the canonical instance of this rule. The original name implied a
known token count. A user reading the name without governance documentation would
interpret it as a verified rate limit. AT-1 formalizes why that interpretation was wrong
and prevents new identifiers from making the same implicit claim.

### Scope

AT-1 applies to:
- Environment variable names
- YAML / JSON configuration keys
- Python constants and variable names for these values
- Any persistent identifier for an advisory threshold in any output artifact

---

## 3. Rule AT-2 — Origin Provenance Record

**Every advisory threshold in operational use must have a committed provenance record
in the registry (Section 7) before first operational use.**

A threshold without a provenance record is ungoverned. An ungoverned threshold may not
be referenced in any governed closeout document.

### Required provenance fields

```yaml
# Template — one entry per advisory threshold per accounting context
identifier: <ENV_VAR_NAME>
status: active | reserved_not_operational | invalidated
epistemic_class: advisory_threshold

value: <integer>
value_unit: tokens
value_metric: <formula — e.g., rate_limit_tokens = input + cache_creation + cache_read>
value_derivation: <arithmetic derivation from calibration_value — must be explicit>

observation_count: <integer — minimum 1 for active status>
observation_date_approx: <date or date range>
observation_context: <description of what was happening during observation>
observation_surface: <what produced the raw signal — UI bar, JSONL field, API header>
calibration_value: <raw observed value, with units>

accounting_regime_confirmed: false
accounting_regime_note: <why it is unconfirmed; which regimes could apply>

observer_notes: <caveats, limitations, untested assumptions>

display_label: <string shown in session display — must include advisory language>
display_footnote: <additional context shown to user>

at_rule_compliance:
  AT-1: PASS | FAIL
  AT-2: PASS (this record) | NOT MET
  AT-3: no invalidity conditions triggered | <condition name if triggered>
  AT-4: no upgrade claimed or in progress | <upgrade doc name if in progress>
  AT-5: applies to all closeout documents referencing this threshold

source_freeze_reference: <CODEBURN_V1_1_ARCHITECTURE_FREEZE.md §N>
registered_date: <YYYY-MM-DD>
```

### What the record must NOT contain

| Prohibited field | Reason |
|---|---|
| `confidence: X%` | Precision without source authority; false quantification |
| `next_review_date` | Implies threshold becomes more authoritative over time (TNP violation by design implication) |
| `validated_by: <name>` | Individual attestation does not substitute for source authority |
| `accuracy: high/medium/low` | Qualitative accuracy claim on an unverified value |

### Edge case — new observation after initial registration

A new observation that gives a different number does not automatically invalidate the
existing entry (see AT-3). It adds a new data point. Whether the advisory value is
updated is an explicit governance decision, documented in the registry entry, not a
silent update to the `value` field.

### Edge case — Codex advisory threshold

`CODEBURN_CODEX_5H_ADVISORY_WARN_THRESHOLD` is referenced in `codeburn_session_display.py`.
Its registry entry (Section 7) has `status: intentionally_inactive_no_observation_authority`
and `observation_count: 0`. This means: the identifier is governed by AT-1 (compliant name),
but it is intentionally unconnected — no observation exists, no value may be used in governed
closeout. A user may set a personal heuristic value; no governed closeout may reference it.

---

## 4. Rule AT-3 — Invalidity Conditions

**The following conditions automatically invalidate an advisory threshold.**

"Invalidated" means: the threshold may not be used in operational display or compared
against observed values. The provenance record is retained as a historical artifact.
The env var must be unset from operational configuration.

### AT-3.1 Provider changes the accounting regime

If Anthropic publishes documentation that explicitly changes how session tokens are
counted, any advisory threshold derived from observation of the previous regime is
invalidated. The change need not affect the numeric value — if the accounting unit
changes (e.g., cache reads counted differently toward session limits), the threshold
is invalidated regardless.

### AT-3.2 Official documentation contradicts the advisory value

If any official Anthropic source (documentation, API rate-limit header semantics with
confirmed documentation, written support confirmation) specifies a numeric value for
the accounting context that contradicts the advisory value by more than 10%, the
advisory threshold is invalidated. The official value creates a candidate verified
boundary (subject to the AT-4 upgrade process).

### AT-3.3 Accounting regime confirmed to differ from observation context

The current advisory threshold was observed in a Claude.ai consumer session. If it is
confirmed that Claude Code Pro subscription sessions use a different accounting regime
from Claude.ai consumer sessions (a specific, documented difference, not a theoretical
one), the advisory threshold derived from Claude.ai observation cannot be applied to
Claude Code contexts. It is invalidated for that context.

### AT-3.4 JSONL field confirmed to not count toward the relevant limit

If Anthropic confirms that `cache_read_input_tokens` in the JSONL does not count toward
session limits — i.e., the `rate_limit_tokens` formula used by CodeBurn does not reflect
the actual quota accounting — the threshold is invalidated because the input to the
formula is wrong.

### AT-3.5 Source observation retracted

If the original observation is found to have been made at a different session percentage
than documented (e.g., it was 85%, not 95%, or the 18.4M figure was a display artifact),
the threshold is invalidated. A new observation must be documented before a new advisory
value is set.

### What does NOT invalidate the threshold

| Non-invalidating event | Reason |
|---|---|
| New sessions where threshold fires earlier or later than expected | Variance is expected in a heuristic; does not retroactively invalidate provenance |
| Time passing without AT-3.1–3.5 occurring | TNP is symmetric: time does not grant authority, but time alone does not strip it either |
| A new observation giving a different number | Creates a new data point; whether the value changes is a governance decision, not an automatic invalidation |
| Users finding the threshold inconvenient | Operational inconvenience is not an epistemic event |

### Partial invalidation

If AT-3.3 applies to one usage context but not another (e.g., invalidated for API-based
sessions but not claude.ai-style sessions), the registry entry is split: one entry per
accounting context. A single entry must not span multiple confirmed-different accounting
regimes.

---

## 5. Rule AT-4 — Upgrade Prohibition

**An advisory threshold cannot be upgraded to a verified boundary through use, time,
or consistency. The only valid upgrade path is documented source authority.**

This is the Temporal Non-Promotion Rule (TNP) applied specifically to advisory
thresholds. The general TNP in the architecture freeze §6 governs evidence class
promotion. AT-4 governs threshold status promotion, which has its own drift pattern.

### The specific drift pattern AT-4 closes

```
Advisory threshold set at value V (one observation, N months ago)
  → threshold operational for N months
  → no complaints about false positives or misses
  → threshold "seems to be working"
  → team treats it as the Anthropic limit
  → closeout document: "rate limit threshold verified through operational use"
```

Each step is individually plausible. The governance violation is in the final step.
AT-4 makes the violation visible at each intermediate step rather than only at closeout.

### Explicitly prohibited upgrade paths

| Prohibited path | Why it fails |
|---|---|
| Repeated use (N sessions, N months, N phases) | Number of uses does not upgrade epistemic class |
| Historical stability ("no problems in N months") | Stability is operational utility, not epistemic validity |
| Implementation convenience ("changing the code is expensive") | Implementation cost does not grant authority |
| Cross-observation consistency (two observations, similar numbers) | Multiple observations of an unverified referent do not create a verified referent (Anti-Collapse Axiom) |
| Informal provider confirmation ("support chat said X") | Not a named, addressable external document |

### The only valid upgrade path

An advisory threshold may be upgraded to a verified boundary if and only if all of
the following conditions are met:

1. A named Anthropic source document specifies a numeric value for the exact accounting
   context (session limit, API rate limit, subscription limit) in which CodeBurn
   applies the threshold.

2. The accounting regime is unambiguously confirmed: the source document specifies
   whether `cache_read_input_tokens` counts toward the limit, at what rate, and whether
   that rate applies to CodeBurn's acquisition context.

3. A new governance document (`CODEBURN_CLAUDE_RATE_LIMIT_VERIFIED_BOUNDARY.md` or
   equivalent) is written that names the source, quotes the relevant text, and
   specifies the verified value and its accounting scope.

4. That document is committed **before** the threshold is relabeled as verified in any
   operational configuration or closeout document.

5. The existing advisory threshold registry entry is updated with:
   `upgraded_to_verified_by: <document name>` and the upgrade timestamp.

**No operational observation, however numerous or consistent, substitutes for
conditions 1–2.** The upgrade is a source authority event, not an empirical
accumulation event.

The advisory threshold may remain in operational use during the upgrade process. What
changes is the label on closeout documents, not the operational behavior.

---

## 6. Rule AT-5 — Closeout Prohibition

**A governed closeout document may not assert that an advisory threshold constitutes
a verified rate limit, quota boundary, or provider-confirmed ceiling.**

This rule applies to all CodeBurn phase closeouts and session closeouts, whether
manually written or programmatically generated.

### Wording that IS permitted in closeout documents

- `"The advisory warning threshold CODEBURN_CLAUDE_5H_ADVISORY_WARN_THRESHOLD (9,705,984 tokens) was active during this phase."`
- `"Advisory threshold firing was observed during N sessions."`
- `"No advisory threshold invalidity conditions (AT-3) were triggered during this phase."`
- `"The advisory threshold remains unverified per AT-4."`
- `"Rate limit observability used advisory heuristic — see AT-2 provenance record."`
- `"Advisory threshold: not triggered"` (in summary tables)
- `"Advisory threshold: fired N times — not a verified limit"` (in summary tables)

### Wording that is NOT permitted in closeout documents

| Prohibited wording | Violation |
|---|---|
| `"The session rate limit threshold has been validated through operational use."` | AT-4 prohibits operational-use as validation |
| `"Session token warnings correspond to approximately X% of the Anthropic 5h limit."` | Architecture Freeze §10: "X% of Anthropic limit" claims are forbidden |
| `"Rate limit threshold is set to 9,705,984 tokens based on observed Anthropic session behavior."` | "Observed Anthropic session behavior" implies empirical verification |
| `"No rate limit violations occurred during this phase."` | Implies the advisory threshold is the rate limit |
| `"Session token ceiling is approximately 18.4M tokens."` | Treats calibration observation as confirmed ceiling |
| `"Rate limit threshold: compliant"` in a summary table | Implicit verified-boundary claim through table structure |
| Any phrase containing `"verified threshold"`, `"confirmed limit"`, `"Anthropic rate limit boundary"`, or `"provider quota"` without explicit advisory qualification | Authority inflation |

### Implicit claims

A table cell reading `"rate limit threshold: compliant"` with the advisory threshold
value is making an implicit verified-boundary claim — the table structure implies the
threshold is the limit and compliance is measured against it. This format is prohibited.
The cell must make the advisory status explicit.

### Automated enforcement (future)

AT-5 is currently enforced through documentation review. A future enforcement gate
could scan closeout documents for the prohibited phrases above, analogous to the
`codeburn_validate_analysis.py` forbidden phrase scanner. P7 does not require
implementing that scanner, but AT-5's wording table is designed to support it.

---

## 7. Current Advisory Threshold Registry

```yaml
registry_version: 1
generated_date: 2026-05-22
governed_by: CODEBURN_P7_ADVISORY_THRESHOLD_GOVERNANCE.md

entries:

  - identifier: CODEBURN_CLAUDE_5H_ADVISORY_WARN_THRESHOLD
    status: active
    epistemic_class: advisory_threshold

    value: 9705984
    value_unit: tokens
    value_metric: >
      rate_limit_tokens = input_tokens + cache_creation_input_tokens +
      cache_read_input_tokens (JSONL fields, per-turn sum across session)
    value_derivation: >
      Derived from calibration: 18,400,000 tokens observed at ~95% session usage.
      Warn threshold = floor(18,400,000 * 0.5274) ≈ 9,705,984.
      Factor 0.5274 ≈ 0.95 / 1.8 (targeting ~50% of estimated 5h ceiling of 19.4M).
      Exact arithmetic was not recorded at derivation time; this reconstruction is
      approximate. The derivation depends on the 95% figure from the UI bar and
      the assumption that 18.4M at 95% implies a 5h ceiling of ~19.4M.
      Both assumptions are unverified.

    observation_count: 1
    observation_date_approx: prior to 2026-05-22 (exact date not recorded)
    observation_context: >
      Claude.ai session approaching session limit. Provider-reported UI bar
      showed ~95% usage. JSONL rate_limit_tokens (cache-inclusive) read at that point.
    observation_surface: >
      Two surfaces read simultaneously:
      (1) claude.ai consumer product session bar — provider-reported percentage display
      (2) JSONL cache_read_input_tokens field in ~/.claude/projects/**/*.jsonl
      Whether these two surfaces measure the same accounting unit is unconfirmed.
    calibration_value: cache-inclusive 5h rate_limit_tokens ≈ 18,400,000 at ~95% session usage

    accounting_regime_confirmed: false
    accounting_regime_note: >
      Four regimes may apply; none confirmed for this value:
        1. Claude.ai session window limit (consumer product)
        2. Anthropic API rate limit (anthropic-ratelimit-tokens-* headers)
        3. Claude Code Pro subscription session accounting
        4. Anthropic billing (cache reads charged at discounted rate)
      NST-1 (generalized): cache_read_input_tokens JSONL field is not a confirmed
      quota unit in Anthropic's session accounting. Same field name != same
      accounting regime across systems.

    observer_notes: >
      Single data point. Observation was made during normal session use, not under
      controlled experimental conditions. The provider-reported percentage (UI bar)
      and the JSONL rate_limit_tokens field may measure different quantities.
      No repeatability testing was performed across different session types,
      model versions, or subscription tiers. The 95% figure is provider-reported
      and its relationship to the underlying token accounting is unknown.

    display_label: "Observed saturation heuristic — NOT verified Anthropic quota boundary"
    display_footnote: "cache_read accounting regime not confirmed"

    at_rule_compliance:
      AT-1: "PASS — identifier contains ADVISORY"
      AT-2: "PASS — this registry entry"
      AT-3: "no invalidity conditions triggered as of 2026-05-22"
      AT-4: "no upgrade claimed or in progress"
      AT-5: "applies to all closeout documents referencing this threshold"

    rename_history:
      - from: CODEBURN_CLAUDE_5H_WARN_TOKENS
        to: CODEBURN_CLAUDE_5H_ADVISORY_WARN_THRESHOLD
        commit: 816966a
        reason: Original name implied a verified token quantity; renamed to encode advisory status

    source_freeze_reference: CODEBURN_V1_1_ARCHITECTURE_FREEZE.md §10
    registered_date: 2026-05-22


  - identifier: CODEBURN_CODEX_5H_ADVISORY_WARN_THRESHOLD
    status: intentionally_inactive_no_observation_authority
    epistemic_class: advisory_threshold_candidate

    value: null
    value_metric: >
      Would follow same rate_limit_tokens formula as Claude entry, applied to
      Codex JSONL fields. Codex field semantics may differ from Claude fields
      (NST-1: tokens not cross-provider comparable).
    value_derivation: null

    observation_count: 0
    observation_date_approx: null
    observation_context: null
    calibration_value: null

    accounting_regime_confirmed: false
    accounting_regime_note: >
      No observation exists. Codex rate limit accounting is independently unverified
      from Claude accounting. NST-1 applies: Codex token fields != Claude token fields.

    at_rule_compliance:
      AT-1: "PASS — identifier contains ADVISORY"
      AT-2: "NOT MET — observation_count = 0; no value may be used in governed closeout"

    note: >
      This identifier is referenced in codeburn_session_display.py as a valid env var.
      A user may set a personal heuristic value for their own operational use.
      No governed closeout document may reference this threshold until AT-2 is
      satisfied: minimum one observation documented and committed to this registry.
      Until then, any value set for this variable is ungoverned.

    registered_date: 2026-05-22
```

---

## 8. Relationship to Architecture Freeze

### 8.1 This document does not modify the freeze

Section 10 of the architecture freeze documents the advisory threshold and the
unverified posture. P7 does not change those statements. Any phrase in P7 that could
be read as relaxing §10 is a P7 drafting error, not a freeze amendment.

### 8.2 P7 operationalizes §10 without claiming to resolve it

The freeze §10 states the boundary is "not verified" and leaves the accounting regime
question "explicitly unresolved." P7 accepts that unresolved status and defines how to
operate with it — how to name it, document it, maintain it, and prevent it from being
implicitly resolved through use. P7 does not provide evidence that would resolve §10.

### 8.3 The only path that modifies §10 is the AT-4 upgrade path

If AT-4 conditions are fully met (official Anthropic source document, confirmed
accounting regime, committed verified boundary document), §10 of the freeze may be
updated to reflect that the boundary is now verified, with a reference to the verified
boundary document. That update is an amendment to §10 (subject to the freeze's own
amendment process in §9.4 of the freeze), not a consequence of P7 alone.

### Rule-to-freeze mapping

| AT Rule | Relationship to Architecture Freeze |
|---|---|
| AT-1 Naming | Extends §10 naming rationale (ADVISORY_WARN_THRESHOLD) to a formal rule |
| AT-2 Provenance | Implements §10 "single observation" statement as a structured required record |
| AT-3 Invalidity | Makes §10 "explicitly unresolved" concrete — names what would resolve it (negatively) |
| AT-4 Upgrade prohibition | Extends TNP (§6) to advisory threshold promotion specifically |
| AT-5 Closeout prohibition | Extends §10 forbidden posture ("X% of Anthropic limit" claims) to the closeout surface |

### Note on advisory_only field in schema

CodeBurn Phase 1 schema has a field `advisory_only INTEGER` for execution signals.
This is a different governance concept:
- `advisory_only` (schema): whether a signal can block execution
- Advisory threshold (AT rules): whether a threshold value carries verified authority

The naming overlap is coincidental. They govern different surfaces and must not be
conflated.

---

## 9. Amendment Process

### Registry-only updates (no P7 version bump required)

- Adding a new advisory threshold entry to the registry
- Updating `at_rule_compliance` when a condition changes
- Recording an AT-3 invalidity trigger on an existing entry
- Recording an AT-4 upgrade on an existing entry (with pointer to verified boundary doc)

### Full P7 amendment required

- Adding a new AT rule
- Relaxing any existing AT rule
- Changing the Section 1 definition of advisory threshold vs. verified boundary
- Changing the valid upgrade path in AT-4
- Changing the permitted/prohibited wording in AT-5

### Amendment process

1. Name the specific AT rule or definition being changed and the reason.
2. State the new rule text or definition.
3. Record the operational finding or governance event that necessitated the change.
4. Commit with a version bump (`version: 1` in header → `version: 2`).
5. If the amendment affects AT-5, review active phase closeout templates.
