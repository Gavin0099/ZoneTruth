# CodeBurn — Token Provenance Ontology

> Written: 2026-05-20
> Status: **BINDING** — P0 constitutional freeze document, effective immediately
> Scope: all CodeBurn versions, all acquisition modes, all provider integrations
> Prerequisite for: any acquisition implementation, any comparability claim, any provenance assertion

---

## Why This Document Must Exist Before Acquisition

Token data is not epistemically uniform.

A token count from a provider API response and a token count reconstructed from a session
log are not the same kind of evidence. They differ not in accuracy, but in **epistemic class** —
in what can be legitimately claimed about them, and what authority those claims carry.

Without an explicit ontology, this distinction collapses under implementation pressure.
The default outcome is:

```
"It's all just token counts"
```

This document prevents that collapse by defining the epistemic types before any
acquisition implementation exists. Once defined, these types are permanent. They
constrain what acquisition implementations may claim, not how they are built.

**Anti-inversion rule: this ontology governs acquisition design, not the reverse.**

If an acquisition implementation produces evidence that does not fit an existing epistemic
class, the correct response is to define a new class — not to reclassify existing evidence
to fit the implementation.

---

## The Acquisition Non-Equivalence Principle

**Different acquisition paths produce epistemically non-equivalent token evidence.**

This holds regardless of:
- How accurate the token count is
- How consistent it is across repeated runs
- How trusted the acquisition infrastructure is
- How long the system has been operational

Equivalence requires shared epistemic grounding — same referent, same observation distance,
same reconstruction assumptions. Acquisition modes differ on all three.

**Corollary: token counts from different acquisition modes cannot be compared
without explicit comparability scope declaration.**

This corollary is absolute. It does not relax when acquisition chains become complete.
It does not relax when provider integration matures. Comparability is not a function of
data quality — it is a function of epistemic class alignment.

---

## Epistemic Class Definitions

### Class A: Provider-Originated

**Definition:** Token count reported directly by the provider in the API response to the
request that generated the tokens. No intermediate observation, reconstruction, or
estimation layer.

**Acquisition modes that produce Class A:**
- Direct API response field (e.g., `usage.input_tokens` in Claude API response)
- Provider webhook with per-request token breakdown
- Provider SDK callback with usage object

**Legitimate claims:**
- "The provider reported N tokens for this request"
- "This token count has provider-grade provenance"
- "The token source is `provider`"

**Prohibited claims:**
- "This session consumed N tokens" (session-level aggregation crosses a boundary)
- "This count reflects actual computation cost" (billing ≠ observability)
- "This count can be compared to Class B or Class C evidence" (non-equivalent)

**Authority ceiling:** Provider report of one request. Nothing above request level.

---

### Class B: Observer-Derived

**Definition:** Token count inferred from artifacts of the AI interaction that are
observable to a wrapper or interceptor — but not reported by the provider. Includes:
parsing stdout/stderr for token information, reading process environment, intercepting
IPC between client and provider.

**Acquisition modes that produce Class B:**
- Runtime command wrapper that parses output
- Claude Code extension hooks (if reading output artifacts, not API response)
- Any layer that observes the interaction without being in the API response path

**Legitimate claims:**
- "N tokens were observed in the command output for this step"
- "This estimate is observer-derived, not provider-reported"
- "The token source is `estimated`"

**Prohibited claims:**
- "This is equivalent to provider-reported token count" (different epistemic class)
- "This observation is as trustworthy as Class A" (observation distance differs)
- "Consistent observer-derived counts validate provider counts" (circular)

**Authority ceiling:** Observer claim about one observable artifact. Cannot be
aggregated with Class A evidence without explicit class declaration.

---

### Class C: Observer-Reconstructed

**Definition:** Token count derived from post-hoc analysis of session logs, recorded
outputs, or stored artifacts. Not observed in real-time. Reconstruction introduces
temporal distance and mutability assumptions.

**Acquisition modes that produce Class C:**
- Session log ingestion after session ends
- Replay of stored session artifacts
- Log file parsing (e.g., Claude Code `.jsonl` session logs)

**Legitimate claims:**
- "Log analysis estimated N tokens for this session segment"
- "This reconstruction is post-hoc; real-time state may have differed"
- "The token source is `estimated` with reconstruction gap"

**Prohibited claims:**
- "This reconstruction is equivalent to real-time observation" (temporal distance)
- "Log completeness implies token completeness" (logs may be partial)
- "Replay accuracy validates original session token usage" (reconstruction ≠ original)

**Authority ceiling:** Reconstruction claim about a logged artifact. Reconstruction
gap must be declared. Cannot be treated as real-time evidence.

---

### Class D: User-Asserted

**Definition:** Token count provided by a human user, either manually entered into
a tool (e.g., `codeburn_run.py --total-tokens N`) or reported verbally. No
automated observation mechanism.

**Acquisition modes that produce Class D:**
- Manual `--prompt-tokens`, `--completion-tokens`, `--total-tokens` CLI flags
- Human-written session notes with token estimates
- Copy-pasted token counts from provider interfaces

**Legitimate claims:**
- "User reported N tokens for this step"
- "This token count is user-asserted, not automatically captured"
- "The token source is `estimated` (user-provided)"

**Prohibited claims:**
- "This count is validated" (no validation mechanism exists for Class D)
- "Consistent user assertion implies accurate observation" (assertion ≠ observation)
- "User assertion has the same provenance as Class A or B" (fundamentally different)

