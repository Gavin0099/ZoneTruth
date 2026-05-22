#!/usr/bin/env python3
"""
CodeBurn Stop Hook ??Session Token Display (P6)

Triggered by Claude Code Stop hook after each session.
Displays per-session token reconstruction + rolling 5h/7d windows.

Epistemic contract (V-1, P6 Scope Constraints):
  - All displayed values are Class C: observer-reconstructed, not provider-measured
  - analysis_safe_for_decision = 0 ??display is for observability only
  - Codex rate_limits.used_percent: read from JSONL, not stored in DB
  - Claude 5h/7d: rolling window from DB (token counts, not % ??limit unknown)
  - Fail-silent by design (hook always exits 0)

Usage:
  Called via Stop hook: python codeburn/phase1/codeburn_session_display.py
  Or manually: python codeburn/phase1/codeburn_session_display.py --transcript PATH

DB path (persistent, for rolling windows):
  Env CODEBURN_DB  ??override path
  Default: ~/.codeburn/codeburn.db
"""
from __future__ import annotations

import argparse
import json
import sqlite3
import sys
import os
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Optional


# ---------------------------------------------------------------------------
# Persistent DB helpers
# ---------------------------------------------------------------------------

def _get_db_path() -> Path:
    env = os.environ.get("CODEBURN_DB")
    if env:
        return Path(env)
    return Path.home() / ".codeburn" / "codeburn.db"


def _ensure_db(db_path: Path) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    schema = Path(__file__).with_name("schema.sql").read_text(encoding="utf-8")
    conn.executescript(schema)
    conn.commit()
    return conn


def _rolling_window(conn: sqlite3.Connection, provider: str, hours: int) -> tuple[int, int]:
    """Return (prompt_tokens, completion_tokens) for provider in last N hours."""
    cutoff = (datetime.now(timezone.utc) - timedelta(hours=hours)).isoformat()
    row = conn.execute(
        """
        SELECT
            COALESCE(SUM(prompt_tokens), 0)     AS pt,
            COALESCE(SUM(completion_tokens), 0) AS ct
        FROM steps
        WHERE provider = ? AND started_at >= ?
        """,
        (provider, cutoff),
    ).fetchone()
    return (row["pt"] if row else 0), (row["ct"] if row else 0)


# ---------------------------------------------------------------------------
# JSONL parsers
# ---------------------------------------------------------------------------

def _parse_claude_jsonl(path: Path) -> dict:
    """Parse Claude Code session JSONL. Returns session summary."""
    prompt_total = 0
    completion_total = 0
    cache_create_total = 0
    cache_read_total = 0
    turns = 0
    first_ts = None
    last_ts = None

    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                ts = rec.get("timestamp")
                if ts:
                    if first_ts is None:
                        first_ts = ts
                    last_ts = ts
                if rec.get("type") != "assistant":
                    continue
                usage = rec.get("message", {}).get("usage") or {}
                inp = usage.get("input_tokens")
                out = usage.get("output_tokens")
                cc  = usage.get("cache_creation_input_tokens", 0)
                cr  = usage.get("cache_read_input_tokens", 0)
                if inp is not None or out is not None:
                    prompt_total += inp or 0
                    completion_total += out or 0
                    cache_create_total += cc or 0
                    cache_read_total += cr or 0
                    turns += 1
    except Exception:
        pass

    return {
        "provider": "claude",
        "turns": turns,
        "prompt_tokens": prompt_total,
        "completion_tokens": completion_total,
        "cache_create_tokens": cache_create_total,
        "cache_read_tokens": cache_read_total,
        # rate_limit_tokens = input + cache_create + cache_read
        # For rate limit estimation ONLY ??not for billing (IAF-4).
        # Claude Code uses aggressive prompt caching; cache reads dominate actual consumption.
        "rate_limit_tokens": prompt_total + cache_create_total + cache_read_total,
        "first_ts": first_ts,
        "last_ts": last_ts,
        "rate_used_pct": None,
        "rate_resets_at": None,
    }


