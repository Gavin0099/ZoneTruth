# Training Analysis Meta-Spec

Last updated: 2026-06-04
Owner: ZoneTruth Product + Core
Status: Draft implementation spec
Source review: `docs/TRAINING_ANALYSIS_LITERATURE_REVIEW.md`

## Purpose

This meta-spec converts the training-analysis literature review into a bounded
implementation contract for VO2 max, Zone 2, and strength analysis.

It defines:

- shared metadata shape for training metrics
- evidence-distance and confidence semantics
- metric-specific claim ceilings
- UI wording rules
- implementation sequence for future analyzer work

It does not authorize:

- clinical diagnosis
- training prescription
- lab-equivalent claims from wearable or field estimates
- copying proprietary product algorithms
- Garmin / Apple / Firstbeat / Polar / WHOOP as truth labels

## Core Principle

ZoneTruth should answer:

> What kind of estimate is this, how far is it from the reference standard, and
> what can we safely say from the available data?

ZoneTruth should not answer:

> Which product is correct, what is the user's true physiological state, or what
> the user must do next.

## Evidence Tier Model

Every VO2 max, Zone 2, and strength output must be assigned one `method_tier`.

| method_tier | Definition | Examples | Claim Ceiling |
|---|---|---|---|
| `gold_standard_anchor` | Direct clinical/lab/standardized test matching the metric's reference standard | CPET/GXT gas analysis, lactate threshold test, direct standardized 1RM | May use `measured` if source is actually present |
| `field_estimator` | Practical estimate from repeatable field data | HR-speed model, HR drift, talk test, e1RM | Must use `estimated` or `consistent with` |
| `product_reference` | Consumer or vendor-produced estimate | Apple VO2 max, Garmin/Firstbeat VO2 max, device HR zones | Product estimate only; never truth source |
| `weak_heuristic` | Low-specificity estimate from broad population rule or sparse input | fixed %HRmax, age formula, vague gym log | Starting point only; must show low confidence |

## Reference Standard Distance

Every output must also include `reference_standard_distance`.

| value | Meaning | Example |
|---|---|---|
| `direct` | The metric was measured by the reference method | CPET VO2 max, lactate LT1, direct standardized 1RM |
| `one_level_below` | A structured field method estimates the reference metric | HR drift for Zone 2, 3-5RM e1RM |
| `two_or_more_levels_below` | Product estimate, sparse field estimate, or heuristic | Apple/Garmin VO2 max, fixed %HRmax |
| `unknown` | Source lacks enough method detail | imported value with no provenance |

Rule:

- `direct` can support `measured`.
- Every other value must render as `estimated`, `field estimate`, `product estimate`,
  or `heuristic`.

## Shared Output Schema

Future analyzer outputs should converge on this shared metadata shape.

```yaml
metric: vo2max | zone2_hr_range | strength
value_kind: scalar | range | classification
value: number | string | object
unit: ml_per_kg_min | bpm | kg | x_bodyweight | none
method:
  tier: gold_standard_anchor | field_estimator | product_reference | weak_heuristic
  name: string
  source: cpet | lactate_test | apple | garmin | firstbeat | hr_drift | e1rm | user_input | unknown
  reference_standard_distance: direct | one_level_below | two_or_more_levels_below | unknown
confidence:
  level: high | medium | medium_low | low | unknown
  basis:
    - string
  limiting_factors:
    - string
claim:
  ceiling: measured_if_direct | estimate_only | starting_point_only | unsupported
  allowed_terms:
    - string
  forbidden_terms:
    - string
data_quality:
  coverage: complete | partial | sparse | unknown
  flags:
    - string
recommended_validation: string | null
```

## Confidence Semantics

Confidence is not a generic model score. It is a combination of:

- evidence distance from the reference standard
- input coverage and quality
- method specificity
- repeatability under similar conditions
- known context gaps

### Confidence Ladder

| level | Meaning | Rendering |
|---|---|---|
| `high` | Direct measurement or tightly standardized test | Can be prominent, still non-diagnostic |
| `medium` | Structured field estimate with adequate data quality | Useful for trend / bounded interpretation |
| `medium_low` | Plausible estimate with meaningful assumptions | Show caveat inline |
| `low` | Heuristic, sparse data, or weak standardization | Render as starting point only |
| `unknown` | Missing method provenance | Do not interpret beyond raw display |

## Metric Specs

### VO2 Max

Reference standard:

- CPET or graded maximal exercise test with gas exchange / indirect calorimetry.

Allowed method tiers:

| Method | tier | reference_standard_distance | default confidence |
|---|---|---|---|
| CPET / GXT gas analysis | `gold_standard_anchor` | `direct` | high |
| Structured outdoor running HR-speed field estimate | `field_estimator` | `one_level_below` | medium |
| Cycling power-HR field estimate | `field_estimator` | `one_level_below` | medium |
| Apple / Garmin / Firstbeat imported VO2 max | `product_reference` | `two_or_more_levels_below` | medium_low |
| Resting-only or opaque imported value | `weak_heuristic` | `unknown` | low |

Required metadata:

```yaml
metric: vo2max
method.name: wearable_estimated_from_running_hr_speed
method.source: garmin | apple | firstbeat | running_hr_speed | cycling_power_hr | cpet | unknown
recommended_validation: CPET if used for clinical or high-performance decisions
```

Allowed claims:

- `VO2 max estimate`
- `trend estimate`
- `not lab-equivalent`
- `consistent with aerobic fitness trend`

Forbidden claims:

- `true VO2 max`
- `lab-equivalent`
- `clinical fitness diagnosis`
- product-to-product accuracy ranking from local ZoneTruth data

