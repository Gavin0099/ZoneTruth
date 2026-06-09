# Apple Health High-Value Expansion List

Last updated: 2026-06-04
Owner: ZoneTruth Product + App
Status: Planning input
Scope: Apple Health data candidates for VO2 max / Zone 2 / Strength only

## Purpose

This document narrows Apple Health expansion work to data that can materially
improve ZoneTruth's:

- VO2 max estimate handling
- Zone 2 threshold starting-point quality
- Strength-context quality

It does not authorize:

- clinical diagnosis
- exact threshold claims from consumer-device data
- copying proprietary Apple algorithms
- collecting every HealthKit field just because it exists

## Spec Position

This document is the Apple Health acquisition and prioritization spec.

Use [TRAINING_ESTIMATOR_EVIDENCE_MAP.md](/Users/gavin_wu/Desktop/ZoneTruth/docs/TRAINING_ESTIMATOR_EVIDENCE_MAP.md)
for:

- literature-based evidence levels
- claim ceilings
- allowed and forbidden inference language

Use [APPLE_HEALTH_TRAINING_DATA_ROLE_MATRIX.md](/Users/gavin_wu/Desktop/ZoneTruth/docs/APPLE_HEALTH_TRAINING_DATA_ROLE_MATRIX.md)
for:

- Apple Health source-role classification
- product-reference vs field-estimator-input vs supportive-context boundaries
- source-specific overclaim prevention

This split is intentional:

- `TRAINING_ESTIMATOR_EVIDENCE_MAP.md` answers what the evidence can support
- `APPLE_HEALTH_TRAINING_DATA_ROLE_MATRIX.md` answers what each Apple Health field is allowed to do
- `APPLE_HEALTH_HIGH_VALUE_EXPANSION.md` answers which Apple Health fields are worth adding next

## Current State

ZoneTruth already reads these Apple Health workout-adjacent inputs:

- workout sessions
- heart rate samples
- HRV SDNN
- active energy
- distance

ZoneTruth now also supports:

- manual `Resting HR`
- one-tap import of recent Apple Health `Resting HR`

## Selection Rule

A new Apple Health field is worth adding only if all three are true:

1. It improves one of the three scoped pillars: `VO2 max`, `Zone 2`, `Strength`.
2. It can be rendered with a bounded claim ceiling using
   `TRAINING_ESTIMATOR_EVIDENCE_MAP.md` and
   `APPLE_HEALTH_TRAINING_DATA_ROLE_MATRIX.md`.
3. It reduces a real ambiguity that current heart-rate-only analysis cannot resolve.

## Priority Summary

| Priority | Data | Primary Value | Why It Matters |
|---|---|---|---|
| P1 | `vo2Max` | VO2 max | Directly provides Apple-produced VO2 max estimate with provenance |
| P1 | `restingHeartRate` | Zone 2 | Better personal baseline than manual-only entry |
| P1 | `heartRateRecoveryOneMinute` | VO2 max / recovery context | Useful bounded cardiovascular recovery signal |
| P1 | `runningPower` | VO2 max / Zone 2 | Better running intensity context than HR alone |
| P1 | `cyclingPower` | VO2 max / Zone 2 | Best Apple-side structured intensity input for cycling |
| P2 | `workoutRoute` | Zone 2 / VO2 max | Terrain and route context for outdoor workouts |
| P2 | `runningSpeed` | VO2 max / Zone 2 | Supports HR-speed field estimate quality checks |
| P2 | `runningGroundContactTime` | Strength / run economy context | Useful secondary running mechanics context |
| P2 | `runningStrideLength` | VO2 max / run economy context | Secondary economy/context feature |
| P2 | `runningVerticalOscillation` | VO2 max / run economy context | Secondary economy/context feature |
| P3 | sleep / temperature / body metrics | recovery context only | Possibly useful later, but outside current narrow analyzer scope |

## Recommended Expansion List

### 1. `vo2Max`

- Apple Health type: `HKQuantityTypeIdentifier.vo2Max`
- Priority: `P1`
- Pillar: `VO2 max`
- Use:
  - import latest Apple-estimated VO2 max into ZoneTruth
  - render as `product_reference`
  - track latest value and trend direction later
- Claim ceiling:
  - `VO2 max estimate`
  - never `lab-equivalent`
  - never `true VO2 max`
- Why high value:
  - this is the cleanest Apple-native signal for the VO2 max pillar
  - it fits current meta-spec directly
