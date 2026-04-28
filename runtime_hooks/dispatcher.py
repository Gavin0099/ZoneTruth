#!/usr/bin/env python3
"""
Dispatch shared runtime events to the correct governance core check.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from runtime_hooks.core.post_task_check import run_post_task_check
from runtime_hooks.core.pre_task_check import run_pre_task_check
from runtime_hooks.core.session_start import build_session_start_context
from runtime_hooks.runtime_path_overrides import apply_runtime_path_overrides


def dispatch_event(event: dict) -> dict:
    event_type = event["event_type"]

    if event_type == "pre_task":
        result = run_pre_task_check(
            project_root=Path(event["project_root"]),
            rules=",".join(event.get("rules", [])),
            risk=event["risk"],
            oversight=event["oversight"],
            memory_mode=event["memory_mode"],
            task_text=event.get("task") or "",
            impact_before_files=[Path(path) for path in event.get("impact_before_files", [])],
            impact_after_files=[Path(path) for path in event.get("impact_after_files", [])],
            contract_file=Path(event["contract"]).resolve() if event.get("contract") else None,
        )
    elif event_type == "session_start":
        result = build_session_start_context(
            project_root=Path(event["project_root"]),
            plan_path=Path(event.get("plan_path") or (Path(event["project_root"]) / "PLAN.md")),
            rules=",".join(event.get("rules", [])),
            risk=event["risk"],
            oversight=event["oversight"],
            memory_mode=event["memory_mode"],
            task_text=event.get("task") or "",
            impact_before_files=[Path(path) for path in event.get("impact_before_files", [])],
            impact_after_files=[Path(path) for path in event.get("impact_after_files", [])],
            contract_file=Path(event["contract"]).resolve() if event.get("contract") else None,
        )
    elif event_type == "post_task":
        response_text = ""
        response_file = event.get("response_file")
        if response_file:
            response_text = Path(response_file).read_text(encoding="utf-8")
        checks = None
        checks_file = event.get("checks_file")
        if checks_file:
            checks = json.loads(Path(checks_file).read_text(encoding="utf-8"))

        result = run_post_task_check(
            response_text=response_text,
            risk=event["risk"],
            oversight=event["oversight"],
            memory_mode=event["memory_mode"],
            memory_root=Path(event["project_root"]) / "memory" if event.get("create_snapshot") else None,
            snapshot_task=event.get("task"),
            snapshot_summary=event.get("snapshot_summary"),
            create_snapshot=event.get("create_snapshot", False),
            checks=checks,
            contract_file=Path(event["contract"]).resolve() if event.get("contract") else None,
            project_root=Path(event["project_root"]),
            evidence_paths=[Path(path).resolve() for path in [response_file, checks_file] if path],
        )
    else:
        raise ValueError(f"Unsupported event_type: {event_type}")

    return {
        "event_type": event_type,
        "result": result,
    }


def format_human_envelope(envelope: dict) -> str:
    lines = [
        f"event_type={envelope['event_type']}",
        f"ok={envelope['result']['ok']}",
    ]
    result = envelope["result"]
    contract_resolution = result.get("contract_resolution") or {}
    if contract_resolution.get("source"):
        lines.append(f"contract_source={contract_resolution['source']}")
    if contract_resolution.get("path"):
        lines.append(f"contract_path={contract_resolution['path']}")
    domain_contract = result.get("domain_contract") or {}
    if domain_contract.get("name"):
        lines.append(f"domain_contract={domain_contract['name']}")
    for warning in result.get("warnings", []):
        lines.append(f"warning: {warning}")
    for error in result.get("errors", []):
        lines.append(f"error: {error}")
    return "\n".join(lines)


def _load_event(file_path: str | None) -> dict:
    if file_path:
        return json.loads(Path(file_path).read_text(encoding="utf-8"))
    return json.loads(sys.stdin.read())


def main() -> None:
    parser = argparse.ArgumentParser(description="Dispatch a shared runtime event to governance core checks.")
    parser.add_argument("--file", "-f", help="Shared event JSON file; defaults to stdin")
    parser.add_argument("--project-root", help="Override project_root in the shared event.")
    parser.add_argument("--plan-path", help="Override plan_path in the shared event.")
    parser.add_argument("--contract", help="Explicit contract.yaml path for the shared event.")
    parser.add_argument("--response-file", help="Override response_file in the shared event.")
    parser.add_argument("--checks-file", help="Override checks_file in the shared event.")
    parser.add_argument("--format", choices=["human", "json"], default="human")
    args = parser.parse_args()

    event = _load_event(args.file)
    event = apply_runtime_path_overrides(
        event,
        project_root=Path(args.project_root).resolve() if args.project_root else None,
        plan_path=Path(args.plan_path).resolve() if args.plan_path else None,
        contract_file=Path(args.contract).resolve() if args.contract else None,
        response_file=Path(args.response_file).resolve() if args.response_file else None,
        checks_file=Path(args.checks_file).resolve() if args.checks_file else None,
    )
    envelope = dispatch_event(event)

    if args.format == "json":
        print(json.dumps(envelope, ensure_ascii=False, indent=2))
    else:
        print(format_human_envelope(envelope))

    sys.exit(0 if envelope["result"]["ok"] else 1)


if __name__ == "__main__":
    main()
