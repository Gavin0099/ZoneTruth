#!/usr/bin/env python3
"""
CodeBurn -- Codex Log Ingestion Smoke Command (P5.4)

Operability smoke only:
  - verifies ingestion pipeline can run deterministically
  - verifies authority ceiling remains intact
  - verifies ingestion boundary invariants are preserved

This command does NOT verify token correctness and does NOT enable
cross-provider comparison.
"""
from __future__ import annotations

import argparse
import json
import sqlite3
import sys
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _ensure_session(conn: sqlite3.Connection, session_id: str) -> None:
    existing = conn.execute(
        "SELECT 1 FROM sessions WHERE session_id = ?",
        (session_id,),
    ).fetchone()
    if existing is not None:
        return
    conn.execute(
        """
        INSERT INTO sessions(
            session_id, task, created_at, data_quality,
            comparability_token, comparability_duration, comparability_change
        ) VALUES(?, ?, ?, ?, ?, ?, ?)
        """,
        (session_id, "codex-log-ingestion-smoke", _now_iso(), "partial", 0, 1, 1),
    )
    conn.commit()


def _count_provenance_rows_for_session(conn: sqlite3.Connection, session_id: str) -> int:
    row = conn.execute(
        """
        SELECT COUNT(*)
        FROM step_ingestion_provenance p
        INNER JOIN steps s ON s.step_id = p.step_id
        WHERE s.session_id = ? AND s.provider = 'codex'
        """,
        (session_id,),
    ).fetchone()
    return int(row[0]) if row else 0


def _count_incomplete_token_records(conn: sqlite3.Connection, session_id: str) -> int:
    row = conn.execute(
        """
        SELECT COUNT(*)
        FROM steps
        WHERE session_id = ? AND provider = 'codex'
          AND (prompt_tokens IS NULL OR completion_tokens IS NULL)
        """,
        (session_id,),
    ).fetchone()
    return int(row[0]) if row else 0


def _authority_flags_all_false(conn: sqlite3.Connection, session_id: str) -> bool:
    row = conn.execute(
        """
        SELECT COUNT(*)
        FROM step_ingestion_provenance p
        INNER JOIN steps s ON s.step_id = p.step_id
        WHERE s.session_id = ? AND s.provider = 'codex'
          AND (
            p.epistemic_class != 'Class C'
            OR p.real_time_observed != 0
            OR p.analysis_safe_for_decision != 0
            OR p.provider_truthfulness_assumed != 0
          )
        """,
        (session_id,),
    ).fetchone()
    return (int(row[0]) if row else 0) == 0


def _boundary_invariants_hold(conn: sqlite3.Connection, session_id: str) -> bool:
    rows = conn.execute(
        """
        SELECT prompt_tokens, completion_tokens, total_tokens
        FROM steps
        WHERE session_id = ? AND provider = 'codex'
        ORDER BY started_at, rowid
        """,
        (session_id,),
    ).fetchall()

    if len(rows) < 2:
        return False

    # Fixture contracts:
    # - first record last_output_tokens is 80 and reasoning is 40 -> completion must remain 80
    # - second record last_input_tokens is 1200 while total_input_tokens is 2200 -> prompt must be 1200
    first_completion = rows[0][1]
    second_prompt = rows[1][0]
    all_total_null = all(row[2] is None for row in rows)
    return first_completion == 80 and second_prompt == 1200 and all_total_null


def _sqlite_surface_rejected(db_path: Path, conn: sqlite3.Connection) -> bool:
    from codeburn.phase2.codex_log_ingestor import ingest_codex_session

    try:
        ingest_codex_session(str(db_path), "smoke-reject-check", conn)
    except (ValueError, TypeError, OSError, IOError):
        return True
    except Exception:
        return False
    return False


def run_smoke(artifact_path: Path, db_path: Path, session_id: str) -> tuple[int, dict]:
    from codeburn.phase1.claude_log_ingestor import _ensure_schema
    from codeburn.phase2.codex_log_ingestor import ingest_codex_session

    conn = sqlite3.connect(str(db_path))
    conn.execute("PRAGMA foreign_keys = ON")
    _ensure_schema(conn)
    _ensure_session(conn, session_id)

    try:
        ingest_result = ingest_codex_session(str(artifact_path), session_id, conn)
    except FileNotFoundError:
        conn.close()
        return 1, {}
    except sqlite3.Error:
        conn.close()
        return 1, {}

    summary = {
        "processed_records": ingest_result.records_admitted,
        "skipped_records": ingest_result.records_skipped,
        "quarantined_records": ingest_result.records_quarantined,
        "provenance_rows_written": _count_provenance_rows_for_session(conn, session_id),
        "incomplete_token_records": _count_incomplete_token_records(conn, session_id),
        "sqlite_surface_rejected": _sqlite_surface_rejected(db_path, conn),
        "authority_flags_all_false": _authority_flags_all_false(conn, session_id),
    }

    invariants_ok = _boundary_invariants_hold(conn, session_id)
    conn.close()

    if not summary["authority_flags_all_false"] or not invariants_ok:
        return 2, summary
    return 0, summary


def _print_summary(summary: dict) -> None:
    ordered_keys = [
        "processed_records",
        "skipped_records",
        "quarantined_records",
        "provenance_rows_written",
        "incomplete_token_records",
        "sqlite_surface_rejected",
        "authority_flags_all_false",
    ]
    for key in ordered_keys:
        value = summary.get(key)
        if isinstance(value, bool):
            value = str(value).lower()
        print(f"{key}: {value}")


def main() -> int:
    default_fixture = (
        Path(__file__).resolve().parent / "examples" / "codex_smoke_fixture.jsonl"
    )
    parser = argparse.ArgumentParser(
        description="CodeBurn P5.4 -- Codex ingestion operability smoke."
    )
    parser.add_argument("--artifact", default=str(default_fixture))
    parser.add_argument("--db", default=None)
    parser.add_argument("--session-id", default=None)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    artifact_path = Path(args.artifact).resolve()
    session_id = args.session_id or f"codex-smoke-{uuid.uuid4().hex[:8]}"

    use_tmp_db = args.db is None
    if use_tmp_db:
        tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
        tmp.close()
        db_path = Path(tmp.name)
    else:
        db_path = Path(args.db)

    try:
        exit_code, summary = run_smoke(artifact_path, db_path, session_id)
        if summary:
            if args.json:
                print(json.dumps(summary, sort_keys=True))
            else:
                _print_summary(summary)
        return exit_code
    finally:
        if use_tmp_db:
            try:
                db_path.unlink(missing_ok=True)
            except Exception:
                pass


if __name__ == "__main__":
    raise SystemExit(main())
