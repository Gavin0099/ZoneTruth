#!/usr/bin/env python3
"""
CodeBurn Notification Hook

Intercepts Claude Code notifications (e.g. "You've used 92% of your session limit").
Parses the session % and writes it to ~/.codeburn/session_rate_pct.json so that
the Stop hook display and PreToolUse checks can show the actual provider-reported %.

This does NOT store the % in the DB (it is ephemeral state, not acquisition evidence).
The % is written to a JSON sidecar file only, for in-process display use.

Usage (configured in .claude/settings.json as a Notification hook):
  python codeburn/phase1/codeburn_notification_hook.py

Stdin (from Claude Code Notification hook):
  {"message": "You've used 92% of your session limit · resets in 3h", ...}

Output file: ~/.codeburn/session_rate_pct.json
  {"session_pct": 92, "message": "...", "recorded_at": "..."}

Fail-silent: exits 0 on any error.
"""
from __future__ import annotations

import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path


_PCT_RE = re.compile(r"(\d{1,3})%\s+of your session limit", re.IGNORECASE)
_RESET_RE = re.compile(r"resets?\s+in\s+(\d+h(?:\s*\d+m)?|\d+m)", re.IGNORECASE)

_SIDECAR_PATH = Path.home() / ".codeburn" / "session_rate_pct.json"


def _parse_notification(payload: dict) -> dict | None:
    """Extract session % from notification payload. Returns None if not a rate-limit notification."""
    # Claude Code notification payload: try common field names
    message = (
        payload.get("message")
        or payload.get("notification")
        or payload.get("text")
        or payload.get("title")
        or ""
    )
    if isinstance(message, dict):
        message = message.get("text") or message.get("content") or str(message)

    m = _PCT_RE.search(str(message))
    if not m:
        return None

    pct = int(m.group(1))
    resets_in = ""
    r = _RESET_RE.search(str(message))
    if r:
        resets_in = r.group(1).strip()

    return {
        "session_pct": pct,
        "resets_in": resets_in,
        "message": str(message)[:200],
        "recorded_at": datetime.now(timezone.utc).isoformat(),
    }


def main() -> int:
    try:
        if sys.stdin.isatty():
            return 0  # not invoked as hook

        raw = sys.stdin.read().strip()
        if not raw:
            return 0

        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            # Try treating the whole stdin as a plain text message
            payload = {"message": raw}

        result = _parse_notification(payload)
        if result is None:
            return 0  # not a rate-limit notification — ignore

        _SIDECAR_PATH.parent.mkdir(parents=True, exist_ok=True)
        _SIDECAR_PATH.write_text(
            json.dumps(result, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

        # If >= warn threshold, print to stderr so it appears in terminal immediately
        env_warn = os.environ.get("CODEBURN_CLAUDE_SESSION_WARN_PCT", "").strip()
        warn_pct = int(env_warn) if env_warn.isdigit() else 80
        if result["session_pct"] >= warn_pct:
            resets = f"  resets in {result['resets_in']}" if result["resets_in"] else ""
            print(
                f"\n!! CodeBurn: Claude session {result['session_pct']}% used{resets} !!\n",
                file=sys.stderr,
            )

    except Exception:
        pass  # fail-silent

    return 0


if __name__ == "__main__":
    sys.exit(main())
