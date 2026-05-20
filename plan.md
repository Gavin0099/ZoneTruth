# ZoneTruth - iOS Workout Intent Analyzer Plan
> **最後更新**: 2026-05-20
> **Owner**: Gavin
> **Freshness**: Sprint (7d)

## 1. 專案定位

ZoneTruth 是一個 iOS 運動分析工具。

核心目的不是排課，也不是一般健身紀錄，而是：

> 匯入 Apple Health 運動資料，判斷「這堂運動的實際刺激」是否符合使用者原本設定的訓練目的。

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

8. 結果輸出格式
Summary Card
Workout: Swimming
Target: Zone 2
Result: Fail

Reason:
- Average HR 134 bpm, above Zone 2 upper bound
- Zone 3 leakage too high
- Session intensity stayed in gray zone

Suggestion:
- Next Zone 2 swim: keep HR below 120 bpm
- Or change this session into interval swim
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
10. 第一階段開發順序
Phase 1: HealthKit 匯入

目標：

授權 HealthKit
取得 workout list
取得 heart rate samples
顯示基本運動資料

完成標準：

可看到近期運動列表
可點進單一 workout
可看到心率資料
Phase 2: Zone 分析

目標：

建立個人 zone 設定
計算 zone distribution
顯示每個 zone 時間

完成標準：

每堂運動能顯示 Zone 1–5 時間分布
Phase 3: Intent Match

目標：

使用者選擇該堂目的
App 根據目的判斷 Pass / Warning / Fail

完成標準：

Zone 2 / VO2 / Strength / Activity 都有基本判斷
Phase 4: Recommendation

目標：

依據失敗原因給建議

完成標準：

不只顯示結果，也能說明「為什麼」與「下次怎麼修」
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


Project name：**ZoneTruth**  
副標可以用：**Train with intent. Verify with data.**
