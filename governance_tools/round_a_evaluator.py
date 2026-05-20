#!/usr/bin/env python3
"""
Evaluate Round A rollout readiness from the run ledger and runtime session index.
"""

from __future__ import annotations

import argparse
import json
import re
import statistics
import subprocess
import sys
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from governance_tools.human_summary import build_summary_line


_RUN_ID_RE = re.compile(r'^run_id:\s+"(?P<run_id>[^"]+)"')
_SUMMARY_COUNT_RE = re.compile(r'^-\s+(?P<key>[a-z_]+)\s*=\s*(?P<value>.+)$')
_SEMANTIC_ROW_RE = re.compile(
    r'^\|\s*(?P<run_id>[^|]+?)\s*\|\s*semantic_slice_commit\s*\|\s*(?P<commit>[^|]+?)\s*\|\s*(?P<covered>yes|no)\s*\|$'
)
_QUICK_LOG_ROW_RE = re.compile(
    r'^\|\s*(?P<run_id>2026-[^|]+?)\s*\|\s*(?P<arm>A|B|single-arm)\s*\|\s*(?P<task_id>[^|]+?)\s*\|\s*(?P<closeout_status>[^|]+?)\s*\|\s*(?P<hard_failure>[^|]+?)\s*\|\s*(?P<anchoring_fail>[^|]+?)\s*\|\s*(?P<disposition>[^|]+?)\s*\|\s*(?P<accepted_change_count>[^|]+?)\s*\|\s*(?P<runtime_gov_ratio>[^|]+?)\s*\|$'
)


@dataclass
class QuickLogRow:
    run_id: str
    closeout_status: str
    hard_failure: bool
    accepted_change_count: int


@dataclass
class SemanticRow:
    run_id: str
    commit_hash: str
    closeout_covered: str


@dataclass
class RunEntry:
    run_id: str
    date_utc: str | None = None
    task_id: str | None = None
    task_type: str | None = None
    baseline_commit: str | None = None
    new_session_confirmed: bool | None = None
    run_source: str | None = None
    commit_hash: str | None = None
    session_id: str | None = None
    closeout_status: str | None = None
    closeout_covered: str | None = None
    mapping_confidence: str | None = None
    revert_needed_after_fix: bool | None = None
    reviewer_edit_effort: int | None = None
    hard_failure: bool | None = None


@dataclass
class RoundAEvaluation:
    ok: bool
    project_root: str
    ledger_path: str
    session_index_path: str
    data_consistency: dict[str, Any]
    closeout_quality: dict[str, Any]
    result_layer: dict[str, Any]
    rollout_gate: dict[str, Any]
    task_packs: dict[str, Any]
    warnings: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)


def _parse_bool(text: str | None) -> bool | None:
    if text is None:
        return None
    lowered = text.strip().lower()
    if lowered == "true":
        return True
    if lowered == "false":
        return False
    return None


def _parse_int(text: str | None) -> int | None:
    if text is None:
        return None
    try:
        return int(text.strip())
    except Exception:
        return None


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


