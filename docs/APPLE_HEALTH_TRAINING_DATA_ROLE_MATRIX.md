---
audience: owner, agent-runtime
authority: product-spec
status: draft
last_updated: 2026-06-11
source_review:
  - docs/TRAINING_ESTIMATOR_EVIDENCE_MAP.md
  - docs/APPLE_HEALTH_HIGH_VALUE_EXPANSION.md
  - docs/TRAINING_ANALYSIS_METADATA_CONTRACT.md
---

# Apple Health Training Data Role Matrix

## Purpose

This document defines how Apple Health data should be used inside ZoneTruth's
training-analysis system.

It does not redefine the evidence hierarchy from
`TRAINING_ESTIMATOR_EVIDENCE_MAP.md`. Instead, it maps Apple Health data into
product roles:

- product reference
- field-estimator input
- supportive context signal
- data-quality context

Core rule:

```text
Apple Health = consumer telemetry layer
Apple Health != physiological gold standard
```

Apple Health can improve estimate quality and reduce ambiguity, but it does not
normally provide the reference anchors required for verified physiological
thresholds, lab-equivalent VO2 max, or direct maximal strength claims.

## Relationship To The Evidence Map

Use `docs/TRAINING_ESTIMATOR_EVIDENCE_MAP.md` for:

- literature-informed evidence levels
- claim ceilings
- allowed and forbidden language
- downgrade rules for estimators

Use this document for:

- Apple Health source-role classification
- how each Apple Health field contributes to product logic
- what Apple Health data may strengthen
- what Apple Health data must not be allowed to overclaim

If another source is added later, such as Garmin, Strava, or COROS, it should
get its own source-role matrix rather than extending Apple Health semantics by
analogy.

## Implementation Hook

For implementation-facing work:

- analyzer metadata should resolve evidence level, claim ceiling, and downgrade
  logic from `TRAINING_ESTIMATOR_EVIDENCE_MAP.md`
- Apple Health ingestion, importer labeling, and source-specific display should
  resolve role semantics from this document
- this matrix may narrow or cap confidence, but it must not upgrade a metric
  above the evidence-layer authority defined in the Evidence Map

If Apple Health is absent, do not borrow this matrix for another source. Use a
source-role layer of `none` or add a dedicated source-role matrix for that
provider.

`TRAINING_ANALYSIS_METADATA_CONTRACT.md` defines when analyzer, importer, and
display metadata must carry this matrix as `spec_resolution.source_role_layer`.

## Apple Health Role Tiers

### AH-R0 `reference_anchor`

Apple Health does not normally provide this tier by default.

Examples not provided by Apple Health:

- CPET gas-exchange VO2 max
- lactate-derived LT1
- ventilatory-derived VT1
- GET
- direct standardized 1RM

This tier may only be used if externally tested data is imported with explicit
provenance and should not be inferred from Apple-generated telemetry.

### AH-R1 `product_reference`

Apple-produced or platform-produced estimate surfaced as a bounded reference.

Examples:

- `vo2Max`

Allowed role:

- imported product estimate
- trend reference
- source-labeled estimate

Forbidden role:

- reference anchor
- lab-equivalent measure
- direct physiological truth

### AH-R2 `field_estimator_input`

Apple Health telemetry that can improve estimator quality when combined with
other signals.

Examples:

- `restingHeartRate`
- `heartRateRecoveryOneMinute`
- heart-rate samples
- `runningPower`
- `cyclingPower`
- `runningSpeed`
- workout duration
- distance

Allowed role:

- baseline input
- external-load support
- interval-pattern support
- steady-state support
- recovery context

Forbidden role:

- threshold proof by itself
- direct VO2 max measurement
- direct maximal-strength measurement

### AH-R3 `supportive_context_signal`

Useful context, but not enough to determine physiological state on its own.

Examples:

- `workoutRoute`
- `sleepAnalysis`
- `activeEnergy`
- workout category
- HRV SDNN
- resting-heart-rate trend
- workout history

Allowed role:

- explain ambiguity
- raise or lower confidence
- route analyzer selection
- provide environmental or workload context

Forbidden role:

- validate threshold
- prove adaptation
- measure strength
- measure VO2 max

## Global Source Rule

Apple Health data may be used as:

```text
product_reference
field_estimator_input
supportive_context_signal
data_quality_context
```

Apple Health data must not be treated as:

```text
CPET
LT1 / VT1 / GET
lactate threshold
ventilatory threshold
direct standardized 1RM
validated maximal-strength test
```

## Apple Health Data Role Matrix

