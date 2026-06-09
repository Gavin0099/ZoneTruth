# Training Classification Plan v3.1

Last updated: 2026-06-09
Owner: ZoneTruth Product + Core
Status: Execution spec

## 1. Product Route

ZoneTruth v1 adopts route C: classify training mode from Apple Watch activity
type plus heart-rate features.

| Route | Definition | Status |
|---|---|---|
| A | Compare completed workouts against a weekly plan | Not adopted |
| B | Ask the user to declare workout intent before or after each workout | Not adopted |
| C | Infer the actual training mode from activity type and heart-rate features | Adopted |

ZoneTruth v1 is a training-mode classifier, not a training-plan comparator.

It answers:

- What did this workout most resemble: Zone 2, VO2 stimulus, strength pattern,
  conditioning-like strength, general low intensity, mixed, or insufficient data?
- What evidence supports that classification?
- How reliable was the heart-rate data?

It does not answer:

- Whether the user achieved a planned workout.
- Whether the user's subjective intent was fulfilled.
- Whether the workout caused VO2 max, hypertrophy, strength, or fitness gains.
- Whether the user should change training without an explicit goal context.

## 2. Sprint 0 Preconditions

Sprint 0 must happen before behavior implementation. Its purpose is to keep the
classifier from resting on hidden assumptions.

### 2.1 Product Route Lock

Write all implementation and UI language against route C.

Required wording:

- Use `判讀結果` or `本次訓練型態`.
- Use `分類信心` and `心率資料品質` as separate concepts.
- Use `偏向` when evidence or data quality is limited.

Forbidden wording in user-facing route C surfaces:

- `本次意圖`
- `目的符合度`
- `達標`
- `訓練成效分數`
- single-session `VO2 max` as a primary classification result
- single-session strength-effect claims such as hypertrophy or force-output claims

### 2.2 Minimal Zone Baseline

Zone 2 and VO2 classification require a visible heart-rate-zone basis.

MVP should use flexible defaults plus later recalculation, not hard-blocking
onboarding.

Required state to add or verify before classifier rollout:

- `zoneConfigVersion`
- `classificationVersion`
- `usedPersonalizedZones`
- age or max-HR basis when available
- Resting HR source when available

When personalized zones are missing, the UI may classify with default zones only
if the result is explicitly marked as coarse:

```text
目前使用預設心率區間，分類可能較粗略。
```

Future zone changes must be able to trigger historical reclassification because
old results need to disclose which zone basis produced them.

### 2.3 Preserve List

Do not remove these existing product assets during the classification refactor:

- dark card-based visual style
- first-screen activity summary
- evidence list / `判讀依據` presentation
- Apple Health import flow
- detailed data section, default collapsed
- the concept that core classification policy is not casually user-editable

Revise, but do not delete, the "core strategy" concept. It should become
classifier-specific minimum evidence requirements instead of a single global
minimum duration rule.

| Classifier | Minimum evidence concept |
|---|---|
| Zone 2 | Enough continuous heart-rate coverage and enough stable Zone 2 segment evidence |
| VO2 stimulus | Enough high-heart-rate segment and recovery-pattern evidence |
| Strength pattern | Enough samples and duration to distinguish typical strength from conditioning-like work |
| HR drift | Stable continuous segment; not applied to typical interval activity |

## 3. Output Model

The classifier output belongs in `ZoneTruthCore`, not the App layer. App views
should render Core classification output and should not recreate semantic
classification.

Initial Swift shape:

```swift
public enum TrainingMode: String, Codable, CaseIterable, Sendable {
    case zone2
    case vo2Stimulus
    case strengthPattern
    case conditioningLike
    case generalLowIntensity
    case mixed
    case insufficientData
}

public enum ClassificationConfidence: String, Codable, CaseIterable, Sendable {
    case high
    case mediumHigh
    case medium
    case low
    case insufficient
}

public enum TrainingDataQuality: String, Codable, CaseIterable, Sendable {
    case high
    case medium
    case low
    case insufficient
}

public enum TrainingClaimLevel: String, Codable, CaseIterable, Sendable {
    case primaryClassification
    case secondaryReference
    case referenceOnly
    case notApplicable
    case unsupported
}

public struct TrainingClassification: Codable, Equatable, Sendable {
    public let primaryMode: TrainingMode
    public let confidence: ClassificationConfidence
    public let dataQuality: TrainingDataQuality
    public let claimLevel: TrainingClaimLevel
    public let evidence: [TrainingClassificationEvidence]
    public let warnings: [TrainingClassificationWarning]
    public let notApplicableReasons: [TrainingNotApplicableReason]
    public let debug: TrainingClassificationDebug?
}
```

