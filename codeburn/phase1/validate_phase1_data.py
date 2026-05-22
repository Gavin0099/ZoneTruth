#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sqlite3
from pathlib import Path


def _count(conn: sqlite3.Connection, sql: str) -> int:
    return int(conn.execute(sql).fetchone()[0])


def validate(db_path: Path) -> dict:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    findings: list[str] = []

    required_tables = {"sessions", "steps", "changed_files", "signals", "recovery_events"}
    rows = conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()
    existing = {str(r[0]) for r in rows}
    missing = sorted(required_tables - existing)
    if missing:
        findings.append(f"missing_tables:{','.join(missing)}")

    if "sessions" in existing:
        bad_sessions = _count(
            conn,
            """
            SELECT COUNT(*) FROM sessions
            WHERE session_id IS NULL OR session_id='' OR task IS NULL OR task='' OR created_at IS NULL OR created_at='' OR data_quality IS NULL OR data_quality=''
            """,
        )
        if bad_sessions:
            findings.append(f"invalid_sessions_required_fields:{bad_sessions}")

        bad_time = _count(
            conn,
            """
            SELECT COUNT(*) FROM sessions
            WHERE ended_at IS NOT NULL AND ended_at <> '' AND created_at IS NOT NULL AND ended_at < created_at
            """,
        )
        if bad_time:
            findings.append(f"invalid_sessions_time_order:{bad_time}")

    if "steps" in existing:
        bad_steps = _count(
            conn,
            """
            SELECT COUNT(*) FROM steps
            WHERE step_id IS NULL OR step_id='' OR session_id IS NULL OR session_id='' OR step_kind IS NULL OR step_kind='' OR command IS NULL OR command='' OR started_at IS NULL OR started_at=''
            """,
        )
        if bad_steps:
            findings.append(f"invalid_steps_required_fields:{bad_steps}")

        # Hard rule: launched command must have exit_code + duration_ms.
        launched_missing = _count(
            conn,
            """
            SELECT COUNT(*) FROM steps
            WHERE ended_at IS NOT NULL
              AND (exit_code IS NULL OR duration_ms IS NULL)
              AND stderr_bytes = 0
            """,
        )
        if launched_missing:
            findings.append(f"invalid_steps_launched_missing_exit_or_duration:{launched_missing}")

        # Hard rule: failed to start -> exit_code NULL + stderr_bytes > 0 + session partial.
        failed_start_invalid = _count(
            conn,
            """
            SELECT COUNT(*)
            FROM steps s
            JOIN sessions sess ON sess.session_id = s.session_id
            WHERE s.exit_code IS NULL
              AND (s.stderr_bytes IS NULL OR s.stderr_bytes <= 0 OR sess.data_quality <> 'partial')
            """,
        )
        if failed_start_invalid:
            findings.append(f"invalid_steps_failed_start_contract:{failed_start_invalid}")

        missing_git_snapshot = _count(
            conn,
            """
            SELECT COUNT(*) FROM steps
            WHERE git_status_before IS NULL OR git_status_after IS NULL
            """,
        )
        if missing_git_snapshot:
            findings.append(f"invalid_steps_missing_git_status_snapshot:{missing_git_snapshot}")

    if "changed_files" in existing:
        bad_changed_file_path = _count(
            conn,
            """
            SELECT COUNT(*) FROM changed_files
            WHERE file_path IS NULL OR file_path='' OR instr(file_path, '\\') > 0
            """,
        )
        if bad_changed_file_path:
            findings.append(f"invalid_changed_files_path:{bad_changed_file_path}")

    if "signals" in existing:
        bad_block = _count(conn, "SELECT COUNT(*) FROM signals WHERE can_block <> 0")
        if bad_block:
            findings.append(f"phase1_signal_can_block_violation:{bad_block}")

        bad_adv = _count(conn, "SELECT COUNT(*) FROM signals WHERE advisory_only <> 1")
        if bad_adv:
            findings.append(f"phase1_signal_advisory_violation:{bad_adv}")

        bad_retry_contract = _count(
            conn,
            """
            SELECT COUNT(*) FROM signals
            WHERE signal='retry_pattern_detected'
              AND (
                type <> 'cost_risk'
                OR source <> 'phase1_heuristic'
                OR confidence NOT IN ('low', 'medium')
                OR advisory_only <> 1
                OR can_block <> 0
              )
            """,
        )
        if bad_retry_contract:
            findings.append(f"phase1_retry_signal_contract_violation:{bad_retry_contract}")

        bad_retry_inferred_contract = _count(
            conn,
            """
            SELECT COUNT(*) FROM signals
            WHERE signal='retry_pattern_inferred'
              AND (
                type <> 'cost_risk'
                OR source <> 'phase1_fallback'
                OR confidence <> 'low'
                OR advisory_only <> 1
                OR can_block <> 0
              )
            """,
        )
        if bad_retry_inferred_contract:
            findings.append(f"phase1_retry_inferred_signal_contract_violation:{bad_retry_inferred_contract}")

    ok = len(findings) == 0
    return {
        "ok": ok,
        "db_path": str(db_path),
        "finding_count": len(findings),
        "findings": findings,
    }


def main() -> int:
    from codeburn_phase1_header import print_phase1_header  # noqa: PLC0415
    print_phase1_header()
    parser = argparse.ArgumentParser(description="Validate CodeBurn Phase 1 data validity contract.")
    parser.add_argument("--db", required=True)
    parser.add_argument("--format", choices=("json",), default="json")
    parser.add_argument(
        "--include-analysis",
        action="store_true",
        help="Also run analysis contract enforcement (M7) for the given session.",
    )
    parser.add_argument(
        "--session",
        default="latest",
        help="Session ID or 'latest' for --include-analysis (default: latest)",
    )
    args = parser.parse_args()

    db = Path(args.db).resolve()
    result = validate(db)

    if args.include_analysis:
        from codeburn_validate_analysis import validate_analysis  # noqa: PLC0415

        analysis_result = validate_analysis(db, args.session)
        result["analysis_contract"] = analysis_result
        if not analysis_result["ok"]:
            result["ok"] = False
            for v in analysis_result["violations"]:
                result["findings"].append(f"analysis_contract_violation:{v}")
            result["finding_count"] = len(result["findings"])

    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