**Authority ceiling:** User assertion about one step. Self-reported provenance.
Cannot substitute for automated acquisition.

**Note on current CodeBurn state:** As of 2026-05-20, all token data in CodeBurn
is Class D. The `--total-tokens` flags in `codeburn_run.py` are user-assertion
inputs. This is not a temporary limitation — it is the current epistemic state.

---

### Class E: Acquisition-Impossible

**Definition:** Token count for an interaction where no acquisition mechanism can
produce verifiable evidence, due to provider-imposed epistemic opacity. The referent
is unknown or unverifiable by design.

**Acquisition modes that produce Class E:**
- ChatGPT web UI (no API path, no structured response)
- Any provider interface where token accounting is opaque or bundled
- Provider configurations where token reporting is disabled

**Legitimate claims:**
- "Token observability is not achievable for this interaction type"
- "This provider interaction cannot be represented in the CodeBurn token ontology"
- "Acquisition mode: impossible"

**Prohibited claims:**
- "We can estimate tokens for this interaction" (estimation requires a referent)
- "Screen-scraped numbers represent token usage" (unverifiable referent)
- "This provider is observability-difficult" (difficulty is not the issue; the category is wrong)

**Authority ceiling:** None. Class E interactions cannot be given token observability
status in CodeBurn. They are recorded as `acquisition_impossible`, not as
`token_source: unknown`.

**Critical distinction:** `token_source: unknown` means "automated acquisition
attempted but provenance not established." `acquisition_impossible` means "the
category of verifiable acquisition does not apply to this interaction type."
These are different conditions that must not be conflated.

---

## Epistemic Class Summary Table

| Class | Label | Acquisition mode | Token source field | Claim ceiling |
|-------|-------|------------------|--------------------|---------------|
| A | Provider-Originated | Direct API response | `provider` | One request |
| B | Observer-Derived | Runtime wrapper/hook | `estimated` | One observable artifact |
| C | Observer-Reconstructed | Log ingestion / replay | `estimated` (+ reconstruction gap) | One logged artifact |
| D | User-Asserted | Manual CLI flags | `estimated` | User assertion |
| E | Acquisition-Impossible | ChatGPT UI, opaque providers | (not applicable) | None |

---

## Implementation Proximity ≠ Epistemic Legitimacy

A common drift pattern: assume that acquisition modes closer to provider runtime
produce more legitimate evidence.

This is false.

**Closeness to runtime does not confer epistemic legitimacy.** It changes the
observation distance but not the epistemic class.

Example:

A Class B observer-derived count captured in real-time from a wrapper is
**not epistemically superior** to a Class C log reconstruction — it is
**epistemically different**. The wrapper has lower observation distance but
the same fundamental limitation: it observes artifacts, not provider computation.

A Class A provider-reported count is **not more legitimate than Class B in the
sense that justifies evaluative use** — both are subject to the Acquisition
Non-Equivalence Principle and the Authority Ceiling Contract.

The relevant question is not:

> "How close is this acquisition mode to provider reality?"

The relevant question is:

> "What can be legitimately claimed from this epistemic class?"

**Implementation topology (how the data is captured) does not determine
epistemic topology (what the data permits).**

This distinction must be preserved when evaluating acquisition implementation
proposals. An L2 direct API hook produces Class A evidence — which carries
the most significant authority drift risk precisely because it appears most
authoritative.

---

## Relationship to Existing Schema

The current schema (`schema.sql`) records `token_source` as:

```sql
token_source TEXT CHECK (token_source IN ('provider', 'estimated', 'unknown'))
```

This maps to the ontology as follows:

| Schema value | Epistemic class(es) |
|---|---|
| `provider` | Class A only |
| `estimated` | Class B, C, or D (undifferentiated in current schema) |
| `unknown` | Acquisition attempted, class not determined |
| (absent) | Class E — use `acquisition_mode: impossible` in metadata |

**Schema limitation:** The current schema cannot differentiate Class B, C, and D.
This limitation is acceptable for Phase 1 but must be addressed before any
cross-acquisition-mode analysis is attempted.

**No schema change is authorized by this document.** Schema changes require
a separate spec with evidence plan.

---

## What This Ontology Does NOT Authorize

Defining epistemic classes does not authorize:

- Cross-class comparison (Class A count vs Class D count from same session)
- Aggregation across acquisition modes without explicit scope declaration
- Upgrading evidence class based on consistency (consistent Class D ≠ Class A)
- Using any class for evaluative conclusions (all classes are observational only)
- Inferring provider computation quality from any class of token evidence

The ontology defines what each class IS. It does not authorize what the evidence
from each class MAY CONCLUDE. That requires the Authority Ceiling Contract.

---

## Amendment Process

This ontology may be extended with new epistemic classes if a new acquisition
mode is identified that does not fit existing classes.

Amendments require:
1. The new class must be defined with the same structure (definition, legitimate claims,
   prohibited claims, authority ceiling)
2. The amendment must be committed before any acquisition implementation that depends on
   the new class
3. The `schema.sql` mapping table must be updated if the new class requires a new
   `token_source` value

Existing class definitions may not be modified to expand claim legitimacy or raise
authority ceilings. Modifications in that direction require the Authority Ceiling
Contract process.

---

*Token evidence is typed. Types are permanent.*
*Acquisition completeness does not change types.*
*Implementation proximity does not override epistemic class.*
