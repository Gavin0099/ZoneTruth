---
audience: agent-runtime
authority: canonical
can_override: false
overridden_by: ~
default_load: always
---

# PLAN.md — ZoneTruth

> **Project Type**: iOS fitness app + governance toolchain
> **Primary Language**: Swift (app core) / Python (governance tooling)
> **Task Level**: L2
> **Planning Window**: 2026-04-01 ~ 2026-06-30
> **最後更新**: 2026-06-09
> **Owner**: Gavin Wu
> **Freshness**: Sprint (7d)

---

## 專案目標

ZoneTruth 是一款 iOS/macOS 訓練分析應用，專注於 Zone 2 訓練品質判斷、多週適應趨勢、以及跨資料源整合。

**Bounded Context:**
- Zone 2 / VO2 / 肌力訓練品質分析（觀測層 + 政策層分離）
- Apple HealthKit、Strava、JSON 手動匯入整合
- 每週適應訊號與訓練狀態推論（non-interventional authority ceiling）
- AI 代理 token 可觀測性工具（CodeBurn，Class C 觀測，不跨 provider 比較）

**Not Responsible For:**
- 即時運動監控或即時 coaching
- Garmin 整合（明確延後至 MVP 後）
- 計費計算或 cross-provider token 成本估算（CodeBurn P6 constraint C-1）
- 訓練計劃生成（不在當前語義權限內）

---

## 當前階段與 phase 狀態

- [x] Phase A: 核心分析引擎建立（Zone 2 / VO2 / 強度分析器，觀測 + 政策層分離）
- [x] Phase B: App 資料源整合（HealthKit adapter、Strava OAuth + 自動 refresh、JSON import）
- [x] Phase C: 語義治理層（WorkoutEvaluation、InferenceProvenance、weekly signal 遷入 Core）
- [x] Phase D: 治理邊界強化（boundary guard 規則化、遙測、clean-pilot admissibility）
- [x] Phase E: 裝置驗證 + 發版準備（on-device HealthKit、Strava 真實憑證測試）

**Current Phase**: Phase E 完成 — 進入 P1 品質提升 / 發版準備

---

## 當前 Sprint / 當前工作

本次產品規格同步（2026-06-09）：
- [x] 將訓練分析 v3 修訂為 v3.1 執行版：正式採用 C 路線（Apple Watch 活動類型 + 心率特徵反推本次訓練型態）
- [x] 新增 `docs/TRAINING_CLASSIFICATION_PLAN_V3_1.md`，明確列出 Sprint 0、不要動清單、Swift Core classification object、資料品質下界、重訓例外優先與本週頁純描述規則
- [x] 確認 v3.1 是規格/計畫同步，不改產品行為、analyzer verdict、weekly rendering contract
- [x] Sprint 1 信任止血 UI：移除 user-facing `本次意圖`、`目的符合度`、`舊版判定`，並避免重訓第一屏出現 VO2 max 主卡
- [x] Sprint 2 Core classification object：在 `ZoneTruthCore` 建立 Swift `TrainingClassification` output contract（mode / confidence / data quality / claim level / evidence / warnings / not-applicable reasons / debug）
- [x] Sprint 3 rule-based classifier aggregator：在 `ZoneTruthCore` 新增 Core-only `TrainingModeClassifier`，輸出 `TrainingClassification`；先驗證資料不足、重訓 high-HR conditioning-like 例外、典型重訓 strengthPattern
- [x] Sprint 4 Core weekly training-mode distribution：新增 `WeeklyTrainingModeDistributionBuilder`，以 `TrainingModeClassifier` 聚合本週 counts / ratios / descriptive lines；測試鎖住不出現「偏少 / 不足 / 達標」等週目標評價語
- [x] Sprint 5 游泳特殊分類：補 Core guard tests，鎖住 swimming 即使呈現 Zone 2 / VO2-like 心率，也只能輸出 low data quality / low confidence / secondary reference；sparse swimming 仍為 insufficientData
- [ ] 下一步 Sprint 6：分類回饋 / 校準機制（先定義回饋資料形狀，不回填使用者意圖）

