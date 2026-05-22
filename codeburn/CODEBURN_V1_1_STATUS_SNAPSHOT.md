# CodeBurn v1.1 — Status Snapshot

> Type: **operational reference** — not a rulebook, not a phase document
> Written: 2026-05-22
> Baseline: CodeBurn v1.1 (phases P0–P7 complete)
> Purpose: Let a future agent or human answer four questions at a glance:
>   (1) What can be done?  (2) What cannot be done?
>   (3) What phrases are permanently forbidden?  (4) What is the current evidence inventory?
>
> This document does not add rules. It indexes what already exists.
> Authoritative sources are the governing documents listed in Section 6.

---

## 0. Reading Posture

### What this document is

**This document constrains inference. It does not transmit capability.**

This is an interpretation admission gate — it decides which interpretations of
CodeBurn v1.1 are permitted to enter before any capability description is read.

Governance erosion begins at the language layer:

```
vocabulary shift → implicit ontology → reviewer expectation → architecture drift
```

Certain words — `quota`, `actual token usage`, `billing-grade`, `cross-provider` —
do not describe operations. They carry unauthorized implicit ontologies: centralized
accounting, provider-coupled observability, precision the evidence class cannot
support. The Forbidden Phrases section (Section 3) is not a style guide.
It is an **ontology containment boundary** — it prevents **semantic preauthorization**:
the stabilization of expectations that makes future capability expansion appear
inevitable and legitimate before any capability has been built.

**Semantic authority drifts before runtime authority does.**

Runtime drift: code → review → merge → deploy. Each step is visible and catchable.
Semantic drift: a reviewer's default, an issue's wording, a dashboard label.
No review gate catches it. The failure mode is **expectation-induced capability
drift** — language builds an organizational model of what the system should be,
then pressure reverses and architecture is asked to match it.

This section must be read before the capability sections, not after.
If read last, boundedness will already have been reinterpreted as temporary caution
or incomplete implementation — which is exactly what this section exists to prevent.

### Three reading errors this section is here to prevent

**"Absence from CAN means future roadmap."**
It does not. Absence from the CAN sections means the action has no governed path
in v1.1. Some absent actions are permanently out of scope. Others may become
in-scope through a formal admission process. Neither is implied by the absence alone.

**"Presence in BLOCKED means engineering incompleteness."**
It does not. The BLOCKED surfaces section distinguishes between engineering choices
and structural constraints. Most blocked surfaces in v1.1 are blocked because the
underlying data is not available, the accounting regime is unverifiable, or the
semantic gap cannot be closed without provider-side changes. These are not backlogs.
They are boundary conditions.

**"Governance documents I haven't read don't apply to me."**
They do. Partial reading produces selective interpretation. The governing documents
index (Section 6) exists so that any constraint referenced in this snapshot can be
traced to its authoritative source. If a constraint seems wrong, the response is to
read the governing document — not to treat the constraint as optional.

> **Boundedness is part of the architecture.**
> CodeBurn v1.1 is intentionally scoped. The boundaries exist because the evidence
> classes have real epistemic limits, not because the system is unfinished.
> A system that claims to do more than its evidence supports is not a better system —
> it is a less honest one.

---

## System Identity

**CodeBurn v1.1 is a bounded multi-surface AI usage evidence system.**

| Property | Value |
|---|---|
| Architecture type | Evidence acquisition — NOT analytics platform |
| Evidence classes active | Class C, Class D |
| Advisory thresholds active | 1 (Claude 5h, unverified) |
| Cross-provider comparison | Permanently forbidden |
| Decision-support use | Permanently forbidden (`analysis_safe_for_decision = 0`) |
| Cost estimation | Permanently forbidden (IAF-4) |
| Real-time observation | None — all evidence is reconstructed or billing-reported |

Three upgrade paths are permanently blocked by governing invariants:

| Forbidden upgrade | Blocking rule |
|---|---|
| Session evidence → provider truth | Anti-Collapse Axiom, FSP-3, real_time_observed = 0 |
| Billing evidence → cost audit truth | IAF-4, CP-1, NST-2, Class D epistemic ceiling |
| Advisory threshold → provider quota boundary | AT-4, TNP, Architecture Freeze §10 |

---

## 1. What You CAN Do

### Ingest

| Action | Provider | Table | Class |
|---|---|---|---|
| Ingest session JSONL (`~/.claude/projects/**/*.jsonl`) | Claude | `steps` + `step_ingestion_provenance` | C |
| Ingest session JSONL (Codex format with rate_limits payload) | Codex | `steps` + `step_ingestion_provenance` | C |
| Ingest AI Credits billing CSV (2026-06-01+ format) | Copilot | `copilot_billing_events` + `copilot_surface_annotations` | D |

### Query

| Action | Constraint |
|---|---|
| Query `steps` per provider | Filter by `provider` column; do not aggregate across providers |
| Query `copilot_billing_events` | Always include `model` column; never join with `steps` |
| Query advisory threshold status | Read `CODEBURN_CLAUDE_5H_ADVISORY_WARN_THRESHOLD` env var; display with advisory label |
| Produce per-provider usage summaries | Label each summary with its evidence class; no cross-class totals |