def _parse_codex_jsonl(path: Path) -> dict:
    """Parse Codex session JSONL. Returns session summary + rate_limits."""
    prompt_total = 0
    completion_total = 0
    turns = 0
    first_ts = None
    last_ts = None
    rate_used_pct = None
    rate_resets_at = None

    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                ts = rec.get("timestamp")
                if ts:
                    if first_ts is None:
                        first_ts = ts
                    last_ts = ts
                if rec.get("type") != "event_msg":
                    continue
                payload = rec.get("payload", {})
                if payload.get("type") != "token_count":
                    continue
                info = payload.get("info", {})
                last_usage = info.get("last_token_usage", {})
                inp = last_usage.get("input_tokens")
                out = last_usage.get("output_tokens")
                if inp is not None or out is not None:
                    prompt_total += inp or 0
                    completion_total += out or 0
                    turns += 1
                # rate_limits: read for display, not stored in DB (not an IAF field)
                rl = payload.get("rate_limits", {})
                if rl.get("used_percent") is not None:
                    rate_used_pct = rl["used_percent"]
                    rate_resets_at = rl.get("resets_at")
    except Exception:
        pass

    return {
        "provider": "codex",
        "turns": turns,
        "prompt_tokens": prompt_total,
        "completion_tokens": completion_total,
        "first_ts": first_ts,
        "last_ts": last_ts,
        "rate_used_pct": rate_used_pct,
        "rate_resets_at": rate_resets_at,
    }


def _detect_provider(path: Path) -> str:
    """Detect provider from JSONL content heuristics."""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                # Codex has event_msg + token_count
                if rec.get("type") == "event_msg":
                    if rec.get("payload", {}).get("type") == "token_count":
                        return "codex"
                # Claude has assistant + message.usage
                if rec.get("type") == "assistant" and "message" in rec:
                    return "claude"
    except Exception:
        pass
    return "claude"  # default


# ---------------------------------------------------------------------------
# Ingest session into persistent DB for rolling window tracking
# ---------------------------------------------------------------------------

def _ingest_into_persistent_db(
    conn: sqlite3.Connection,
    session_id: str,
    summary: dict,
) -> None:
    """Write session token records into persistent DB for rolling window queries."""
    provider = summary["provider"]
    turns = summary["turns"]
    if turns == 0:
        return

    # Ensure session row exists
    existing = conn.execute(
        "SELECT session_id FROM sessions WHERE session_id = ?", (session_id,)
    ).fetchone()
    if not existing:
        conn.execute(
            "INSERT INTO sessions (session_id, provider_summary) VALUES (?, ?)",
            (session_id, f"provider={provider}"),
        )

    # Check if already ingested (avoid double-counting)
    already = conn.execute(
        "SELECT COUNT(*) as n FROM steps WHERE session_id = ? AND provider = ?",
        (session_id, provider),
    ).fetchone()
    if already and already["n"] > 0:
        return  # already ingested this session

    # Write a single aggregate step for the session (not turn-by-turn)
    # This is sufficient for rolling window queries
    ts = summary.get("last_ts") or datetime.now(timezone.utc).isoformat()
    conn.execute(
        """
        INSERT INTO steps
            (session_id, provider, step_kind, started_at,
             prompt_tokens, completion_tokens, total_tokens,
             token_source, real_time_observed)
        VALUES (?, ?, 'execution', ?, ?, ?, NULL, 'unknown', 0)
        """,
        (
            session_id,
            provider,
            ts,
            summary["prompt_tokens"],
            summary["completion_tokens"],
        ),
    )
    conn.commit()


# ---------------------------------------------------------------------------
# Display
# ---------------------------------------------------------------------------

def _fmt(n: int) -> str:
    """Format token count with commas."""
    if n >= 1_000_000:
        return f"{n/1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n:,}"
    return str(n)


def _bar(pct: float, width: int = 20) -> str:
    """ASCII progress bar for percentage."""
    filled = int(round(pct / 100 * width))
    filled = max(0, min(width, filled))
    bar = "#" * filled + "-" * (width - filled)
    return f"[{bar}] {pct:.0f}%"


def _resets_in(resets_at: Optional[str]) -> str:
    if not resets_at:
        return ""
    try:
        reset_dt = datetime.fromisoformat(resets_at.replace("Z", "+00:00"))
        now = datetime.now(timezone.utc)
        delta = reset_dt - now
        if delta.total_seconds() <= 0:
            return " (resetting...)"
        h, rem = divmod(int(delta.total_seconds()), 3600)
        m = rem // 60
        return f" (resets in {h}h {m:02d}m)"
    except Exception:
        return ""


