#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import json
import sqlite3
import subprocess
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


def _load_phase1_bootstrap_module():
    module_path = Path(__file__).resolve().with_name("_phase1_cli_bootstrap.py")
    spec = importlib.util.spec_from_file_location("_phase1_cli_bootstrap", module_path)
    if spec is None or spec.loader is None:
        raise ImportError(f"unable to load phase1 bootstrap: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_BOOTSTRAP = _load_phase1_bootstrap_module()


DATA_QUALITY_COMPLETE = "complete"
DATA_QUALITY_PARTIAL = "partial"
DATA_QUALITY_RECOVERED = "recovered"


def _now_utc_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _parse_iso(value: str) -> datetime:
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    dt = datetime.fromisoformat(text)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _git_output(repo: Path, args: list[str]) -> str:
    try:
        res = subprocess.run(["git", *args], cwd=repo, capture_output=True, text=True, check=True)
        return res.stdout.strip()
    except Exception:
        return ""


def _git_branch(repo: Path) -> str:
    out = _git_output(repo, ["rev-parse", "--abbrev-ref", "HEAD"])
    return out or "unknown"


def _git_status_porcelain(repo: Path) -> str:
    out = _git_output(repo, ["status", "--porcelain"])
    return out


def _ensure_schema(conn: sqlite3.Connection, schema_path: Path) -> None:
    sql = schema_path.read_text(encoding="utf-8")
    conn.executescript(sql)
    conn.commit()


@dataclass
class OpenSession:
    session_id: str
    created_at: str


def _find_open_session(conn: sqlite3.Connection) -> OpenSession | None:
    row = conn.execute(
        """
        SELECT session_id, created_at
        FROM sessions
        WHERE ended_at IS NULL OR ended_at = ''
        ORDER BY created_at DESC
        LIMIT 1
        """
    ).fetchone()
    if not row:
        return None
    return OpenSession(session_id=str(row[0]), created_at=str(row[1]))


def _record_recovery_event(
    conn: sqlite3.Connection,
    *,
    previous_session_id: str,
    new_session_id: str | None,
    action_taken: str,
    reason: str,
    operator: str,
) -> None:
    conn.execute(
        """
        INSERT INTO recovery_events(previous_session_id, new_session_id, action_taken, reason, operator, created_at)
        VALUES(?, ?, ?, ?, ?, ?)
        """,
        (previous_session_id, new_session_id, action_taken, reason, operator, _now_utc_iso()),
    )
    conn.commit()


def _close_session(conn: sqlite3.Connection, session_id: str, ended_by: str, data_quality: str) -> None:
    conn.execute(
        """
        UPDATE sessions
        SET ended_at = ?, ended_by = ?, data_quality = ?
        WHERE session_id = ?
        """,
        (_now_utc_iso(), ended_by, data_quality, session_id),
    )
    conn.commit()


def session_start(args: argparse.Namespace) -> int:
    db_path = Path(args.db).resolve()
    repo = Path(args.repo).resolve()
    schema_path = Path(args.schema).resolve()
    db_path.parent.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(db_path)
    _ensure_schema(conn, schema_path)

    open_sess = _find_open_session(conn)
    if open_sess:
        created = _parse_iso(open_sess.created_at)
        idle_mins = (datetime.now(timezone.utc) - created).total_seconds() / 60.0
        timed_out = idle_mins >= args.idle_timeout_minutes

        if timed_out:
            _close_session(conn, open_sess.session_id, "idle_timeout", DATA_QUALITY_PARTIAL)
            _record_recovery_event(
                conn,
                previous_session_id=open_sess.session_id,
                new_session_id=None,
                action_taken="auto_close_previous",
                reason=f"idle-timeout-{args.idle_timeout_minutes}m",
                operator=args.operator,
            )
        else:
            action = args.open_session_action
            if action == "abort_start":
                _record_recovery_event(
                    conn,
                    previous_session_id=open_sess.session_id,
                    new_session_id=None,
                    action_taken="abort_start",
                    reason="open-session-detected",
                    operator=args.operator,
                )
                print(json.dumps({
                    "ok": False,
                    "error": "open_session_exists",
                    "open_session_id": open_sess.session_id,
                    "hint": "use --open-session-action auto_close_previous|resume_previous",
                }, ensure_ascii=False, indent=2))
                return 1
            if action == "resume_previous":
                conn.execute(
                    "UPDATE sessions SET data_quality = ? WHERE session_id = ?",
                    (DATA_QUALITY_RECOVERED, open_sess.session_id),
                )
                conn.commit()
                _record_recovery_event(
                    conn,
                    previous_session_id=open_sess.session_id,
                    new_session_id=open_sess.session_id,
                    action_taken="resume_previous",
                    reason="open-session-detected",
                    operator=args.operator,
                )
                print(json.dumps({
                    "ok": True,
                    "action": "resumed",
                    "session_id": open_sess.session_id,
                }, ensure_ascii=False, indent=2))
                return 0
            # auto close
            _close_session(conn, open_sess.session_id, "auto_close_previous", DATA_QUALITY_RECOVERED)
            _record_recovery_event(
                conn,
                previous_session_id=open_sess.session_id,
                new_session_id=None,
                action_taken="auto_close_previous",
                reason="open-session-detected",
                operator=args.operator,
            )

    session_id = str(uuid.uuid4())
    created_at = _now_utc_iso()
    row = (
        session_id,
        args.task,
        str(repo),
        _git_branch(repo),
        created_at,
        None,
        "manual",
        DATA_QUALITY_COMPLETE,
        None,
        0,
        1,
        1,
    )
    conn.execute(
        """
        INSERT INTO sessions(
          session_id, task, repo_path, git_branch, created_at, ended_at,
          ended_by, data_quality, provider_summary,
          comparability_token, comparability_duration, comparability_change
        ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        row,
    )
    conn.commit()

    print(json.dumps({
        "ok": True,
        "session_id": session_id,
        "task": args.task,
        "repo_path": str(repo),
        "git_branch": _git_branch(repo),
        "initial_git_status": _git_status_porcelain(repo),
        "created_at": created_at,
    }, ensure_ascii=False, indent=2))
    return 0


def session_end(args: argparse.Namespace) -> int:
    db_path = Path(args.db).resolve()
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    open_sess = _find_open_session(conn)
    if not open_sess:
        print(json.dumps({"ok": False, "error": "no_open_session"}, ensure_ascii=False, indent=2))
        return 1
    row = conn.execute("SELECT data_quality FROM sessions WHERE session_id=?", (open_sess.session_id,)).fetchone()
    data_quality = str(row["data_quality"]) if row and row["data_quality"] else DATA_QUALITY_COMPLETE
    _close_session(conn, open_sess.session_id, "manual", data_quality)
    result = {"ok": True, "session_id": open_sess.session_id, "ended_at": _now_utc_iso(), "data_quality": data_quality}

    # Always attach token observability summary on session close so operators can
    # see token state every time without needing a separate report command.
    report_path = Path(__file__).resolve().with_name("codeburn_report.py")
    report_spec = importlib.util.spec_from_file_location("codeburn_phase1_report", report_path)
    if report_spec and report_spec.loader:
        report_module = importlib.util.module_from_spec(report_spec)
        report_spec.loader.exec_module(report_module)
        report = report_module.build_report(db_path, open_sess.session_id)
        if report.get("ok"):
            token_count = report.get("token_count", {})
            token_summary = {
                "prompt_tokens": token_count.get("prompt_tokens"),
                "completion_tokens": token_count.get("completion_tokens"),
                "total_tokens": token_count.get("total_tokens"),
                "token_source_summary": report.get("token_source_summary", "unknown"),
                "token_observability_level": report.get("token_observability_level", "none"),
                "provenance_warning": report.get("provenance_warning", "provenance_unverified"),
                "decision_usage_allowed": report.get("decision_usage_allowed", False),
                "analysis_safe_for_decision": report.get("analysis_safe_for_decision", False),
            }
            result["token_summary"] = token_summary
            result["token_non_authoritative_notice"] = (
                "Token fields are observational only and MUST NOT be used for automated decision, gating, or quality inference."
            )

    print(json.dumps(result, ensure_ascii=False, indent=2))
    if "token_summary" in result:
        t = result["token_summary"]
        print(
            "Token summary: "
            f"prompt={t['prompt_tokens']}, completion={t['completion_tokens']}, total={t['total_tokens']}, "
            f"source={t['token_source_summary']}, observability={t['token_observability_level']}, "
            f"decision_usage_allowed={str(t['decision_usage_allowed']).lower()}"
        )
        print(result["token_non_authoritative_notice"])

    if args.analyze:
        analyze_path = Path(__file__).resolve().with_name("codeburn_analyze.py")
        spec = importlib.util.spec_from_file_location("codeburn_phase1_analyze", analyze_path)
        if spec and spec.loader:
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            analysis = module.build_analysis(db_path, open_sess.session_id)
            if analysis.get("ok"):
                print("")
                module.print_analysis_text(analysis)
    return 0


def session_status(args: argparse.Namespace) -> int:
    db_path = Path(args.db).resolve()
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    open_sess = _find_open_session(conn)
    if not open_sess:
        print(json.dumps({"ok": True, "open_session": None}, ensure_ascii=False, indent=2))
        return 0
    row = conn.execute("SELECT * FROM sessions WHERE session_id=?", (open_sess.session_id,)).fetchone()
    print(json.dumps({"ok": True, "open_session": dict(row)}, ensure_ascii=False, indent=2))
    return 0


def main() -> int:
    print_phase1_header = _BOOTSTRAP.load_print_phase1_header()
    print_phase1_header()
    parser = argparse.ArgumentParser(description="CodeBurn Phase 1 session CLI.")
    parser.add_argument("--db", default="codeburn/phase1/examples/phase1_demo.db")
    parser.add_argument("--schema", default="codeburn/phase1/schema.sql")
    parser.add_argument("--repo", default=".")
    parser.add_argument("--operator", default="local-operator")

    sub = parser.add_subparsers(dest="cmd", required=True)

    p_start = sub.add_parser("session-start")
    p_start.add_argument("--task", required=True)
    p_start.add_argument("--idle-timeout-minutes", type=int, default=60)
    p_start.add_argument(
        "--open-session-action",
        choices=["auto_close_previous", "resume_previous", "abort_start"],
        default="auto_close_previous",
    )

    p_end = sub.add_parser("session-end")
    p_end.add_argument("--analyze", dest="analyze", action="store_true", default=True)
    p_end.add_argument("--no-analyze", dest="analyze", action="store_false")
    sub.add_parser("session-status")

    args = parser.parse_args()

    if args.cmd == "session-start":
        return session_start(args)
    if args.cmd == "session-end":
        return session_end(args)
    return session_status(args)


if __name__ == "__main__":
    raise SystemExit(main())