本次治理同步（2026-06-09）：
- [x] 對齊 `ai-governance-framework` upstream 到 `9eb793dbf6c6`（沿用 adopt + lock 模式，非 submodule pointer）
- [x] 補入新拆分的治理 routing / protocol 文件：`AI_GOVERNANCE_UPDATE_PROTOCOL.md`、`F7_FULL_UPDATE.md`、`GOVERNANCE_SURFACE_RULES.md`、`MEMORY_PROTOCOL.md`
- [x] 刷新 `.governance/baseline.yaml` 與 `governance/framework.lock.json`
- [x] 保持產品行為、analyzer verdict、weekly rendering contract 不變

前次治理同步（2026-06-05）：
- [x] 對齊 `ai-governance-framework` upstream 到 `cae11be`（沿用 adopt + lock 模式，非 submodule pointer）
- [x] 補入適用於非-submodule consuming repo 的新增治理 surface：`claim_enforcement_receipt_validator.py`、`external_governance_submodule_updater.py`、`update-governance-submodule.ps1`、`governance_scope.local.example.yaml`、F-7 updater docs
- [x] 刷新 `AGENTS.base.md`、`.governance/baseline.yaml`、`governance/framework.lock.json`
- [x] 修正 `expansion_boundary_checker.py` 與新版 governance surface 的相容性，確認 drift clean

前次治理同步（2026-06-04）：
- [x] pull `ai-governance-framework` 最新 upstream 到 `0ae039e`
- [x] 正式 adopt 最新 baseline，新增 `governance/RESPONSE_ENVELOPE_CONTRACT.md`，刷新 `.governance/baseline.yaml`
- [x] 更新 `governance/framework.lock.json` adopted commit 到 `0ae039e`
- [x] readiness / drift / version audit 全部通過；response envelope validator valid fixtures 通過

前次治理同步（2026-06-03）：
- [x] 確認 `ai-governance-framework` upstream 最新快照為 `70a54b3`
- [x] dry-run adopt / readiness 分析，確認安全導入不會覆寫既有 repo-local 治理檔
- [x] 補齊缺漏 governance 文件並修正 `contract.yaml` repo identity
- [x] 更新 framework lock 與 baseline freshness

本次產品切片（2026-06-03）：
- [x] 完成 P1「個人化 zone 界線設定」垂直 slice：使用者輸入 Resting HR / Zone 2 上下界 → 分析器採用自訂界線 → 週報與單筆詳情顯示已套用個人化設定
- [x] 支援 Resting HR 產生 Zone 2 起始建議、來源 / 非驗證閾值標示、套用建議、重設回預設界線
- [x] 支援 Resting HR 建議公式上下偏移量調整，並在設定頁顯示目前 Zone 2 設定狀態摘要

本次研究切片（2026-06-04）：
- [x] 完成 Training Analysis Literature Review：VO2 max / Zone 2 / Strength 分層整理 gold standard anchor、field estimator、product reference、claim ceiling 與 confidence basis
- [x] 將 literature review 轉成 `TRAINING_ANALYSIS_META_SPEC.md`：定義 shared metric metadata、confidence ladder、claim ceiling、UI wording rules 與 implementation sequence
- [x] Slice 1「Core Metadata Types」：新增 method tier / source / reference-standard distance / confidence / claim ceiling metadata 型別，不改 analyzer verdict
- [x] Slice 2「Analyzer Adapter Metadata」：讓 Zone 2 / VO2 / Strength analyzer result 產出 metadata，但不改既有 verdict threshold；現有 VO2 analyzer 標示為 `vo2_interval_quality`，不宣稱 VO2 max
- [x] Slice 3「UI Disclosure」最小切片：在單筆分析結果揭露 estimate / measured 狀態與 confidence reason；不改 weekly rendering contract
- [x] Slice 4「Metric-specific Claim Profiles + Guard Tests」：新增 VO2 / Zone 2 / Strength claim profiles，並驗證 UI disclosure 不混淆 metric-specific claim ceiling
- [x] Weekly disclosure preflight guard：新增 weekly rendering contract guard，禁止 weekly UI / presenter 出現 metric measurement overclaim
- [x] Test Candidate 2026-06-04：整理可測範圍、不可宣稱範圍、local smoke commands 與 manual test checklist
- [x] 測試策略調整：正式產品測試延後到 VO2 max / Zone 2 / Strength 三類功能完整；目前 checkpoint 僅作 developer verification
- [x] VO2 max scalar estimate/import vertical slice：JSON / domain model 可攜帶 VO2 max estimate，單筆 UI 顯示估算值與 source / claim-bounded disclosure；現有 VO2 interval quality 不被誤當 VO2 max
- [x] Strength metric vertical slice：JSON / domain model 可攜帶 structured strength metrics，單筆 UI 顯示 exercise-specific direct 1RM / e1RM 類值與 claim-bounded disclosure；heart-rate-only Strength 仍保留 session-pattern claim ceiling
- [x] 下一步：跑完整 local smoke / meta-closeout，準備第一個 owner acceptance 測試候選

