---
audience: owner, agent-runtime
authority: product-spec
status: draft
last_updated: 2026-06-09
---

# Training Estimator Evidence Map

## Purpose

Define how ZoneTruth translates exercise-science evidence into product
behavior.

This document does not define medical diagnosis, laboratory equivalence, or
verified physiological thresholds. It defines evidence levels, allowed claims,
forbidden claims, confidence rules, and downgrade conditions for
VO2-oriented interval quality, Zone 2 estimation, and strength-pattern
analysis.

## Scope Boundary

This document governs:

- literature-informed evidence levels
- reference anchors vs field estimators vs weak heuristics
- allowed and forbidden language
- downgrade rules and UI copy tiers

This document does not govern:

- source-specific ingestion policy
- Apple Health field-by-field role assignment
- future Garmin / Strava / COROS source-role mapping

Use [APPLE_HEALTH_TRAINING_DATA_ROLE_MATRIX.md](/Users/gavin_wu/Desktop/ZoneTruth/docs/APPLE_HEALTH_TRAINING_DATA_ROLE_MATRIX.md)
for Apple Health source-role classification. Keep the split stable:

- `TRAINING_ESTIMATOR_EVIDENCE_MAP.md` = literature and inference layer
- `APPLE_HEALTH_TRAINING_DATA_ROLE_MATRIX.md` = Apple Health data-source role layer

## Evidence Levels

### L0 — Reference Anchor

Strongest available reference standard.

Examples:

- VO2 max: CPET / laboratory gas-exchange measurement
- Zone 2 / aerobic threshold: LT1, VT1, GET, lactate-derived threshold,
  ventilatory-derived threshold
- Strength: direct standardized 1RM under controlled protocol

Allowed language:

- measured
- tested
- externally verified
- reference-based

Forbidden unless actual L0 data exists:

- verified threshold
- lab-equivalent VO2 max
- confirmed LT1 / VT1
- confirmed maximal strength

### L1 — Strong Field Estimator

Field method with protocol control and supporting evidence, but still not
equivalent to L0.

Examples:

- validated exercise-based wearable VO2 max estimate
- structured submaximal VO2 max protocol
- Talk Test combined with stable HR and stable pace/power
- HRV-derived threshold with high-quality RR data and artifact control
- validated exercise-specific e1RM or velocity-based model

Allowed language:

- estimated
- field-estimated
- consistent with
- likely near
- threshold-informed estimate

Forbidden language:

- confirmed
- measured physiological threshold
- lab-equivalent
- exact VO2 max
- exact 1RM unless directly tested

### L2 — Weak Field Estimator / Heuristic

Useful as a starting point, but not enough to claim personalization or
threshold calibration.

Examples:

- Resting HR + fixed offset
- percent HRmax
- age-predicted HRmax formula
- product preset zones
- RPE alone
- HR drift alone
- swimming wrist HR without device/source validation
- e1RM from incomplete or inconsistent training logs

Allowed language:

- initial reference range
- starting point
- weak estimate
- heuristic estimate
- needs more data

Forbidden language:

- personalized calibrated threshold
- verified Zone 2
- LT1 / VT1 found
- VO2 max improved
- precise strength score

### L3 — Supportive Context Signal

Useful for pattern recognition, but not enough to determine a zone or
physiological value alone.

Examples:

- session duration
- consistency
- pace stability
- HR stability
- subjective feel
- fatigue notes
- stroke type
- exercise category
- volume trend
- density trend
- rest-interval pattern

Allowed language:

- supports this interpretation
- pattern suggests
- contributes to confidence
- session quality signal

Forbidden language:

- proves
- confirms
- validates threshold
- determines VO2 max
- determines maximal strength

## VO2-Oriented Analysis

### Product Object

The current analyzer should be treated as:

```text
vo2_interval_quality
```

Not:

```text
vo2max
```

### Reference Anchor

VO2 max reference anchor is CPET / gas-exchange measurement.

### Product Interpretation

The product may classify a session as having VO2-oriented interval
characteristics when available data supports high-intensity repeated efforts,
appropriate recovery pattern, and sufficient time near high intensity.

Allowed claims:

- VO2-oriented interval work
- high-intensity interval characteristics
- likely VO2 stimulus pattern
- consistent with VO2-focused training

Forbidden claims:

- your VO2 max increased
- this session measured VO2 max
- this confirms VO2 max improvement
- this is equivalent to CPET
- this determines your VO2 max

### Confidence Rules

Increase confidence when:

- repeated high-intensity intervals are visible
- recovery intervals are visible
- HR reaches high-intensity range repeatedly
- pace/power pattern supports interval structure
- workout duration and repetition count are sufficient

Decrease confidence when:

- activity type does not support clear interval interpretation
- HR data is missing or low quality
- only average HR is available
- no pace/power/repetition structure is available
- session is continuous steady-state rather than interval-based

## Zone 2 Analysis

### Reference Anchor

Zone 2 should be anchored conceptually around first-threshold work:

```text
LT1 / VT1 / GET / lactate-derived threshold / ventilatory-derived threshold
```

Without such data, ZoneTruth must not claim that the true physiological
threshold has been found.