| Apple Health Data | Role Tier | Product Role | Allowed Claim Surface | Forbidden Claim Surface |
|---|---|---|---|---|
| `vo2Max` | `AH-R1 product_reference` | Apple-produced VO2 max estimate | Apple Health VO2 max estimate; trend reference | lab VO2 max; CPET-equivalent; true VO2 max |
| `restingHeartRate` | `AH-R2 field_estimator_input` | baseline input for initial Zone 2 range | initial Zone 2 reference range | personalized calibrated threshold; LT1 found |
| `heartRateRecoveryOneMinute` | `AH-R2 field_estimator_input` | recovery context after effort | recovery response context | VO2 max proof; fitness proof alone |
| heart-rate samples | `AH-R2 field_estimator_input` | session intensity and pattern input | HR pattern supports interpretation | verified zone; verified threshold |
| `runningPower` | `AH-R2 field_estimator_input` | external-load context for running | supports interval or steady-state interpretation | metabolic-threshold proof |
| `cyclingPower` | `AH-R2 field_estimator_input` | external-load context for cycling | supports interval or steady-state interpretation | metabolic-threshold proof |
| `runningSpeed` | `AH-R2 field_estimator_input` | pace and HR relationship input | supports pace-HR consistency interpretation | Zone 2 proof |
| `workoutRoute` | `AH-R3 supportive_context_signal` | terrain and route context | explains pace or HR distortion | fitness truth; threshold validation |
| `sleepAnalysis` | `AH-R3 supportive_context_signal` | supportive recovery context | sleep duration and coverage context | recovery diagnosis; readiness verdict; training prescription |
| distance | `AH-R3 supportive_context_signal` | volume context | supports workload interpretation | physiological adaptation proof |
| `activeEnergy` | `AH-R3 supportive_context_signal` | session-load context | contextual energy/load estimate | precise metabolic truth |
| workout category | `AH-R3 supportive_context_signal` | analyzer routing and modality context | activity-type context | exercise-physiology proof |
| HRV SDNN | `AH-R3 supportive_context_signal` | recovery/autonomic context | bounded recovery context signal | readiness truth; threshold proof |

## VO2-Oriented Analysis

### Product Boundary

ZoneTruth must keep these concepts separate:

```text
Apple Health vo2Max = product reference estimate
ZoneTruth vo2_interval_quality = session pattern inference
CPET VO2 max = reference anchor
```

These must not collapse into one metric.

### `vo2Max`

Role:

```text
AH-R1 product_reference
```

Allowed:

- Apple Health VO2 max estimate
- VO2 max trend reference
- platform-estimated cardio fitness value

Forbidden:

- measured VO2 max
- true VO2 max
- lab VO2 max
- CPET-equivalent VO2 max
- ZoneTruth measured VO2 max

Recommended copy:

```text
Apple Health 提供的 VO2 max 估算值，可作為趨勢參考，不等同實驗室 CPET 測量。
```

### `runningPower` And `cyclingPower`

Role:

```text
AH-R2 field_estimator_input
```

Use for:

- interval-structure validation
- external-load support
- HR-power consistency
- steady-state analysis
- decoupling context

Allowed:

- power data supports high-intensity interval interpretation
- power data supports steady aerobic interpretation
- power and HR relationship appears stable

Forbidden:

- power data proves VO2 max improved
- power data confirms VO2 max
- power data directly measures oxygen uptake

### `heartRateRecoveryOneMinute`

Role:

```text
AH-R2 field_estimator_input
```

Use for:

- recovery context
- session-strain interpretation
- post-effort recovery trend

Allowed:

- HRR provides recovery context after high effort
- HRR trend may support recovery interpretation

Forbidden:

- HRR proves VO2 max
- HRR proves cardiovascular fitness change
- HRR alone validates training effect

## Zone 2 Analysis

### Product Boundary

Apple Health can improve Zone 2 estimation quality, but cannot replace
threshold testing.

Required claim ceiling:

```text
Without LT1 / VT1 / GET / lactate / ventilatory-threshold data, ZoneTruth must
not claim verified Zone 2.
```

### `restingHeartRate`

Role:

```text
AH-R2 field_estimator_input
```

Use for:

- initial Zone 2 reference range
- baseline personalization input
- reducing manual setup friction

Allowed:

- initial Zone 2 reference range
- Resting-HR-based starting point
- needs validation from training data

Forbidden:

- personalized Zone 2 calibrated
- LT1 found
- VT1 found
- aerobic threshold confirmed
- verified Zone 2

Required UI title:

