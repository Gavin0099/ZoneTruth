# Training Product Doctrine (P3b-P3i)

Last updated: 2026-05-21
Owner: ZoneTruth Product + Core
Status: Active

## 1) Product Position

ZoneTruth is not an authoritative AI coach.
ZoneTruth is an evidence-bound training observatory and decision-support system.

Core principle:

- Action-guiding, not action-authoritative
- State-transition, not binary verdict
- Evidence-typed, not confidence-only
- No-overclaim by default

## 2) Decision Model

Decision-first does not mean “the system knows the best answer.”
Given current data surfaces (HR, duration, frequency, distribution, partial HRV), ZoneTruth only guides plausible directions.

Allowed output style:

- “恢復訊號偏弱，建議降低高強度比例”
- “本週累積負荷偏高，建議優先有氧基礎課”

Forbidden output style:

- “今天必須休息”
- “你不適合高強度”

## 3) Temporal Hierarchy

Define time scope and responsibility:

- Single session: retrospective inspection only (what happened)
- 7 days: load structure and short fatigue pressure
- 28 days: adaptation trend proxy
- Long term (>= 8 weeks): fitness direction and consistency

Rules:

- No 28-day adaptation claims from single-session metrics.
- Single-session cards must not dominate primary decision surface.

## 4) Semantic Authority Layer

Every user-facing statement must map to one layer:

- `observational`: direct measurements (HR samples, duration, frequency)
- `derived`: deterministic transforms (zone distribution, drift, monotony proxy)
- `interpretive`: bounded interpretation (recovery pressure, load balance)
- `speculative`: unsupported by current data stack

Hard rule:

- No automatic cross-layer escalation (`observational` -> `speculative`) in UI summaries.

## 5) Evidence Type Contract

Each decision card must expose evidence type, not only a scalar confidence.

Required labeling:

- `Direct observation`
- `Derived metrics`
- `Bounded inference`
- `Weak inference`
- `Unsupported / not measured`

Minimum rendering behavior:

- If major conclusion relies on weak/unsupported inference, show evidence gap inline.
- If unsupported, do not render as recommendation.

Interpretation notes:

- `Bounded inference`: supported by stable deterministic transforms and explicit limits.
- `Weak inference`: plausible but higher ambiguity, sensitive to missing context.
- `Unsupported`: beyond current evidence surface; must not be rendered as coach-like action.

## 6) Claim Authority Matrix

| Data Surface | Allowed Claims | Disallowed Claims |
|---|---|---|
| HR only | zone distribution, session intensity pattern | hypertrophy effect, CNS fatigue |
| HR + duration/frequency | aerobic load tendency, load clustering | overtraining diagnosis |
| HR + HRV (sparse) | recovery trend signal (bounded) | definitive readiness verdict |
| Power meter (future) | pacing efficiency, external load structure | injury risk diagnosis |
| RPE + HR (future) | internal load estimate, perceived strain trend | neuromuscular adaptation diagnosis |
| User-declared goal + weekly summary | weekly pattern alignment tendency (aligned/partial/divergent) | goal achievement prediction, causal attribution, progress claim |

## 7) Decision Surface Priority

Home (primary) can include only:

- readiness signal (bounded)
- weekly load balance
- recovery trend
- suggested intensity range (probabilistic wording)

Home (primary) must exclude:

- detailed VO2 classification narrative
- zone-by-zone deep breakdown
- drift technical details

Those belong to secondary drill-down pages.

Additionally required on Home:

- adaptation direction signal (`endurance build` / `maintenance` / `mixed adaptation` / `recovery-biased`)

## 8) Uncertainty Rendering Rules

When uncertainty is elevated (low coverage, sparse HR/HRV, mixed evidence):

- reduce claim strength (prefer “偏向/可能/與…一致”)
- disable imperative recommendation verbs (“必須/應該立刻/不能”)
- display evidence gap reason
- lower color saturation / visual urgency
- reduce CTA prominence
- disable recommendation-card elevation
- render missing-evidence chips

When uncertainty is low:

- still avoid diagnostic language
- keep recommendation phrasing as guidance, not command

Important:

- Uncertainty wording alone is insufficient. Interaction-level and visual-level uncertainty rendering is mandatory.

## 9) Coaching Language Contract

Forbidden lexicon (default):

- `最佳`
- `必須`
- `過度訓練` / `overtraining`
- `神經疲勞`
- `肌肥大效果`
- any diagnosis-style certainty claims

Preferred lexicon:

- `偏向`
- `可能`
- `observed pattern`
- `consistent with`
- `建議`

## 10) P3 Execution Scope

### P3b (HRV uncertainty signal)

- Add HRV coverage and sparsity indicators to observation pipeline.
- Add evidence-type tags to weekly decision cards.
- Do not change policy score weighting yet.

### P3c (Weekly policy confidence adjustment)

- Calibrate confidence semantics using HR + HRV completeness gates.
- Apply wording downgrades automatically under low evidence.
- Keep recommendation generation bounded by Claim Authority Matrix.

### P3d (Authority Rendering System)

- Build visual governance for authority levels (observation vs interpretation vs uncertainty).
- Tie card styling, CTA prominence, and color intensity to evidence authority.
- Prevent psychologically authoritative rendering under low-confidence evidence.

### P3e (Training State Machine)

- Formalize state model:
  - `recovered`
  - `accumulating_load`
  - `functional_fatigue`
  - `possible_under_recovery`
  - `recovery_normalizing`
- Disallow direct binary collapse (`fatigue -> bad`) in user-facing summaries.

### P3f (Data Freshness Authority)

- Add freshness classes for major data channels:
  - `fresh`
  - `partial`
  - `stale`
  - `missing`
- `stale` and `missing` evidence must downgrade decision authority and recommendation strength.

### P3g (Inference Stratification)

- Enforce three inference classes:
  - `bounded_inference`
  - `weak_inference`
  - `unsupported_speculation`
- Require explicit mapping from metric family to inference class.

### P3h (Adaptation Direction Surface)

- Add adaptation-direction output to primary weekly decision surface.
- Ensure direction output is trend-based (7d/28d), not single-session derived.

### P3i (Non-Authority Reminder)

- Add persistent boundedness reminder on high-interpretation cards:
  - "Based on available HR-derived observations. Not a physiological diagnosis."
- Reminder visibility must increase when evidence is partial/stale.

## 11) Guardrails and Enforcement

Required guards before P3c closeout:

- UI forbidden semantics checks
- evidence-layer mapping tests for decision cards
- uncertainty rendering behavior tests (low-confidence wording downgrade)
- snapshot drift gate + semantic annotation (`SEM-*.json`)
- freshness-authority downgrade tests (`stale`/`missing` cannot produce high-authority guidance)
- state-machine transition validity tests (no invalid jumps)
- authority-rendering tests (low evidence cannot render high-emphasis coaching surface)

## 12) Non-Goals

- Not building diagnosis engine.
- Not inferring neuromuscular state from HR-only streams.
- Not replacing human coaching authority.
