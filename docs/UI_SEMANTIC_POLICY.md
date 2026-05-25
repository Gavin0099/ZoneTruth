# UI Semantic Policy

## Purpose
This policy defines allowed and forbidden user-facing language for ZoneTruth surfaces.
It prevents authority inflation and avoids accidental medical/coaching implication.

## Core Rule
Use observational language, not diagnostic or prescriptive language.

## Forbidden Wording
- "過度訓練"
- "你恢復不足"
- "你今天不適合高強度"
- "你必須休息"
- "恢復分數"
- "readiness score"
- "today recommendation"

## Preferred Rewrites
- "恢復不足" -> "觀測到恢復壓力訊號"
- "過度訓練" -> "高負荷累積跡象"
- "你必須休息" -> "可考慮降低強度"
- "你不適合高強度" -> "目前高強度證據覆蓋不足"

## Confidence Semantics
- Never compress uncertainty into a single medical-like verdict.
- Use bounded phrasing:
  - "觀測到"
  - "資料覆蓋不足"
  - "目前無法判定"

## Enforcement
- This policy is enforced by closeout semantic and structural guards.
- Violations block release-gate workflows.