def _read_session_pct() -> Optional[dict]:
    """
    Read Claude session % from notification hook sidecar file.
    Written by codeburn_notification_hook.py when Claude Code fires a rate-limit notification.
    Returns dict with {session_pct, resets_in, recorded_at} or None if not available.
    """
    sidecar = Path.home() / ".codeburn" / "session_rate_pct.json"
    try:
        if not sidecar.exists():
            return None
        data = json.loads(sidecar.read_text(encoding="utf-8"))
        # Only use if recorded in the last 6 hours (stale beyond that)
        recorded = datetime.fromisoformat(data.get("recorded_at", ""))
        if (datetime.now(timezone.utc) - recorded).total_seconds() > 6 * 3600:
            return None
        return data
    except Exception:
        return None


def _get_warn_threshold(provider: str) -> Optional[int]:
    """
    Read advisory warning threshold from environment.

    Env vars:
      CODEBURN_CLAUDE_5H_ADVISORY_WARN_THRESHOLD
      CODEBURN_CODEX_5H_ADVISORY_WARN_THRESHOLD

    Epistemic status of this value:
      - Derived from ONE observed calibration point (cache-inclusive tokens at X% session)
      - cache_read_input_tokens accounting regime NOT verified against Anthropic quota semantics
      - billing / rate-limiting / subscription accounting may differ for the same token category
      - "same field name" (cache_read_input_tokens) ≠ "same accounting unit" across regimes
      - This is an observed saturation heuristic, NOT a verified provider quota boundary

    Permitted use: advisory warning / usage anomaly observation
    Forbidden use: "X% of Anthropic limit" claims, decision authority
    """
    key = {
        "claude": "CODEBURN_CLAUDE_5H_ADVISORY_WARN_THRESHOLD",
        "codex":  "CODEBURN_CODEX_5H_ADVISORY_WARN_THRESHOLD",
    }.get(provider)
    if key is None:
        return None
    val = os.environ.get(key, "").strip()
    if not val:
        return None
    try:
        n = int(val)
        return n if n > 0 else None
    except ValueError:
        return None


def _warn_threshold_pct(tokens: int, threshold: int) -> float:
    """Return how far past the warning threshold we are (0.0 = at threshold)."""
    return max(0.0, (tokens - threshold) / threshold * 100)