- Risk:
  - Apple Watch estimate is still a product estimate, not CPET truth
  - sparse update cadence may confuse users if shown without date/source
- Implementation note:
  - prefer latest sample plus sample date
- if metadata is sparse, keep `reference_standard_distance = two_or_more_levels_below`
- source-role must remain `product_reference`, not reference anchor

### 2. `restingHeartRate`

- Apple Health type: `HKQuantityTypeIdentifier.restingHeartRate`
- Priority: `P1`
- Pillar: `Zone 2`
- Use:
  - autofill personal baseline
  - generate heuristic Zone 2 starting bounds
  - reduce manual entry friction
- Claim ceiling:
  - starting point only
  - not validated threshold
- Why high value:
  - already part of current Zone 2 personalization flow
  - simple user-facing win with low conceptual risk
- Risk:
  - daily value may shift with illness, fatigue, alcohol, stress, travel
  - using one sample is noisier than averaging a recent window
- Implementation note:
  - use recent rolling average, not a single latest sample
- keep the UI explicit that this is a heuristic starting point
- source-role must remain weak heuristic input for an initial range, not calibrated threshold

### 3. `heartRateRecoveryOneMinute`

- Apple Health type: `HKQuantityTypeIdentifier.heartRateRecoveryOneMinute`
- Priority: `P1`
- Pillar: `VO2 max / recovery context`
- Use:
  - add bounded post-exercise recovery context
  - help distinguish "hard workout with normal recovery" vs "hard workout with weaker recovery response"
- Claim ceiling:
  - observational recovery signal only
  - not diagnosis
  - not direct VO2 max measurement
- Why high value:
  - helps explain session quality without pretending to measure aerobic capacity directly
  - complements HRV and workout HR pattern
- Risk:
  - availability may be sparse
  - depends on workout type and device behavior
- Implementation note:
- attach as secondary evidence, not a primary verdict driver at first
- source-role must remain bounded recovery context, not VO2 max proof

### 4. `runningPower`

- Apple Health type: `HKQuantityTypeIdentifier.runningPower`
- Priority: `P1`
- Pillar: `VO2 max / Zone 2`
- Use:
  - provide better external-load context for running
  - support future HR-power decoupling / steadiness analysis
  - help separate cardiac drift from changing mechanical output
- Claim ceiling:
  - field-estimator support signal
  - not direct threshold measurement
- Why high value:
  - HR alone cannot tell whether intensity changed because pace/power changed or because physiology drifted
- Risk:
  - not all devices produce this data
  - sample density and condensation behavior may vary
- Implementation note:
- use only when coverage is sufficient
- do not silently mix runs with and without power into one confidence level
- source-role must remain field-estimator support, not threshold anchor

### 5. `cyclingPower`

- Apple Health type: `HKQuantityTypeIdentifier.cyclingPower`
- Priority: `P1`
- Pillar: `VO2 max / Zone 2`
- Use:
  - highest-value Apple-side intensity input for cycling
  - enables stronger field-estimator logic than HR-only cycling sessions
- Claim ceiling:
  - field-estimator support signal
  - not direct metabolic threshold
- Why high value:
  - cycling HR-only analysis is especially blind without power
- Risk:
  - depends on connected peripherals and device setup
  - coverage will be uneven across users
- Implementation note:
- if absent, fall back to HR-only path and lower confidence
- source-role must remain field-estimator support, not threshold anchor

### 6. `workoutRoute`

- Apple Health type: `HKSeriesType.workoutRoute()`
- Priority: `P2`
- Pillar: `Zone 2 / VO2 max`
- Use:
  - identify hills, route variation, and terrain-driven pace distortion
  - explain why HR was high even when apparent pace was lower
- Claim ceiling:
  - context only
  - not direct fitness or threshold measure
- Why useful:
  - route context reduces false interpretation of outdoor steady-state quality
- Risk:
  - privacy sensitivity is higher than scalar metrics
  - route queries are heavier and can complicate permissions and caching
- Implementation note:
- do not make route mandatory for core analysis
- avoid storing more route detail than needed
- source-role must remain context-only

### 7. `runningSpeed`

- Apple Health type: `HKQuantityTypeIdentifier.runningSpeed`
- Priority: `P2`
- Pillar: `VO2 max / Zone 2`
- Use:
  - support HR-speed consistency checks
  - improve field-estimator quality for running sessions
- Claim ceiling:
  - field-estimator input only
- Why useful:
  - more direct than deriving speed from sparse distance snapshots
- Risk:
  - often overlaps with route or distance-derived pace
  - may not justify complexity if route/distance already covers most needs

