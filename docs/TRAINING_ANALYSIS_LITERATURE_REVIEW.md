# Training Analysis Literature Review

Last updated: 2026-06-04
Owner: ZoneTruth Product + Core
Status: Draft input for meta-spec

## Purpose

This document translates public literature, clinical testing standards, and product
documentation into ZoneTruth design constraints for VO2 max, Zone 2, and strength
analysis.

It is not an algorithm spec. It is the evidence map that the later
`TRAINING_ANALYSIS_META_SPEC.md` should use.

Core rule:

- Public clinical / academic standards are calibration anchors.
- Product algorithms are reference implementations or sanity checks.
- ZoneTruth must not copy proprietary product algorithms or promote estimates into
  lab-equivalent measurements.

## Evidence Tiers

| Tier | Meaning | Examples | ZoneTruth Authority |
|---|---|---|---|
| Gold standard anchor | Clinical or lab protocol used as reference standard | CPET/GXT with gas exchange, lactate threshold test, direct standardized 1RM | Highest claim authority, if actually measured |
| Field estimator | Practical estimate derived from repeatable field data | HR-speed model, Cooper/submax tests, HR drift, e1RM, talk test | Useful for trend and bounded interpretation |
| Product reference | Consumer or vendor implementation | Apple, Garmin, Firstbeat, Polar, WHOOP | Comparison only; never truth source |

Global claim ceiling:

- Use `measured` only when the underlying method is direct lab/standardized test.
- Use `estimated` for wearable, field, or formula outputs.
- Use `consistent with` for pattern interpretation.
- Avoid `diagnosis`, `guarantees`, `true VO2 max`, `optimal Zone 2`, and product-derived
  certainty claims.

## VO2 Max

### Key Sources

| Source | Type | Reference Standard | ZoneTruth Use |
|---|---|---|---|
| Molina-Garcia et al. 2022 INTERLIVE systematic review | Systematic review / validation framework | Maximal exercise test with indirect calorimetry | Anchor wearable validation expectations and error humility |
| ARTP Statement on Cardiopulmonary Exercise Testing 2021 | Clinical/professional statement | CPET with gas exchange and protocol controls | Anchor CPET as lab standard |
| Firstbeat VO2max white paper | Product algorithm documentation | HR-speed relationship filtered from training data | Reference implementation only |
| Apple Cardio Fitness / HealthKit VO2 max docs | Product documentation | Apple Watch estimate from supported outdoor activities | Product estimate disclosure pattern |
| Garmin VO2 max support / validation studies | Product documentation / validation study | Device estimate vs lab criterion in validation contexts | Product sanity check, not source of truth |

### Literature Notes

The INTERLIVE review is the strongest first-pass source for ZoneTruth because it
explicitly asks how wearables were validated against lab VO2 max. Its practical
lesson is not "wearable VO2 max is wrong"; it is "wearable VO2 max should be labeled
as estimate, with method and error context." Exercise-based algorithms generally
perform better than resting-only algorithms, but individual error remains relevant.

CPET/GXT with gas exchange remains the reference anchor when ZoneTruth needs to
explain the difference between lab-measured VO2 max and watch-estimated VO2 max.
ZoneTruth should therefore separate:

- `lab_measured_vo2max`
- `field_test_estimated_vo2max`
- `wearable_estimated_vo2max`

Firstbeat and Garmin documentation are useful because they describe the common
product pattern: infer aerobic fitness from relationships among heart rate, speed,
GPS/running/cycling context, and data-quality filtering. They should influence
feature vocabulary, not become ZoneTruth's authoritative method.

Apple documentation is useful as product-disclosure precedent: Apple presents
cardio fitness as an Apple Watch estimate produced in supported contexts, not as
clinical CPET.

### Allowed Claims

- "VO2 max estimate from wearable / field data."
- "Useful for trend monitoring when source and method remain consistent."
- "Not equivalent to lab CPET unless directly measured."
- "Confidence is higher when outdoor activity, stable GPS/speed, reliable HR, and
  sufficient exertion are present."

### Forbidden Claims

- "True VO2 max" from Apple/Garmin/Firstbeat/watch data.
- "Lab-equivalent VO2 max" without CPET/GXT gas analysis.
- Provider ranking, e.g. "Garmin is more accurate than Apple" from ZoneTruth local data.
- Clinical or performance decisions based only on wearable estimate.

### Implementation Notes

Suggested metadata:

```yaml
metric: vo2max
method_type: lab_measured | field_test_estimated | wearable_estimated
input_source: cpet | apple | garmin | firstbeat | running_hr_speed | cycling_power_hr
reference_standard_distance: direct | one_level_below | product_estimate
confidence_basis:
  - hr_quality
  - gps_or_speed_quality
  - activity_supported
  - effort_sufficient
  - recent_validation
claim_ceiling: estimate_unless_lab_measured
```

## Zone 2 / Thresholds

### Key Sources

