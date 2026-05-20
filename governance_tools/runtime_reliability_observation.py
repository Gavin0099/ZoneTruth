#!/usr/bin/env python3
"""
Observation-only runtime reliability evidence writer.

This module intentionally emits artifacts that are NOT gate-authoritative.
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SCHEMA_VERSION = "0.1"
PRODUCER_MODE = "observation_only"
DECISION_USAGE_ALLOWED = False
GATE_CONSUMPTION_ALLOWED = False

RUNTIME_ROOT = Path("artifacts") / "runtime"
INCIDENT_LOG = RUNTIME_ROOT / "incident-log.ndjson"
RECOVERY_LOG = RUNTIME_ROOT / "recovery-log.ndjson"
SIDE_EFFECT_JOURNAL = RUNTIME_ROOT / "side-effect-journal.ndjson"
DETERMINISM_BOUNDARY_LOG = RUNTIME_ROOT / "determinism-boundary-log.ndjson"


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _base_event(event_type: str) -> dict[str, Any]:
    return {
        "schema_version": SCHEMA_VERSION,
        "producer_mode": PRODUCER_MODE,
        "decision_usage_allowed": DECISION_USAGE_ALLOWED,
        "gate_consumption_allowed": GATE_CONSUMPTION_ALLOWED,
        "event_type": event_type,
        "timestamp_utc": _now(),
    }


def append_observation_event(project_root: Path, relpath: Path, event_type: str, payload: dict[str, Any]) -> Path:
    path = project_root / relpath
    path.parent.mkdir(parents=True, exist_ok=True)
    event = _base_event(event_type)
    event.update(payload)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(event, ensure_ascii=False) + "\n")
    return path


def safe_append_observation_event(project_root: Path, relpath: Path, event_type: str, payload: dict[str, Any]) -> Path | None:
    try:
        return append_observation_event(project_root, relpath, event_type, payload)
    except Exception:
        return None