已完成（Phase D）：
- [x] App-test / App-source boundary guard 規則化（`app_test_boundary_rules` / `app_source_boundary_rules`）
- [x] 邊界 guard 設定遷至 JSON 單一來源（`scripts/closeout_boundary_patterns.json`）
- [x] JSON schema 驗證（`schemas/closeout_boundary_patterns.schema.json`）
- [x] 境界 guard 遙測排放（`artifacts/runtime/boundary-telemetry/`）
- [x] 邊界趨勢閘道整合 closeout（threshold 控制 + fail-close）
- [x] Clean-pilot admissibility 整合 closeout（disclosed guard + optional enforce mode）
- [x] Enforce-mode smoke test（`scripts/closeout_clean_pilot_enforce_smoke.sh`）
- [x] 10 個 GovernanceBoundaryGuardTests 全部通過

已完成（Phase E P0）：
- [x] 裝置端 HealthKit 授權 → 載入訓練 → 週報儀表板驗證（2026-05-26）
- [x] ZoneTruthHost HealthKit capability 簽署確認（裝置可正常啟動）
- [x] 使用者可見字串全面繁體中文化（e4510c3，185/185 tests pass）

已完成（Phase E P0 全部）：
- [x] Strava OAuth 端對端測試（Client ID: 248735，redirect URI: zonetruth://localhost）

---

## Backlog

### P0（Phase E 就緒必要條件）
- [x] 裝置端 HealthKit 查詢路徑驗證（真實裝置，sparse HR 邊界）
- [x] Strava 真實憑證端對端測試（Client ID: 248735，redirect URI: zonetruth://localhost）
- [x] `ZoneTruthHost` Xcode project 在裝置上確認 HealthKit 能力簽署正確

### P1（Phase E 品質提升）
- [x] 個人化 zone 界線設定（Resting HR、Zone 2 上下界輸入、建議 / 套用 / 重設 / 狀態摘要）
- [x] 擴充邊緣案例標籤集（drift / leakage 閾值附近）
- [x] VO2/強度分析路徑擴充（接入 interval pattern / recovery hint 觀測訊號到 user-facing reasons）
- [x] Training Classification v3.1 Sprint 1：信任止血 UI，先修正 user-facing 語義，再進 Core classification object
- [x] Training Classification v3.1 Sprint 2：Core classification object
- [x] Training Classification v3.1 Sprint 3：rule-based classifier aggregator
- [x] Training Classification v3.1 Sprint 4：本週分類分布（descriptive only）
- [x] Training Classification v3.1 Sprint 5：游泳特殊分類與資料品質下界
- [ ] Training Classification v3.1 Sprint 6：回饋與校準

### P2（非阻擋，有空再做）
- [x] Meta-closeout wrapper（一個指令跑常用 governance / syntax / targeted smoke checks）
- [x] CodeBurn P6：acquisition surface statistics display（觀測層，遵守 A-1/T-1/C-1/R-1/O-1/V-1 約束）
- [x] 文字/UI 語氣精修（Zone 2 / VO2 / Strength reasons 與 recommendations 降低高宣稱 / 命令式語氣）

