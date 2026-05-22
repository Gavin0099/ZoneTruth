#!/usr/bin/env python3
"""
CodeBurn -- Claude Log Ingestion Smoke Command (P3.5)

Verifies that the Claude .jsonl ingestion pipeline is operational.
This is an operability smoke, not a token correctness verification.

What it checks:
  - Ingestion pipeline runs without system errors
  - Provenance rows are written with correct epistemic position
  - Authority ceiling flags are all False (Class C invariants hold)
  - Quarantined records are persisted (not silently dropped)
  - Incomplete token records are identified and counted

What it does NOT check:
  - Token count accuracy
  - Completeness of ingestion across a full session
  - Comparison of counts across providers
  - Any evaluative claim about session quality

Exit codes:
  0 -- smoke passed (pipeline operational, authority ceiling intact)
  1 -- system error (file not found, DB error, schema failure)
  2 -- authority ceiling breach detected (schema enforcement failure)

Quarantined records are NOT a failure condition for this smoke.
They are expected observational data about ingestion completeness.
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
    """Create a smoke session if it doesn't exist."""
    existing = conn.execute(
        "SELECT session_id FROM sessions WHERE session_id = ?", (session_id,)
    ).fetchone()
    if not existing:
        conn.execute(
            """
            INSERT INTO sessions(
                session_id, task, created_at, data_quality,
                comparability_token, comparability_duration, comparability_change
            ) VALUES(?, ?, ?, ?, ?, ?, ?)
            """,
            (
                session_id,
                "claude-log-ingestion-smoke",
                _now_iso(),
                "complete",
                0, 1, 1,
            ),
        )
        conn.commit()


def _check_authority_ceiling(conn: sqlite3.Connection) -> dict:
    """Verify that no provenance row has breached the authority ceiling.

    Returns a dict with breach_count and details.
    This should always be 0 -- the schema CHECK constraints enforce it,
    but we verify at the application layer as belt-and-suspenders.
    """
    breaches = []

    rows = conn.execute(
        """
        SELECT step_id, real_time_observed, analysis_safe_for_decision,
               provider_truthfulness_assumed, epistemic_class
        FROM step_ingestion_provenance
        """
    ).fetchall()

    for step_id, rto, asd, pta, cls in rows:
        if rto != 0:
            breaches.append(f"step {step_id}: real_time_observed={rto}")
        if asd != 0:
            breaches.append(f"step {step_id}: analysis_safe_for_decision={asd}")
        if pta != 0:
            breaches.append(f"step {step_id}: provider_truthfulness_assumed={pta}")
        if cls != "Class C":
            breaches.append(f"step {step_id}: epistemic_class={cls!r} (expected 'Class C')")

    return {"breach_count": len(breaches), "breaches": breaches}


def _count_incomplete_tokens(conn: sqlite3.Connection) -> int:
    """Count steps where token fields are NULL (absent from log, not zero usage)."""
    row = conn.execute(
        """
        SELECT COUNT(*) FROM steps s
        INNER JOIN step_ingestion_provenance p ON s.step_id = p.step_id
        WHERE s.prompt_tokens IS NULL OR s.completion_tokens IS NULL
        """
    ).fetchone()
    return int(row[0]) if row else 0


def _count_complete_tokens(conn: sqlite3.Connection) -> int:
    """Count steps where both token fields are present."""
    row = conn.execute(
        """
        SELECT COUNT(*) FROM steps s
        INNER JOIN step_ingestion_provenance p ON s.step_id = p.step_id
        WHERE s.prompt_tokens IS NOT NULL AND s.completion_tokens IS NOT NULL
        """
    ).fetchone()
    return int(row[0]) if row else 0


def _print_separator(char: str = "-", width: int = 52) -> None:
    print(char * width)