```text
初步 Zone 2 參考範圍
```

Required badge:

```text
初步估算，尚未驗證
```

Recommended reason:

```text
依 Apple Health Resting HR 與產品預設偏移規則產生初步 Zone 2 參考範圍。此範圍尚未經外部閾值測試或足夠訓練資料驗證。
```

### `runningPower` And `cyclingPower`

Role:

```text
AH-R2 field_estimator_input
```

Use for:

- steady-state validation
- HR-power decoupling
- aerobic-stability analysis
- external-load normalization

Allowed:

- power stability supports steady aerobic interpretation
- HR and power relationship appears stable
- power data improves confidence in session classification

Forbidden:

- power confirms Zone 2
- power finds LT1
- power finds VT1
- power proves metabolic threshold

### `workoutRoute`

Role:

```text
AH-R3 supportive_context_signal
```

Use for:

- terrain explanation
- pace-distortion context
- elevation or route-related HR interpretation
- outdoor workout quality context

Allowed:

- route context may explain pace or HR changes
- terrain may reduce confidence in pace-based interpretation

Forbidden:

- route proves fitness
- route validates Zone 2
- route determines threshold

### Heart-Rate Samples

Role:

```text
AH-R2 field_estimator_input
```

Use for:

- HR-zone distribution
- steady-state check
- interval pattern
- drift or decoupling support

Allowed:

- HR pattern supports Zone 2-like interpretation
- HR stayed mostly within the initial reference range
- HR drift may suggest aerobic stability or instability

Forbidden:

- HR alone verifies Zone 2
- HR alone confirms LT1 or VT1
- HR-zone distribution proves physiological threshold

Downgrade conditions:

- wrist HR source
- swimming activity
- missing samples
- irregular sampling
- noisy HR series
- many pauses
- HR conflicts with RPE or pace/power

## Swimming-Specific Rule

Swimming requires stricter confidence caps.

Default:

```text
Swimming wrist HR = confidence capped unless validated or corroborated
```

Apple Health swim data may support:

- duration
- distance
- pace consistency
- HR pattern
- workout continuity

But must not alone support:

- precise Zone 2
- verified aerobic threshold
- high-confidence HR-zone classification

Allowed:

- 這次游泳型態偏向穩定有氧。
- 心率資料支持但不足以單獨確認 Zone 2。

Forbidden:

- 這次游泳已確認在 Zone 2。
- Apple Health swim HR 驗證了你的 Zone 2。
- 這次游泳找到你的有氧閾值。

Downgrade conditions:

- wrist-only HR
- frequent stroke switching
- many stops
- missing lap or pace consistency
- RPE conflicts with HR
- implausible HR pattern

## Strength Analysis

### Product Boundary

Apple Health is mostly context-only for strength.

Apple Health does not normally provide:

```text
direct 1RM
exercise-specific load
reps
RIR
ROM quality
failure proximity
load-velocity profile
```

Therefore Apple Health must not upgrade strength analysis into maximal-strength
measurement.

### Workout Category, Heart Rate, And Active Energy

Role:

```text
AH-R3 supportive_context_signal
```

Use for:

- distinguishing typical strength vs conditioning-like session
- detecting circuit-like density
- session-load context
- rest-pattern approximation when available

Allowed:

- strength session appears conditioning-like
- session pattern suggests higher density
- HR pattern is unusual for typical strength training

Forbidden:

- your maximal strength improved
- your true 1RM increased
- Apple Health measured your strength
- this proves strength gain

## Sleep Context

### `sleepAnalysis`

Role:

```text
AH-R3 supportive_context_signal
```

Use for:

- weekly supportive recovery context
- sleep duration and coverage summary
- removing `sleep` from displayed missing-evidence gaps when recent sleep data is available
- explaining that recovery interpretation has more context than workout data alone

Do not use for:

- recovery diagnosis
- readiness score
- training prescription
- classifier changes
- proving under-recovery, overtraining, illness, or stress

Allowed copy:

```text
近 7 天睡眠資料可作為恢復脈絡參考，不直接輸出恢復診斷。
```

Forbidden copy:

```text
你恢復不足。
你睡眠不足，所以今天不要練。
睡眠資料證明你已恢復。
ZoneTruth 診斷你的恢復狀態。
```

Implementation boundary:

- HealthKit ingestion may read `HKCategoryTypeIdentifier.sleepAnalysis`.
- Weekly display may show nights covered, average sleep duration, and coverage ratio.
- Weekly provenance display may stop listing `sleep` as missing when a valid recent sleep context exists.
- Weekly classifier, training-mode classifier, and coaching policy must not change because sleep is present.

