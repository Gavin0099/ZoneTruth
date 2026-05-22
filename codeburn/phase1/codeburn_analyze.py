#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import json
import sqlite3
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
token_observability_level = _BOOTSTRAP.load_token_observability_level()


def _format_duration_ms(ms: int | None) -> str:
    if ms is None or ms < 0:
        return "unknown"
    total_seconds = ms // 1000
    minutes = total_seconds // 60
    seconds = total_seconds % 60
    return f"{minutes}m{seconds:02d}s"


def _resolve_session_id(conn: sqlite3.Connection, session_id: str | None) -> str | None:
    if session_id and session_id != "latest":
        row = conn.execute("SELECT session_id FROM sessions WHERE session_id=?", (session_id,)).fetchone()
        return str(row[0]) if row else None
    row = conn.execute("SELECT session_id FROM sessions ORDER BY created_at DESC, session_id DESC LIMIT 1").fetchone()
    return str(row[0]) if row else None


def _step_order(conn: sqlite3.Connection, session_id: str) -> list[sqlite3.Row]:
    return conn.execute(
        """
        SELECT step_id, step_kind, command, retry_of, exit_code
        FROM steps
        WHERE session_id=?
        ORDER BY started_at ASC, step_id ASC
        """,
        (session_id,),
    ).fetchall()


def _token_observability_level(conn: sqlite3.Connection, session_id: str) -> str:
    rows = conn.execute(
        """
        SELECT token_source, prompt_tokens, completion_tokens, total_tokens
        FROM steps
        WHERE session_id=?
        """,
        (session_id,),
    ).fetchall()
    if not rows:
        return "none"
    return token_observability_level(rows)


def _derive_signal_steps(conn: sqlite3.Connection, session_id: str, signal: str, signal_step_id: str) -> list[str]:
    ordered = _step_order(conn, session_id)
    ids = [str(r["step_id"]) for r in ordered]
    if signal_step_id not in ids:
        return [signal_step_id]
    idx = ids.index(signal_step_id)
    if idx < 2:
        return [signal_step_id]

    window = ordered[idx - 2 : idx + 1]
    if signal == "retry_pattern_detected":
        def _is_retry(r: sqlite3.Row) -> bool:
            return str(r["step_kind"]) == "retry" or (r["retry_of"] is not None and str(r["retry_of"]).strip() != "")

        if all(_is_retry(r) for r in window):
            return [str(r["step_id"]) for r in window]
        return [signal_step_id]

    if signal == "retry_pattern_inferred":
        kinds = {str(r["step_kind"]) for r in window}
        commands = {str(r["command"] or "").strip() for r in window}
        nonzero_exit = all(r["exit_code"] is not None and int(r["exit_code"]) != 0 for r in window)
        no_retry_marker = all(str(r["step_kind"]) != "retry" and not (r["retry_of"] and str(r["retry_of"]).strip()) for r in window)
        if len(kinds) == 1 and list(kinds)[0] in {"execution", "test"} and len(commands) == 1 and nonzero_exit and no_retry_marker:
            return [str(r["step_id"]) for r in window]
        return [signal_step_id]

    return [signal_step_id]