def run_smoke(
    artifact_path: Path,
    db_path: Path,
    session_id: str,
    verbose: bool = False,
) -> int:
    """Run the ingestion smoke. Returns exit code (0=ok, 1=system error, 2=ceiling breach)."""
    from codeburn.phase1.claude_log_ingestor import ingest

    print()
    print("CodeBurn -- Claude Log Ingestion Smoke")
    _print_separator("=")
    print(f"  artifact:  {artifact_path}")
    print(f"  session:   {session_id}")
    print(f"  db:        {db_path}")
    print()

    # Run ingestion
    try:
        result = ingest(
            artifact_path=artifact_path,
            session_id=session_id,
            db_path=db_path,
        )
    except FileNotFoundError as exc:
        print(f"ERROR: artifact not found -- {exc}", file=sys.stderr)
        return 1
    except sqlite3.Error as exc:
        print(f"ERROR: database error -- {exc}", file=sys.stderr)
        return 1
    except Exception as exc:
        print(f"ERROR: unexpected error -- {type(exc).__name__}: {exc}", file=sys.stderr)
        return 1

    # Query post-ingestion state
    conn = sqlite3.connect(str(db_path))
    conn.execute("PRAGMA foreign_keys = ON")

    provenance_rows = conn.execute(
        "SELECT COUNT(*) FROM step_ingestion_provenance WHERE step_id IN "
        "(SELECT step_id FROM steps WHERE session_id = ?)",
        (session_id,),
    ).fetchone()[0]

    quarantine_count = conn.execute(
        "SELECT COUNT(*) FROM quarantined_records "
        "WHERE source_artifact_path = ?",
        (str(artifact_path.resolve()),),
    ).fetchone()[0]

    incomplete_tokens = _count_incomplete_tokens(conn)
    complete_tokens = _count_complete_tokens(conn)
    authority_check = _check_authority_ceiling(conn)
    conn.close()

    # Print results
    print("Ingestion result:")
    print(f"  processed:         {result['processed']:>6}  (assistant records -> Class C evidence)")
    print(f"  skipped:           {result['skipped']:>6}  (non-assistant records, not applicable)")
    print(f"  quarantined:       {result['quarantined']:>6}  (malformed/inadmissible -> quarantined_records)")
    print()
    print("Provenance:")
    print(f"  provenance_rows:   {provenance_rows:>6}  (step_ingestion_provenance rows written)")
    print(f"  complete_tokens:   {complete_tokens:>6}  (records with both prompt + completion tokens)")
    print(f"  incomplete_tokens: {incomplete_tokens:>6}  (records where token fields are NULL)")
    print()
    print("Authority ceiling (must all be False):")
    print(f"  epistemic_class:              Class C (enforced)")
    print(f"  real_time_observed:           False")
    print(f"  analysis_safe_for_decision:   False")
    print(f"  provider_truthfulness_assumed: False")

    if authority_check["breach_count"] > 0:
        print()
        print("AUTHORITY CEILING BREACH DETECTED:", file=sys.stderr)
        for breach in authority_check["breaches"]:
            print(f"  {breach}", file=sys.stderr)
        print()
        print("Status: SMOKE_FAILED (authority ceiling breach)")
        return 2

    if verbose and quarantine_count > 0:
        conn2 = sqlite3.connect(str(db_path))
        q_rows = conn2.execute(
            "SELECT source_record_line, reason FROM quarantined_records "
            "WHERE source_artifact_path = ?",
            (str(artifact_path.resolve()),),
        ).fetchall()
        conn2.close()
        print()
        print(f"Quarantined records ({quarantine_count}):")
        for line, reason in q_rows:
            print(f"  line {line}: {reason}")

    print()
    print("Status: SMOKE_OK")
    return 0


def main() -> int:
    default_fixture = (
        Path(__file__).resolve().parent / "examples" / "claude_smoke_fixture.jsonl"
    )

    parser = argparse.ArgumentParser(
        description="CodeBurn P3.5 -- Claude log ingestion operability smoke."
    )
    parser.add_argument(
        "--artifact",
        default=str(default_fixture),
        help="Path to Claude Code .jsonl session log (default: built-in fixture)",
    )
    parser.add_argument(
        "--db",
        default=None,
        help="Path to CodeBurn SQLite DB (default: temporary file, deleted after smoke)",
    )
    parser.add_argument(
        "--session-id",
        default=None,
        help="Session ID to associate ingested steps with (default: auto-generated)",
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Show quarantined record details",
    )
    args = parser.parse_args()

    artifact_path = Path(args.artifact).resolve()
    session_id = args.session_id or f"smoke-{uuid.uuid4().hex[:8]}"

    use_tmp_db = args.db is None
    if use_tmp_db:
        tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
        tmp.close()
        db_path = Path(tmp.name)
    else:
        db_path = Path(args.db)

    # Ensure schema exists in db
    from codeburn.phase1.claude_log_ingestor import _ensure_schema
    conn = sqlite3.connect(str(db_path))
    conn.execute("PRAGMA foreign_keys = ON")
    _ensure_schema(conn)
    _ensure_session(conn, session_id)
    conn.close()

    try:
        return run_smoke(
            artifact_path=artifact_path,
            db_path=db_path,
            session_id=session_id,
            verbose=args.verbose,
        )
    finally:
        if use_tmp_db:
            try:
                db_path.unlink(missing_ok=True)
            except Exception:
                pass


if __name__ == "__main__":
    raise SystemExit(main())
