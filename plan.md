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
> **最後更新**: 2026-06-03
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

本次治理同步（2026-06-03）：
- [x] 確認 `ai-governance-framework` upstream 最新快照為 `70a54b3`
- [x] dry-run adopt / readiness 分析，確認安全導入不會覆寫既有 repo-local 治理檔
- [x] 補齊缺漏 governance 文件並修正 `contract.yaml` repo identity
- [x] 更新 framework lock 與 baseline freshness

下一個產品優先建議：
- [ ] 進入 P1「個人化 zone 界線設定」切一個可用垂直 slice：使用者輸入 Resting HR / Zone 2 上下界 → 分析器採用自訂界線 → 週報顯示已套用個人化設定

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
- 個人化 zone 界線設定（Resting HR、Zone 2 上下界輸入）
- 擴充邊緣案例標籤集（drift / leakage 閾值附近）
- VO2/強度分析路徑擴充（超出「MVP 範圍外」佔位符後）

### P2（非阻擋，有空再做）
- Meta-closeout wrapper（一個指令跑全套 governance regression checks）
- CodeBurn P6：acquisition surface statistics display（觀測層，需遵守 A-1/T-1/C-1/R-1/O-1/V-1 約束）
- 文字/UI 語氣精修

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

### Phase E 完成條件（待定義）
- on-device HealthKit 路徑驗證 pass
- Strava 真實憑證端對端 pass
- `ZoneTruthHost` 裝置簽署確認

---

## 已知問題與技術債

| 項目 | 狀態 | 優先 |
|---|---|---|
| `artifacts/governance/version_compatibility.json` 時間戳未提交 | 待提交 | Low |
| `PLAN.md` 過去為樣板文件，實質規劃缺失 | 已修正（本次） | Done |
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
| 2026-06-03 | 同步 ai-governance-framework 最新 baseline（70a54b3）導入分析；補齊缺漏治理文件、修正 contract identity、刷新 PLAN freshness |
| 2026-05-26 | Phase E 全部完成：HealthKit、Strava OAuth、ZoneTruthHost 裝置驗證均通過 |
| 2026-05-26 | 全面重寫：從樣板文件改為實質專案計劃；導入當前 phase 狀態、backlog、anti-goals、gate 條件 |
| 2026-05-25 | 對齊 header 欄位（最後更新 / Owner / Freshness）；加入 gitignore runtime artifacts |