### Display

| Action | Required label |
|---|---|
| Show Claude/Codex session token counts | "observer-reconstructed, Class C, not decision-authoritative" |
| Show Copilot AI Credits | "billing-reported, Class D, not token evidence" |
| Show advisory threshold warning | "Observed saturation heuristic — NOT verified Anthropic quota boundary" |
| Show rate_limit_tokens | "rate limit estimation only — not billing" |

### Closeout

| Action | Constraint |
|---|---|
| Write phase closeout documents | Must use permitted AT-5 wording (Section 3); no upgrade claims |
| Reference advisory threshold in closeout | Permitted only with "advisory threshold — not verified" language |
| Confirm evidence class in closeout | `real_time_observed = 0`, `analysis_safe_for_decision = 0`, `provider_truthfulness_assumed = 0` on all rows |

---

## 2. What You CANNOT Do

### Cross-provider operations

| Forbidden action | Blocking rule |
|---|---|
| Aggregate `input_tokens` across Claude + Codex | NST-1: tokens not cross-provider comparable |
| JOIN `steps` with `copilot_billing_events` | Schema isolation; Class C + Class D must not be aggregated |
| Produce a "total AI consumption" metric | FCP-1 (Normalization Slide) |
| Rank sessions or providers by cost efficiency | FCP-2 (Cost Efficiency Ranking) |

### Cost and billing operations

| Forbidden action | Blocking rule |
|---|---|
| Multiply token counts by pricing rates | IAF-4 (billing computation forbidden) |
| Convert `aic_quantity` to token counts | CP-1, NST-2 |
| Ingest `aic_gross_amount` from billing CSV | C-1 |
| Store `cached_input_tokens` for billing | IAF-4 |
| Use `rate_limit_tokens` for cost estimation | NST-3 |

### Evidence promotion

| Forbidden action | Blocking rule |
|---|---|
| Treat consistent replay as measurement | Anti-Collapse Axiom |
| Upgrade evidence class through historical consistency | FSP-3, TNP |
| Use `analysis_safe_for_decision = 0` rows as decision input | Schema CHECK (column permanently 0) |
| Claim advisory threshold is a verified quota | AT-4 |
| Upgrade advisory threshold through repeated use | AT-4 (explicit prohibited path) |

### New provider or surface ingestion

| Forbidden action | Blocking rule |
|---|---|
| Ingest a new provider without an admission gate | Architecture Freeze §5 (6-question minimum) |
| Ingest Copilot completions usage | completions_excluded = 1 (schema CHECK, always) |
| Create a new evidence class without a formal definition | Admission gate process required |

---

## 3. Permanently Forbidden Phrases

These exact phrases — and their semantic equivalents — are forbidden in any governed
output: closeout documents, session displays, dashboards, analysis reports.

| Forbidden phrase | Category | Blocking rule |
|---|---|---|
| `"X% of Anthropic limit"` | Authority inflation | Architecture Freeze §10, AT-5 |
| `"X% of your rate limit"` | Authority inflation | Architecture Freeze §10 |
| `"total AI consumption"` | Cross-class normalization | FCP-1 |
| `"cost per session"` | Billing computation | FCP-2, IAF-4 |
| `"cost efficiency"` | Billing computation | FCP-2 |
| `"verified through operational use"` | Upgrade inflation | AT-4 |
| `"compared across providers"` | Cross-provider comparison | NST-1, FSP-3 |
| `"session token ceiling is approximately N"` | Unverified boundary claim | Architecture Freeze §10 |
| `"rate limit threshold: compliant"` (table cell) | Implicit verified-boundary claim | AT-5 |
| `"no rate limit violations occurred"` | Implied verified limit | AT-5 |
| `"analysis safe for decision"` (without `= 0`) | Decision authority inflation | FCP-4 |
| `"tokens are equivalent across providers"` | NST-1 violation | NST-1 |
| `"AI Credits ≈ N tokens"` | NST-2, CP-1 violation | NST-2, CP-1 |
| `"billing data confirms usage"` | Class D promotion | IAF-4, Class D ceiling |

---

## 4. Evidence Inventory

### Class C — Observer-Reconstructed Session Evidence

| Property | Value |
|---|---|
| Providers | Claude (Anthropic), Codex (OpenAI) |
| Source surface | Session JSONL (`~/.claude/projects/**/*.jsonl`, Codex equivalents) |
| Granularity | Per API turn (JSONL line) |
| Token fields ingested | `input_tokens`, `output_tokens` (prompt/completion) |
| Rate-limit field | `rate_limit_tokens = input + cache_creation + cache_read` (display only) |
| `real_time_observed` | 0 permanently |
| `analysis_safe_for_decision` | 0 permanently |
| `provider_truthfulness_assumed` | 0 permanently |
| Tables | `steps`, `step_ingestion_provenance` |
| Cross-provider queries | Forbidden |

