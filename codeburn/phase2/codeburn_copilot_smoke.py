#!/usr/bin/env python3
"""
CodeBurn -- Copilot Billing Ingestion Smoke Command

Operability smoke only (Class D boundary verification):
  - verifies billing evidence ingestion pipeline is operational
  - verifies preview/final states are represented correctly
  - verifies malformed rows are quarantined
  - verifies duplicate rows are skipped
  - verifies authority flags remain false

This command does NOT perform cost audit, token truth recovery,
or provider efficiency comparison.
"""
from __future__ import annotations

import argparse
import json
import sqlite3
import sys
import tempfile
import uuid
from pathlib import Path

# Allow direct script execution: python codeburn/phase2/codeburn_copilot_smoke.py
PROJECT_ROOT = Path(__file__).resolve().parents[2]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))


def _count_events(conn: sqlite3.Connection, csv_path: str) -> int:
    row = conn.execute(
        "SELECT COUNT(*) FROM copilot_billing_events WHERE source_artifact_path = ?",
        (csv_path,),
    ).fetchone()
    return int(row[0]) if row else 0


def _count_preview(conn: sqlite3.Connection, csv_path: str) -> int:
    row = conn.execute(
        "SELECT COUNT(*) FROM copilot_billing_events WHERE source_artifact_path = ? AND is_preview = 1",
        (csv_path,),
    ).fetchone()
    return int(row[0]) if row else 0


def _count_final(conn: sqlite3.Connection, csv_path: str) -> int:
    row = conn.execute(
        "SELECT COUNT(*) FROM copilot_billing_events WHERE source_artifact_path = ? AND is_preview = 0",
        (csv_path,),
    ).fetchone()
    return int(row[0]) if row else 0


def _count_quarantine(conn: sqlite3.Connection, csv_path: str) -> int:
    row = conn.execute(
        """
        SELECT COUNT(*)
        FROM quarantined_records
        WHERE provider = 'copilot_billing' AND source_artifact_path = ?
        """,
        (csv_path,),
    ).fetchone()
    return int(row[0]) if row else 0


def _authority_flags_all_false(conn: sqlite3.Connection, csv_path: str) -> bool:
    row = conn.execute(
        """
        SELECT COUNT(*)
        FROM copilot_billing_events
        WHERE source_artifact_path = ?
          AND (
            epistemic_class != 'Class D'
            OR acquisition_mode != 'billing_report_daily_aggregate'
            OR real_time_observed != 0
            OR analysis_safe_for_decision != 0
            OR provider_truthfulness_assumed != 0
          )
        """,
        (csv_path,),
    ).fetchone()
    return (int(row[0]) if row else 0) == 0


def run_smoke(csv_path: Path, db_path: Path, mark_final: bool = False) -> tuple[int, dict]:
    from codeburn.phase2.copilot_billing_ingestor import _ensure_db, ingest_copilot_csv

    conn = _ensure_db(db_path)
    try:
        result = ingest_copilot_csv(
            csv_path=str(csv_path),
            conn=conn,
            mark_final=mark_final,
        )
        inserted_events = _count_events(conn, str(csv_path))
        summary = {
            "processed_rows": result.rows_scanned,
            "inserted_events": inserted_events,
            "skipped_duplicates": result.rows_skipped_duplicate,
            "quarantined_rows": _count_quarantine(conn, str(csv_path)),
            "preview_events": _count_preview(conn, str(csv_path)),
            "final_events": _count_final(conn, str(csv_path)),
            "authority_flags_all_false": _authority_flags_all_false(conn, str(csv_path)),
        }
    except FileNotFoundError:
        conn.close()
        return 1, {}
    except sqlite3.Error:
        conn.close()
        return 1, {}
    finally:
        try:
            conn.commit()
            conn.close()
        except Exception:
            pass

    if not summary["authority_flags_all_false"]:
        return 2, summary
    return 0, summary


def _print_summary(summary: dict) -> None:
    ordered_keys = [
        "processed_rows",
        "inserted_events",
        "skipped_duplicates",
        "quarantined_rows",
        "preview_events",
        "final_events",
        "authority_flags_all_false",
    ]
    for key in ordered_keys:
        value = summary.get(key)
        if isinstance(value, bool):
            value = str(value).lower()
        print(f"{key}: {value}")


def main() -> int:
    default_fixture = Path(__file__).resolve().parent / "examples" / "copilot_smoke_fixture.csv"

    parser = argparse.ArgumentParser(
        description="CodeBurn -- Copilot billing evidence ingestion smoke command"
    )
    parser.add_argument("--csv", default=str(default_fixture))
    parser.add_argument("--db", default=None)
    parser.add_argument("--mark-final", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    csv_path = Path(args.csv).resolve()

    use_tmp_db = args.db is None
    if use_tmp_db:
        tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
        tmp.close()
        db_path = Path(tmp.name)
    else:
        db_path = Path(args.db)

    try:
        exit_code, summary = run_smoke(csv_path, db_path, mark_final=args.mark_final)
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
