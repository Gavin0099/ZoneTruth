#!/usr/bin/env python3
"""
CodeBurn -- Claude Log Replay Smoke Command (P4.5)

Verifies that ingesting the same Claude .jsonl artifact twice produces
stable provenance identity tuples, confirming the three replay invariants:

  R1 -- source_record_line is stable across replay
  R2 -- source_record_offset is stable across replay
  R3 -- quarantine (line, offset) is stable across replay

Also confirms the non-idempotency contract:
  Row count doubles on second ingest (design decision, not a bug).

Exit codes:
  0 -- REPLAY_SMOKE_OK (all invariants hold)
  1 -- system error (file not found, DB error)
  2 -- replay invariant violation (line/offset changed between ingests)

What this does NOT verify:
  - Token count accuracy
  - epistemic class correctness (see P3.5 smoke for that)
  - Provider truthfulness
"""
from __future__ import annotations

import argparse
import sqlite3
import sys
import tempfile
import uuid
from pathlib import Path


def _print_separator(char: str = "-", width: int = 52) -> None:
    print(char * width)


def _get_provenance_pairs(conn: sqlite3.Connection, artifact_str: str) -> list[tuple]:
    rows = conn.execute(
        """
        SELECT p.source_record_line, p.source_record_offset
        FROM step_ingestion_provenance p
        INNER JOIN steps s ON p.step_id = s.step_id
        WHERE p.source_artifact_path = ?
        ORDER BY p.source_record_line, p.source_record_offset
        """,
        (artifact_str,),
    ).fetchall()
    return [(r[0], r[1]) for r in rows]


def _get_quarantine_pairs(conn: sqlite3.Connection, artifact_str: str) -> list[tuple]:
    rows = conn.execute(
        """
        SELECT source_record_line, source_record_offset
        FROM quarantined_records
        WHERE source_artifact_path = ?
        ORDER BY source_record_line, source_record_offset
        """,
        (artifact_str,),
    ).fetchall()
    return [(r[0], r[1]) for r in rows]


