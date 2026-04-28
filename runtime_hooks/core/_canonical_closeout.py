#!/usr/bin/env python3
"""
Canonical closeout producer.

Trust boundary:
  - AI output (candidate) is untrusted input.
  - This module validates, normalizes, and produces the canonical closeout artifact.
  - Only this module may write to artifacts/runtime/closeouts/.

Caller (run_session_end) is responsible for all IO before calling build_canonical_closeout():
  - load candidate via pick_latest_candidate()
  - supply closed_at from datetime.now()
  - supply existing_artifacts snapshot
  - supply runtime_signals from session

build_canonical_closeout() is a pure function: no filesystem IO, no timestamp generation.
Same inputs → same canonical output. Enables replay, audit re-run, dry-run testing.
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# Controlled vocabulary for closeout_status
_VALID_STATUSES = frozenset({
    "valid",
    "missing",
    "schema_invalid",
    "content_insufficient",
    "inconsistent",
})

# Tool names that imply verifiable execution traces.
# FROZEN TAXONOMY — do not extend without updating docs/closeout-schema.md.
# Matching is case-insensitive (lowercased before comparison).
# Normalization is NOT performed: "python -m pytest" does NOT match "pytest".
# Callers that want fuzzy matching must normalize tool names before supplying
# runtime_signals["tools_executed"].
_VERIFIABLE_TOOLS = frozenset({"pytest", "build", "lint", "test", "make"})

# Required fields in candidate payload
_CANDIDATE_REQUIRED_FIELDS: dict[str, type] = {
    "task_intent": str,
    "work_summary": str,
    "tools_used": list,
    "artifacts_referenced": list,
    "open_risks": list,
}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def pick_latest_candidate(session_id: str, project_root: Path) -> dict[str, Any] | None:
    """
    Load the most recent candidate closeout for session_id.

    Returns the parsed dict, or None if no candidate exists.
    Candidates are stored at:
        artifacts/runtime/closeout_candidates/{session_id}/{timestamp}.json

    Timestamp filenames are lexicographically sortable (YYYYmmddTHHMMSSffffffZ).
    "Latest" means authoring precedence — last written, not most complete.
    """
    candidates_dir = (
        project_root / "artifacts" / "runtime" / "closeout_candidates" / session_id
    )
    if not candidates_dir.is_dir():
        return None

    files = sorted(candidates_dir.glob("*.json"))
    if not files:
        return None

    latest = files[-1]
    try:
        return json.loads(latest.read_text(encoding="utf-8"))
    except Exception:
        return None


def build_canonical_closeout(
    *,
    session_id: str,
    closed_at: str,
    candidate_payload: dict[str, Any] | None,
    existing_artifacts: frozenset[str],
    runtime_signals: dict[str, Any] | None,
) -> dict[str, Any]:
    """
    Pure function: validate + normalize candidate → canonical closeout dict.

    GUARANTEE: never raises. Any input produces a valid canonical dict.
    The worst case is closeout_status = "missing" or "schema_invalid"; a
    canonical result is always assembled. Callers MUST NOT wrap this in
    try/except to suppress the return — the canonical dict is always usable.

    Does NOT perform filesystem IO, timestamp generation, or runtime dispatch.
    All external inputs must be supplied by the caller.

    closeout_status decision order:
        candidate_payload is None          → "missing"
        schema validation fails            → "schema_invalid"
        semantic validation: insufficient  → "content_insufficient"
        semantic validation: inconsistent  → "inconsistent"
        all checks pass                    → "valid"
    """
    if candidate_payload is None:
        return _make_canonical(session_id, closed_at, "missing", None)

    schema_ok, schema_reason = _validate_candidate_schema(candidate_payload)
    if not schema_ok:
        return _make_canonical(session_id, closed_at, "schema_invalid", candidate_payload)

    semantic_status = _run_semantic_validation(
        candidate=candidate_payload,
        existing_artifacts=existing_artifacts,
        runtime_signals=runtime_signals or {},
    )
    return _make_canonical(session_id, closed_at, semantic_status, candidate_payload)


def write_canonical_closeout(canonical: dict[str, Any], project_root: Path) -> Path:
    """
    Write canonical closeout artifact to artifacts/runtime/closeouts/{session_id}.json.
    Creates directory if needed. Returns the written path.
    """
    closeouts_dir = project_root / "artifacts" / "runtime" / "closeouts"
    closeouts_dir.mkdir(parents=True, exist_ok=True)
    path = closeouts_dir / f"{canonical['session_id']}.json"
    path.write_text(json.dumps(canonical, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return path


def candidate_timestamp() -> str:
    """
    Generate a lexicographically sortable timestamp string for candidate filenames.
    Format: YYYYmmddTHHMMSSffffffZ
    """
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")


def write_candidate(
    session_id: str,
    project_root: Path,
    candidate: dict[str, Any],
    *,
    timestamp: str | None = None,
) -> Path:
    """
    Write a candidate closeout for session_id.
    Append-only: each call writes a new timestamped file.
    Called by /wrap-up, not by session_end.
    """
    ts = timestamp or candidate_timestamp()
    candidate_dir = (
        project_root / "artifacts" / "runtime" / "closeout_candidates" / session_id
    )
    candidate_dir.mkdir(parents=True, exist_ok=True)
    path = candidate_dir / f"{ts}.json"
    path.write_text(json.dumps(candidate, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return path


# ---------------------------------------------------------------------------
# Internal: schema validation
# ---------------------------------------------------------------------------

def _validate_candidate_schema(candidate: dict[str, Any]) -> tuple[bool, str]:
    """
    Check that candidate has all required fields with correct types.
    Returns (ok, reason).
    """
    if not isinstance(candidate, dict):
        return False, "candidate is not a dict"

    for field, expected_type in _CANDIDATE_REQUIRED_FIELDS.items():
        if field not in candidate:
            return False, f"missing required field: {field}"
        if not isinstance(candidate[field], expected_type):
            return False, f"field {field!r} has wrong type: expected {expected_type.__name__}"

    # All list elements must be strings
    for list_field in ("tools_used", "artifacts_referenced", "open_risks"):
        for item in candidate.get(list_field, []):
            if not isinstance(item, str):
                return False, f"field {list_field!r} contains non-string element"

    return True, "ok"


# ---------------------------------------------------------------------------
# Internal: semantic validation
# ---------------------------------------------------------------------------

def _run_semantic_validation(
    *,
    candidate: dict[str, Any],
    existing_artifacts: frozenset[str],
    runtime_signals: dict[str, Any],
) -> str:
    """
    Minimal semantic validation. Returns the closeout_status string.

    Does NOT try to prove the candidate is truthful — only detects obvious gaps:
    - content_insufficient: work_summary empty, or no evidence at all
    - inconsistent: artifacts_referenced don't exist, or verifiable tools claimed
                    without corresponding runtime signal
    - valid: passes all checks
    """
    work_summary = (candidate.get("work_summary") or "").strip()
    tools_used = candidate.get("tools_used") or []
    artifacts_referenced = candidate.get("artifacts_referenced") or []

    # content_insufficient: work_summary empty
    if not work_summary:
        return "content_insufficient"

    # content_insufficient: no evidence whatsoever
    if not tools_used and not artifacts_referenced:
        return "content_insufficient"

    # inconsistent: artifacts_referenced files don't exist on disk
    for artifact in artifacts_referenced:
        if artifact and artifact not in existing_artifacts:
            return "inconsistent"

    # inconsistent: verifiable tool claimed but no runtime signal present
    claimed_verifiable = {t.lower() for t in tools_used} & _VERIFIABLE_TOOLS
    if claimed_verifiable:
        tool_signals = set(runtime_signals.get("tools_executed") or [])
        if not tool_signals:
            return "inconsistent"

    return "valid"


# ---------------------------------------------------------------------------
# Internal: canonical builder
# ---------------------------------------------------------------------------

def _make_canonical(
    session_id: str,
    closed_at: str,
    status: str,
    candidate: dict[str, Any] | None,
) -> dict[str, Any]:
    """
    Assemble the canonical closeout dict from validated inputs.
    When candidate is None or invalid, fields default to null/empty.
    """
    if candidate and status not in ("missing", "schema_invalid"):
        task_intent = candidate.get("task_intent") or None
        work_summary = candidate.get("work_summary") or None
        tools_used = list(candidate.get("tools_used") or [])
        artifacts_referenced = list(candidate.get("artifacts_referenced") or [])
        open_risks = list(candidate.get("open_risks") or [])
    else:
        task_intent = None
        work_summary = None
        tools_used = []
        artifacts_referenced = []
        open_risks = []

    return {
        "session_id": session_id,
        "closed_at": closed_at,
        "closeout_status": status,
        "task_intent": task_intent,
        "work_summary": work_summary,
        "evidence_summary": {
            "tools_used": tools_used,
            "artifacts_referenced": artifacts_referenced,
        },
        "open_risks": open_risks,
    }