def _git_commit_timestamp(project_root: Path, commit_hash: str) -> datetime | None:
    if commit_hash in (None, "", "uncommitted-validation-note"):
        return None
    result = subprocess.run(
        ["git", "-C", str(project_root), "show", "-s", "--format=%cI", commit_hash],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return None
    return _parse_iso8601(result.stdout.strip())


def _extract_yaml_blocks(ledger_text: str) -> list[str]:
    blocks: list[str] = []
    current: list[str] | None = None
    in_yaml = False
    for line in ledger_text.splitlines():
        if line.strip() == "```yaml":
            current = []
            in_yaml = True
            continue
        if line.strip() == "```" and in_yaml:
            blocks.append("\n".join(current or []))
            current = None
            in_yaml = False
            continue
        if in_yaml and current is not None:
            current.append(line)
    return blocks


def _parse_run_entry(block: str) -> RunEntry | None:
    values: dict[str, str] = {}
    current_section: str | None = None
    for raw_line in block.splitlines():
        line = raw_line.rstrip()
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.endswith(":") and not stripped.startswith("-"):
            current_section = stripped[:-1]
            continue
        if ":" not in stripped:
            continue
        key, value = stripped.split(":", 1)
        full_key = f"{current_section}.{key}" if current_section in {"metrics", "failure_flags"} else key
        values[full_key] = value.strip().strip('"')

    run_id = values.get("run_id")
    if not run_id:
        return None
    return RunEntry(
        run_id=run_id,
        date_utc=values.get("date_utc"),
        task_id=values.get("task_id"),
        task_type=values.get("task_type"),
        baseline_commit=values.get("baseline_commit"),
        new_session_confirmed=_parse_bool(values.get("new_session_confirmed")),
        run_source=values.get("run_source"),
        commit_hash=values.get("commit_hash"),
        session_id=values.get("session_id"),
        closeout_status=values.get("closeout_status"),
        closeout_covered=values.get("closeout_covered"),
        mapping_confidence=values.get("mapping_confidence"),
        revert_needed_after_fix=_parse_bool(values.get("metrics.revert_needed_after_fix")),
        reviewer_edit_effort=_parse_int(values.get("metrics.reviewer_edit_effort")),
        hard_failure=_parse_bool(values.get("failure_flags.hard_failure")),
    )


def _parse_ledger(ledger_path: Path) -> tuple[list[QuickLogRow], list[SemanticRow], list[RunEntry], dict[str, str]]:
    text = ledger_path.read_text(encoding="utf-8")
    quick_rows: list[QuickLogRow] = []
    semantic_rows: list[SemanticRow] = []
    summary_counts: dict[str, str] = {}

    for line in text.splitlines():
        match = _QUICK_LOG_ROW_RE.match(line)
        if match:
            quick_rows.append(
                QuickLogRow(
                    run_id=match.group("run_id").strip(),
                    closeout_status=match.group("closeout_status").strip(),
                    hard_failure=match.group("hard_failure").strip().lower() == "true",
                    accepted_change_count=int(match.group("accepted_change_count").strip()),
                )
            )
            continue

        match = _SEMANTIC_ROW_RE.match(line)
        if match:
            semantic_rows.append(
                SemanticRow(
                    run_id=match.group("run_id").strip(),
                    commit_hash=match.group("commit").strip(),
                    closeout_covered=match.group("covered").strip(),
                )
            )
            continue

        match = _SUMMARY_COUNT_RE.match(line)
        if match:
            summary_counts[match.group("key")] = match.group("value").strip()

    run_entries = [entry for entry in (_parse_run_entry(block) for block in _extract_yaml_blocks(text)) if entry]
    return quick_rows, semantic_rows, run_entries, summary_counts


def _parse_session_index(session_index_path: Path) -> list[dict[str, Any]]:
    sessions: list[dict[str, Any]] = []
    for line in session_index_path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        sessions.append(json.loads(stripped))
    return sessions


def _safe_ratio(numerator: int, denominator: int) -> float | None:
    if denominator == 0:
        return None
    return round(numerator / denominator, 3)


def _parse_summary_ratio(text: str | None) -> tuple[int, int] | None:
    if not text:
        return None
    match = re.search(r'(?P<num>\d+)\s*/\s*(?P<den>\d+)', text)
    if not match:
        return None
    return int(match.group("num")), int(match.group("den"))


def _normalize_semantic_detail_entries(
    semantic_rows: list[SemanticRow],
    run_entries: list[RunEntry],
) -> dict[str, RunEntry]:
    summary_by_run_id = {row.run_id: row for row in semantic_rows}
    semantic_detail_entries: dict[str, RunEntry] = {}

    for entry in run_entries:
        summary_row = summary_by_run_id.get(entry.run_id)
        if entry.run_source == "semantic_slice_commit" or summary_row is not None:
            semantic_detail_entries[entry.run_id] = RunEntry(
                run_id=entry.run_id,
                date_utc=entry.date_utc,
                task_id=entry.task_id,
                task_type=entry.task_type,
                baseline_commit=entry.baseline_commit,
                new_session_confirmed=entry.new_session_confirmed,
                run_source=entry.run_source or ("semantic_slice_commit" if summary_row else None),
                commit_hash=entry.commit_hash or (summary_row.commit_hash if summary_row else None),
                session_id=entry.session_id,
                closeout_status=entry.closeout_status,
                closeout_covered=entry.closeout_covered or (summary_row.closeout_covered if summary_row else None),
                mapping_confidence=entry.mapping_confidence,
                revert_needed_after_fix=entry.revert_needed_after_fix,
                reviewer_edit_effort=entry.reviewer_edit_effort,
                hard_failure=entry.hard_failure,
            )

    return semantic_detail_entries


def _build_task_packs() -> dict[str, Any]:
    return {
        "comparable_3x3": [
            "docs consistency repair",
            "claim-boundary wording repair",
            "small cross-file sync repair",
        ],
        "ambiguity_stress_pack": [
            "authority conflict narration",
            "stale evidence citation",
            "lifecycle ambiguity wording",
        ],
        "ablation_pack": [
            "no governance vocabulary",
            "docs-only governance",
            "runtime-hooks-only",
            "full governance contract",
        ],
        "lanes": ["Copilot", "Claude", "ChatGPT"],
    }


def evaluate_round_a(
    project_root: Path,
    *,
    commit_timestamp_resolver: Callable[[Path, str], datetime | None] = _git_commit_timestamp,
) -> RoundAEvaluation:
    project_root = project_root.resolve()
    ledger_path = project_root / "docs" / "ab-v1.2-run-ledger.md"
    session_index_path = project_root / "artifacts" / "session-index.ndjson"

    quick_rows, semantic_rows, run_entries, summary_counts = _parse_ledger(ledger_path)
    sessions = _parse_session_index(session_index_path)
    session_by_id = {str(item.get("session_id")): item for item in sessions if item.get("session_id")}

    semantic_detail_entries = _normalize_semantic_detail_entries(semantic_rows, run_entries)
    detail_run_ids = set(semantic_detail_entries)
    summary_run_ids = {row.run_id for row in semantic_rows}

    missing_detail_runs = sorted(summary_run_ids - detail_run_ids)
    orphan_detail_runs = sorted(detail_run_ids - summary_run_ids)

    session_missing_for_entries = sorted(
        entry.run_id
        for entry in semantic_detail_entries.values()
        if entry.session_id and entry.session_id not in session_by_id
    )

    inconsistent_high_mappings: list[str] = []
    for entry in semantic_detail_entries.values():
        if entry.mapping_confidence != "high":
            continue
        session = session_by_id.get(entry.session_id or "")
        commit_time = commit_timestamp_resolver(project_root, entry.commit_hash or "")
        closed_at = _parse_iso8601(session.get("closed_at") if session else None)
        if not session or entry.closeout_status != "valid" or closed_at is None or commit_time is None or closed_at < commit_time:
            inconsistent_high_mappings.append(entry.run_id)

    engineering_count = _parse_int(summary_counts.get("engineering_run_count"))
    covered_ratio = _parse_summary_ratio(summary_counts.get("closeout_covered_runs"))
    excluded_rows = _parse_int(summary_counts.get("excluded_non_commit_rows", "0")) or 0

    actual_semantic_total = len(semantic_rows)
    actual_covered_total = sum(1 for row in semantic_rows if row.closeout_covered == "yes")
    summary_count_match = engineering_count == actual_semantic_total
    summary_ratio_match = covered_ratio == (actual_covered_total, actual_semantic_total)

    valid_sessions = [item for item in sessions if item.get("closeout_status") == "valid"]
    completion_contract_pass_count = sum(
        1
        for row in semantic_rows
        if (
            (entry := semantic_detail_entries.get(row.run_id)) is not None
            and entry.closeout_status == "valid"
            and entry.closeout_covered == "yes"
            and entry.mapping_confidence == "high"
            and entry.session_id in session_by_id
        )
    )
    high_mapping_count = sum(1 for entry in semantic_detail_entries.values() if entry.mapping_confidence == "high")

    reviewer_efforts = [
        entry.reviewer_edit_effort
        for entry in run_entries
        if entry.reviewer_edit_effort is not None
    ]
    recent_entries = [entry for entry in run_entries if entry.date_utc]
    recent_entries.sort(key=lambda item: item.date_utc or "")
    recent_efforts = [
        entry.reviewer_edit_effort
        for entry in recent_entries[-5:]
        if entry.reviewer_edit_effort is not None
    ]
    revert_count = sum(1 for entry in run_entries if entry.revert_needed_after_fix is True)
    hard_failure_count = sum(1 for row in quick_rows if row.hard_failure)

    data_consistency = {
        "summary_count_match": summary_count_match,
        "summary_ratio_match": summary_ratio_match,
        "summary_detail_entry_match": not missing_detail_runs and not orphan_detail_runs,
        "session_id_exists_for_mapped_entries": not session_missing_for_entries,
        "mapping_confidence_reproducible": not inconsistent_high_mappings,
        "actual_semantic_total": actual_semantic_total,
        "actual_covered_total": actual_covered_total,
        "summary_engineering_run_count": engineering_count,
        "summary_closeout_covered_runs": covered_ratio,
        "excluded_non_commit_rows": excluded_rows,
        "missing_detail_runs": missing_detail_runs,
        "orphan_detail_runs": orphan_detail_runs,
        "session_missing_for_entries": session_missing_for_entries,
        "inconsistent_high_mappings": inconsistent_high_mappings,
    }

    closeout_quality = {
        "completion_contract_pass_rate": _safe_ratio(completion_contract_pass_count, actual_semantic_total),
        "completion_contract_pass_count": completion_contract_pass_count,
        "native_closeout_ratio": _safe_ratio(len(valid_sessions), len(sessions)),
        "valid_session_count": len(valid_sessions),
        "session_total": len(sessions),
        "mapped_high_ratio": _safe_ratio(high_mapping_count, actual_semantic_total),
        "mapped_high_count": high_mapping_count,
    }

    reviewer_edit_effort_avg = round(statistics.mean(reviewer_efforts), 3) if reviewer_efforts else None
    reviewer_edit_effort_recent_avg = round(statistics.mean(recent_efforts), 3) if recent_efforts else None
    reviewer_burden_non_increasing = (
        reviewer_edit_effort_avg is not None
        and reviewer_edit_effort_recent_avg is not None
        and reviewer_edit_effort_recent_avg <= reviewer_edit_effort_avg
    )

    result_layer = {
        "reviewer_edit_effort_avg": reviewer_edit_effort_avg,
        "reviewer_edit_effort_recent_avg": reviewer_edit_effort_recent_avg,
        "reviewer_burden_non_increasing": reviewer_burden_non_increasing,
        "reopen_or_revert_rate": _safe_ratio(revert_count, len(run_entries)),
        "revert_event_count": revert_count,
        "integration_stability_rate": _safe_ratio(len(quick_rows) - hard_failure_count, len(quick_rows)),
        "hard_failure_count": hard_failure_count,
        "quick_log_row_count": len(quick_rows),
        "note": "reopen_or_revert_rate currently uses revert_needed_after_fix because no separate reopen field exists in the ledger schema.",
    }

    pause_reasons: list[str] = []
    if not all(
        [
            data_consistency["summary_count_match"],
            data_consistency["summary_ratio_match"],
            data_consistency["summary_detail_entry_match"],
            data_consistency["session_id_exists_for_mapped_entries"],
            data_consistency["mapping_confidence_reproducible"],
        ]
    ):
        pause_reasons.append("data_consistency_check_failed")
    if closeout_quality["completion_contract_pass_rate"] is not None and closeout_quality["completion_contract_pass_rate"] < 1.0:
        pause_reasons.append("completion_contract_below_target")
    if closeout_quality["mapped_high_ratio"] is not None and closeout_quality["mapped_high_ratio"] < 1.0:
        pause_reasons.append("mapped_high_ratio_below_target")
    if result_layer["reviewer_burden_non_increasing"] is False:
        pause_reasons.append("reviewer_burden_rising")

    rollout_gate = {
        "expand_ready": len(pause_reasons) == 0,
        "pause_reasons": pause_reasons,
        "pass_criteria": {
            "data_consistency_without_manual_repair": len(pause_reasons) == 0 and data_consistency["summary_detail_entry_match"],
            "closeout_quality_stable": closeout_quality["completion_contract_pass_rate"] == 1.0,
            "reviewer_burden_flat_or_down": reviewer_burden_non_increasing,
            "no_text_only_drift_masking_signal": data_consistency["mapping_confidence_reproducible"],
        },
    }

    warnings: list[str] = []
    if excluded_rows:
        warnings.append("Non-commit rows are excluded from semantic coverage and must be tracked separately.")
    if result_layer["reviewer_edit_effort_avg"] is None:
        warnings.append("Reviewer edit effort trend is unavailable because no detailed run entries carried reviewer_edit_effort.")

    ok = len(pause_reasons) == 0
    return RoundAEvaluation(
        ok=ok,
        project_root=str(project_root),
        ledger_path=str(ledger_path),
        session_index_path=str(session_index_path),
        data_consistency=data_consistency,
        closeout_quality=closeout_quality,
        result_layer=result_layer,
        rollout_gate=rollout_gate,
        task_packs=_build_task_packs(),
        warnings=warnings,
        errors=[],
    )


def _to_jsonable(result: RoundAEvaluation) -> dict[str, Any]:
    return asdict(result)


def _build_human_output(result: RoundAEvaluation) -> str:
    status = "PASS" if result.ok else "PAUSE"
    line1 = build_summary_line(
        "round_a",
        status,
        (
            f"summary/detail={'ok' if result.data_consistency['summary_detail_entry_match'] and result.data_consistency['summary_count_match'] and result.data_consistency['summary_ratio_match'] else 'mismatch'}; "
            f"completion_contract={result.closeout_quality['completion_contract_pass_count']}/{result.data_consistency['actual_semantic_total']}; "
            f"mapped_high={result.closeout_quality['mapped_high_count']}/{result.data_consistency['actual_semantic_total']}"
        ),
    )
    lines = [line1]
    lines.append(json.dumps(_to_jsonable(result), indent=2, sort_keys=True))
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Evaluate Round A rollout readiness.")
    parser.add_argument("--project-root", default=".")
    parser.add_argument("--format", choices=["human", "json"], default="human")
    parser.add_argument("--output")
    args = parser.parse_args(argv)

    result = evaluate_round_a(Path(args.project_root))
    if args.format == "json":
        rendered = json.dumps(_to_jsonable(result), indent=2, sort_keys=True)
    else:
        rendered = _build_human_output(result)

    if args.output:
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(rendered + "\n", encoding="utf-8")

    print(rendered)
    return 0 if result.ok else 1


if __name__ == "__main__":
    raise SystemExit(main())