The three axes must stay independent:

- `claimLevel`: what this result may safely claim.
- `visibility`: whether an item is user-visible, advanced, or dev-only.
- `dataQuality`: how reliable the input heart-rate data was.

Do not collapse all three into a single percentage score.

## 4. Classifier Priorities

### 4.1 Strength

Strength classification must prioritize exception detection.

Order:

1. insufficient data
2. conditioning-like / circuit-like
3. typical strength pattern
4. general low-intensity / recovery-like strength session

Normal case wording should be short:

```text
判讀結果：典型肌力訓練型態
心率表現符合一般重訓特徵。
```

High-value exception wording:

```text
判讀結果：偏高密度循環訓練
這次雖然是重量訓練，但心率長時間維持在較高區間，較不像傳統組間休息明確的肌力訓練。
```

Do not let the product merely say "you did strength training during a strength
workout." The useful signal is whether the heart-rate pattern was typical,
conditioning-like, recovery-like, or unreadable.

### 4.2 Swimming

Swimming must gate on data quality before strong classification.

Order:

1. If data quality is insufficient: `insufficientData`.
2. If data quality is low: only `偏向` wording; no strong primary claim.
3. If data quality is medium/high: allow Zone 2 or VO2 stimulus classification
   based on heart-rate distribution and segment pattern.

This prevents contradictory rules where swimming is known to have low
measurement quality but is still strongly classified.

### 4.3 VO2

Use `VO2 刺激型態`.

Do not use single-session wording that implies `VO2 max` estimation or
achievement unless a separate imported VO2 max metric is being rendered as a
bounded product/field estimate with its own claim metadata.

## 5. Weekly Surface

The first weekly classification surface is descriptive only.

Allowed MVP wording:

```text
本週訓練型態分布
Zone 2：2 次
VO2 刺激：1 次
肌力：2 次
一般活動：1 次
資料不足：0 次
```

Allowed observation:

```text
本週尚未出現 VO2 刺激型態。
```

Forbidden without explicit weekly goals:

- `VO2 偏少`
- `VO2 不足`
- `Zone 2 足夠`
- `肌力訓練達標`
- `本週訓練成效良好`

Goal comparison is a later feature. It requires user-visible weekly targets
before any "不足 / 達標" language is admitted.

## 6. Execution Order

| Order | Slice | Done condition |
|---|---|---|
| Sprint 0 | Route C spec + zone baseline audit + preserve list | Spec and plan updated; no behavior change |
| Sprint 1 | Trust stopgap UI wording | User-facing detail UI no longer shows `本次意圖`, `目的符合度`, user-facing `舊版判定`, or strength-first-screen `VO2 max` |
| Sprint 2 | Core classification object | Swift Core output exists with mode, confidence, data quality, claim level, evidence, warnings, and not-applicable reasons |
| Sprint 3 | Rule-based classifier aggregator | Zone 2 / VO2 stimulus / strength candidate classifiers produce explainable output; strength exception paths are tested first |
| Sprint 4 | Descriptive weekly distribution | Weekly page groups workouts by classification mode without goal-language evaluation |
| Sprint 5 | Swimming data-quality gate | Swimming classification cannot strong-claim when HR quality is low |
| Sprint 6 | Feedback and calibration | User feedback records classification correction, not workout intent |

## 7. MVP v3.1

The revised MVP is:

1. Adopt route C: infer actual training mode from activity type + HR features.
2. Verify minimal zone baseline state and default-zone disclosure path.
3. Rename user-facing `本次意圖` to `判讀結果` / `本次訓練型態`.
4. Remove `目的符合度`; do not replace it with a dressed-up goal score.
5. Remove user-facing `舊版判定`.
6. Remove `VO2 max` from the strength detail primary surface.
7. Add Swift `TrainingClassification` output in Core.
8. Add data-quality gating.
9. Implement Zone 2 / VO2 stimulus / strength-pattern classifiers.
10. Add descriptive weekly classification distribution.

Swimming-specific classification may move into MVP only if swimming is the
current owner-acceptance priority; otherwise it follows after the first
classification distribution is stable.

## 8. Non-Claims

This spec does not change runtime behavior yet.

It does not authorize:

- App-layer semantic classification.
- New weekly goal comparison.
- Training prescription.
- VO2 max, hypertrophy, or strength-effect claims from heart-rate-only data.
- Weakening existing weekly rendering contract tests.