### 8. `runningGroundContactTime`

- Apple Health type: `HKQuantityTypeIdentifier.runningGroundContactTime`
- Priority: `P2`
- Pillar: `Strength / run economy context`
- Use:
  - secondary mechanics context for fatigue or run economy interpretation
  - may help explain strength-related carryover, but only as supporting evidence
- Claim ceiling:
  - mechanics observation only
  - not strength measurement
- Why not P1:
  - high nuance, lower user comprehension, weaker immediate value than power
- Risk:
  - easy to overinterpret
  - device availability is limited

### 9. `runningStrideLength`

- Apple Health type: `HKQuantityTypeIdentifier.runningStrideLength`
- Priority: `P2`
- Pillar: `VO2 max / run economy context`
- Use:
  - secondary form/economy context alongside speed and power
- Claim ceiling:
  - observational only
- Risk:
  - high interpretation complexity relative to product value

### 10. `runningVerticalOscillation`

- Apple Health type: `HKQuantityTypeIdentifier.runningVerticalOscillation`
- Priority: `P2`
- Pillar: `VO2 max / run economy context`
- Use:
  - secondary form/economy context
- Claim ceiling:
  - observational only
- Risk:
  - easy to imply technique coaching or efficiency claims we should avoid

## Not Recommended Right Now

These may be interesting, but should not be in the next slice:

- sleep analysis
- wrist temperature
- respiratory rate
- blood oxygen
- body mass / body fat
- walking steadiness
- ECG / AFib-related signals

Reason:

- they are either outside the current three-pillar scope
- or they create authority / medical-claim risk faster than they improve core workout interpretation

## Suggested Implementation Order

1. `vo2Max`
2. `heartRateRecoveryOneMinute`
3. `runningPower`
4. `cyclingPower`
5. `workoutRoute`
6. `runningSpeed`
7. running mechanics metrics

Rationale:

- `vo2Max` gives the cleanest user-visible improvement for an existing pillar
- recovery and power signals improve interpretation quality without forcing route/privacy complexity too early
- route and mechanics are useful, but they are harder to explain safely

## Data-to-Pillar Mapping

| Data | VO2 max | Zone 2 | Strength | Recommended Role |
|---|---|---|---|---|
| `vo2Max` | High | Low | None | primary imported metric |
| `restingHeartRate` | None | High | None | personalization baseline |
| `heartRateRecoveryOneMinute` | Medium | Low | Low | secondary recovery context |
| `runningPower` | High | High | None | primary field-estimator support |
| `cyclingPower` | High | High | None | primary field-estimator support |
| `workoutRoute` | Medium | Medium | None | context / false-positive reduction |
| `runningSpeed` | Medium | Medium | None | field-estimator support |
| `runningGroundContactTime` | Low | Low | Medium-low | mechanics context only |
| `runningStrideLength` | Low | Low | Low | mechanics context only |
| `runningVerticalOscillation` | Low | Low | Low | mechanics context only |

## Risks To Carry Forward

### 1. Availability Risk

Apple Health does not guarantee every field exists for every user, device, or
session. ZoneTruth must degrade gracefully.

### 2. Source Heterogeneity

HealthKit merges device and app data from multiple sources. ZoneTruth should
prefer source-labeled imports and keep confidence conservative when provenance is
unclear.

### 3. Privacy Surface

`workoutRoute` is meaningfully more sensitive than scalar metrics. Route should
be opt-in in both product and implementation posture.

### 4. Overclaim Risk

More data does not automatically authorize stronger claims. Each new field must
inherit the same evidence-tier and claim-ceiling rules from
`TRAINING_ANALYSIS_META_SPEC.md`.

## Official Apple References

- HealthKit overview:
  - https://developer.apple.com/documentation/healthkit
- HealthKit data types:
  - https://developer.apple.com/documentation/healthkit/data-types
- `vo2Max`:
  - https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/vo2max
- `restingHeartRate`:
  - https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/restingheartrate
- `heartRateRecoveryOneMinute`:
  - https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartraterecoveryoneminute
- `runningPower`:
  - https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/runningpower
- `cyclingPower`:
  - https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/cyclingpower
- `runningGroundContactTime`:
  - https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/runninggroundcontacttime
- `runningStrideLength`:
  - https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/runningstridelength
- `runningVerticalOscillation`:
  - https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/runningverticaloscillation
- `workoutRoute`:
  - https://developer.apple.com/documentation/healthkit/hkseriestype/workoutroute()