### Resting HR + Fixed Offset

Evidence level:

```text
L2 weak heuristic
```

Allowed claims:

- initial Zone 2 reference range
- starting Zone 2 estimate
- heuristic range based on Resting HR
- needs validation from training data

Forbidden claims:

- personalized Zone 2 calibrated
- verified Zone 2 threshold
- LT1 found
- VT1 found
- aerobic threshold confirmed

Required UI language:

```text
初步 Zone 2 參考範圍
```

Required badge:

```text
初步估算，尚未驗證
```

### Talk Test

Evidence level:

```text
L1 field estimator when combined with stable HR and pace/power
L2 weak estimator when used alone
```

Allowed claims:

- speech comfort suggests below-threshold effort
- consistent with easy aerobic work
- supports Zone 2 interpretation

Forbidden claims:

- Talk Test confirms LT1
- Talk Test directly measures VT1
- Talk Test alone verifies Zone 2

### RPE

Evidence level:

```text
L2 weak field estimator
L3 supportive context signal when unstructured
```

Allowed claims:

- subjective intensity supports interpretation
- effort felt easy / moderate / hard
- contributes to confidence

Forbidden claims:

- RPE alone determines Zone 2
- RPE confirms threshold
- RPE validates physiological zone

### HR Drift / Aerobic Decoupling

Evidence level:

```text
L2 session quality estimator
L3 supportive context signal
```

Allowed claims:

- HR drift suggests aerobic stability or instability
- low drift supports steady aerobic interpretation
- high drift may indicate fatigue, heat, dehydration, excessive intensity, or
  sensor issue

Forbidden claims:

- HR drift alone validates Zone 2
- HR drift alone finds LT1
- low drift proves correct Zone 2

### HRV-Derived Threshold / DFA Alpha 1

Evidence level:

```text
L1 promising field estimator when RR data quality and protocol are controlled
L2 or lower when signal quality is unknown
```

Allowed claims:

- HRV-derived threshold estimate
- threshold-informed estimate
- promising non-invasive estimator

Forbidden claims:

- verified LT1
- verified VT1
- gold-standard threshold
- valid without artifact filtering

### Swimming Zone 2

Evidence level:

```text
Depends on sensor source and activity data quality.
```

Default rule:

```text
Swimming wrist HR should be confidence-capped unless the device/source has
swimming-specific validation or corroborating signals.
```

Allowed claims:

- likely easy aerobic swimming
- likely moderate continuous effort
- HR data supports but does not prove zone classification
- pattern suggests Zone 2-like work

Forbidden claims:

- precise Zone 2 from wrist HR alone
- verified swimming Zone 2
- confirmed threshold from swim HR alone

## Strength Analysis

### Reference Anchor

Strength reference anchor:

```text
direct standardized 1RM
```

### Product Object

The product should initially prioritize:

```text
strength_pattern_analysis
```

Not:

```text
true_max_strength_measurement
```

### Direct 1RM

Evidence level:

```text
L0 reference anchor when standardized and recent
```

Allowed claims:

- tested 1RM
- directly tested strength
- exercise-specific strength anchor

Forbidden claims:

- general full-body strength truth
- permanent max strength
- transferable 1RM across different exercises or equipment

### e1RM

Evidence level:

```text
L1 or L2 depending on data quality
```

Allowed claims:

- estimated 1RM
- exercise-specific estimate
- trend indicator
- progression signal

Forbidden claims:

- exact 1RM
- directly tested strength
- confirmed maximal strength

### Velocity-Based Strength Estimate

Evidence level:

```text
L1 when individualized load-velocity profile exists
L2 when generic assumptions are used
```

Allowed claims:

- velocity-based estimate
- load-velocity-informed estimate
- useful for trend tracking

Forbidden claims:

- exact 1RM
- valid without device/protocol details
- valid across exercises without calibration

### RIR / Resistance Training RPE

Evidence level:

```text
L1/L2 training prescription signal
L3 supportive context if unreliable
```

Allowed claims:

- useful for load adjustment
- supports intensity interpretation
- helps estimate proximity to failure

Forbidden claims:

- RIR proves exact 1RM
- RIR alone determines maximal strength
- novice RIR is always reliable

## UI Copy Rules

### Strong Anchor Present

Use:

```text
measured
tested
reference-based
```

Only when actual external or direct test data exists.

### Field Estimate

Use:

```text
estimated
likely
consistent with
threshold-informed
exercise-specific estimate
```

### Weak Heuristic

Use:

```text
initial
starting point
reference range
heuristic
needs more data
```

### Supportive Context

Use:

```text
suggests
supports
pattern indicates
contributes to confidence
```

## Forbidden Global Claims

The product must not say:

```text
Your VO2 max improved
This session measured VO2 max
Your Zone 2 is confirmed
Your LT1 was found
Your VT1 was found
Your aerobic threshold is verified
Your true 1RM is known
Your maximal strength was measured
```

Unless the required reference anchor exists.

## Implementation Rule

Every analyzer output should include:

```text
metric_id
evidence_level
claim_level
allowed_claims
forbidden_claims
confidence
confidence_reason
downgrade_reasons
data_quality_flags
ui_copy_tier
```
