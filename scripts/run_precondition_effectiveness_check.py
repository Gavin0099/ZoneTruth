#!/usr/bin/env python3
"""
Run a minimal precondition-gate effectiveness check.

Checks only:
1. recommended_mode
2. forbidden_claims
3. human-readable vs machine-readable surface consistency
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Any

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from runtime_hooks.core.pre_task_check import format_human_result, run_pre_task_check


@dataclass
class CheckCase:
    case_id: str
    description: str
    task_text: str
    expected_recommended_mode: str
    expected_missing: tuple[str, ...]
    expected_forbidden_claims: tuple[str, ...]


CASES: list[CheckCase] = [
    CheckCase(
        case_id="missing_reset_codegen",
        description="missing reset, with codegen intent",
        task_text=(
            "Generate synthesizable SystemVerilog RTL for fifo controller module with ready/valid handshake. "
            "No reset definition is provided."
        ),
        expected_recommended_mode="allow_draft_with_assumptions",
        expected_missing=("missing_reset_definition",),
        expected_forbidden_claims=("claim_reset_safe_codegen",),
    ),
    CheckCase(
        case_id="missing_handshake_codegen",
        description="missing handshake, with codegen intent",
        task_text=(
            "Implement synthesizable Verilog control interface logic with active-low asynchronous reset (rst_n). "
            "No protocol timing or backpressure behavior is provided."
        ),
        expected_recommended_mode="allow_analysis_only",
        expected_missing=("missing_interface_or_handshake_definition",),
        expected_forbidden_claims=("claim_interface_correctness_codegen",),
    ),
    CheckCase(
        case_id="ready_for_codegen",
        description="reset + handshake present, allow-codegen",
        task_text=(
            "Generate synthesizable SystemVerilog RTL for queue controller. "
            "Use active-low asynchronous reset (rst_n). "
            "Interface uses ready/valid handshake with one-cycle backpressure latency."
        ),
        expected_recommended_mode="allow_draft_with_assumptions",
        expected_missing=(),
        expected_forbidden_claims=(),
    ),
    CheckCase(
        case_id="analysis_task_missing_preconditions",
        description="non-codegen analysis task with missing preconditions",
        task_text=(
            "Analyze control-interface risk and propose assumption checks before implementation. "
            "No reset polarity and no protocol timing details are currently defined."
        ),
        expected_recommended_mode="allow_analysis_only",
        expected_missing=("missing_interface_or_handshake_definition",),
        expected_forbidden_claims=("claim_interface_correctness_codegen",),
    ),
]


def _check_subset(expected: tuple[str, ...], actual: list[str]) -> bool:
    actual_set = set(actual)
    return all(item in actual_set for item in expected)


def _run_case(project_root: Path, case: CheckCase) -> dict[str, Any]:
    result = run_pre_task_check(
        project_root=project_root,
        rules="common",
        risk="medium",
        oversight="review-required",
        memory_mode="candidate",
        task_text=case.task_text,
        task_level="L1",
    )
    gate = result.get("precondition_gate_validator") or {}
    human = format_human_result(result)

    actual_mode = str(gate.get("recommended_mode") or "")
    actual_missing = [str(x) for x in gate.get("missing_preconditions", [])]
    actual_forbidden = [str(x) for x in gate.get("forbidden_claims", [])]

    machine_mode_ok = actual_mode == case.expected_recommended_mode
    machine_missing_ok = _check_subset(case.expected_missing, actual_missing)
    machine_forbidden_ok = _check_subset(case.expected_forbidden_claims, actual_forbidden)
    human_mode_ok = f"recommended_mode={actual_mode}" in human
    human_missing_ok = f"missing={','.join(actual_missing)}" in human
    surface_consistent = human_mode_ok and human_missing_ok

    passed = machine_mode_ok and machine_missing_ok and machine_forbidden_ok and surface_consistent
    return {
        "case_id": case.case_id,
        "description": case.description,
        "expected": {
            "recommended_mode": case.expected_recommended_mode,
            "missing_preconditions": list(case.expected_missing),
            "forbidden_claims": list(case.expected_forbidden_claims),
        },
        "observed": {
            "recommended_mode": actual_mode,
            "missing_preconditions": actual_missing,
            "forbidden_claims": actual_forbidden,
            "ok": bool(gate.get("ok", False)),
        },
        "checks": {
            "recommended_mode_match": machine_mode_ok,
            "forbidden_claims_match": machine_forbidden_ok,
            "missing_preconditions_match": machine_missing_ok,
            "surface_consistent": surface_consistent,
        },
        "passed": passed,
    }


def _render_report(out: dict[str, Any], output_dir: Path) -> str:
    lines = [
        "# Precondition Gate Effectiveness Check",
        "",
        f"- Date: {out['run_date']}",
        f"- Cases: {out['summary']['cases_total']}",
        f"- Passed: {out['summary']['cases_passed']}",
        f"- Failed: {out['summary']['cases_failed']}",
        "",
        "## Case Results",
        "",
    ]
    for item in out["cases"]:
        lines.append(
            f"- {item['case_id']} ({item['description']}): "
            f"mode={item['observed']['recommended_mode']} "
            f"missing={item['observed']['missing_preconditions']} "
            f"forbidden={item['observed']['forbidden_claims']} "
            f"passed={item['passed']}"
        )
    lines.extend(
        [
            "",
            "## Artifacts",
            "",
            f"- JSON: `{output_dir / 'precondition_effectiveness.json'}`",
            f"- Report: `{output_dir / 'precondition_effectiveness_report.md'}`",
        ]
    )
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description="Run minimal precondition gate effectiveness check.")
    parser.add_argument("--project-root", default=".")
    parser.add_argument("--output-dir")
    args = parser.parse_args()

    run_date = str(date.today())
    project_root = Path(args.project_root).resolve()
    output_dir = (
        Path(args.output_dir)
        if args.output_dir
        else project_root / "artifacts" / "precondition_effectiveness" / run_date
    )
    output_dir.mkdir(parents=True, exist_ok=True)

    # Isolated runtime sandbox inside workspace (Windows temp can be permission-restricted).
    tmp_root = project_root / "tmp_precondition_effectiveness"
    tmp_root.mkdir(parents=True, exist_ok=True)
    (tmp_root / "PLAN.md").write_text("> **Owner**: Effectiveness\n", encoding="utf-8")
    case_results = [_run_case(tmp_root, case) for case in CASES]

    cases_passed = sum(1 for c in case_results if c["passed"])
    out = {
        "run_date": run_date,
        "summary": {
            "cases_total": len(case_results),
            "cases_passed": cases_passed,
            "cases_failed": len(case_results) - cases_passed,
        },
        "cases": case_results,
    }

    json_path = output_dir / "precondition_effectiveness.json"
    json_path.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")

    report = _render_report(out, output_dir)
    report_path = output_dir / "precondition_effectiveness_report.md"
    report_path.write_text(report, encoding="utf-8")

    print(
        json.dumps(
            {
                "output_dir": str(output_dir),
                "report": str(report_path),
                "summary": out["summary"],
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
