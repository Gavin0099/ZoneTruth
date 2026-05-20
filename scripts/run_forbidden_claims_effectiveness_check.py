#!/usr/bin/env python3
"""
Run a minimal forbidden-claims effectiveness check for precondition gate output.
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
    expected_forbidden_claims: tuple[str, ...]
    must_be_empty: bool = False


CASES: list[CheckCase] = [
    CheckCase(
        case_id="missing_reset_codegen_claim_boundary",
        description="missing reset -> must forbid reset-correctness codegen claim",
        task_text=(
            "Generate synthesizable SystemVerilog RTL for fifo controller with ready/valid handshake. "
            "No reset behavior is specified."
        ),
        expected_forbidden_claims=("claim_reset_safe_codegen",),
    ),
    CheckCase(
        case_id="missing_handshake_codegen_claim_boundary",
        description="missing handshake -> must forbid interface-correctness codegen claim",
        task_text=(
            "Implement synthesizable Verilog interface/control logic with active-low reset rst_n. "
            "Handshake and backpressure semantics are not specified."
        ),
        expected_forbidden_claims=("claim_interface_correctness_codegen",),
    ),
    CheckCase(
        case_id="preconditions_satisfied_no_false_positive",
        description="preconditions satisfied -> forbidden claims should be empty",
        task_text=(
            "Generate synthesizable SystemVerilog RTL for queue controller. "
            "Use active-low asynchronous reset rst_n. "
            "Interface uses ready/valid handshake with one-cycle backpressure latency."
        ),
        expected_forbidden_claims=(),
        must_be_empty=True,
    ),
    CheckCase(
        case_id="analysis_task_missing_preconditions_claim_boundary",
        description="analysis-only task still exposes claim-boundary when handshake missing",
        task_text=(
            "Analyze interface risk and list assumptions before implementation. "
            "Protocol timing/backpressure details are not specified."
        ),
        expected_forbidden_claims=("claim_interface_correctness_codegen",),
    ),
]


def _contains_all(expected: tuple[str, ...], actual: list[str]) -> bool:
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
    human = format_human_result(result)
    gate = result.get("precondition_gate_validator") or {}
    forbidden = [str(x) for x in gate.get("forbidden_claims", [])]
    forbidden_csv = ",".join(forbidden)

    forbidden_match = _contains_all(case.expected_forbidden_claims, forbidden)
    no_false_positive = (forbidden == []) if case.must_be_empty else True
    human_surface_ok = f"forbidden_claims={forbidden_csv}" in human
    machine_surface_ok = isinstance(gate.get("forbidden_claims"), list)
    surface_consistent = human_surface_ok and machine_surface_ok

    passed = forbidden_match and no_false_positive and surface_consistent
    return {
        "case_id": case.case_id,
        "description": case.description,
        "expected": {
            "forbidden_claims": list(case.expected_forbidden_claims),
            "must_be_empty": case.must_be_empty,
        },
        "observed": {
            "forbidden_claims": forbidden,
            "recommended_mode": gate.get("recommended_mode"),
            "ok": gate.get("ok"),
        },
        "checks": {
            "forbidden_claims_match": forbidden_match,
            "no_false_positive": no_false_positive,
            "surface_consistent": surface_consistent,
        },
        "passed": passed,
    }


def _render_report(data: dict[str, Any], output_dir: Path) -> str:
    lines = [
        "# Forbidden Claims Effectiveness Check",
        "",
        f"- Date: {data['run_date']}",
        f"- Cases: {data['summary']['cases_total']}",
        f"- Passed: {data['summary']['cases_passed']}",
        f"- Failed: {data['summary']['cases_failed']}",
        "",
        "## Case Results",
        "",
    ]
    for item in data["cases"]:
        lines.append(
            f"- {item['case_id']} ({item['description']}): "
            f"forbidden={item['observed']['forbidden_claims']} "
            f"passed={item['passed']}"
        )
    lines.extend(
        [
            "",
            "## Artifacts",
            "",
            f"- JSON: `{output_dir / 'forbidden_claims_effectiveness.json'}`",
            f"- Report: `{output_dir / 'forbidden_claims_effectiveness_report.md'}`",
        ]
    )
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description="Run forbidden-claims effectiveness check.")
    parser.add_argument("--project-root", default=".")
    parser.add_argument("--output-dir")
    args = parser.parse_args()

    run_date = str(date.today())
    project_root = Path(args.project_root).resolve()
    output_dir = (
        Path(args.output_dir)
        if args.output_dir
        else project_root / "artifacts" / "forbidden_claims_effectiveness" / run_date
    )
    output_dir.mkdir(parents=True, exist_ok=True)

    tmp_root = project_root / "tmp_forbidden_claims_effectiveness"
    tmp_root.mkdir(parents=True, exist_ok=True)
    (tmp_root / "PLAN.md").write_text("> **Owner**: ForbiddenClaimsEffectiveness\n", encoding="utf-8")

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

    json_path = output_dir / "forbidden_claims_effectiveness.json"
    json_path.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    report = _render_report(out, output_dir)
    report_path = output_dir / "forbidden_claims_effectiveness_report.md"
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
