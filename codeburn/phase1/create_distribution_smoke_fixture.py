#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sqlite3
from pathlib import Path


def build_fixture(db_path: Path) -> dict[str, object]:
    phase1_dir = Path(__file__).resolve().parent
    schema_path = phase1_dir / "schema.sql"
    db_path.parent.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(db_path)
    conn.executescript(schema_path.read_text(encoding="utf-8"))
    conn.execute("DELETE FROM changed_files")
    conn.execute("DELETE FROM signals")
    conn.execute("DELETE FROM recovery_events")
    conn.execute("DELETE FROM steps")
    conn.execute("DELETE FROM sessions")

    session_id = "distribution-smoke-session"
    conn.execute(
        """
        INSERT INTO sessions(
          session_id, task, repo_path, git_branch, created_at, ended_at, ended_by, data_quality,
          provider_summary, comparability_token, comparability_duration, comparability_change
        ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            session_id,
            "distribution smoke fixture",
            ".",
            "main",
            "2026-05-05T00:00:00+00:00",
            "2026-05-05T00:00:03+00:00",
            "manual",
            "complete",
            None,
            0,
            1,
            1,
        ),
    )

    rows = [
        (
            "st1",
            session_id,
            "planning",
            "echo distribution-plan",
            "copilot",
            "2026-05-05T00:00:00+00:00",
            "2026-05-05T00:00:01+00:00",
            1000,
            0,
            2,
            0,
            120,
            45,
            165,
            "provider",
            "",
            "",
        ),
        (
            "st2",
            session_id,
            "execution",
            "echo distribution-execution",
            "copilot",
            "2026-05-05T00:00:01+00:00",
            "2026-05-05T00:00:02+00:00",
            1000,
            0,
            2,
            0,
            None,
            None,
            210,
            "estimated",
            "",
            "",
        ),
        (
            "st3",
            session_id,
            "test",
            "echo distribution-test",
            "local",
            "2026-05-05T00:00:02+00:00",
            "2026-05-05T00:00:03+00:00",
            1000,
            0,
            2,
            0,
            None,
            None,
            None,
            "unknown",
            "",
            "",
        ),
    ]
    conn.executemany(
        """
        INSERT INTO steps(
          step_id, session_id, step_kind, command, provider, started_at, ended_at, duration_ms, exit_code,
          stdout_bytes, stderr_bytes, prompt_tokens, completion_tokens, total_tokens, token_source,
          git_status_before, git_status_after
        ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        rows,
    )
    conn.commit()
    conn.close()

    return {
        "ok": True,
        "db_path": str(db_path),
        "session_id": session_id,
        "expected": {
            "token_observability_level": "step_level",
            "token_source_summary": "mixed(provider, estimated)",
            "decision_usage_allowed": False,
            "analysis_safe_for_decision": False,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Create a deterministic Phase 1 distribution smoke fixture DB.")
    parser.add_argument("--db", default="codeburn/phase1/examples/distribution_smoke.db")
    args = parser.parse_args()

    result = build_fixture(Path(args.db).resolve())
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())