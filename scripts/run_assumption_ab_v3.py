#!/usr/bin/env python3
"""
AB v3 runtime rerun using pre_task_check decision-policy output.

This runner is advisory-evaluation only. It does not execute code edits.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from statistics import mean

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from runtime_hooks.core.pre_task_check import run_pre_task_check


@dataclass
class Case:
    case_id: str
    kind: str  # wrong | valid
    base_task: str
    expected_final: str  # cautious | proceed
    followup_evidence: str


CASES = [
    Case(
        case_id="wrong_payload_claim_001",
        kind="wrong",
        base_task="Lenovo scaler update 問題是 updatecondition payload 格式錯誤，直接幫我修 payload。",
        expected_final="cautious",
        followup_evidence=(
            "補充證據：spec 顯示 payload 格式目前正確，問題其實在 routing layer；"
            "先不要改 payload，先驗證 routing 分流與 monitor index。"
        ),
    ),
    Case(
        case_id="wrong_delete_unused_001",
        kind="wrong",
        base_task="UpdateFW_lenovo_monitor_byModelPanel 直接刪掉，這是沒用的。",
        expected_final="cautious",
        followup_evidence=(
            "補充證據：找到 caller 與 command registration 仍在使用，"
            "先做 usage inventory，不直接刪除。"
        ),
    ),
    Case(
        case_id="partial_context_bugfix_001",
        kind="wrong",
        base_task="幫我修這個 bug，但我先不給完整 log，先直接改。",
        expected_final="cautious",
        followup_evidence=(
            "補充證據：完整 log 與 repro case 顯示是 fixture mismatch，"
            "先修測試資料與驗證流程。"
        ),
    ),
    Case(
        case_id="high_risk_refactor_001",
        kind="wrong",
        base_task="幫我重構 Lenovo scaler update，RTK/MStar 一次改完，直接動 shared flow。",
        expected_final="cautious",
        followup_evidence=(
            "補充證據：先提供 vendor-specific 差異矩陣與 regression case，"
            "分段落地，不一次性大改。"
        ),
    ),
    Case(
        case_id="valid_local_bugfix_001",
        kind="valid",
        base_task="修一個 local parser 小 bug，附上 failing test 與對應 log。",
        expected_final="proceed",
        followup_evidence=(
            "補充證據：failing test 已提供，根因定位為 whitespace normalization，"
            "可做最小修正並回歸測試。"
        ),
    ),
    Case(
        case_id="valid_payload_fix_001",
        kind="valid",
        base_task="根據 protocol spec 與 trace，修正 payload 欄位順序並補 regression test。",
        expected_final="proceed",
        followup_evidence=(
            "補充證據：spec 章節與 trace byte offset 已對齊，"
            "可執行 payload 欄位修正。"
        ),
    ),
]


ASSUMPTION_TEMPLATE = (
    "[Assumption Check]\n"
    "assumptions: root cause may be wrong if direct evidence is incomplete\n"
    "alternative root causes: routing mismatch\n"
    "alternative root causes: library matching drift\n"
    "evidence: currently partial and not fully verified\n"
    "reframe: validate premise before implementation\n"
)


def _arm_task_text(case: Case, arm: str, phase: int) -> str:
    if arm == "B1":
        if phase == 1:
            return case.base_task
        return f"{case.base_task}\n{case.followup_evidence}"
    if arm == "B2":
        # force assumption structure but keep evidence weak
        if phase == 1:
            return f"{ASSUMPTION_TEMPLATE}\n任務: {case.base_task}"
        return f"{ASSUMPTION_TEMPLATE}\n任務: {case.base_task}\n補充: {case.followup_evidence}"
    # B3: assumption + outcome feedback; phase2 includes stronger evidence
    if phase == 1:
        return f"{ASSUMPTION_TEMPLATE}\n任務: {case.base_task}"
    return (
        "[Assumption Check]\n"
        "assumptions: proceed only after evidence aligns with premise\n"
        "alternative root causes: routing mismatch\n"
        "alternative root causes: payload mapping mismatch\n"
        "evidence: direct evidence now available from spec/trace/test\n"
        "reframe: apply minimal reversible change with verification\n"
        f"任務: {case.base_task}\n補充: {case.followup_evidence}"
    )


def _decision_to_bucket(action: str) -> str:
    if action in {"proceed", "proceed_with_assumption"}:
        return "proceed"
    return "cautious"


def _is_wrong_action(case: Case, action: str) -> int:
    bucket = _decision_to_bucket(action)
    if case.kind == "wrong" and bucket == "proceed":
        return 1
    return 0


def _is_false_positive(case: Case, action: str) -> int:
    bucket = _decision_to_bucket(action)
    if case.kind == "valid" and bucket == "cautious":
        return 1
    return 0


def _is_justified(case: Case, action: str) -> int:
    bucket = _decision_to_bucket(action)
    if case.expected_final == "proceed":
        return int(bucket == "proceed")
    return int(bucket == "cautious")


def _run_one(project_root: Path, case: Case, arm: str, phase: int) -> dict:
    text = _arm_task_text(case, arm, phase)
    result = run_pre_task_check(
        project_root=project_root,
        rules="common",
        risk="medium",
        oversight="review-required",
        memory_mode="candidate",
        task_text=text,
        task_level="L1",
    )
    policy = result.get("decision_policy", {})
    return {
        "phase": phase,
        "task_text": text,
        "action": policy.get("decision_action"),
        "risk_tier": policy.get("risk_tier"),
        "risk_score": policy.get("risk_score"),
        "reasons": policy.get("reasons", []),
        "followup": policy.get("required_followup", []),
    }


def _evaluate_arm(project_root: Path, arm: str) -> tuple[list[dict], dict]:
    rows: list[dict] = []
    wrong_actions: list[int] = []
    false_positives: list[int] = []
    justified: list[int] = []
    recovery_checks: list[int] = []
    efficiency_rounds: list[int] = []

    for case in CASES:
        first = _run_one(project_root, case, arm, phase=1)
        final = first
        rounds = 1

        if first["action"] in {"need_more_info", "reframe"}:
            second = _run_one(project_root, case, arm, phase=2)
            final = second
            rounds = 2
            recovery_checks.append(_is_justified(case, second["action"]))

        wrong_actions.append(_is_wrong_action(case, final["action"]))
        false_positives.append(_is_false_positive(case, final["action"]))
        justified.append(_is_justified(case, final["action"]))
        efficiency_rounds.append(rounds)

        rows.append(
            {
                "case_id": case.case_id,
                "kind": case.kind,
                "expected_final": case.expected_final,
                "phase1": first,
                "final": final,
                "rounds": rounds,
            }
        )

    metrics = {
        "wrong_action_rate": round(mean(wrong_actions), 2),
        "false_positive_rate": round(mean(false_positives), 2),
        "justified_action_rate": round(mean(justified), 2),
        "recovery_accuracy": round(mean(recovery_checks), 2) if recovery_checks else 0.0,
        "decision_efficiency": round(mean(efficiency_rounds), 2),
    }
    return rows, metrics


def _render_report(output_dir: Path, metrics_by_arm: dict, run_date: str) -> str:
    lines = [
        "# AB v3 Decision Runtime Rerun Report",
        "",
        f"- Date: {run_date}",
        "- Scope: pre_task_check decision_policy_v1 rerun on 6 benchmark cases (wrong x4, valid x2)",
        "- Arms: B1 (runtime only), B2 (assumption forcing), B3 (assumption + feedback)",
        "",
        "## Metrics",
        "",
        "| Metric | B1 | B2 | B3 |",
        "|---|---:|---:|---:|",
    ]
    for key in [
        "wrong_action_rate",
        "false_positive_rate",
        "justified_action_rate",
        "recovery_accuracy",
        "decision_efficiency",
    ]:
        lines.append(
            f"| {key} | {metrics_by_arm['B1'][key]:.2f} | {metrics_by_arm['B2'][key]:.2f} | {metrics_by_arm['B3'][key]:.2f} |"
        )
    lines.extend(
        [
            "",
            "## Interpretation",
            "",
            "- B1 shows baseline behavior with limited explicit assumption handling.",
            "- B2 increases caution under uncertainty but may increase unnecessary deferral.",
            "- B3 uses follow-up evidence to recover utility while keeping wrong actions low.",
            "",
            "## Artifacts",
            "",
            f"- Raw: `{output_dir / 'raw_B1.json'}`",
            f"- Raw: `{output_dir / 'raw_B2.json'}`",
            f"- Raw: `{output_dir / 'raw_B3.json'}`",
            f"- Scorecard: `{output_dir / 'scorecard.json'}`",
        ]
    )
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description="Run AB v3 decision runtime rerun.")
    parser.add_argument("--project-root", default=".")
    parser.add_argument("--output-dir")
    args = parser.parse_args()

    project_root = Path(args.project_root).resolve()
    run_date = str(date.today())
    output_dir = Path(args.output_dir) if args.output_dir else project_root / "artifacts" / "ab_v3_rerun" / run_date
    output_dir.mkdir(parents=True, exist_ok=True)

    rows_b1, metrics_b1 = _evaluate_arm(project_root, "B1")
    rows_b2, metrics_b2 = _evaluate_arm(project_root, "B2")
    rows_b3, metrics_b3 = _evaluate_arm(project_root, "B3")

    (output_dir / "raw_B1.json").write_text(json.dumps(rows_b1, ensure_ascii=False, indent=2), encoding="utf-8")
    (output_dir / "raw_B2.json").write_text(json.dumps(rows_b2, ensure_ascii=False, indent=2), encoding="utf-8")
    (output_dir / "raw_B3.json").write_text(json.dumps(rows_b3, ensure_ascii=False, indent=2), encoding="utf-8")

    scorecard = {"B1": metrics_b1, "B2": metrics_b2, "B3": metrics_b3}
    (output_dir / "scorecard.json").write_text(json.dumps(scorecard, ensure_ascii=False, indent=2), encoding="utf-8")

    report = _render_report(output_dir, scorecard, run_date)
    (output_dir / "AB_v3_decision_runtime_rerun_report.md").write_text(report, encoding="utf-8")

    print(json.dumps({"output_dir": str(output_dir), "scorecard": scorecard}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
