#!/usr/bin/env python3
"""
Canonical closeout context loader for session_start.

Reads the most recent canonical closeout artifact and assembles a
continuity context block based on closeout_status injection rules.

Trust boundary:
  - Reads from artifacts/runtime/closeouts/ ONLY (canonical artifacts).
  - Never reads closeout_candidates/ or session-index.ndjson.
  - Graceful degradation: any failure returns a no-context result, never raises.

Injection rules by closeout_status (from docs/closeout-schema.md):
  valid                → inject task_intent + work_summary + open_risks
  content_insufficient → diagnostic warning only (no summary content)
  missing / schema_invalid / inconsistent → minimal status warning only
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def load_closeout_context(project_root: Path) -> dict[str, Any]:
    """
    Load the most recent canonical closeout and return an injection context dict.

    GUARANTEE: never raises. Any failure (missing dir, bad JSON, empty dir)
    returns a degraded context with inject=False.

    Returns:
        {
            "inject": bool,
            "closeout_status": str | None,
            "session_id": str | None,
            "closed_at": str | None,
            "injection_level": "full" | "warning_only" | "none",
            "task_intent": str | None,          # only when injection_level = "full"
            "work_summary": str | None,         # only when injection_level = "full"
            "open_risks": list[str],            # only when injection_level = "full"
            "diagnostic": str | None,           # message for warning_only or none
        }
    """
    canonical = _load_latest_canonical(project_root)
    if canonical is None:
        return _no_context()
    return _build_context(canonical)


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

def _load_latest_canonical(project_root: Path) -> dict[str, Any] | None:
    """
    Find and load the canonical closeout with the most recent closed_at timestamp.

    Selection is by closed_at field value (ISO-8601 string), not filename.
    Returns None on any failure.
    """
    closeouts_dir = project_root / "artifacts" / "runtime" / "closeouts"
    if not closeouts_dir.is_dir():
        return None

    candidates: list[tuple[str, dict[str, Any]]] = []
    for path in closeouts_dir.glob("*.json"):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            closed_at = data.get("closed_at") or ""
            if closed_at and isinstance(closed_at, str):
                candidates.append((closed_at, data))
        except Exception:
            continue

    if not candidates:
        return None

    candidates.sort(key=lambda x: x[0], reverse=True)
    return candidates[0][1]


def _build_context(canonical: dict[str, Any]) -> dict[str, Any]:
    """
    Apply injection rules from docs/closeout-schema.md — Downstream Consumer Rules.
    """
    status = canonical.get("closeout_status")
    session_id = canonical.get("session_id")
    closed_at = canonical.get("closed_at")

    if status == "valid":
        return {
            "inject": True,
            "closeout_status": status,
            "session_id": session_id,
            "closed_at": closed_at,
            "injection_level": "full",
            "task_intent": canonical.get("task_intent"),
            "work_summary": canonical.get("work_summary"),
            "open_risks": list(canonical.get("open_risks") or []),
            "diagnostic": None,
        }

    if status == "content_insufficient":
        return {
            "inject": True,
            "closeout_status": status,
            "session_id": session_id,
            "closed_at": closed_at,
            "injection_level": "warning_only",
            "task_intent": None,
            "work_summary": None,
            "open_risks": [],
            "diagnostic": (
                "Previous session closeout quality insufficient: "
                "work_summary was empty or lacked evidence. "
                "Continuity context not available."
            ),
        }

    # missing / schema_invalid / inconsistent — minimal status note only
    _status_label = status or "unknown"
    return {
        "inject": True,
        "closeout_status": _status_label,
        "session_id": session_id,
        "closed_at": closed_at,
        "injection_level": "none",
        "task_intent": None,
        "work_summary": None,
        "open_risks": [],
        "diagnostic": f"Previous session closeout status: {_status_label}.",
    }


def _no_context() -> dict[str, Any]:
    """Return an empty context block when no canonical closeout is available."""
    return {
        "inject": False,
        "closeout_status": None,
        "session_id": None,
        "closed_at": None,
        "injection_level": "none",
        "task_intent": None,
        "work_summary": None,
        "open_risks": [],
        "diagnostic": None,
    }
