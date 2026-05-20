# ZoneTruth - iOS Workout Intent Analyzer Plan
> **最後更新**: 2026-05-20
> **Owner**: Gavin
> **Freshness**: Sprint (7d)

## 0. 實作現況對齊（2026-05-20）

本節用於對齊「計畫」與「目前 repo 真實狀態」，避免後續決策依賴過時假設。

### 已完成（MVP 基礎能力）

- 已有核心 Intent 分析流程：Zone 2 / VO2-Interval / Strength / Activity。
- 已有 Explainable output（理由 + 建議），並開始導入語意層 `WorkoutEvaluation`（tendency / goal fit / split confidence）。
- 已完成資料來源骨幹：HealthKit、Strava、JSON import（含 fallback 流程）。
- 已有 edge-case 測試擴充（Zone3 leakage、drift、sparse HR）與 semantic consistency guard。

### 未完成（仍在 roadmap）

- 尚未把 active calories、distance、swim/cycle distance、avg/max HR 納入核心判斷。
- 尚未完成「單一官方輸出語意」收斂（legacy pass/fail 與新語意層仍共存）。
- 尚未完成全場景真機驗證閉環（特別是 sparse/missing HR 與多運動型態資料品質差異）。
- 尚未將 plan 內舊架構描述全面更新為目前 Adapter + Host 實作形態。

### Deferred（暫緩）

- Garmin 尚未導入，目前不在本期交付範圍。

## 1. 專案定位

ZoneTruth 是一個 iOS 運動分析工具。

核心目的不是排課，也不是一般健身紀錄，而是：

> 匯入 Apple Health 運動資料，推定「這堂運動較偏向的訓練刺激」是否符合使用者設定的訓練目的。

---

## 2. 核心問題

目前常見問題：

- 以為在做 Zone 2，實際落在 Zone 3
- 以為在做 HIIT，實際只是中強度有氧
- 重訓變成代謝型訓練，影響力量輸出
- 羽球、游泳、腳踏車被誤當成同一種有氧刺激

ZoneTruth 要解決的是：

> 運動後提供「刺激是否對齊目標」的判斷。

---

## 3. MVP 目標

第一版只回答一個問題：

> 這堂運動是否符合預期訓練目的？

支援四種目的：

1. Zone 2
2. VO2 / Interval
3. Strength
4. Activity / Skill

---

## 4. 資料來源

### Apple Health / HealthKit

需讀取：

- Workout type
- Start / end time
- Duration
- Heart rate samples
- Active calories
- Distance
- Swimming distance
- Cycling distance
- Average heart rate
- Max heart rate

第一版不處理：

- 飲食
- 睡眠
- 體重趨勢
- 社群功能
- 自動排課

### Garmin（目前狀態）

- 目前 **未導入 Garmin Connect API**，也沒有 Garmin adapter 實作。
- 現階段資料來源以 Apple Health、Strava、JSON 匯入為主。
- Garmin 先列為後續擴充項目，不放在第一版關鍵路徑。

未在本期導入 Garmin 的主要原因：

1. 第一版優先驗證「分析語意與判定可解釋性」，避免同時擴大資料來源與規則複雜度。
2. 既有 HealthKit + Strava 已可覆蓋多數目標使用情境，先完成品質穩定與語意一致性。
3. Garmin 串接需要額外 OAuth / API 契約與資料映射維護，會拉長 MVP 交付時間。

---

## 5. 使用流程

1. 使用者授權 HealthKit
2. App 匯入近期 workout
3. 使用者選擇某堂運動
4. 使用者指定該堂目標：
   - Zone 2
   - VO2 / Interval
   - Strength
   - Activity / Skill
5. App 分析實際心率與時間分布
6. 輸出：
   - Pass
   - Warning
   - Fail
7. 顯示原因與下次修正建議

---

## 6. 個人化 Zone 設定

### 初版預設

根據使用者手動設定：

- Resting HR
- Zone 2 lower bound
- Zone 2 upper bound
- Zone 4 threshold
- Zone 5 threshold

### 你的初始設定

- Zone 1: <110 bpm
- Zone 2: 110–125 bpm
- Zone 3: 126–140 bpm
- Zone 4: 141–155 bpm
- Zone 5: >155 bpm

