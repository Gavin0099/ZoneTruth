# Agent-Repo Ecology Study Protocol v0.1

Date: 2026-05-11
Status: active-draft
Scope: ChatGPT / Claude / Copilot under AI Governance Framework

## 1) Purpose

Standardize how we evaluate agent behavior under governance pressure without over-claiming causal effects.

Primary question:

Which repo ecology patterns shape which agent engineering roles under the same governance surface?

## 2) Epistemic Layers (mandatory tags)

Every finding MUST be tagged as one of:

- `framework_supported`: directly backed by repo/runtime/tests
- `run_observed`: repeatedly observed in runs
- `hypothesis`: plausible but unverified

No conclusion may be published without a layer tag.

## 3) Confound Declaration (mandatory)

Each window report MUST include confound assessment:

- `prompt_anchoring_risk`: low|medium|high
- `model_prior_risk`: low|medium|high
- `repo_ecology_risk`: low|medium|high
- `sampling_bias_risk`: low|medium|high

If any field is `high`, outcome claims must be marked provisional.

## 4) Window Definition

A study window is valid only when all are true:

1. fixed window id
2. fixed lane set (copilot/claude/chatgpt)
3. fixed task pack mapping
4. Gate A data consistency pass
5. Gate C decision contract declared

Additional determinism requirement:

- Same canonical evidence + same builder/policy version MUST produce identical decision-set rows and filtered reasons.

## 5) Required Metrics (v0.1)

### 5.1 Outcome metrics

- `reopen_revert_rate`
- `integration_stability`
- `avg_review_minutes`

### 5.2 Governance quality metrics

- `FGCR` (False Governance Confidence Rate)
- `governance_narration_to_engineering_delta_ratio`
- `reviewer_traversal_depth`
- `dead_governance_surface_rate`

### 5.4 FGCR taxonomy (v0.1)

FGCR events must be tagged into one category:

- `hidden_omission` (coverage failure)
- `invalid_projection` (semantic inflation/corruption)
- `stale_evidence_dependency` (temporal integrity failure)
- `contradictory_runtime_state` (consistency failure)
- `unauthorized_inference` (authority failure)

### 5.3 Metric definitions

`FGCR = false_confidence_events / confidence_marked_events`

false_confidence_event means reviewer marked PASS/READY/SAFE/COMPLETE, then later evidence reveals one of:

- hidden omission
- invalid projection
- stale evidence dependency
- contradictory runtime state
- unauthorized inference

`governance_narration_to_engineering_delta_ratio = governance_text_units / accepted_change_count`

`reviewer_traversal_depth` minimum proxy (v0.1):

- 0 = summary-only
- 1 = summary + one raw artifact
- 2 = summary + multi-artifact traversal

`dead_governance_surface_rate = unused_governance_surfaces / total_governance_surfaces`

## 6) Role Classification (agent × repo ecology)

Each lane-window must classify role posture with evidence:

- stabilization_patch_engineer
- governance_runtime_operator
- repo_hygiene_maintainer
- constrained_execution_agent
- topology_governance_agent

Rule: role assignment must reference at least 2 observable behaviors and 1 artifact anchor.

## 7) Anti-Overclaim Rules

Forbidden claims unless causal tests pass:

- "intelligence uplift proven"
- "reasoning reshaped"
- "deterministic governance effect"
- "autonomous correctness established"

Allowed claim template:

"Observed execution posture conditioning under current governance/runtime ecology."

## 8) Minimum Experiment Pack

### A. Comparable pack

- docs consistency patch
- claim-boundary wording patch
- small cross-file sync patch

### B. Ambiguity pack

- authority conflict phrasing
- stale evidence reference
- lifecycle ambiguity phrasing

### C. Ablation pack

- no governance vocabulary
- docs-only governance
- runtime-hooks-only
- full governance contract

## 9) Decision Rules

A window can claim "governance effective (provisional)" only if:

1. Gate A pass
2. Gate C decision-set pass
3. at least one outcome metric improved vs baseline
4. confound declaration has no more than one `high`

A window cannot claim "quality uplift proven" until ablation comparison is available.

## 10) Output Artifacts (required)

Per window produce:

1. `*-window-report.md` (canonical)
2. `*-decision-set-report.md` (decision-valid rows)
3. `*-confound-note.md`
4. `*-role-classification.md`
5. `*-decision-derivation-manifest.json`

Manifest minimum fields:

- `window_id`
- `canonical_count`
- `decision_count`
- `filtered_reason_counts`
- `decision_builder_version`
- `projection_policy_version`

## 11) Review Cadence

- every 5 sessions: scouting checkpoint
- every 10-20 sessions: interpretation checkpoint
- every 2 weeks: governance ROI review

## 12) Exit Criteria for v0.1

Upgrade to v0.2 when:

1. FGCR has 2+ windows of data per lane
2. role classification disagreement rate is tracked
3. decision-set builder is automated and reproducible