| Source | Type | Reference Standard | ZoneTruth Use |
|---|---|---|---|
| Sitko et al. 2025, "What Is Zone 2 Training?" | Expert viewpoint / consensus-style framing | LT1 / VT1 / threshold-based physiology | Anchor "popular Zone 2" near or below first threshold |
| Kaufmann et al. 2023 HRV-derived thresholds review | Systematic review | LT/VT/GET/RCP threshold comparisons | Frame HRV threshold as estimate, not lab truth |
| Kanniainen et al. 2023 / Frontiers HRV-threshold work | Validation / threshold estimation study | Individual thresholds vs HRmax heuristics | Justify low confidence for fixed %HRmax zones |
| Seiler & Kjerland / training-intensity distribution literature | Exercise science background | Three-zone threshold models | Prevent confusion between zone-number systems |

### Literature Notes

The main risk is semantic: "Zone 2" means different things across consumer five-zone
models and exercise-science three-zone models. In many threshold-based three-zone
models, the first zone is below LT1/VT1, while consumer "Zone 2" often points to
low aerobic intensity. ZoneTruth should therefore store the physiological basis,
not just the consumer label.

For the product, the most important distinction is:

- Popular label: `Zone 2`
- Physiological target: `below_or_near_first_threshold`
- Basis: `LT1`, `VT1`, `AeT`, `HR_drift`, `HRV_threshold`, `talk_test`, `%HRmax`

Fixed HRmax percentages are convenient but weak for personal threshold detection.
The literature repeatedly warns that HRmax formulas and the percent of HRmax at
which individual thresholds occur vary meaningfully between people. ZoneTruth can
use HRmax percentage as a fallback heuristic, but it must be low-confidence and
clearly marked.

### Allowed Claims

- "Estimated Zone 2 range based on selected threshold basis."
- "Range is consistent with a low-aerobic / below-first-threshold target."
- "Confidence is higher with lactate or ventilatory threshold testing."
- "HR drift or decoupling can support a field estimate when conditions are stable."

### Forbidden Claims

- "This is your exact Zone 2" from HRmax percentage alone.
- Treating all `Zone 2` labels as physiologically equivalent.
- Equating watch/Garmin/Strava zones with LT1/VT1 without validation.
- Ignoring day-to-day context such as fatigue, heat, dehydration, altitude, caffeine,
  sleep, and HR drift.

### Implementation Notes

Suggested metadata:

```yaml
metric: zone2_hr_range
popular_label: Zone 2
physiological_domain: below_or_near_first_threshold
threshold_basis: LT1 | VT1 | AeT | HR_drift | HRV_threshold | talk_test | percent_hrmax
model_basis: lab_threshold | field_estimate | heuristic | product_reference
confidence_basis:
  - threshold_test_available
  - steady_state_duration
  - hr_drift_quality
  - environmental_stability
  - input_source_consistency
claim_ceiling: estimated_range_unless_lab_threshold
```

Confidence ladder:

| Method | Confidence |
|---|---|
| Lactate threshold test identifying LT1 | High |
| CPET identifying VT1 / GET | High |
| HR drift / decoupling under controlled steady-state conditions | Medium |
| HRV-derived threshold | Medium-low to medium |
| Talk test / RPE | Low-medium |
| Fixed %HRmax or age formula | Low |

## Strength / 1RM

### Key Sources

| Source | Type | Reference Standard | ZoneTruth Use |
|---|---|---|---|
| ACSM 2026 Resistance Training Position Stand | Guideline / position stand | 1RM percentage, volume, sets, power/hypertrophy domains | Anchor training-intensity language |
| Grgic et al. 2020 1RM reliability systematic review | Systematic review | Direct 1RM test-retest reliability | Anchor direct 1RM as valid if standardized |
| Seo et al. 2012 1RM protocol reliability | Reliability study | Standardized 1RM protocol | Anchor familiarization/warm-up/protocol controls |
| Ribeiro et al. 2024 e1RM equation comparison | Validation/comparison study | Direct 1RM vs prediction equations | Anchor formula-specific e1RM metadata |
| Handgrip strength meta-analyses | Health proxy literature | Dynamometry / mortality associations | Treat grip as health proxy, not whole-body strength |

### Literature Notes

Strength should not be modeled as one scalar. ZoneTruth should distinguish:

- Direct standardized 1RM
- Estimated 1RM from rep-max or reps-to-failure
- Relative strength normalized to bodyweight
- Velocity-based estimate
- Grip strength as a health proxy

Direct 1RM is appropriate as a non-lab maximum-strength anchor when protocol,
range of motion, equipment, warm-up, rest, and familiarization are controlled.
e1RM is useful, but formula choice and exercise context matter. A 5RM-derived squat
estimate and a high-rep arm-curl estimate should not be given the same confidence.

Grip strength has health-risk relevance but should not replace exercise-specific
strength analysis for squat/deadlift/bench/pull movements.

### Allowed Claims

