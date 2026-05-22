#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import sqlite3
import subprocess
import uuid
from datetime import datetime, timezone
from pathlib import Path


def _load_phase1_bootstrap_module():
    module_path = Path(__file__).resolve().with_name("_phase1_cli_bootstrap.py")
    spec = importlib.util.spec_from_file_location("_phase1_cli_bootstrap", module_path)
    if spec is None or spec.loader is None:
        raise ImportError(f"unable to load phase1 bootstrap: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_BOOTSTRAP = _load_phase1_bootstrap_module()


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _ensure_schema(conn: sqlite3.Connection, schema_path: Path) -> None:
    conn.executescript(schema_path.read_text(encoding="utf-8"))
    conn.commit()


def _get_open_session(conn: sqlite3.Connection) -> str | None:
    row = conn.execute(
        """
        SELECT session_id
        FROM sessions
        WHERE ended_at IS NULL OR ended_at = ''
        ORDER BY created_at DESC
        LIMIT 1
        """
    ).fetchone()
    return str(row[0]) if row else None


def _git_status(repo: Path) -> str:
    try:
        out = subprocess.run(["git", "status", "--porcelain"], cwd=repo, capture_output=True, text=True, check=True)
        return out.stdout.strip()
    except Exception:
        return ""


def _git_changed_files(repo: Path) -> list[str]:
    try:
        out = subprocess.run(["git", "diff", "--name-only"], cwd=repo, capture_output=True, text=True, check=True)
        lines = [ln.strip() for ln in out.stdout.splitlines() if ln.strip()]
        return [ln.replace("\\", "/") for ln in lines]
    except Exception:
        return []


def _mark_session_partial(conn: sqlite3.Connection, session_id: str) -> None:
    conn.execute("UPDATE sessions SET data_quality='partial' WHERE session_id=?", (session_id,))
    conn.commit()


def _is_retry_step(step_kind: str | None, retry_of: str | None) -> bool:
    return step_kind == "retry" or (retry_of is not None and str(retry_of).strip() != "")


def _maybe_emit_retry_signal(conn: sqlite3.Connection, session_id: str, current_step_id: str) -> None:
    row = conn.execute(
        "SELECT step_kind, retry_of, started_at FROM steps WHERE step_id=?",
        (current_step_id,),
    ).fetchone()
    if not row:
        return
    current_kind, current_retry_of, current_started_at = row
    if not _is_retry_step(current_kind, current_retry_of):
        return

    rows = conn.execute(
        """
        SELECT step_id, step_kind, retry_of
        FROM steps
        WHERE session_id=?
          AND (started_at < ? OR (started_at = ? AND step_id <= ?))
        ORDER BY started_at DESC, step_id DESC
        LIMIT 20
        """,
        (session_id, current_started_at, current_started_at, current_step_id),
    ).fetchall()

    streak_ids: list[str] = []
    for step_id, step_kind, retry_of in rows:
        if _is_retry_step(step_kind, retry_of):
            streak_ids.append(str(step_id))
            continue
        break

    if len(streak_ids) != 3:
        return

    placeholders = ",".join("?" for _ in streak_ids)
    changed_count = conn.execute(
        f"SELECT COUNT(*) FROM changed_files WHERE step_id IN ({placeholders})",
        tuple(streak_ids),
    ).fetchone()[0]
    confidence = "low" if int(changed_count) > 0 else "medium"

    conn.execute(
        """
        INSERT INTO signals(
          session_id, step_id, signal, type, advisory_only, can_block, confidence, source, created_at
        ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            session_id,
            current_step_id,
            "retry_pattern_detected",
            "cost_risk",
            1,
            0,
            confidence,
            "phase1_heuristic",
            _now_iso(),
        ),
    )
    conn.commit()


def _maybe_emit_retry_fallback_signal(conn: sqlite3.Connection, session_id: str, current_step_id: str) -> None:
    row = conn.execute(
        "SELECT step_kind, retry_of, command, exit_code, started_at FROM steps WHERE step_id=?",
        (current_step_id,),
    ).fetchone()
    if not row:
        return
    current_kind, current_retry_of, current_command, current_exit_code, current_started_at = row
    if current_kind not in ("execution", "test"):
        return
    if _is_retry_step(current_kind, current_retry_of):
        return
    if current_exit_code is None or int(current_exit_code) == 0:
        return

    rows = conn.execute(
        """
        SELECT step_id, step_kind, retry_of, command, exit_code
        FROM steps
        WHERE session_id=?
          AND (started_at < ? OR (started_at = ? AND step_id <= ?))
        ORDER BY started_at DESC, step_id DESC
        LIMIT 20
        """,
        (session_id, current_started_at, current_started_at, current_step_id),
    ).fetchall()

    streak_ids: list[str] = []
    baseline_kind = str(current_kind)
    baseline_command = str(current_command or "").strip()
    for step_id, step_kind, retry_of, command, exit_code in rows:
        if step_kind != baseline_kind:
            break
        if _is_retry_step(step_kind, retry_of):
            break
        if str(command or "").strip() != baseline_command:
            break
        if exit_code is None or int(exit_code) == 0:
            break
        changed_cnt = conn.execute("SELECT COUNT(*) FROM changed_files WHERE step_id=?", (step_id,)).fetchone()[0]
        if int(changed_cnt) > 0:
            break
        streak_ids.append(str(step_id))

    if len(streak_ids) != 3:
        return

    existing = conn.execute(
        "SELECT COUNT(*) FROM signals WHERE session_id=? AND step_id=? AND signal='retry_pattern_inferred'",
        (session_id, current_step_id),
    ).fetchone()[0]
    if int(existing) > 0:
        return

    conn.execute(
        """
        INSERT INTO signals(
          session_id, step_id, signal, type, advisory_only, can_block, confidence, source, created_at
        ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            session_id,
            current_step_id,
            "retry_pattern_inferred",
            "cost_risk",
            1,
            0,
            "low",
            "phase1_fallback",
            _now_iso(),
        ),
    )
    conn.commit()


def run_step(args: argparse.Namespace) -> int:
    db_path = Path(args.db).resolve()
    schema = Path(args.schema).resolve()
    repo = Path(args.repo).resolve()

    conn = sqlite3.connect(db_path)
    _ensure_schema(conn, schema)

    session_id = _get_open_session(conn)
    if not session_id:
        print('{"ok":false,"error":"no_open_session"}')
        return 1

    step_id = str(uuid.uuid4())
    started_at = _now_iso()
    git_before = _git_status(repo)

    cmd_text = " ".join(args.command).strip()
    if not cmd_text:
        print('{"ok":false,"error":"empty_command"}')
        return 1

    launched = True
    exit_code = None
    duration_ms = None
    stdout_bytes = 0
    stderr_bytes = 0
    stderr_text = ""
    ended_at = None

    start_dt = datetime.now(timezone.utc)
    try:
        proc = subprocess.run(
            cmd_text,
            cwd=repo,
            shell=True,
            capture_output=True,
            text=False,
        )
        end_dt = datetime.now(timezone.utc)
        ended_at = end_dt.isoformat()
        duration_ms = int((end_dt - start_dt).total_seconds() * 1000)
        exit_code = int(proc.returncode)
        stdout_bytes = len(proc.stdout or b"")
        stderr_bytes = len(proc.stderr or b"")
    except Exception as exc:
        launched = False
        end_dt = datetime.now(timezone.utc)
        ended_at = end_dt.isoformat()
        stderr_text = str(exc)
        stderr_bytes = len(stderr_text.encode("utf-8", errors="ignore"))
        _mark_session_partial(conn, session_id)

    git_after = _git_status(repo)

    conn.execute(
        """
        INSERT INTO steps(
          step_id, session_id, step_kind, command, provider,
          started_at, ended_at, duration_ms, exit_code,
          stdout_bytes, stderr_bytes,
          prompt_tokens, completion_tokens, total_tokens, token_source,
          retry_of, git_status_before, git_status_after
        ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            step_id,
            session_id,
            args.step_kind,
            cmd_text,
            args.provider,
            started_at,
            ended_at,
            duration_ms,
            exit_code,
            stdout_bytes,
            stderr_bytes,
            getattr(args, "prompt_tokens", None),
            getattr(args, "completion_tokens", None),
            getattr(args, "total_tokens", None),
            args.token_source,
            args.retry_of,
            git_before,
            git_after,
        ),
    )

    changed = _git_changed_files(repo)
    for path in changed:
        conn.execute(
            "INSERT INTO changed_files(step_id, file_path, change_kind, source) VALUES(?, ?, ?, ?)",
            (step_id, path, "modified", "git_diff_name_only"),
        )

    # Hard rule: failed to start -> session data_quality must be partial.
    if not launched:
        _mark_session_partial(conn, session_id)

    _maybe_emit_retry_signal(conn, session_id, step_id)
    _maybe_emit_retry_fallback_signal(conn, session_id, step_id)

    conn.commit()

    result = {
        "ok": True,
        "session_id": session_id,
        "step_id": step_id,
        "launched": launched,
        "step_kind": args.step_kind,
        "command": cmd_text,
        "exit_code": exit_code,
        "duration_ms": duration_ms,
        "stdout_bytes": stdout_bytes,
        "stderr_bytes": stderr_bytes,
        "changed_files_count": len(changed),
    }
    import json

    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if launched and exit_code == 0 else 1


def main() -> int:
    print_phase1_header = _BOOTSTRAP.load_print_phase1_header()
    print_phase1_header()
    parser = argparse.ArgumentParser(description="CodeBurn Phase1 run wrapper.")
    parser.add_argument("--db", default="codeburn/phase1/examples/phase1_demo.db")
    parser.add_argument("--schema", default="codeburn/phase1/schema.sql")
    parser.add_argument("--repo", default=".")
    parser.add_argument("--step-kind", required=True, choices=["planning", "execution", "test", "retry", "reflection", "other"])
    parser.add_argument("--provider", default="local")
    parser.add_argument("--token-source", default="unknown", choices=["provider", "estimated", "unknown"])
    parser.add_argument("--prompt-tokens", type=int, default=None)
    parser.add_argument("--completion-tokens", type=int, default=None)
    parser.add_argument("--total-tokens", type=int, default=None)
    parser.add_argument("--retry-of", default=None)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    # allow: codeburn_run.py ... -- <command>
    if args.command and args.command[0] == "--":
        args.command = args.command[1:]

    return run_step(args)


if __name__ == "__main__":
    raise SystemExit(main())
