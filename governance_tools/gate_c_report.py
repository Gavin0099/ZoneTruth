#!/usr/bin/env python3
"""
Generate a Gate C window report from reviewer timing, rework, and stability logs.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from governance_tools.human_summary import build_summary_line


LANES = ("copilot", "claude", "chatgpt")
STABILITY_STATUSES = {"stable", "degraded", "unknown"}
WINDOW_ID_RE = re.compile(r"^gate-c-window-\d{4}-\d{2}-\d{2}$")
MIN_VALID_REVIEW_TIMINGS_FOR_PASS = 10


@dataclass
class ReviewEntry:
    window_id: str
    lane: str
    run_id: str
    review_start_utc: str | None = None
    review_end_utc: str | None = None
    review_minutes: float | None = None
    review_decision: str | None = None


@dataclass
class ReworkEntry:
    window_id: str
    lane: str
    run_id: str
    reopen_count: int
    revert_count: int
    total_changes: int
    reopen_revert_rate: float | None


@dataclass
class StabilityEntry:
    window_id: str
    lane: str
    run_id: str
    integration_stability: str
    stability_note: str


@dataclass
class LaneGateCReport:
    window_id: str
    lane: str
    review_effort: dict[str, Any]
    quality_rework: dict[str, Any]
    integration_stability: dict[str, Any]
    gate_c_result: str
    evidence_gaps: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)


@dataclass
class GateCWindowReport:
    window_id: str
    lane_reports: list[LaneGateCReport]
    review_log_path: str
    rework_log_path: str
    stability_log_path: str


def _parse_iso8601(text: str | None) -> datetime | None:
    if not text:
        return None
    try:
        dt = datetime.fromisoformat(text)
    except Exception:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _read_ndjson(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    records: list[dict[str, Any]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        records.append(json.loads(stripped))
    return records


def _parse_review_entries(path: Path) -> list[ReviewEntry]:
    entries: list[ReviewEntry] = []
    for item in _read_ndjson(path):
        lane = str(item.get("lane", "")).strip().lower()
        window_id = str(item.get("window_id", "")).strip()
        run_id = str(item.get("run_id", "")).strip()
        if not lane or not window_id or not run_id:
            continue
        entries.append(
            ReviewEntry(
                window_id=window_id,
                lane=lane,
                run_id=run_id,
                review_start_utc=item.get("review_start_utc"),
                review_end_utc=item.get("review_end_utc"),
                review_minutes=float(item.get("review_minutes")) if item.get("review_minutes") is not None else None,
                review_decision=str(item.get("review_decision", "")).strip().lower() or None,
            )
        )
    return entries


def _parse_rework_entries(path: Path) -> list[ReworkEntry]:
    entries: list[ReworkEntry] = []
    for item in _read_ndjson(path):
        lane = str(item.get("lane", "")).strip().lower()
        window_id = str(item.get("window_id", "")).strip()
        run_id = str(item.get("run_id", "")).strip()
        reopen_count = int(item.get("reopen_count", 0) or 0)
        revert_count = int(item.get("revert_count", 0) or 0)
        total_changes = int(item.get("total_changes", 0) or 0)
        raw_rate = item.get("reopen_revert_rate")
        reopen_revert_rate = float(raw_rate) if raw_rate is not None else None
        if not lane or not window_id or not run_id:
            continue
        entries.append(
            ReworkEntry(
                window_id=window_id,
                lane=lane,
                run_id=run_id,
                reopen_count=reopen_count,
                revert_count=revert_count,
                total_changes=total_changes,
                reopen_revert_rate=reopen_revert_rate,
            )
        )
    return entries


def _parse_stability_entries(path: Path) -> list[StabilityEntry]:
    entries: list[StabilityEntry] = []
    for item in _read_ndjson(path):
        lane = str(item.get("lane", "")).strip().lower()
        window_id = str(item.get("window_id", "")).strip()
        run_id = str(item.get("run_id", "")).strip()
        status = str(item.get("integration_stability", "")).strip().lower()
        if not lane or not window_id or status not in STABILITY_STATUSES:
            continue
        entries.append(
            StabilityEntry(
                window_id=window_id,
                lane=lane,
                run_id=run_id,
                integration_stability=status,
                stability_note=str(item.get("stability_note", "")).strip(),
            )
        )
    return entries


def _review_minutes(entry: ReviewEntry) -> float | None:
    if entry.review_minutes is not None:
        return round(float(entry.review_minutes), 1)
    start = _parse_iso8601(entry.review_start_utc)
    end = _parse_iso8601(entry.review_end_utc)
    if start is None or end is None or end < start:
        return None
    minutes = (end - start).total_seconds() / 60.0
    return round(minutes, 1)


def _percentile(values: list[float], q: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    rank = max(0, math.ceil(q * len(ordered)) - 1)
    return round(float(ordered[rank]), 1)


def _median(values: list[float]) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    mid = len(ordered) // 2
    if len(ordered) % 2 == 1:
        return round(float(ordered[mid]), 1)
    return round((ordered[mid - 1] + ordered[mid]) / 2.0, 1)


def _avg(values: list[float]) -> float | None:
    if not values:
        return None
    return round(sum(values) / len(values), 1)


def _markdown_report(report: GateCWindowReport) -> str:
    lines = [f"# Gate C Window Report {report.window_id}", ""]
    lines.append(f"- review_log_path: {report.review_log_path}")
    lines.append(f"- rework_log_path: {report.rework_log_path}")
    lines.append(f"- stability_log_path: {report.stability_log_path}")
    lines.append("")
    for lane_report in report.lane_reports:
        lines.append(f"## {lane_report.lane}")
        lines.append("")
        lines.append("```yaml")
        lines.append(json.dumps(asdict(lane_report), indent=2, sort_keys=False))
        lines.append("```")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def _jsonable(report: GateCWindowReport) -> dict[str, Any]:
    return asdict(report)


def evaluate_gate_c_window(
    project_root: Path,
    *,
    window_id: str,
    review_log_path: Path | None = None,
    rework_log_path: Path | None = None,
    stability_log_path: Path | None = None,
) -> GateCWindowReport:
    project_root = project_root.resolve()
    review_log_path = review_log_path or (project_root / "docs" / "status" / "gate-c-review-log.ndjson")
    rework_log_path = rework_log_path or (project_root / "docs" / "status" / "gate-c-rework-log.ndjson")
    stability_log_path = stability_log_path or (project_root / "docs" / "status" / "gate-c-stability-log.ndjson")

    review_entries = _parse_review_entries(review_log_path)
    rework_entries = _parse_rework_entries(rework_log_path)
    stability_entries = _parse_stability_entries(stability_log_path)
    window_id_valid = WINDOW_ID_RE.fullmatch(window_id) is not None

    lane_reports: list[LaneGateCReport] = []
    for lane in LANES:
        lane_reviews = [entry for entry in review_entries if entry.window_id == window_id and entry.lane == lane]
        lane_rework = [entry for entry in rework_entries if entry.window_id == window_id and entry.lane == lane]
        lane_stability_entries = [entry for entry in stability_entries if entry.window_id == window_id and entry.lane == lane]

        review_minutes = [minutes for minutes in (_review_minutes(entry) for entry in lane_reviews) if minutes is not None]
        valid_review_timing_count = len(review_minutes)
        reopen_count = sum(entry.reopen_count for entry in lane_rework)
        revert_count = sum(entry.revert_count for entry in lane_rework)
        total_changes = sum(entry.total_changes for entry in lane_rework)
        reopen_revert_rate = round((reopen_count + revert_count) / total_changes, 3) if total_changes else None
        inconsistent_rework_rows = [
            entry.run_id
            for entry in lane_rework
            if entry.total_changes <= 0
            or entry.reopen_revert_rate is None
            or round((entry.reopen_count + entry.revert_count) / entry.total_changes, 3) != round(entry.reopen_revert_rate, 3)
        ]

        evidence_gaps: list[str] = []
        warnings: list[str] = []
        if not window_id_valid:
            evidence_gaps.append("window_id does not match gate-c-window-YYYY-MM-DD")
        if not lane_reviews:
            evidence_gaps.append("review log entries missing")
        elif len(review_minutes) != len(lane_reviews):
            evidence_gaps.append("some review timestamps are missing or invalid")
        if valid_review_timing_count < MIN_VALID_REVIEW_TIMINGS_FOR_PASS:
            evidence_gaps.append(f"valid review timing count below {MIN_VALID_REVIEW_TIMINGS_FOR_PASS}")
        if total_changes == 0:
            evidence_gaps.append("reopen/revert denominator missing")
        if inconsistent_rework_rows:
            evidence_gaps.append("some rework rows have invalid denominator or rate")
        if not lane_stability_entries:
            evidence_gaps.append("stability log entry missing")

        lane_stability_status = "unknown"
        if lane_stability_entries:
            if any(entry.integration_stability == "degraded" for entry in lane_stability_entries):
                lane_stability_status = "degraded"
            else:
                lane_stability_status = "stable"

        integration_stability = {
            "integration_stability": lane_stability_status,
            "stability_note": lane_stability_entries[-1].stability_note if lane_stability_entries else "No explicit stability note recorded for this lane/window.",
            "stability_row_count": len(lane_stability_entries),
        }
        if integration_stability["integration_stability"] == "unknown":
            evidence_gaps.append("stability status unknown")

        gate_c_result = "pass"
        if integration_stability["integration_stability"] == "degraded" and not evidence_gaps:
            gate_c_result = "pause"
        elif evidence_gaps:
            gate_c_result = "provisional-pass"

        if inconsistent_rework_rows:
            warnings.append("rework rows with invalid rate were excluded from pass eligibility")

        lane_reports.append(
            LaneGateCReport(
                window_id=window_id,
                lane=lane,
                review_effort={
                    "avg_review_minutes": _avg(review_minutes) or 0,
                    "median_review_minutes": _median(review_minutes) or 0,
                    "p90_review_minutes": _percentile(review_minutes, 0.9) or 0,
                    "valid_review_timing_count": valid_review_timing_count,
                    "review_count": len(lane_reviews),
                },
                quality_rework={
                    "reopen_count": reopen_count,
                    "revert_count": revert_count,
                    "total_changes": total_changes,
                    "reopen_revert_rate": reopen_revert_rate,
                },
                integration_stability=integration_stability,
                gate_c_result=gate_c_result,
                evidence_gaps=evidence_gaps,
                warnings=warnings,
            )
        )

    return GateCWindowReport(
        window_id=window_id,
        lane_reports=lane_reports,
        review_log_path=str(review_log_path),
        rework_log_path=str(rework_log_path),
        stability_log_path=str(stability_log_path),
    )


def _build_human_output(report: GateCWindowReport) -> str:
    status_order = {"pass": 0, "provisional-pass": 1, "pause": 2}
    worst = max(report.lane_reports, key=lambda item: status_order[item.gate_c_result]).gate_c_result
    summary = build_summary_line(
        "gate_c",
        worst.upper(),
        "; ".join(f"{item.lane}={item.gate_c_result}" for item in report.lane_reports),
    )
    return summary + "\n" + json.dumps(_jsonable(report), indent=2, sort_keys=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Generate a Gate C window report.")
    parser.add_argument("--project-root", default=".")
    parser.add_argument("--window-id", required=True)
    parser.add_argument("--format", choices=["human", "json", "markdown"], default="human")
    parser.add_argument("--output")
    parser.add_argument("--review-log")
    parser.add_argument("--rework-log")
    parser.add_argument("--stability-log")
    args = parser.parse_args(argv)

    report = evaluate_gate_c_window(
        Path(args.project_root),
        window_id=args.window_id,
        review_log_path=Path(args.review_log) if args.review_log else None,
        rework_log_path=Path(args.rework_log) if args.rework_log else None,
        stability_log_path=Path(args.stability_log) if args.stability_log else None,
    )

    if args.format == "json":
        rendered = json.dumps(_jsonable(report), indent=2, sort_keys=True)
    elif args.format == "markdown":
        rendered = _markdown_report(report)
    else:
        rendered = _build_human_output(report)

    if args.output:
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(rendered if rendered.endswith("\n") else rendered + "\n", encoding="utf-8")

    print(rendered)
    return 1 if any(item.gate_c_result == "pause" for item in report.lane_reports) else 0


if __name__ == "__main__":
    raise SystemExit(main())