- "Direct 1RM measured under standardized protocol."
- "Estimated 1RM from XRM using named equation."
- "Valid for trend if exercise, ROM, equipment, and effort definition remain consistent."
- "Grip strength is a health proxy, not a substitute for whole-body maximal strength."

### Forbidden Claims

- "Muscle gain" or hypertrophy causation from heart-rate-only strength sessions.
- Treating vague gym logs as direct maximal strength.
- Comparing e1RM across different exercises/equipment without normalization context.
- Treating grip strength as proof of squat/deadlift/bench strength.

### Implementation Notes

Suggested metadata:

```yaml
metric: strength
metric_type: direct_1RM | estimated_1RM | rep_max | velocity_based_estimate | grip_strength | relative_strength
exercise_standardization:
  - exercise_name
  - equipment
  - range_of_motion
  - tempo
  - rest_time
  - bodyweight
  - failure_definition
confidence_basis:
  - direct_test
  - reps_in_prediction_range
  - technique_standardized
  - bodyweight_known
  - same_equipment
claim_ceiling: strength_estimate_unless_direct_standardized_test
```

Confidence ladder:

| Method | Confidence |
|---|---|
| Direct 1RM with standardized protocol | High |
| Standardized 3RM-5RM converted to e1RM | Medium |
| 6RM-10RM converted to e1RM | Medium-low |
| High-rep or unclear failure set converted to e1RM | Low |
| Vague gym log without ROM/equipment/bodyweight | Low |
| Grip strength | Health proxy only |

## Cross-Metric Output Pattern

All three domains should eventually use the same output skeleton:

```yaml
metric: vo2max | zone2_hr_range | strength
value: number | range | classification
unit: ml/kg/min | bpm | kg | x_bodyweight
method: string
method_tier: gold_standard_anchor | field_estimator | product_reference
reference_standard_distance: direct | one_level_below | two_or_more_levels_below
confidence: high | medium | medium_low | low
error_or_uncertainty_band: string
data_quality_flags:
  - string
interpretation: bounded_observation
recommended_validation: optional_string
claim_ceiling: string
```

Rendering rule:

- Show `method_tier` and `reference_standard_distance` whenever the value can be
  confused with a gold-standard measurement.
- If `method_tier = product_reference`, render as estimate and include source.
- If confidence is low, prefer "usable starting point" over "training zone."

## First Meta-Spec Decisions

1. VO2 max estimates from Apple/Garmin/Firstbeat are admissible as trend estimates,
   not lab-equivalent values.
2. Zone 2 must be stored with `threshold_basis`; the label alone is insufficient.
3. Strength must separate direct 1RM, e1RM, relative strength, and health proxies.
4. Confidence is evidence-distance plus data quality, not a generic model score.
5. Product algorithms can be compared against ZoneTruth output only as sanity checks,
   never as truth labels.

## Candidate Implementation Sequence

1. `TRAINING_ANALYSIS_META_SPEC.md`: formalize schema, confidence ladder, and claim ceiling.
2. Core model additions: add method tier, reference-standard distance, and confidence basis.
3. Analyzer adapters: map existing Zone 2 / VO2 / Strength paths into the new metadata.
4. UI wording: show estimate vs measured status and validation suggestions.
5. Targeted tests: enforce forbidden claims and metadata presence for ambiguous estimates.

## Source Links

- INTERLIVE wearable VO2 max systematic review: https://pmc.ncbi.nlm.nih.gov/articles/PMC9213394/
- ARTP CPET statement 2021: https://www.artp.org.uk/resources/68/artp_statement_on_cardiopulmonary_exercise_testing_2021
- Apple Cardio Fitness / VO2 max estimate support: https://support.apple.com/en-us/108790
- Apple HealthKit VO2 max type: https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/vo2max
- Firstbeat VO2max estimation white paper: https://www.firstbeat.com/en/aerobic-fitness-level-vo%E2%82%82max-estimation-firstbeat-white-paper-2/
- Garmin VO2 max support: https://support.garmin.com/en-US/?faq=lWqSVlq3w76z5WoihLy5f8
- Garmin fenix 6 validation study: https://pubmed.ncbi.nlm.nih.gov/39797066/
- Zone 2 expert viewpoint: https://cris.maastrichtuniversity.nl/en/publications/what-is-zone-2-training-experts-viewpoint-on-definition-training-/
- HRV-derived thresholds systematic review: https://pmc.ncbi.nlm.nih.gov/articles/PMC11461412/
- HRmax / threshold variability example: https://www.frontiersin.org/journals/physiology/articles/10.3389/fphys.2023.1299104/full
- ACSM 2026 resistance training update: https://acsm.org/resistance-training-guidelines-update-2026/
- ACSM 2026 resistance training position stand: https://pmc.ncbi.nlm.nih.gov/articles/PMC12965823/
- 1RM reliability systematic review: https://pmc.ncbi.nlm.nih.gov/articles/PMC7367986/