def display(
    session_id: str,
    summary: dict,
    conn: Optional[sqlite3.Connection],
) -> None:
    provider = summary["provider"]
    turns = summary["turns"]
    pt = summary["prompt_tokens"]
    ct = summary["completion_tokens"]
    cache_create = summary.get("cache_create_tokens", 0)
    cache_read = summary.get("cache_read_tokens", 0)
    rate_limit_tokens = summary.get("rate_limit_tokens")
    provider_reported_percent = summary["rate_used_pct"]
    rate_resets = summary["rate_resets_at"]

    W = 64
    sep = "-" * W

    print()
    print(f"+{sep}+")
    print(f"|  CodeBurn | Session Token Summary | Class C{' ' * (W - 45)}|")
    print(f"|  observer-reconstructed | not decision-authoritative{' ' * (W - 53)}|")
    print(f"+{sep}+")
    print(f"|  provider : {provider:<51}|")
    print(f"|  session  : {session_id[:8]}...{' ' * (W - 22)}|")
    print(f"|  turns    : {turns:<51}|")
    print(f"|  input    : {_fmt(pt):>10}  tokens (reconstructed){' ' * (W - 46)}|")
    print(f"|  output   : {_fmt(ct):>10}  tokens (reconstructed){' ' * (W - 46)}|")
    if provider == "claude":
        print(f"|  cache+   : {_fmt(cache_create):>10}  creation cache tokens{' ' * (W - 47)}|")
        print(f"|  cache=   : {_fmt(cache_read):>10}  read cache tokens{' ' * (W - 47)}|")
        if rate_limit_tokens is not None:
            line = f"  observed_rate_limit_tokens: {_fmt(rate_limit_tokens)} (reconstructed)"
            print(f"|{line:<{W}}|")

    # Codex: 5h rate limit from JSONL
    if provider == "codex" and provider_reported_percent is not None:
        reset_str = _resets_in(rate_resets)
        bar = _bar(provider_reported_percent)
        print(f"+{sep}+")
        line = f"  provider_reported_percent  {bar}{reset_str}"
        print(f"|{line:<{W}}|")

    # Claude: 5h % from notification hook sidecar (provider-reported, not reconstructed)
    if provider == "claude":
        pct_data = _read_session_pct()
        if pct_data:
            pct = pct_data.get("session_pct", 0)
            resets = pct_data.get("resets_in", "")
            reset_str = f"  resets in {resets}" if resets else ""
            bar = _bar(pct)
            print(f"+{sep}+")
            line = f"  provider_reported_percent  {bar}{reset_str}"
            print(f"|{line:<{W}}|")
            src = f"  (provider-reported via notification hook)"
            print(f"|{src:<{W}}|")

    # Rolling windows from DB
    pt5 = ct5 = pt7d = ct7d = 0
    if conn is not None:
        print(f"+{sep}+")
        print(f"|  Rolling windows (Class C | all sessions){' ' * (W - 42)}|")
        pt5, ct5 = _rolling_window(conn, provider, 5)
        pt7d, ct7d = _rolling_window(conn, provider, 24 * 7)
        line5h = f"  last 5h : in={_fmt(pt5)}  out={_fmt(ct5)}"
        line7d = f"  last 7d : in={_fmt(pt7d)}  out={_fmt(ct7d)}"
        print(f"|{line5h:<{W}}|")
        print(f"|{line7d:<{W}}|")

    print(f"+{sep}+")

    # Advisory warning: cache-inclusive 5h tokens vs. observed saturation heuristic
    # NOT a verified provider quota boundary. See _get_warn_threshold() docstring.
    advisory_threshold = _get_warn_threshold(provider)
    if conn is not None and advisory_threshold is not None and pt5 >= advisory_threshold:
        over_pct = _warn_threshold_pct(pt5, advisory_threshold)
        print(f"|{'!' * W}|")
        warn1 = f"  !! ADVISORY: cache-inclusive 5h tokens {_fmt(pt5)} >= {_fmt(advisory_threshold)}"
        warn2 = f"  !! Observed saturation heuristic -- NOT verified Anthropic quota boundary"
        warn3 = f"  !! cache_read accounting regime not confirmed. Check claude.ai for actual %."
        print(f"|{warn1:<{W}}|")
        print(f"|{warn2:<{W}}|")
        print(f"|{warn3:<{W}}|")
        print(f"|{'!' * W}|")
    elif conn is not None and advisory_threshold is None and provider == "claude":
        hint = "  Tip: CODEBURN_CLAUDE_5H_ADVISORY_WARN_THRESHOLD=<n> (observed heuristic)"
        print(f"|{hint:<{W}}|")

    print()


def _display_no_data(reason: str, session_id: Optional[str] = None) -> None:
    """Always show a compact status panel when tokens are unavailable."""
    W = 64
    sep = "-" * W
    sid = (session_id or "unknown")[:8]
    print()
    print(f"+{sep}+")
    print(f"|  CodeBurn | Session Token Summary | Class C{' ' * (W - 45)}|")
    print(f"|  status   : no token display{' ' * (W - 30)}|")
    print(f"+{sep}+")
    print(f"|  session  : {sid}...{' ' * (W - 22)}|")
    print(f"|  reason   : {reason:<51}|")
    print(f"+{sep}+")
    print()


def _extract_transcript_and_session(hook_data: dict) -> tuple[Optional[Path], Optional[str]]:
    """Best-effort extraction across stop-hook payload variants."""
    path_keys = (
        "transcript_path",
        "transcript",
        "log_path",
        "session_log_path",
        "conversation_path",
    )
    sid_keys = ("session_id", "sessionId", "id")

    def _find_path(d: dict) -> Optional[str]:
        for k in path_keys:
            v = d.get(k)
            if isinstance(v, str) and v.strip():
                return v.strip()
        return None

    def _find_sid(d: dict) -> Optional[str]:
        for k in sid_keys:
            v = d.get(k)
            if isinstance(v, str) and v.strip():
                return v.strip()
        return None

    tp = _find_path(hook_data)
    sid = _find_sid(hook_data)
    if tp:
        p = Path(tp)
        return p, sid or p.stem

    for nested_key in ("payload", "data", "context", "event"):
        nested = hook_data.get(nested_key)
        if not isinstance(nested, dict):
            continue
        tp = _find_path(nested)
        sid_nested = _find_sid(nested)
        if tp:
            p = Path(tp)
            return p, sid_nested or sid or p.stem
        if sid is None and sid_nested:
            sid = sid_nested

    return None, sid