---

## Anti-Goals（當前 sprint / Phase D～E）

- 不實作 Garmin 整合（明確延後至 MVP 後語義/model 穩定）
- 不實作成本估算、跨 provider token 比較（CodeBurn P6 constraint C-1 / O-1）
- 不把 advisory threshold 升格為 verified boundary（CodeBurn P7 AT-4）
- 不在 App layer 重新加入 inference 語義分類呼叫（已由 Core 負責，boundary guard 防線保護）
- 不在沒有 observed failure 驅動下擴展治理表面（AGENTS.md 原則）
- 不在 Phase E 開始前做 feature expansion

---

## AI 執行規則

1. **當前 phase 外的 feature** → escalate，不默默開始
2. **adjacent engineering**（build / test / debug / docs sync / governance analysis）→ 可直接做
3. **遇到 PLAN.md 不完整或過期** → 先更新 PLAN.md，再繼續
4. **boundary guard 相關測試** → 任何改動都要跑 `swift test --filter GovernanceBoundaryGuardTests`
5. **closeout 相關腳本改動** → 要跑 `bash -n scripts/closeout_workout_evaluation.sh`
6. **App layer 不得** 呼叫 inference 語義分類 / 產生 provenance（boundary guard 負責檢查）
7. **CodeBurn 工作** → 嚴格遵守 P6 六大約束（A-1、T-1、C-1、R-1、O-1、V-1）

---

## Gate / 完成條件

### Phase D 完成條件（已達成）
- [x] GovernanceBoundaryGuardTests 10 tests, 0 failures
- [x] `bash -n scripts/closeout_workout_evaluation.sh` SYNTAX OK
- [x] boundary telemetry artifact 存在於 `artifacts/runtime/boundary-telemetry/`
- [x] clean-pilot admissibility smoke 可執行（enforce 模式）

### Phase E 開始條件
- [x] `version_compatibility.json` 時間戳變更已提交（928f835）
- [x] Phase D 記憶文件已更新（7fd8a09）

### Phase E 完成條件（已達成）
- [x] on-device HealthKit 路徑驗證 pass
- [x] Strava 真實憑證端對端 pass
- [x] `ZoneTruthHost` 裝置簽署確認

---

## 已知問題與技術債

| 項目 | 狀態 | 優先 |
|---|---|---|
| `artifacts/governance/version_compatibility.json` 時間戳未提交 | 待提交 | Low |
| `PLAN.md` 過去為樣板文件，實質規劃缺失 | 已修正（本次） | Done |
| P1 個人化 zone 界線設定 | 已完成（Resting HR 建議 / 套用 / 重設 / 狀態摘要） | Done |
| P1 drift / leakage 邊緣案例標籤 | 已完成（10%/20% leakage、5%/8% drift 邊界提示） | Done |
| P1 VO2/強度分析路徑擴充 | 已完成（VO2 interval pattern、Strength recovery hint reason） | Done |
| P2 meta-closeout wrapper | 已完成（`bash scripts/meta_closeout.sh`） | Done |
| P2 文字/UI 語氣精修 | 已完成（Zone 2 / VO2 / Strength user-facing reasons 與 recommendations 降低高宣稱 / 命令式語氣） | Done |
| P2 CodeBurn P6 acquisition surface statistics display | 已完成（structural observation only；不做成本 / 跨 provider 比較 / efficiency / optimization） | Done |
| Training Analysis Literature Review | 已完成（VO2 max / Zone 2 / Strength evidence hierarchy、claim ceiling、confidence basis） | Done |
| Training Analysis Meta-Spec | 已完成（shared metadata schema、confidence ladder、claim ceiling、UI wording rules、implementation sequence） | Done |
| Training Analysis Core Metadata Types | 已完成（method tier / source / reference-standard distance / confidence / claim ceiling 型別與 targeted tests） | Done |
| Training Analysis Analyzer Adapter Metadata | 已完成（Zone 2 / VO2 interval quality / Strength result metadata；不改 verdict threshold） | Done |
| Training Analysis UI Disclosure | 已完成最小切片（單筆分析揭露 estimate / measured 與 confidence reason；不改 weekly rendering） | Done |
| Training Analysis Claim Profiles / Guards | 已完成（metric-specific claim profiles；guard tests 防止 UI disclosure 混淆 VO2 / Zone 2 / Strength） | Done |
| Weekly disclosure preflight guard | 已完成（weekly rendering contract 禁止 metric measurement overclaim；未改 weekly UI） | Done |
| Test Candidate 2026-06-04 | 已升級為 local product acceptance candidate（VO2 max / Zone 2 / Strength 最小 feature gate 完成；尚未產生 TestFlight build） | Done |
| VO2 max feature-complete slice | 已完成最小切片（scalar estimate/import + source labeling + claim-bounded disclosure；不做 lab-equivalent claim） | Done |
| Strength feature-complete slice | 已完成最小切片（direct 1RM / e1RM structured metric import/display + claim-bounded disclosure；不做全身/臨床肌力診斷） | Done |
| Zone 2 feature-complete gate | 大致完成（manual bounds / Resting HR / reset / single + weekly policy；需維持非 exact threshold claim） | P1 |
| Daily memory closeout format | 已標準化（commit/push 狀態、claim ceiling、not-claimed、workspace/remote state 分欄） | Done |
| `memory/00_long_term.md` 不存在（AGENTS.md 要求） | 待建立 | P1 |
| clean-pilot admissibility 顯示 `false`（unclassified paths 4 個） | 已解決（git 現況只剩 1 個修改） | Resolved |
| Garmin 整合尚未啟動 | 明確延後 | Deferred |