def build_analysis(db_path: Path, session_id: str | None = "latest") -> dict:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row

    resolved = _resolve_session_id(conn, session_id)
    if not resolved:
        return {"ok": False, "error": "session_not_found"}

    session = conn.execute("SELECT * FROM sessions WHERE session_id=?", (resolved,)).fetchone()
    steps = conn.execute(
        """
        SELECT step_id, step_kind, command, duration_ms, exit_code
        FROM steps
        WHERE session_id=?
        ORDER BY started_at ASC, step_id ASC
        """,
        (resolved,),
    ).fetchall()
    step_count = len(steps)
    total_duration_ms = sum(int(r["duration_ms"]) for r in steps if r["duration_ms"] is not None)
    slowest = None
    for row in steps:
        if row["duration_ms"] is None:
            continue
        if slowest is None or int(row["duration_ms"]) > int(slowest["duration_ms"]):
            slowest = row

    breakdown = {
        "planning": 0,
        "execution": 0,
        "test": 0,
        "retry": 0,
        "reflection": 0,
        "other": 0,
    }
    for row in steps:
        kind = str(row["step_kind"])
        breakdown[kind] = breakdown.get(kind, 0) + 1

    changed_files_rows = conn.execute(
        """
        SELECT DISTINCT cf.file_path
        FROM changed_files cf
        JOIN steps s ON s.step_id = cf.step_id
        WHERE s.session_id=?
        ORDER BY cf.file_path ASC
        """,
        (resolved,),
    ).fetchall()
    changed_files = [str(r["file_path"]) for r in changed_files_rows]

    signals_rows = conn.execute(
        """
        SELECT signal, confidence, source, step_id
        FROM signals
        WHERE session_id=?
        ORDER BY id ASC, step_id ASC
        """,
        (resolved,),
    ).fetchall()
    signals = []
    for r in signals_rows:
        signal_name = str(r["signal"])
        signal_step = str(r["step_id"]) if r["step_id"] is not None else ""
        signals.append(
            {
                "signal": signal_name,
                "confidence": str(r["confidence"]),
                "source": str(r["source"]),
                "derived_from_steps": _derive_signal_steps(conn, resolved, signal_name, signal_step) if signal_step else [],
            }
        )

    token_observability_level = _token_observability_level(conn, resolved)
    analysis = {
        "ok": True,
        "phase": "phase1",
        "status": "closed",
        "decision_usage_allowed": False,
        "decision_safety": "NON_DECISIONAL",
        "session_id": resolved,
        "task": str(session["task"]),
        "data_quality": str(session["data_quality"]),
        "token_comparability": False,
        "token_observability_level": token_observability_level,
        "observability_boundary_disclosed": True,
        "analysis_safe_for_decision": False,
        "step_count": step_count,
        "total_duration_ms": total_duration_ms,
        "step_breakdown": breakdown,
        "slowest_step": (
            {
                "step_kind": str(slowest["step_kind"]),
                "command": str(slowest["command"]),
                "duration_ms": int(slowest["duration_ms"]),
                "exit_code": slowest["exit_code"],
            }
            if slowest
            else None
        ),
        "changed_files": changed_files,
        "signals": signals,
        "file_activity": {
            "git_visible_only": True,
            "file_reads": 0,
            "file_writes": 0,
            "file_reads_visible": False,
        },
        "observability_limits": {
            "token_usage": token_observability_level,
            "file_reads": "unsupported",
            "file_activity": "git-visible only",
        },
        "analysis_boundary": {
            "analysis_type": "observation",
            "interpretation_level": "low",
            "claims": False,
            "notes": [
                "This summary reports observed execution patterns only.",
                "No efficiency or correctness judgment is made.",
            ],
        },
        "non_authoritative_fields": [
            "token_observability_level",
        ],
    }
    return analysis


def print_analysis_text(analysis: dict) -> None:
    print("CodeBurn Post-Job Analysis")
    print("Interpretation notice: This analysis is observational. It is not a basis for optimization or correctness decisions.")
    print("")
    print("Session:")
    print(f"  Task: {analysis['task']}")
    print(f"  Data quality: {analysis['data_quality']}")
    print(f"  Token comparability: {'true' if analysis['token_comparability'] else 'false'}")
    print(f"  Token observability level: {analysis['token_observability_level']}")
    print("")
    print("Execution:")
    print(f"  Steps: {analysis['step_count']}")
    print(f"  Total duration: {_format_duration_ms(analysis['total_duration_ms'])}")
    slowest = analysis["slowest_step"]
    if slowest:
        print("  Slowest step:")
        print(
            f"    {slowest['step_kind']} | {slowest['command']} | "
            f"{_format_duration_ms(slowest['duration_ms'])} | exit_code={slowest['exit_code']} "
            "(by duration, not normalized)"
        )
    else:
        print("  Slowest step: none")
    print("")
    print("Step breakdown:")
    for key in ["planning", "execution", "test", "retry", "reflection", "other"]:
        print(f"  {key}: {analysis['step_breakdown'].get(key, 0)}")
    print("")
    print("Git-visible changes:")
    if analysis["changed_files"]:
        print(f"  {len(analysis['changed_files'])} file(s) changed")
        for path in analysis["changed_files"]:
            print(f"  - {path}")
    else:
        print("  0 file(s) changed")
    print("")
    print("Signals (diagnostic hints, not decision signals):")
    if analysis["signals"]:
        for item in analysis["signals"]:
            print(f"  [ADVISORY] {item['signal']}")
            print(f"  confidence: {item['confidence']}")
            print(f"  source: {item['source']}")
            if item["derived_from_steps"]:
                print(f"  derived_from_steps: {item['derived_from_steps']}")
    else:
        print("  none")
    print("")
    print("Observability limits:")
    print(f"  - Token usage: {analysis['token_observability_level']}")
    print("  - File reads: unsupported")
    print("  - File activity: git-visible only")
    print("")
    print("Analysis boundary:")
    print("  - Observations only")
    print("  - No efficiency judgment")
    print("  - No correctness judgment")


def main() -> int:
    print_phase1_header = _BOOTSTRAP.load_print_phase1_header()
    print_phase1_header()
    parser = argparse.ArgumentParser(description="CodeBurn Phase 1 post-job analysis.")
    parser.add_argument("--db", default="codeburn/phase1/examples/phase1_demo.db")
    parser.add_argument("--session", default="latest")
    parser.add_argument("--format", choices=["text", "json"], default="text")
    args = parser.parse_args()

    result = build_analysis(Path(args.db).resolve(), args.session)
    if not result.get("ok"):
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 1
    if args.format == "json":
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print_analysis_text(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
