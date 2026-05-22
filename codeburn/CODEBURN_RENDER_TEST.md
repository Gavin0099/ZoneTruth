# CodeBurn Render Test

> Type: **render test** — verifies md→html renderer feature coverage
> Written: 2026-05-22
> Purpose: Confirm render_docs.py correctly handles all styled element types.

---

## 1. Epistemic Class Badges

This sentence references Class C evidence.

This sentence references Class D evidence.

---

## 2. Warning Boxes

FORBIDDEN: this paragraph contains a prohibited pattern.

FCP-1 applies here. This is a normalization slide warning paragraph.

BLOCKED surface detected — this operation is not permitted.

---

## 3. Frozen Boxes

FROZEN INVARIANT: this rule does not change across versions.

LOCKED RULE: the Anti-Collapse Axiom applies at all abstraction layers.

PERMANENTLY blocked by architecture decision.

---

## 4. Advisory Boxes

ADVISORY threshold in use — not a verified provider boundary.

HEURISTIC value: 9,705,984 tokens. Single observation. UNVERIFIED.

NOT VERIFIED — accounting regime unconfirmed.

OBSERVABILITY ONLY: this surface does not provide decision-safe evidence.

---

## 5. Blockquotes

> This is a standard blockquote. It should render in a blockquote box.

> FORBIDDEN inside a blockquote — should render as a warn-styled blockquote paragraph.

> Boundedness is part of the architecture.

---

## 6. Tables

| Evidence Class | Provider | Token fields | Decision-safe |
|---|---|---|---|
| Class C | Claude, Codex | input_tokens, output_tokens | No |
| Class D | Copilot | aic_quantity (AI Credits, not tokens) | No |

| Forbidden phrase | Blocking rule |
|---|---|
| `"total AI consumption"` | FCP-1 |
| `"cost per session"` | FCP-2, IAF-4 |
| `"X% of Anthropic limit"` | Architecture Freeze §10 |

---

## 7. Code Blocks

```yaml
identifier: CODEBURN_CLAUDE_5H_ADVISORY_WARN_THRESHOLD
status: active
value: 9705984
value_unit: tokens
at_rule_compliance:
  AT-1: PASS
  AT-2: PASS
  AT-4: no upgrade claimed
```

```sql
SELECT provider, SUM(input_tokens) AS total
FROM steps
WHERE provider = 'claude'
GROUP BY provider;
-- Cross-provider SUM is FORBIDDEN by NST-1
```

---

## 8. Inline Formatting

This paragraph has **bold**, *italic*, `inline code`, and a [link](#1-epistemic-class-badges).

The value `analysis_safe_for_decision = 0` is enforced by a schema CHECK constraint.

Forbidden vocabulary: `quota`, `actual token usage`, `billing-grade`, `cross-provider`.

---

## 9. Nested Lists

- Tier 1 — scaffolded surfaces
  - hook code exists
  - not yet connected to live data
- Tier 2 — blocked by external dependency
  - requires provider-side changes
  - cannot be unblocked unilaterally

1. Read the governing document
2. Check the evidence class
3. Confirm `real_time_observed = 0`

---

## 10. Mixed Paragraph Sequence

This is a normal paragraph before a warn paragraph.

FORBIDDEN operation: aggregating Class C and Class D without normalization disclosure.

This is a normal paragraph after the warn paragraph. It should not inherit warn styling.

FROZEN INVARIANT: the evidence class cannot be upgraded through consistency.

This is another normal paragraph after a frozen paragraph.

---

## 11. Navigation Anchor Test

The nav sidebar should contain links to all sections 1–11 above.
Each `##` heading should produce a nav entry.
`###` headings should also appear in nav (up to h3).

### 11a. Sub-section anchor

This sub-section heading should appear in nav.

### 11b. Another sub-section

This one too.