def _debug_hook_payload(hook_data: dict) -> None:
    """Print a compact debug view of stop-hook stdin payload keys."""
    top_keys = sorted(hook_data.keys())
    print("[codeburn_session_display] hook payload debug")
    print(f"  top_level_keys: {top_keys}")
    for nested_key in ("payload", "data", "context", "event"):
        nested = hook_data.get(nested_key)
        if isinstance(nested, dict):
            print(f"  {nested_key}_keys: {sorted(nested.keys())}")
    tp, sid = _extract_transcript_and_session(hook_data)
    print(f"  detected_transcript: {str(tp) if tp else None}")
    print(f"  detected_session_id: {sid}")


def _discover_latest_transcript(session_id_hint: Optional[str] = None) -> tuple[Optional[Path], Optional[str]]:
    """Fallback discovery when hook payload does not provide transcript_path."""
    roots = [
        Path.home() / ".codex" / "sessions",
        Path.home() / ".claude" / "projects",
    ]

    # 1) If we have a session-id hint, try exact stem match first.
    if session_id_hint:
        for root in roots:
            if not root.exists():
                continue
            try:
                for p in root.rglob("*.jsonl"):
                    if p.stem == session_id_hint:
                        return p, session_id_hint
            except Exception:
                continue

    # 2) Otherwise pick the most recently modified plausible transcript.
    newest_path: Optional[Path] = None
    newest_mtime: float = -1.0
    for root in roots:
        if not root.exists():
            continue
        try:
            for p in root.rglob("*.jsonl"):
                name = p.name.lower()
                # Exclude known non-session JSONL artifacts
                if name == "session_index.jsonl":
                    continue
                if "observed-usage" in str(p).lower():
                    continue
                try:
                    mtime = p.stat().st_mtime
                except Exception:
                    continue
                if mtime > newest_mtime:
                    newest_mtime = mtime
                    newest_path = p
        except Exception:
            continue

    if newest_path is None:
        return None, session_id_hint
    return newest_path, (session_id_hint or newest_path.stem)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="CodeBurn session token display (Stop hook)",
        add_help=True,
    )
    parser.add_argument("--transcript", help="Path to session JSONL (overrides stdin)")
    parser.add_argument("--session-id", help="Session ID (overrides detection)")
    parser.add_argument("--no-db", action="store_true", help="Skip persistent DB (display only)")
    parser.add_argument(
        "--verbose-reason",
        action="store_true",
        help="Keep status panel even when transcript/tokens are unavailable",
    )
    parser.add_argument(
        "--debug-hook-json",
        action="store_true",
        help="Print hook stdin payload keys and detected transcript/session fields",
    )
    args = parser.parse_args()

    # 1. Get transcript path
    transcript_path: Optional[Path] = None
    session_id: Optional[str] = None

    if args.transcript:
        transcript_path = Path(args.transcript)
        session_id = args.session_id or transcript_path.stem
    else:
        # Read Stop hook stdin
        try:
            if not sys.stdin.isatty():
                hook_data = json.load(sys.stdin)
                if args.debug_hook_json and isinstance(hook_data, dict):
                    _debug_hook_payload(hook_data)
                transcript_path, extracted_sid = _extract_transcript_and_session(hook_data)
                session_id = args.session_id or extracted_sid
        except Exception:
            pass

    if transcript_path is None or not transcript_path.exists():
        discovered_path, discovered_sid = _discover_latest_transcript(session_id)
        if discovered_path is not None and discovered_path.exists():
            transcript_path = discovered_path
            session_id = session_id or discovered_sid
        else:
            _display_no_data("no_transcript_path_or_missing_file", session_id)
            return 0

    if session_id is None:
        session_id = transcript_path.stem

    # 2. Detect provider and parse
    provider = _detect_provider(transcript_path)
    if provider == "codex":
        summary = _parse_codex_jsonl(transcript_path)
    else:
        summary = _parse_claude_jsonl(transcript_path)

    if summary["turns"] == 0:
        _display_no_data("no_token_records_in_transcript", session_id)
        return 0

    # 3. Persistent DB for rolling windows
    conn = None
    if not args.no_db:
        try:
            db_path = _get_db_path()
            conn = _ensure_db(db_path)
            _ingest_into_persistent_db(conn, session_id, summary)
        except Exception:
            conn = None  # fail-silent: display without DB

    # 4. Display
    try:
        display(session_id, summary, conn)
    except Exception:
        pass  # fail-silent

    if conn:
        try:
            conn.close()
        except Exception:
            pass

    return 0


if __name__ == "__main__":
    sys.exit(main())