注意：

> 這些只是初始值，之後要透過 drift test 校正。

---

## 7. 核心分析模組

### 7.1 Zone Distribution

計算每堂運動在各 Zone 的時間比例。

輸出範例：

```text
Zone 1: 34 min
Zone 2: 23 min
Zone 3: 7 min
Zone 4: 1 min
Zone 5: 0 min
7.2 Zone 3 Leakage Detector

目的：

判斷運動是否不小心落入 Zone 3。

規則初版：

Zone 3 時間 > 10%：Warning
Zone 3 時間 > 20%：Fail
Zone 3 + Zone 4 時間過高：Fail
7.3 Zone 2 Quality Check

適用：

腳踏車
游泳
快走

判斷：

平均心率是否在 Zone 2
是否長時間超過 Zone 2 上限
後半段心率是否明顯上升
是否有 drift

初版規則：

平均 HR 在 Zone 2：加分
Zone 3 leakage <10%：通過
Drift <5%：通過
Drift 5–7%：Warning
Drift >7%：Fail
7.4 Fake HIIT Detector

適用：

HIIT
間歇訓練
游泳 interval
腳踏車 interval

判斷：

是否有明顯高強度區段
是否進入 Zone 4 / Zone 5
高強度區段是否集中
是否只是長時間 Zone 3

初版規則：

Zone 4+ 時間 <5%：Fail
Zone 4+ 時間 5–10%：Warning
Zone 4+ 有明顯區段：Pass
7.5 Strength Session Check

適用：

傳統肌力訓練

判斷：

是否長時間維持高心率
是否變成代謝型訓練
組間是否有恢復跡象

初版規則：

平均 HR 90–115：正常
平均 HR 116–130：Warning
平均 HR >130：可能變成代謝型重訓

注意：

重訓單組心率衝到 140–150 是正常的，重點是組間是否下降。

7.6 Activity / Skill Classifier

適用：

羽球
球類
技術課

判斷原則：

不拿來當 Zone 2
不拿來當 VO2 主訓
標記為 Activity / Skill

輸出重點：

這堂課有活動與協調價值，但不應作為主要 Zone 2 或 VO2 訓練判斷。

8. 結果輸出格式（語意層）
Summary Card
Workout: Swimming
Primary Intent Baseline: Zone 2
Training Tendency: Mixed aerobic session
Goal Fit: 42%

Primary Findings:
- Zone 3 leakage elevated
- HR drift remained stable

Next Action:
- Reduce swim pace to remain below Zone 2 upper bound
9. App 架構
ZoneTruth
├── App
│   └── ZoneTruthApp.swift
│
├── HealthKit
│   ├── HealthKitManager.swift
│   ├── WorkoutFetcher.swift
│   └── HeartRateFetcher.swift
│
├── Models
│   ├── WorkoutSummary.swift
│   ├── HeartRateSample.swift
│   ├── TrainingZone.swift
│   ├── WorkoutIntent.swift
│   └── AnalysisResult.swift
│
├── Analyzer
│   ├── ZoneDistributionAnalyzer.swift
│   ├── Zone2QualityAnalyzer.swift
│   ├── Zone3LeakageAnalyzer.swift
│   ├── FakeHIITAnalyzer.swift
│   └── StrengthAnalyzer.swift
│
├── Recommendation
│   └── RecommendationEngine.swift
│
├── UI
│   ├── WorkoutListView.swift
│   ├── WorkoutDetailView.swift
│   ├── IntentPickerView.swift
│   ├── AnalysisResultView.swift
│   └── SettingsView.swift
│
└── Tests
    ├── ZoneDistributionAnalyzerTests.swift
    ├── Zone2QualityAnalyzerTests.swift
    └── FakeHIITAnalyzerTests.swift

註：
以上為初版概念架構。實際 repo 已演進為 `ZoneTruthCore` + `ZoneTruthApp` + `ZoneTruthHost`（adapter 邊界 + host app capability wrapper）模式，後續需以實作結構回寫本節。
10. 近期開發順序（Next Sprint）

Phase A：語意層穩定化（最高優先）

目標：

- 穩定 `WorkoutEvaluationAdapter` 輸出語意，避免前後矛盾。
- 固化 semantic guard 與 fixture snapshot，讓 UI 與語意層解耦。

完成標準：

- 關鍵案例 fixture 全通過（Zone2 偏離、VO2 達標、Strength 代謝循環、Activity、Sparse HR）。
- `keyFindings`、`nextAction`、confidence 雙軸輸出行為穩定且可回歸驗證。

Phase B：資料品質與裝置驗證閉環

目標：

- 在真機驗證 HealthKit/Strava 匯入流程與 sparse/missing HR 處理。
- 針對不同 workout type 進行資料品質分層檢查。

完成標準：

- 可穩定讀取近期運動與 HR 樣本。
- 資料不足時有一致的 fail-closed 與可解釋輸出。

Phase C：分析訊號擴充（從 HR-only 走向多訊號）

目標：

- 將 active calories、distance、swim/cycle distance、avg/max HR 導入判斷輔助層。
- 維持 `ZoneTruthCore` 與平台 adapter 邊界清晰。

完成標準：

- 新增訊號不破壞既有判定回歸。
- 新訊號在理由/建議中可被解釋，不只是內部分數加權。

Phase D：UI 首屏重排（語意層穩後才做）

目標：

- 以「主結論 + 目標符合度 + 下一步動作」取代 metrics-first 讀取路徑。
- 將技術細節下沉到可收合區塊。

完成標準：

- 第一屏可在 3 秒內回答「這次像什麼」「我下次怎麼做」。
- 進階指標保留但不干擾主決策流程。
11. 第一版不做的事
不做 AI 教練
不自動排課
不做飲食追蹤
不做社群
不做排行榜
不做複雜週期化
不預測死亡率

原因：

第一版只做「運動目的與實際刺激是否一致」。

12. Phase 5：Semantic Consistency & Evaluation Layer（進行中）

目標：

- 將 legacy analyzer 輸出穩定映射到語意層（`PrimaryIntent baseline`、`trainingTendency`、`goalFitScore`）。
- 將 `classificationConfidence` 與 `evaluationConfidence` 分離，避免語意誤導。
- 建立 fixture snapshot + semantic guard，防止輸出語意漂移。

完成標準：

- `WorkoutEvaluationAdapter` 輸出欄位穩定，且有 snapshot fixture 保護。
- 關鍵案例（Zone2 偏離、VO2 達標、Strength 代謝循環、Activity、Sparse HR）可重現且可比對。

13. P1i：Observation-to-Policy Migration Gate（下一步）

定位：

- Observation layer 已具備 coverage discipline，但尚未成為 production authority。
- 本階段不直接切換執行路徑，先定義「何時允許有意圖地改變」。

Migration Gate（需同時滿足）：

1. Primitive snapshots 穩定（無非預期 diff）。
2. 四種 observation snapshots 穩定（Zone2 / VO2 / Strength / Activity）。
3. Evaluation snapshot 無 drift（`workout_evaluation_snapshot.json` 無非預期 diff）。
4. Policy 可直接 consume observation（不再依賴 legacy `AnalysisResult`）。
5. Fallback path 明確保留，且可在一次變更內回退。

治理附加條件：

6. 所有 snapshot 更新需帶 `change-intent annotation`（說明預期變更與影響面）。
7. 採用 migration mode 三段切換：
   - `observe_only`
   - `dual_run`
   - `policy_primary`

完成標準：

- 形成可執行 migration checklist（可用於 PR gate / closeout gate）。
- 在不破壞現有語意穩定性的前提下，允許有意圖的 policy 切換。

14. P1n：Migration Gate Full Condition Verification（完成）

定位：

- 把「能不能討論 policy_primary」變成可執行 checklist，不靠人工印象。
- 五個條件 + fallback path sub-checks，全部機器可驗。

9 個 check ID：

1. `primitive_snapshots_stable` — swift test PrimitiveBuilder
2. `observation_snapshots_stable` — swift test Zone2/VO2/Strength/Activity Observation
3. `evaluation_snapshot_stable_or_annotated` — swift test snapshot fixture 或有 SEM-*.json
4. `shadow_policy_consumes_observation` — shadow/legacy tendency 一致（in-process）
5. `policy_primary_disabled_by_default` — SettingsManager 預設 observeOnly
6. `policy_primary_requires_explicit_allow` — updateMigrationMode(.policyPrimary) 被攔截
7. `dual_run_revertible_to_observe_only` — dual_run → observe_only 可回退
8. `observe_only_never_writes_dual_run_artifact` — structural guard in ViewModels
9. `ui_path_forces_legacy_evaluation` — evaluationResult 永遠走 legacy

輸出：`artifacts/migration/migration_gate_report.json`

關鍵約定：

- `policy_primary_admissible`: 永遠 `false`（v1 硬碼）
- `policy_primary_admissible_for_discussion`: 全通過才 `true`

腳本：`scripts/run_migration_gate.sh`

15. P1m：Semantic Change Annotation Gate（完成）

定位：

- 解決「合理 drift」與「偷改產品語意」混在一起的治理風險。
- 任何 evaluation snapshot 更新都必須伴隨結構化 `SemanticChangeAnnotation`。

Annotation schema：

```json
{
  "change_id": "SEM-YYYY-MM-DD-NNN",
  "reason": "...",
  "affected_fixtures": ["..."],
  "expected_behavior_change": ["..."],
  "reviewed_by": "manual",
  "admissibility": "intentional_semantic_change | observation_refinement | bug_fix"
}
```

Admissibility 規則：

- snapshot changed + 無 annotation → `requiresAnnotation`（closeout fail）
- `blocking_drift` + admissibility ≠ `intentional_semantic_change` → `blockedByAdmissibility`（closeout fail）
- `review_required` 或 `minor_drift` + 任意有效 annotation → `admissible`

完成標準：

- `AnnotationGate.validate()` 覆蓋所有 admissibility 分支，guard tests 全通過。
- Closeout script 在 `snapshot_fixture=changed` 時自動觸發 annotation gate。
- `artifacts/semantic_changes/SEM-TEMPLATE.json` 為規範格式。

15. P1l：ObservationBridge + Shadow Evaluator Rewiring（完成）

定位：

- `ObservationPolicyShadowEvaluator` 原本手寫 inline scoring，與 `WorkoutEvaluationPolicyFactory` 邏輯重複且略有差異。
- P1l 新增 `ObservationBridge`，統一橋接 `WorkoutObservationPrimitives` → `WorkoutObservation`，並讓 shadow path 走相同 policy factory。

完成標準：
- `ObservationBridge.observation(from:intent:)` 為唯一 primitives → observation 橋接路徑。
- `ObservationPolicyShadowEvaluator` 移除 hand-coded scoring，改呼叫 `WorkoutEvaluationPolicyFactory`。
- Shadow 與 legacy 在相同 Zone 2 穩定案例上 tendency 必須一致（guard test）。
- 乾淨 Zone 2 案例的 dual-run diff 為 `minor_drift`。

15. P1j：Dual-run Admissibility Guard（完成）

定位：

- `dual_run` 只允許作為觀察差異的 admissible path。
- 不允許成為 product behavior authority。

規則：

1. `observe_only` 不產生 dual-run shadow artifact。
2. `dual_run` 可產生 artifact，但 UI `evaluationResult` 仍使用 legacy path。
3. `policy_primary` 需明確 gate，禁止 accidental enable。
4. artifact 必須包含 `migrationMode`、`generatedAt`、`totalWorkouts`。
5. artifact 不得帶入 user-facing override（例如 recommendation override）。

Dual-run 差異解讀契約（P1k）：

- `goalFitDelta <= 5`：`minor_drift`
- `goalFitDelta 6–15`：`review_required`
- `goalFitDelta > 15`：`blocking_drift`
- `tendencyChanged == true`：`review_required`
- `userFacingOverrideApplied == true`：`invalid_report`

Closeout Gate：

- `blocking_drift` 或 `invalid_report` 時，closeout fail。
- 不可自動宣稱 shadow 比 legacy 更正確，只能聲明差異已記錄與分級。


Project name：**ZoneTruth**  
副標可以用：**Train with intent. Verify with data.**