---

## 里程碑

| 里程碑 | 目標日期 | 狀態 |
|---|---|---|
| Phase A: 分析引擎完成 | 2026-04-30 | ✅ Done |
| Phase B: 資料源整合完成 | 2026-05-10 | ✅ Done |
| Phase C: 語義治理層完成 | 2026-05-20 | ✅ Done |
| Phase D: 治理邊界強化完成 | 2026-05-26 | ✅ Done |
| Phase E: 裝置驗證 + 發版準備 | 2026-05-26 | ✅ Done |

---

## 更新紀錄

| 日期 | 更新內容 |
|---|---|
| 2026-06-09 | 完成 Training Classification v3.1 Sprint 2：新增 Core `TrainingClassification` / `TrainingMode` / confidence / data quality / claim level / evidence / warnings / not-applicable / debug 型別與 Codable guard tests；尚未接入 analyzer |
| 2026-06-09 | 完成 Training Classification v3.1 Sprint 1 信任止血 UI：單次詳情移除本次意圖 / 目的符合度 / 舊版判定，重訓主要 metric surface 不顯示 VO2 max；新增 targeted UI guard tests |
| 2026-06-09 | 新增 Training Classification Plan v3.1：正式採用 C 路線（資料反推訓練型態），補 Sprint 0、不要動清單、Core classification object、資料品質下界與純描述週分布規則；不改產品行為 |
| 2026-06-09 | 同步 ai-governance-framework 最新 upstream（`9eb793dbf6c6`）：導入拆分後的 AI Governance update / F-7 / governance surface / memory protocol 文件，刷新 baseline / framework lock；產品行為不變 |
| 2026-06-05 | 同步 ai-governance-framework 最新 upstream（`cae11be`）導入分析；補入非-submodule consuming repo 適用的治理工具與 F-7 文件，刷新 baseline / framework lock，drift clean / readiness 通過 |
| 2026-06-04 | 完成 Strength structured metric 最小切片：JSON / domain model / metadata / 單筆 UI disclosure 支援 direct 1RM / e1RM 類肌力指標，並保留 exercise-specific claim ceiling |
| 2026-06-04 | 完成 VO2 max scalar estimate/import 最小切片：JSON / domain model / metadata / 單筆 UI disclosure 支援 VO2 max estimate，並保留 estimate-only claim ceiling |
| 2026-06-04 | 調整測試策略：正式產品測試延後到 VO2 max / Zone 2 / Strength 三類 feature-complete；目前 Test Candidate 僅作 developer checkpoint |
| 2026-06-04 | 建立 Test Candidate 2026-06-04：整理目前可本機測試範圍、claim ceiling、local smoke command 與 manual checklist |
| 2026-06-04 | 完成 weekly disclosure preflight guard：新增 WeeklyRenderingContractTests，禁止 weekly rendering 出現 VO2 max 實測、精準 Zone 2、1RM/肌力測量等過度宣稱 |
| 2026-06-04 | 完成 Training Analysis Slice 4 Claim Profiles / Guard Tests：新增 metric-specific claim profiles，修正 Zone 2 驗證提示誤判 CPET 的 UI 文案風險 |
| 2026-06-04 | 完成 Training Analysis Slice 3 UI Disclosure 最小切片：單筆分析結果顯示 estimate / measured 與 confidence reason，targeted tests 驗證不含過度宣稱 |
| 2026-06-04 | 標準化 daily memory closeout format：拆分 commit/push status，補 claim ceiling、not-claimed、workspace_state 與 remote_state |
| 2026-06-04 | 完成 Training Analysis Slice 2 Analyzer Adapter Metadata：Zone 2 / VO2 interval quality / Strength 分析結果附帶 metadata，不改 verdict threshold 或 UI rendering |
| 2026-06-04 | 完成 Training Analysis Slice 1 Core Metadata Types：新增 method tier / source / reference-standard distance / confidence / claim ceiling 型別與 targeted tests，不改 analyzer verdict |
| 2026-06-04 | 完成 Training Analysis Meta-Spec：將 literature review 轉成 shared metric metadata、confidence ladder、claim ceiling、UI wording rules 與四段 implementation sequence |
| 2026-06-04 | 同步 ai-governance-framework 最新 upstream（0ae039e）：導入 response envelope contract、刷新 baseline / framework lock，readiness、drift、version audit 通過 |
| 2026-06-04 | 完成 Training Analysis Literature Review：整理 VO2 max / Zone 2 / Strength 的學術/臨床標準、field estimator、產品對照與 ZoneTruth claim ceiling |
| 2026-06-03 | 完成 P2 CodeBurn P6 acquisition surface statistics display：新增 fixture/demo CLI 與 targeted tests，輸出 surface record/source/quarantine 摘要並保留 A-1/T-1/C-1/R-1/O-1/V-1 約束 |
| 2026-06-03 | 完成 P2 文字/UI 語氣精修：Zone 2 / VO2 / Strength 分析 reasons、recommendations 與 evaluation nextAction 改為觀測 / 建議語氣，新增 targeted tone tests |
| 2026-06-03 | 完成 P2 meta-closeout wrapper：新增 `bash scripts/meta_closeout.sh` 一鍵跑 syntax、runtime governance smoke、boundary guard 與 weekly UI smoke |
| 2026-06-03 | 完成 P1 VO2/強度分析路徑擴充：VO2 analysis 顯示 interval pattern hint，Strength analysis 顯示 recovery pattern hint |
| 2026-06-03 | 完成 P1 drift / leakage 邊緣案例標籤：Zone 3 leakage 10%/20% 與 heart-rate drift 5%/8% 附近會產生低宣稱提示 |
| 2026-06-03 | 完成 P1 個人化 Zone 2 設定產品線：Resting HR 輸入、建議公式、偏移量調整、套用 / 重設、週報與單筆詳情顯示、設定狀態摘要 |
| 2026-06-03 | 同步 ai-governance-framework 最新 baseline（70a54b3）導入分析；補齊缺漏治理文件、修正 contract identity、刷新 PLAN freshness |
| 2026-05-26 | Phase E 全部完成：HealthKit、Strava OAuth、ZoneTruthHost 裝置驗證均通過 |
| 2026-05-26 | 全面重寫：從樣板文件改為實質專案計劃；導入當前 phase 狀態、backlog、anti-goals、gate 條件 |
| 2026-05-25 | 對齊 header 欄位（最後更新 / Owner / Freshness）；加入 gitignore runtime artifacts |
