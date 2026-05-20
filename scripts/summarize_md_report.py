#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Summarize contract-driven markdown rerun report.")
    parser.add_argument("--report", required=True, help="Path to rerun report JSON.")
    return parser.parse_args()


def _to_bool(value: object, default: bool) -> bool:
    if isinstance(value, bool):
        return value
    return default


def _to_int(value: object, default: int) -> int:
    if isinstance(value, int):
        return value
    return default


def review_required_visibility(aggregate: dict) -> dict:
    ids = aggregate.get("review_required_sample_ids")
    if not isinstance(ids, list):
        ids = []
    return {
        "count": _to_int(aggregate.get("review_required_sample_count"), 0),
        "ids": [str(item) for item in ids],
        "advisory_only": _to_bool(aggregate.get("review_required_advisory_only"), True),
    }


def build_repo_summary_lines(repo: dict) -> list[str]:
    aggregate = repo.get("aggregate", {})
    review_required = review_required_visibility(aggregate)
    lines = [
        str(repo.get("repo")),
        f"  targets_scanned: {repo.get('targets_scanned')}",
        f"  missing_targets: {len(repo.get('missing_targets', []))}",
        f"  any_clean_fail: {aggregate.get('any_clean_fail')}",
        f"  any_noise_fail: {aggregate.get('any_noise_fail')}",
        f"  closure_gate: {aggregate.get('closure_gate')}",
        f"  scope_filter_compliance: {aggregate.get('scope_filter_compliance')}",
        "  review_required_visibility:",
        f"    review_required_sample_count: {review_required['count']}",
        f"    review_required_sample_ids: {review_required['ids']}",
        f"    review_required_advisory_only: {review_required['advisory_only']}",
    ]
    return lines


def render_summary(report: dict) -> str:
    lines = [
        f"contract_id: {report.get('contract_id')}",
        f"generated_at_utc: {report.get('generated_at_utc')}",
        f"contract_path: {report.get('contract_path')}",
        f"runner_sha256: {report.get('tooling', {}).get('runner_sha256')}",
        "",
    ]

    repos = report.get("repos", [])
    for repo in repos:
        lines.extend(build_repo_summary_lines(repo))
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    args = parse_args()
    report_path = Path(args.report).resolve()
    with report_path.open("r", encoding="utf-8") as fh:
        report = json.load(fh)
    print(render_summary(report), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