### Class D — Billing-Reported Evidence

| Property | Value |
|---|---|
| Provider | GitHub Copilot |
| Source surface | AI Credits usage report CSV (2026-06-01+ billing format) |
| Granularity | Per user / model / day (daily billing aggregate) |
| Field ingested | `aic_quantity` (AI Credits — NOT tokens) |
| Field excluded | `aic_gross_amount` (C-1: cost ingestion forbidden) |
| Session identity | None — CSV has no session UUID |
| `completions_excluded` | 1 permanently (schema CHECK) |
| `is_preview` | 1 default; `--mark-final` sets 0 after GitHub confirms |
| `real_time_observed` | 0 permanently |
| `analysis_safe_for_decision` | 0 permanently |
| Tables | `copilot_billing_events`, `copilot_surface_annotations` |
| Cross-class queries | Forbidden (must not JOIN with `steps`) |

### Advisory Threshold Registry (summary)

| Identifier | Status | Value | AT-2 | Accounting regime |
|---|---|---|---|---|
| `CODEBURN_CLAUDE_5H_ADVISORY_WARN_THRESHOLD` | active | 9,705,984 tokens | Complete | Unconfirmed — see AT-2 record |
| `CODEBURN_CODEX_5H_ADVISORY_WARN_THRESHOLD` | intentionally_inactive | null | NOT MET | No observation — cannot become operational without AT-2 |

Full provenance: `CODEBURN_P7_ADVISORY_THRESHOLD_GOVERNANCE.md` §7.

---

## 5. Blocked Surfaces

These surfaces are structurally excluded from CodeBurn v1.1. They are listed so a
future agent does not attempt to ingest them without a new admission gate.

| Surface | Reason blocked | Required to unblock |
|---|---|---|
| Copilot code completions | Billing design: completions do not consume AI Credits; permanently absent from Class D surface | None possible — structural absence in source data |
| Copilot session identity | Daily billing aggregate has no session UUID; `session_id` is NULL by design | Would require a different Copilot data surface (e.g., IDE telemetry) — new admission gate required |
| Copilot token counts | `aic_quantity` is AI Credits, not tokens; back-calculation is forbidden (CP-1) | Cannot be unblocked without a fundamentally different Copilot evidence surface |
| Real-time API observation (any provider) | No pull API for Pro subscription rate limit state; notification hook is passive | Would require Anthropic to expose a rate-limit query endpoint — external dependency |
| Any new provider | No admission gate exists | Full admission gate (6 questions minimum, per Architecture Freeze §5) |
| Verified rate-limit boundary (Claude) | No official Anthropic documentation confirms the accounting regime | Named Anthropic source doc + confirmed accounting unit + AT-4 upgrade process |

---

## 6. Governing Documents Index

| Document | Governs |
|---|---|
| `CODEBURN_V1_1_ARCHITECTURE_FREEZE.md` | Overall architecture; NST-1..3; FCP-1..5; admission gate requirements; frozen invariants |
| `CODEBURN_P7_ADVISORY_THRESHOLD_GOVERNANCE.md` | AT-1..5 rules; advisory threshold registry; upgrade path |
| `CODEBURN_COPILOT_AI_CREDITS_ADMISSION_GATE.md` | Class D admission; CP-1..3; AG-Copilot-1..6 |
| `CODEBURN_CLASS_D_EPISTEMIC_CLASSIFICATION.md` | Class D definition; distance from Class C |
| `CODEBURN_ACQUISITION_SEMANTIC_FREEZE.md` | FSP-3; TNP; Anti-Collapse Axiom |
| `CODEBURN_TOKEN_PROVENANCE_ONTOLOGY.md` | Epistemic class definitions (Class A–E) |
| `CODEBURN_P6_SCOPE_CONSTRAINTS.md` | A-1, T-1, C-1, R-1, O-1, V-1 scope constraints |
| `CODEBURN_CROSS_PROVIDER_COMPARABILITY_BOUNDARY.md` | NST-1 detail; cross-provider query contracts |
| `CODEBURN_AUTHORITY_CEILING_CONTRACT.md` | IAF-4; authority ceiling per evidence class |
| `phase1/schema.sql` | Schema enforcement of all epistemic constants (CHECK constraints) |

---

## 7. Quick Reference — Evidence Class Ceilings

What the highest-authority claim each class may make:

| Class | Maximum permitted claim |
|---|---|
| Class C | "Observer reconstructed N tokens from session JSONL. Source: provider client log. Not verified." |
| Class D | "GitHub billing system reported N AI Credits for user/model/day. Not a token count. Not session-level. Not final until `is_preview = 0`." |
| Advisory threshold | "Observed saturation heuristic at N tokens. Single observation. Accounting regime unconfirmed. Not a verified Anthropic boundary." |

No class currently in CodeBurn may assert:
- Real-time measurement
- Provider truthfulness
- Decision-safe analysis
- Cross-provider comparability
- Cost or billing accuracy
