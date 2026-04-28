#!/usr/bin/env python3
"""
Shared runner for harness adapters that normalize native payloads and invoke core checks.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Callable

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from runtime_hooks.core.post_task_check import run_post_task_check
from runtime_hooks.core.pre_task_check import run_pre_task_check
from runtime_hooks.core.session_start import build_session_start_context
from governance_tools.contract_validator import validate_contract


def _load_payload(file_path: str | None) -> dict:
    if file_path:
        return json.loads(Path(file_path).read_text(encoding="utf-8"))
    return json.loads(sys.stdin.read())




def _post_task_contract_required(normalized: dict, response_text: str, checks: dict | None) -> bool:
    if normalized.get("task"):
        return True
    if normalized.get("create_snapshot"):
        return True
    if normalized.get("response_file") and response_text.strip():
        return True
    if normalized.get("checks_file") and checks is not None:
        return True
    return False

def run_adapter_event(
    normalize_event: Callable[[dict, str], dict],
    event_type: str,
    payload: dict,
) -> dict:
    normalized = normalize_event(payload, event_type=event_type)

    if event_type == "session_start":
        result = build_session_start_context(
            project_root=Path(normalized["project_root"]),
            plan_path=Path(normalized.get("plan_path") or "PLAN.md"),
            rules=",".join(normalized.get("rules", [])),
            risk=normalized["risk"],
            oversight=normalized["oversight"],
            memory_mode=normalized["memory_mode"],
            task_text=normalized.get("task") or "",
            impact_before_files=[Path(path) for path in normalized.get("impact_before_files", [])],
            impact_after_files=[Path(path) for path in normalized.get("impact_after_files", [])],
            contract_file=Path(normalized["contract"]).resolve() if normalized.get("contract") else None,
        )
    elif event_type == "pre_task":
        result = run_pre_task_check(
            project_root=Path(normalized["project_root"]),
            rules=",".join(normalized.get("rules", [])),
            risk=normalized["risk"],
            oversight=normalized["oversight"],
            memory_mode=normalized["memory_mode"],
            contract_file=Path(normalized["contract"]).resolve() if normalized.get("contract") else None,
        )
    else:
        response_text = ""
        response_file = normalized.get("response_file")
        if response_file:
            response_text = Path(response_file).read_text(encoding="utf-8")
        checks = None
        checks_file = normalized.get("checks_file")
        if checks_file:
            checks = json.loads(Path(checks_file).read_text(encoding="utf-8"))

        contract_required = _post_task_contract_required(normalized, response_text, checks)
        adapter_contract = {
            "required": contract_required,
            "contract_found": None,
            "compliant": None,
            "errors": [],
            "warnings": [],
        }
        if contract_required:
            contract_validation = validate_contract(response_text)
            adapter_contract.update(
                {
                    "contract_found": contract_validation.contract_found,
                    "compliant": contract_validation.compliant,
                    "errors": list(contract_validation.errors),
                    "warnings": list(contract_validation.warnings),
                }
            )

        result = run_post_task_check(
            response_text=response_text,
            risk=normalized["risk"],
            oversight=normalized["oversight"],
            memory_mode=normalized["memory_mode"],
            memory_root=Path(normalized["project_root"]) / "memory" if normalized.get("create_snapshot") else None,
            snapshot_task=normalized.get("task"),
            snapshot_summary=normalized.get("snapshot_summary"),
            create_snapshot=normalized.get("create_snapshot", False),
            checks=checks,
            contract_file=Path(normalized["contract"]).resolve() if normalized.get("contract") else None,
            project_root=Path(normalized["project_root"]),
            evidence_paths=[Path(path).resolve() for path in [response_file, checks_file] if path],
        )
        if contract_required and not adapter_contract["contract_found"]:
            message = "adapter-contract: Missing [Governance Contract] block in non-trivial post_task response"
            result.setdefault("adapter_errors", []).append(message)
            result["errors"].append(message)
            result["ok"] = False
        result["adapter_contract"] = adapter_contract

    return {
        "normalized_event": normalized,
        "result": result,
    }


def adapter_main(harness: str, normalize_event: Callable[[dict, str], dict], event_type: str) -> None:
    parser = argparse.ArgumentParser(
        description=f"{harness} adapter for runtime {event_type} governance checks."
    )
    parser.add_argument("--file", "-f", help="Native JSON payload file; defaults to stdin")
    parser.add_argument("--format", choices=["human", "json"], default="human")
    args = parser.parse_args()

    payload = _load_payload(args.file)
    envelope = run_adapter_event(normalize_event, event_type=event_type, payload=payload)

    if args.format == "json":
        print(json.dumps(envelope, ensure_ascii=False, indent=2))
    else:
        print(f"harness={harness}")
        print(f"event_type={event_type}")
        print(f"ok={envelope['result']['ok']}")
        print(f"project_root={envelope['normalized_event']['project_root']}")
        if event_type == "post_task" and envelope["result"].get("snapshot"):
            print(f"snapshot={envelope['result']['snapshot']['snapshot_path']}")
        for warning in envelope["result"].get("warnings", []):
            print(f"warning: {warning}")
        for error in envelope["result"].get("errors", []):
            print(f"error: {error}")

    sys.exit(0 if envelope["result"]["ok"] else 1)