### Zone 2 / Threshold Range

Reference standard:

- LT1 from lactate testing, or VT1/GET from CPET-style ventilatory analysis.

Allowed method tiers:

| Method | tier | reference_standard_distance | default confidence |
|---|---|---|---|
| Lactate threshold LT1 | `gold_standard_anchor` | `direct` | high |
| VT1 / GET from CPET | `gold_standard_anchor` | `direct` | high |
| HR drift / decoupling under controlled steady state | `field_estimator` | `one_level_below` | medium |
| HRV-derived threshold | `field_estimator` | `one_level_below` | medium_low |
| Talk test / RPE | `field_estimator` | `two_or_more_levels_below` | medium_low |
| Fixed %HRmax or age formula | `weak_heuristic` | `two_or_more_levels_below` | low |
| Garmin / Apple / Strava / Polar HR zones | `product_reference` | `two_or_more_levels_below` | medium_low |

Required metadata:

```yaml
metric: zone2_hr_range
popular_label: Zone 2
physiological_domain: below_or_near_first_threshold
threshold_basis: LT1 | VT1 | GET | AeT | HR_drift | HRV_threshold | talk_test | percent_hrmax | product_zone | unknown
```

Allowed claims:

- `estimated Zone 2 range`
- `below or near first-threshold target`
- `usable starting point`
- `should be validated if precision matters`

Forbidden claims:

- `exact Zone 2`
- `optimal Zone 2`
- all zone-number systems are equivalent
- product HR zone equals LT1/VT1 without validation

Special rule:

- If `threshold_basis = percent_hrmax`, confidence must not exceed `low`.
- If `threshold_basis = product_zone`, render source and keep estimate wording.

### Strength / 1RM

Reference standard:

- Direct standardized 1RM for exercise-specific maximal strength.

Allowed method tiers:

| Method | tier | reference_standard_distance | default confidence |
|---|---|---|---|
| Direct standardized 1RM | `gold_standard_anchor` | `direct` | high |
| Standardized 3RM-5RM converted to e1RM | `field_estimator` | `one_level_below` | medium |
| 6RM-10RM converted to e1RM | `field_estimator` | `one_level_below` | medium_low |
| Velocity-based estimate | `field_estimator` | `one_level_below` | medium_low |
| High-rep / unclear failure e1RM | `weak_heuristic` | `two_or_more_levels_below` | low |
| Vague gym log | `weak_heuristic` | `unknown` | low |
| Grip strength | `field_estimator` | `one_level_below` | health_proxy_only |

Required metadata:

```yaml
metric: strength
metric_type: direct_1RM | estimated_1RM | rep_max | velocity_based_estimate | grip_strength | relative_strength
exercise:
  name: string
  equipment: string | unknown
  range_of_motion: standardized | partial | unknown
  bodyweight_known: true | false
  failure_definition: technical_failure | volitional_failure | unknown
```

Allowed claims:

- `direct 1RM measured under standardized protocol`
- `estimated 1RM`
- `relative strength`
- `valid for trend if protocol remains consistent`
- `grip strength as health proxy`

Forbidden claims:

- hypertrophy or muscle gain from HR-only strength sessions
- vague logs as direct maximal strength
- grip strength as whole-body maximal strength
- cross-exercise e1RM comparisons without context

## UI Wording Rules

Use this wording map when rendering results:

| Condition | Preferred Wording | Avoid |
|---|---|---|
| `reference_standard_distance = direct` | `measured under standardized protocol` | `diagnostic`, `guaranteed` |
| `method.tier = field_estimator` | `estimated from field data` | `true`, `exact` |
| `method.tier = product_reference` | `product estimate from <source>` | `verified`, `lab-equivalent` |
| `method.tier = weak_heuristic` | `starting point` | `training zone confirmed` |
| `confidence.level = low` | `interpret cautiously` | strong CTA / imperative advice |

Global forbidden terms for these metric summaries:

- `true VO2 max`
- `exact Zone 2`
- `optimal Zone 2`
- `lab-equivalent`
- `diagnosis`
- `guaranteed`
- `must`
- `best provider`

## Minimal Implementation Sequence

### Slice 1: Core Metadata Types

Goal:

- Add shared types for `TrainingMetricMethod`, `ReferenceStandardDistance`,
  `TrainingMetricConfidence`, and `TrainingMetricClaimCeiling`.

No analyzer behavior change.

Targeted tests:

- Construct each enum / model.
- Verify product-reference metrics cannot claim `measured`.
- Verify percent-HRmax Zone 2 cannot exceed low confidence.

### Slice 2: Analyzer Adapter Metadata

Goal:

- Attach metadata to existing Zone 2 / VO2 / Strength outputs without changing
  verdict thresholds.

Targeted tests:

- Existing verdict tests still pass.
- Existing outputs include method tier and claim ceiling.

### Slice 3: UI Disclosure

Goal:

- Show estimate vs measured status and confidence reason in user-visible summaries.

Targeted tests:

- Wearable/product VO2 max renders as estimate.
- Percent-HRmax Zone 2 renders as starting point.
- Strength e1RM renders formula / protocol caveat.

### Slice 4: Guard Tests

Goal:

- Enforce forbidden wording and metadata presence for ambiguous estimates.

Targeted tests:

- No `true VO2 max`, `exact Zone 2`, `lab-equivalent`, or `optimal Zone 2`
  in user-visible analysis summaries.
- Every VO2 max / Zone 2 / Strength metric has method tier and claim ceiling.

## Current Decision

The next code-bearing task should be Slice 1 only.

Do not change Zone 2 thresholds, VO2 verdict rules, or Strength verdict rules until
metadata exists and current behavior is locked by tests.
