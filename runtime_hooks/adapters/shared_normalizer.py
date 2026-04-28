#!/usr/bin/env python3
"""
Shared helpers for normalizing harness-specific payloads into the runtime event contract.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def _first_value(payload: dict, *keys, default=None):
    for key in keys:
        if key in payload and payload[key] not in (None, ""):
            return payload[key]
    return default


def _normalize_rules(value) -> list[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    if isinstance(value, str):
        return [item.strip() for item in value.split(",") if item.strip()]
    return [str(value).strip()]


def normalize_payload(payload: dict, harness: str, event_type: str) -> dict:
    task = _first_value(payload, "task", "prompt", "request", "goal", "title")
    response_file = _first_value(
        payload,
        "response_file",
        "output_file",
        "assistant_response_path",
        "transcript_path",
        "result_file",
    )
    checks_file = _first_value(
        payload,
        "checks_file",
        "checks_path",
        "evidence_file",
        "evidence_path",
    )

    normalized = {
        "event_type": event_type,
        "project_root": _first_value(payload, "project_root", "cwd", "workspace", "repo_root", default="."),
        "plan_path": _first_value(payload, "plan_path", "plan", default="PLAN.md"),
        "task": task,
        "rules": _normalize_rules(_first_value(payload, "rules", "rule_packs", "active_rules")),
        "risk": _first_value(payload, "risk", "risk_level", default="medium"),
        "oversight": _first_value(payload, "oversight", "oversight_mode", default="review-required"),
        "memory_mode": _first_value(payload, "memory_mode", "memory", default="candidate"),
        "response_file": response_file,
        "impact_before_files": _normalize_rules(_first_value(payload, "impact_before_files", "impact_before")),
        "impact_after_files": _normalize_rules(_first_value(payload, "impact_after_files", "impact_after")),
        "create_snapshot": bool(
            _first_value(payload, "create_snapshot", "snapshot", "emit_snapshot", default=(event_type == "post_task"))
        ),
        "snapshot_summary": _first_value(payload, "snapshot_summary", "summary"),
        "metadata": {
            "harness": harness,
            "session_id": _first_value(payload, "session_id", "conversation_id", "run_id"),
            "native_event_type": _first_value(payload, "hook_event_name", "event", "event_name", default=event_type),
        },
    }
    contract = _first_value(payload, "contract", "contract_file")
    if contract not in (None, ""):
        normalized["contract"] = contract
    if checks_file not in (None, ""):
        normalized["checks_file"] = checks_file
    return normalized


def _load_payload(file_path: str | None) -> dict:
    if file_path:
        return json.loads(Path(file_path).read_text(encoding="utf-8"))
    return json.loads(sys.stdin.read())


def cli_main(harness: str) -> None:
    parser = argparse.ArgumentParser(description=f"Normalize {harness} payloads into the runtime event contract.")
    parser.add_argument("--event-type", choices=["session_start", "pre_task", "post_task"], required=True)
    parser.add_argument("--file", "-f", help="JSON payload file; defaults to stdin")
    args = parser.parse_args()

    payload = _load_payload(args.file)
    normalized = normalize_payload(payload, harness=harness, event_type=args.event_type)
    print(json.dumps(normalized, ensure_ascii=False, indent=2))
