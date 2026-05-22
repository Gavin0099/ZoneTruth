# AI Governance Framework — 評估與使用指南

讀者定位：正在評估「要不要在團隊導入 AI Governance」的工程主管 / 技術同事  
資料來源：2026-05-07 之 5 個子任務 A/B 實測 + v1.2 評分模板首次落地  
本文立場：誠實版，揭露能力與成本，讓團隊自己判斷是否導入  
適用範圍：已實測 Doc remediation；Code 場景仍待補量化，但核心原則（scope lock、evidence anchoring、可量化評分）可跨場景

## TL;DR（30 秒）

v1.2 在本輪實測展現三個可量化能力：

1. Scope Lock 有效：`scope_violation_count = 0`（未越界改 firmware / driver / cfg / governance docs）
2. Evidence 可追溯：`evidence_traceability = 5/5`（修改可回掛到 manifest/log/artifact）
3. 訊號不空轉：`governance_signal_without_material_improvement = false`

同時也有成本：

1. `tokens_per_actionable_fix ≈ 8630 (proxy)`  
2. `actionable_fix_latency_sec = 405`（約 6.75 分鐘）

一句話：  
這個框架把「能不能審計、能不能追溯、能不能不越界」變成可量化工程品質。  
它不是讓 AI 更聰明，而是讓 AI 輸出更可驗證。

## 1. 這次測了什麼

2026-05-07 共 5 個子任務，核心都在 `FW_Validation_Package_0504_1`：

1. 定位 package 內容與 cfg/manifest/README/topology 一致性
2. 主題漂移修補（governance 文檔 vs package 證據語意）
3. Cross-file consistency remediation（含完整 v1.2 run record）
4. Partial failure remediation（L1 PASS / L2 FAIL）
5. Calibration（含多個子測試）

每個任務都有 A/B：

- A：沒有 ai governance  
- B：有 ai governance

## 2. 方法限制（必須先攤）

1. 單一 evaluator，缺 inter-rater reliability
2. 同一 base agent，差異主要來自 governance 注入
3. `n=5` 且場景同質（集中在同一 package）
4. 以 Doc remediation 為主，Code 場景尚待補量化
5. 目前 B arm 有較完整量化，A arm 尚需補齊對等 run record 才能算嚴格 delta

可宣稱範圍：  
在這 5 個 Doc 任務上，B 展現可量化的邊界紀律與成本輪廓。  
不可宣稱範圍：  
「對所有 codebase / 任務類型都普遍有效」。

## 3. v1.2 指標觀測（B arm 首次落地）

### 能力面

1. `scope_violation_count = 0`
2. `coverage_completion = 4/4`
3. `evidence_traceability = 5/5`
4. `accepted_change_count = 4`
5. `governance_signal_without_material_improvement = false`
6. `claim_overreach_count = 0`
7. `unintended_change_count = 0`
8. `revert_needed_after_fix = false`
9. `semantic_consistency = 4/5`

### 成本面

1. `tokens_per_actionable_fix ≈ 8630 (proxy)`  
   注意：這是 proxy，不是 provider 精準 token accounting。
2. `actionable_fix_latency_sec = 405`
3. `stalled_reasoning_count = 1`
4. `repeated_boundary_warning_count = 1`
5. `reviewer_edit_effort = 4/5`

### 判定面

1. `hard_failure = false`
2. `attention_anchoring_failure = false`
3. `under_commit_failure = false`
4. `governance_drag = false`
5. `reviewer_disposition = minor_edit`

`minor_edit` 的主因是：  
primary targets 已收斂，但 package 內非 target 文檔仍有舊語句殘留。  
這是 scope lock 的設計副作用，不是單純品質不足。

## 4. 強項（目前證據支持）

1. Scope lock 可重複：避免越界改動  
2. Evidence anchoring 可審計：reviewer 可直接追證據  
3. Claim boundary 較穩：抑制 partial-failure 過度宣稱  
4. Artifact 汙染低：治理 meta 多留在 runtime，不污染 deliverable

## 5. 弱點與成本（同樣有證據）

1. Runtime overhead 增加：初始化、邊界重述、語義防呆有成本  
2. Scope-bounded 不等於 package-wide 完整修補  
3. A/B 對等量化仍不完整：A arm 需要補 run record 才能做嚴格 delta

## 6. 核心使用觀念：Multi-Scope Chain

若目標是 package-wide 一致性，單次 scope 通常不夠。  
建議拆成 2-3 個 scope 串接：

1. Scope 1：primary reviewer-facing 核心檔案
2. Scope 2：secondary guide / reference 同步
3. Scope 3：historical / analysis 殘留清理

優點：每個 scope 可獨立審計、可中斷、可定位失敗來源。  
成本：每個 scope 都有治理初始化成本（時間 + token）。

## 7. 什麼場景適合

### 已實測強適用

1. Cross-file consistency review
2. Reviewer-facing wording 修補
3. Validation evidence boundary 收斂

### 可推論但尚待量化（Code）

1. scope-bounded refactor
2. root-cause bound bugfix
3. multi-artifact coordination task

使用前提：先跑自己的 v1.2 run record，不要直接外推。

### 不建議

1. prototype / spike / 快速一次性小修
2. 單檔極小變更
3. 高發散探索任務

## 8. 給工程主管的導入判準

若以下問題大多為 Yes，可導入：

1. 你需要 reviewer 可追溯證據鏈嗎？
2. 你可接受每任務約 6-7 分鐘初始化成本嗎？
3. 你團隊能讀懂 v1.2 指標嗎？
4. 你能把大任務拆成 multi-scope chain 嗎？

若 No 較多，建議先限縮到高風險、高審計需求任務使用。

## 9. 尚未完成的驗證

1. A arm 對等量化仍需補齊  
2. Code 場景 5-10 個任務的重跑樣本  
3. 不同 base model 下指標穩定性  
4. multi-scope chain 的累積成本曲線

## 10. 目前最可信的一句結論

目前證據最支持的不是「Governance 提升通用 correctness」，而是：

Governance 穩定提升 failure-state semantic coordination 與 reviewer-safe inference control。

---

關聯文件：

- [docs/ab-implementation-pressure-scorecard-v1.2.md](docs/ab-implementation-pressure-scorecard-v1.2.md)
- [docs/ab-v1.2-run-ledger.md](docs/ab-v1.2-run-ledger.md)
- [docs/ab-v1.2-round-summary.md](docs/ab-v1.2-round-summary.md)

## Claim-Level Boundary (Normative)

This framework currently supports:

- bounded failure containment
- reviewer-checkable observability surfaces

This framework does **not** currently claim:

- engineering quality uplift proof
- reasoning uplift proof
- deterministic cognitive control
- machine-authoritative compliance verdict
- universal semantic correctness verification
- automatic truth judgement over ambiguous reasoning
- long-horizon semantic drift elimination without reviewer oversight

For detailed rationale and epistemic limits, see:

- `docs/LIMITATIONS.md`
