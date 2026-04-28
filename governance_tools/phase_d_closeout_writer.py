#!/usr/bin/env python3
"""
Phase D reviewer closeout artifact writer and assessor.

The closeout artifact is the authority gate between 'resumable' and 'completed'
for Phase D.  It must exist and carry trusted writer identity before any system
is permitted to mark Phase D as completed.

Design:
- Absent artifact → fail-closed (ok=False).  This is unconditional — unlike
  escalation register which falls back to ok=True when absent.
  Phase D completed without a reviewer closeout artifact is a governance violation.
- Untrusted writer → fail-closed.
- state_generator cannot derive 'completed' without this artifact passing
  assess_phase_d_closeout().

Canonical path (relative to project root):
  artifacts/governance/phase-d-reviewer-closeout.json
"""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


CLOSEOUT_WRITER_ID = "governance_tools.phase_d_closeout_writer"
CLOSEOUT_WRITER_VERSION = "1.0"
CLOSEOUT_SCHEMA = "governance.phase_d.closeout.v1"

CANONICAL_CLOSEOUT_RELPATH = Path("artifacts") / "governance" / "phase-d-reviewer-closeout.json"


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def write_phase_d_closeout(
    path: Path,
    reviewer_id: str,
    confirmed_conditions: list[str],
    *,
    confirmed_at: str | None = None,
    written_at: str | None = None,
) -> dict[str, Any]:
    """
    Write the Phase D reviewer closeout artifact.

    reviewer_id: identity of the reviewer explicitly confirming Phase D completion.
    confirmed_conditions: non-empty list of conditions the reviewer is confirming.
      Caller is responsible for meaningful content.

    Returns the artifact dict that was written.
    """
    if not isinstance(reviewer_id, str) or not reviewer_id.strip():
        raise ValueError("reviewer_id must be a non-empty string")
    if not isinstance(confirmed_conditions, list) or not confirmed_conditions:
        raise ValueError("confirmed_conditions must be a non-empty list")

    artifact = {
        "closeout_schema": CLOSEOUT_SCHEMA,
        "writer_id": CLOSEOUT_WRITER_ID,
        "writer_version": CLOSEOUT_WRITER_VERSION,
        "written_at": written_at or _utc_now(),
        "phase_completed": "D",
        "verdict": "completed",
        "reviewer_id": reviewer_id.strip(),
        "confirmed_at": confirmed_at or _utc_now(),
        "confirmed_conditions": list(confirmed_conditions),
        "reviewer_confirmation": "explicit",
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(artifact, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return artifact


def assess_phase_d_closeout(path: Path) -> dict[str, Any]:
    """
    Read and validate the Phase D reviewer closeout artifact.

    Returns:
      {
        "available": bool,
        "ok": bool,
        "review_confirmed": bool,
        "trusted_writer": bool,
        "reviewer_id": str | None,
        "confirmed_conditions": list[str],
        "verdict": str | None,
        "confirmed_at": str | None,
        "release_block_reasons": list[str],
      }

    Fail-closed semantics (stricter than escalation register):
      Absent artifact → ok=False, available=False.
      Callers MUST NOT treat absent as "not required" — absence means the
      closeout gate has not been satisfied.
    """
    if not path.is_file():
        return {
            "available": False,
            "ok": False,
            "review_confirmed": False,
            "trusted_writer": False,
            "reviewer_id": None,
            "confirmed_conditions": [],
            "release_block_reasons": ["phase_d_closeout_artifact_absent"],
        }

    try:
        artifact = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return {
            "available": True,
            "ok": False,
            "review_confirmed": False,
            "trusted_writer": False,
            "reviewer_id": None,
            "confirmed_conditions": [],
            "release_block_reasons": [f"phase_d_closeout_artifact_unreadable:{exc}"],
        }

    trusted_writer = (
        artifact.get("writer_id") == CLOSEOUT_WRITER_ID
        and artifact.get("writer_version") == CLOSEOUT_WRITER_VERSION
        and artifact.get("closeout_schema") == CLOSEOUT_SCHEMA
        and artifact.get("phase_completed") == "D"
        and artifact.get("reviewer_confirmation") == "explicit"
    )
    reviewer_id = artifact.get("reviewer_id")
    reviewer_id_valid = isinstance(reviewer_id, str) and bool(reviewer_id.strip())
    confirmed_conditions = list(artifact.get("confirmed_conditions") or [])
    conditions_present = len(confirmed_conditions) > 0
    confirmed_at = artifact.get("confirmed_at")
    confirmed_at_valid = isinstance(confirmed_at, str) and bool(confirmed_at.strip())
    verdict_valid = artifact.get("verdict") == "completed"

    ok = (
        trusted_writer
        and reviewer_id_valid
        and conditions_present
        and confirmed_at_valid
        and verdict_valid
    )
    reasons: list[str] = []
    if not trusted_writer:
        reasons.append("phase_d_closeout_writer_untrusted")
    if not reviewer_id_valid:
        reasons.append("phase_d_closeout_reviewer_id_missing")
    if not conditions_present:
        reasons.append("phase_d_closeout_confirmed_conditions_empty")
    if not confirmed_at_valid:
        reasons.append("phase_d_closeout_confirmed_at_missing")
    if not verdict_valid:
        reasons.append("phase_d_closeout_verdict_not_completed")

    return {
        "available": True,
        "ok": ok,
        "review_confirmed": ok,
        "trusted_writer": trusted_writer,
        "reviewer_id": reviewer_id if reviewer_id_valid else None,
        "confirmed_conditions": confirmed_conditions,
        "verdict": artifact.get("verdict"),
        "confirmed_at": confirmed_at if confirmed_at_valid else None,
        "release_block_reasons": reasons,
    }
