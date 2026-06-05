# Owner Acceptance 2026-06-05

Status: local owner acceptance flow  
Audience: owner / local tester  
Scope: `Zone 2` / `VO2 max` / `肌力`

## 這份要回答什麼

這輪不是在驗證學術正確性，也不是在做 TestFlight 發版檢查。

這份流程只回答 3 件事：

1. 使用者能不能看懂目前狀態
2. 三類分析能不能穩定顯示
3. app 有沒有避免過度宣稱

## 測試前準備

1. 確認 app 可正常 build / run
2. 確認 sample seed 已存在，或 app 第一次啟動會自動載入 sample workouts
3. 若要測 Apple Health 實機資料：
   - 允許 `心率`、`靜息心率`、`VO2 max`、`路線`
   - 若可得，也允許 `跑步功率`、`自行車功率`
4. 若只做 owner acceptance，先以 app 內 sample + 已有 HealthKit 資料為主，不必另外準備 Garmin 或 TestFlight

## 先跑一次最小檢查

先執行：

```bash
bash scripts/meta_closeout.sh
```

預期：

- `syntax` checks 全部 `PASS`
- `claim enforcement receipt validator` 為 `PASS`
- `overall: PASS`

## 主測流程

### 1. Zone 2

1. 打開一筆偏低到中等強度的有氧訓練
2. 確認主畫面先看到的是狀態，不是一堆規格字
3. 確認文案像是：
   - 目前狀態
   - 可靠度 / 資料有限
   - 建議如何理解
4. 確認不會出現：
   - `精準 Zone 2`
   - `已量測 LT1`
   - `最佳區間`
5. 進入設定頁，測這 4 件事：
   - 手動改 Zone 2 上下界
   - 輸入 Resting HR
   - 使用 `依 Resting HR 產生建議`
   - 使用 `重設為預設`
6. 回到單筆與週摘要，確認都能反映目前採用的 Zone 2 policy

### 2. VO2 max

1. 打開一筆有 `VO2 max` 估算值的訓練
2. 確認顯示的是：
   - `VO2 max 估算`
   - 來源 / 可靠度 / 補充說明
3. 確認不會顯示成：
   - `已測得 VO2 max`
   - `實驗室結果`
   - `lab-equivalent`
4. 再打開一筆只有間歇型態、沒有 scalar VO2 值的訓練
5. 確認這筆會呈現為 `最大攝氧量 / 間歇` 的訓練脈絡，而不是硬說有 VO2 max 測值

### 3. 肌力

1. 打開一筆有結構化肌力指標的訓練
2. 確認會看到 exercise-specific 指標，例如 `e1RM`
3. 確認文案是在說：
   - 肌力指標
   - 這次資料的可參考程度
   - 這不是全身肌力診斷
4. 再打開一筆只有心率樣態、沒有結構化肌力值的肌力訓練
5. 確認它仍然只被描述成 `肌力訓練型態` 或相近語意，而不是直接當成力量測量

## HealthKit 加值檢查

若使用真機資料，再多看這幾項是否有合理顯示：

- `VO2 max` 估算
- `1 分鐘心率恢復`
- `跑步功率`
- `自行車功率`
- `路線脈絡`

預期：

- 有資料時顯示
- 沒資料時安靜缺省
- 不因缺一項資料就把整筆分析說成失敗

## 驗收重點

這輪 owner acceptance 只要能回答下面問題，就算有價值：

1. 三類分類是否已收斂成只有 `Zone 2`、`最大攝氧量 / 間歇`、`肌力`
2. 主文案是否先講「目前狀態」與「可靠度」
3. 詳細資訊是否可展開，但不會一開始就塞滿學術字眼
4. 是否避免把估算值講成量測真值
5. Resting HR / Zone 2 設定流程是否夠直覺

## 本輪不要求

- TestFlight build
- Garmin 資料
- 臨床或實驗室等級驗證
- weekly UI 大改版
- 所有英文內部名詞完全消失

## 驗收結論格式

建議直接用這個格式記：

```text
Zone 2: pass / concern / fail
VO2 max: pass / concern / fail
肌力: pass / concern / fail
文案理解度: clear / mixed / confusing
詳細資訊層次: good / too much / too little
下一步建議: <一句話>
```
