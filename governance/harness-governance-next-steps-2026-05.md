# Harness Governance 下一步（2026-05）

日期：2026-05-11
定位：把 `Harness Engineering` 升級為 `Governance-aware Harness Engineering`。

## 1. 文章判讀（可落地版本）

這篇《Harness Engineering》的核心不是「Agent 很強」，而是：

- 模型不可靠是前提
- runtime 結構與驗證能力決定可用性
- 可驗證範圍決定可自動化範圍

對本 framework 的直接意義：

- 我們已經有 execution harness（hook、closeout、validator）
- 下一步要補的是 epistemic harness（projection integrity、review authority、decision contract）

一句話：

`LLM capability` 不是終點，`reviewable runtime` 才是終點。

## 2. 現在的成熟度（現況分層）

### 已成立（較強證據）

- Claim discipline（over-claim 壓制）
- Scope containment（最小切片）
- Artifact traceability（run/ledger/session）
- Runtime advisory hooks（不直接 block）

### 未完成（下一步重點）

- Gate C decision set 契約（valid rows only vs canonical 全量）
- Projection integrity runtime hook（summary 不得偷推論）
- Reviewer traversal contract（注意力路由）
- Outcome ROI（治理成本 vs 工程收益）

## 3. 30 天執行路線（P0~P3）

### P0（本週）Decision Contract 固化

目標：終止 `provisional-pass` 的口徑爭議。

交付：

- `docs/governance/gate-c-decision-set-contract-v0.1.md`
- 定義：
  - canonical logs = 保留全量證據（含 reconstructed/null）
  - decision set = 僅 valid timestamp rows
  - decision report 必須顯示 `canonical_count` 與 `decision_count`
  - 不允許直接刪 canonical rows 來「洗 pass」

驗收：

- 同一 window 可同時產出：
  - canonical report（含 evidence gaps）
  - decision-set report（可判 pass/pause）

### P1（1~2 週）Outcome Layer 標準化

目標：把行為收斂變成可比較成果。

交付：

- 統一三 lane 指標：
  - `avg_review_minutes`
  - `reopen_revert_rate`
  - `integration_stability`
- 每 lane 至少 1 個完整窗口（>=10 valid rows）

驗收：

- 三 lane 可做同窗比較
- 任何結論都能回跳 raw rows

### P2（2~3 週）Causal Separation（Ablation）

目標：分離 prompt anchoring 與 framework effect。

實驗組：

1. no governance vocabulary
2. docs-only governance
3. runtime-hooks-only
4. full governance contract

驗收：

- 至少一項 outcome 指標在 full-contract 優於其他組
- 且不是只改善「語氣」

### P3（3~4 週）Hostile Ambiguity Pack

目標：驗證 failure containment，不是只看保守語言。

場景：

- authority conflict
- stale evidence
- lifecycle ambiguity
- contradictory validator signals

驗收：

- damage boundary 可觀測（不擴散、不越權、不過度 claim）

## 4. Governance Hooks 下一步（技術面）

新增一層 `projection governance hook`：

- 檢查 summary 是否出現語義升級（例如 PARTIAL -> Mostly Complete）
- 檢查 severity 與 evidence 是否對齊
- 檢查 coverage 是否有 omission 且未揭露
- 全部先 advisory，不直接 block

## 4.1 Decision Derivation Manifest（新增）

每次 decision-set 計算必須輸出可重跑 manifest，至少包含：

- `window_id`
- `decision_builder_version`
- `projection_policy_version`
- `canonical_count`
- `decision_count`
- `filtered_reason_counts`
- `source_artifact_hashes`（或等價可追溯欄位）

目的：確保同一份 canonical evidence 在不同 reviewer/不同時間可得到相同 decision-set。

## 5. Token 成本策略（避免治理疲勞）

原則：先減敘事重複，再減治理能力。

執行：

- 能 machine-readable 就不重複自然語言描述
- 報告層分三層：
  - executive line（1~2 行）
  - decision metrics（固定欄位）
  - raw evidence links（可追溯）
- 每週檢查 `governance narration` 是否超過 `engineering delta`

## 6. 決策規則（避免治理劇場）

只在以下條件同時成立時，才宣稱治理有效：

1. 行為層指標穩定（claim/scope/traceability）
2. 結果層指標改善（reopen/revert、review effort、integration stability）
3. 成本可接受（token/time 不失控）

若只滿足第 1 點，不可宣稱「工程品質已被證明提升」。

## 6.1 治理語義新增硬規則（新增）

所有新增 governance semantics 必須綁定下列三者之一，否則不准新增：

1. observable failure（可指向具體失敗樣本）
2. runtime enforcement（有可執行的 runtime 機制）
3. explicit non-enforcement disclosure（明確標註僅 advisory）

此規則用於抑制 `governance semantic inflation`。

## 7. 下一步（可立即執行）

1. 起草 `gate-c-decision-set-contract-v0.1.md`
2. 對現有 window 同步輸出 canonical + decision-set 雙報告
3. 在 Round A/B 報告模板加入 `sample_quality` 與 `interpretation boundary`
4. 兩週後做第一次 Governance ROI Review

---

這份文件的定位：

- 不是新功能宣傳
- 是治理推論邊界與執行順序的控制面
- 用來避免「觀測訊號」被誤讀成「政策授權」