## Confidence Rules

Confidence may increase when:

- Apple Health adds external load, such as running or cycling power
- HR, pace, and power are internally consistent
- route explains pace or HR changes
- repeated sessions show stable relationships
- Apple Health estimates are used only as product references, not truth
- subjective inputs agree with telemetry

Confidence must decrease when:

- Apple Health is the only source
- HR data source is unknown
- wrist HR is used during swimming
- route or terrain is missing for outdoor pace analysis
- HR conflicts with pace, power, or RPE
- activity type has known sensor limitations
- data is sparse, paused, or irregular
- a field estimate is being mistaken for a reference anchor

## Analyzer Output Extension

Any analyzer output that materially depends on Apple Health should be able to
carry source-role disclosure like:

```yaml
apple_health:
  used: true
  data_types:
    - restingHeartRate
    - heartRate
    - runningPower
  role:
    - field_estimator_input
  claim_ceiling: initial_reference_range
  not_reference_anchor: true
  downgrade_reasons:
    - no_external_threshold_test
    - fixed_offset_rule
spec_resolution:
  evidence_layer: TRAINING_ESTIMATOR_EVIDENCE_MAP
  source_role_layer: APPLE_HEALTH_TRAINING_DATA_ROLE_MATRIX
```

This is a schema direction, not a requirement that every existing analyzer be
rewired immediately.

## Examples

### Resting-HR Zone 2

```yaml
metric_id: resting_hr_zone2_reference
source: apple_health
apple_health:
  used: true
  data_types:
    - restingHeartRate
  role:
    - field_estimator_input
  not_reference_anchor: true
evidence_level: L2_WEAK_HEURISTIC
claim_level: INITIAL_REFERENCE_RANGE
allowed_claims:
  - 初步 Zone 2 參考範圍
  - Apple Health Resting-HR-based starting point
forbidden_claims:
  - 個人化 Zone 2 已校正
  - LT1 已找到
  - VT1 已找到
  - 有氧閾值已確認
confidence_reason:
  - Apple Health Resting HR available
  - no external threshold test
  - no sufficient session validation yet
downgrade_reasons:
  - fixed_offset_rule
  - no_lactate_or_ventilatory_anchor
ui_copy_tier: conservative
```

### Apple Health VO2 Max

```yaml
metric_id: apple_health_vo2max_reference
source: apple_health
apple_health:
  used: true
  data_types:
    - vo2Max
  role:
    - product_reference
  not_reference_anchor: true
evidence_level: AH_R1_PRODUCT_REFERENCE
claim_level: ESTIMATE_ONLY
allowed_claims:
  - Apple Health VO2 max 估算值
  - 長期趨勢參考
forbidden_claims:
  - CPET 實測 VO2 max
  - lab-equivalent VO2 max
  - true VO2 max
  - ZoneTruth measured VO2 max
confidence_reason:
  - Apple-produced estimate available
  - no CPET data
ui_copy_tier: bounded_estimate
```

### Strength Context From Apple Health

```yaml
metric_id: apple_health_strength_session_context
source: apple_health
apple_health:
  used: true
  data_types:
    - workoutCategory
    - heartRate
    - activeEnergy
  role:
    - supportive_context_signal
  not_reference_anchor: true
evidence_level: AH_R3_CONTEXT_SIGNAL
claim_level: PATTERN_ONLY
allowed_claims:
  - 重訓型態偏向高密度
  - HR pattern suggests conditioning-like strength session
forbidden_claims:
  - 最大肌力提升
  - true 1RM increased
  - Apple Health measured strength
downgrade_reasons:
  - no_load_reps_data
  - no_direct_1rm
  - no_failure_proximity
ui_copy_tier: pattern_only
```

### Sleep Context From Apple Health

```yaml
metric_id: apple_health_sleep_context
source: apple_health
apple_health:
  used: true
  data_types:
    - sleepAnalysis
  role:
    - supportive_context_signal
  not_reference_anchor: true
evidence_level: AH_R3_CONTEXT_SIGNAL
claim_level: SUPPORTIVE_RECOVERY_CONTEXT
allowed_claims:
  - 睡眠脈絡
  - 近 7 天睡眠資料覆蓋
  - 恢復脈絡參考
forbidden_claims:
  - 恢復診斷
  - readiness verdict
  - 今天不要練
  - overtraining proof
downgrade_reasons:
  - context_only
  - no_clinical_sleep_protocol
  - no_training_prescription_authority
ui_copy_tier: supportive_context
```