def run_replay_smoke(
    artifact_path: Path,
    db_path: Path,
    session_id: str,
    verbose: bool = False,
) -> int:
    """Run replay smoke. Returns exit code (0=ok, 1=system error, 2=invariant violation)."""
    from codeburn.phase1.claude_log_ingestor import ingest
    from codeburn.phase1.provenance_identity import provenance_identity

    print()
    print("CodeBurn -- Claude Log Replay Smoke (P4.5)")
    _print_separator("=")
    print(f"  artifact:  {artifact_path}")
    print(f"  session:   {session_id}")
    print(f"  db:        {db_path}")
    print()

    artifact_str = str(artifact_path.resolve())

    # --- First ingest ---
    print("Ingest 1 of 2 ...")
    try:
        result1 = ingest(
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
        print(f"ERROR: unexpected -- {type(exc).__name__}: {exc}", file=sys.stderr)
        return 1

    conn = sqlite3.connect(str(db_path))
    pairs_1 = _get_provenance_pairs(conn, artifact_str)
    q_pairs_1 = _get_quarantine_pairs(conn, artifact_str)
    conn.close()

    print(f"  processed:   {result1['processed']}")
    print(f"  quarantined: {result1['quarantined']}")
    print(f"  provenance pairs: {len(pairs_1)}")
    print(f"  quarantine pairs: {len(q_pairs_1)}")
    print()

    # --- Second ingest ---
    print("Ingest 2 of 2 ...")
    try:
        result2 = ingest(
            artifact_path=artifact_path,
            session_id=session_id,
            db_path=db_path,
        )
    except Exception as exc:
        print(f"ERROR: second ingest failed -- {type(exc).__name__}: {exc}", file=sys.stderr)
        return 1

    conn = sqlite3.connect(str(db_path))
    pairs_2 = _get_provenance_pairs(conn, artifact_str)
    q_pairs_2 = _get_quarantine_pairs(conn, artifact_str)
    conn.close()

    print(f"  processed:   {result2['processed']}")
    print(f"  quarantined: {result2['quarantined']}")
    print(f"  provenance pairs: {len(pairs_2)}")
    print(f"  quarantine pairs: {len(q_pairs_2)}")
    print()

    # --- Verify replay invariants ---
    violations = []

    # Non-idempotency contract: row count doubles
    if len(pairs_2) != 2 * len(pairs_1):
        violations.append(
            f"P4.4 non-idempotency: expected {2*len(pairs_1)} provenance rows "
            f"after 2 ingests, got {len(pairs_2)}"
        )

    if len(q_pairs_2) != 2 * len(q_pairs_1):
        violations.append(
            f"P4.4 non-idempotency: expected {2*len(q_pairs_1)} quarantine rows "
            f"after 2 ingests, got {len(q_pairs_2)}"
        )

    # R1 + R2: line/offset stability
    unique_1 = set(pairs_1)
    unique_2 = set(pairs_2)
    if unique_1 != unique_2:
        violations.append(
            f"R1/R2 violation: provenance identity pairs changed.\n"
            f"  ingest 1 unique: {sorted(unique_1)}\n"
            f"  ingest 2 unique: {sorted(unique_2)}"
        )

    # R3: quarantine stability
    unique_q1 = set(q_pairs_1)
    unique_q2 = set(q_pairs_2)
    if unique_q1 != unique_q2:
        violations.append(
            f"R3 violation: quarantine identity pairs changed.\n"
            f"  ingest 1 unique: {sorted(unique_q1)}\n"
            f"  ingest 2 unique: {sorted(unique_q2)}"
        )

    # --- Print results ---
    print("Replay invariant check:")
    _print_separator()
    print(f"  R1 source_record_line stable:   {'OK' if not any('R1' in v for v in violations) else 'FAIL'}")
    print(f"  R2 source_record_offset stable: {'OK' if not any('R2' in v for v in violations) else 'FAIL'}")
    print(f"  R3 quarantine (line,off) stable: {'OK' if not any('R3' in v for v in violations) else 'FAIL'}")
    print(f"  P4.4 non-idempotency contract:  {'OK' if not any('P4.4' in v for v in violations) else 'FAIL'}")
    print()

    if verbose:
        print("Provenance identity pairs (unique, from ingest 1):")
        for line, offset in sorted(unique_1):
            pid = provenance_identity(artifact_path, line, offset)
            print(f"  line={line:>4}  offset={offset}  -> {pid[0]}")
        print()

    if violations:
        print("REPLAY INVARIANT VIOLATIONS:", file=sys.stderr)
        for v in violations:
            print(f"  {v}", file=sys.stderr)
        print()
        print("Status: REPLAY_SMOKE_FAILED")
        return 2

    print("Non-idempotency contract: CONFIRMED")
    print(f"  First ingest produced {len(pairs_1)} provenance row(s).")
    print(f"  Second ingest produced {len(pairs_2)} provenance row(s) (expected 2x).")
    print()
    print("Status: REPLAY_SMOKE_OK")
    return 0


def main() -> int:
    default_fixture = (
        Path(__file__).resolve().parent / "examples" / "claude_smoke_fixture.jsonl"
    )

    parser = argparse.ArgumentParser(
        description="CodeBurn P4.5 -- Claude log replay smoke (provenance identity stability)."
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
        help="Session ID (default: auto-generated)",
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Show provenance identity tuples",
    )
    args = parser.parse_args()

    artifact_path = Path(args.artifact).resolve()
    session_id = args.session_id or f"replay-smoke-{uuid.uuid4().hex[:8]}"

    use_tmp_db = args.db is None
    if use_tmp_db:
        tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
        tmp.close()
        db_path = Path(tmp.name)
    else:
        db_path = Path(args.db)

    from codeburn.phase1.claude_log_ingestor import _ensure_schema
    conn = sqlite3.connect(str(db_path))
    conn.execute("PRAGMA foreign_keys = ON")
    _ensure_schema(conn)
    conn.execute(
        """
        INSERT OR IGNORE INTO sessions(
            session_id, task, created_at, data_quality,
            comparability_token, comparability_duration, comparability_change
        ) VALUES(?, ?, ?, ?, ?, ?, ?)
        """,
        (session_id, "claude-replay-smoke", "2026-05-20T00:00:00+00:00", "complete", 0, 1, 1),
    )
    conn.commit()
    conn.close()

    try:
        return run_replay_smoke(
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
