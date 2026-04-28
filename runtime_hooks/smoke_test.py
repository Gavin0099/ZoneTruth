#!/usr/bin/env python3
"""
Run documented runtime smoke flows end-to-end.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from runtime_hooks.adapters.claude_code.normalize_event import normalize_event as normalize_claude
from runtime_hooks.adapters.codex.normalize_event import normalize_event as normalize_codex
from runtime_hooks.adapters.gemini.normalize_event import normalize_event as normalize_gemini
from runtime_hooks.adapters.shared_adapter_runner import run_adapter_event
from runtime_hooks.dispatcher import dispatch_event
from runtime_hooks.runtime_path_overrides import apply_runtime_path_overrides


NORMALIZERS = {
    "claude_code": normalize_claude,
    "codex": normalize_codex,
    "gemini": normalize_gemini,
}


DEFAULT_EXAMPLES = {
    ("claude_code", "session_start"): Path("runtime_hooks/examples/claude_code/session_start.native.json"),
    ("claude_code", "pre_task"): Path("runtime_hooks/examples/claude_code/pre_task.native.json"),
    ("claude_code", "post_task"): Path("runtime_hooks/examples/claude_code/post_task.native.json"),
    ("codex", "session_start"): Path("runtime_hooks/examples/codex/session_start.native.json"),
    ("codex", "pre_task"): Path("runtime_hooks/examples/codex/pre_task.native.json"),
    ("codex", "post_task"): Path("runtime_hooks/examples/codex/post_task.native.json"),
    ("gemini", "session_start"): Path("runtime_hooks/examples/gemini/session_start.native.json"),
    ("gemini", "pre_task"): Path("runtime_hooks/examples/gemini/pre_task.native.json"),
    ("gemini", "post_task"): Path("runtime_hooks/examples/gemini/post_task.native.json"),
}

DEFAULT_SHARED_EXAMPLES = {
    "session_start": Path("runtime_hooks/examples/shared/session_start.shared.json"),
}


def run_smoke(
    harness: str,
    event_type: str,
    payload_file: Path | None = None,
    *,
    project_root: Path | None = None,
    plan_path: Path | None = None,
    contract_file: Path | None = None,
    response_file: Path | None = None,
    checks_file: Path | None = None,
) -> dict:
    normalize_event = NORMALIZERS[harness]
    payload_path = payload_file or DEFAULT_EXAMPLES[(harness, event_type)]
    payload = json.loads(payload_path.read_text(encoding="utf-8"))
    payload = apply_runtime_path_overrides(
        payload,
        project_root=project_root,
        plan_path=plan_path,
        contract_file=contract_file,
        response_file=response_file,
        checks_file=checks_file,
    )
    envelope = run_adapter_event(normalize_event, event_type=event_type, payload=payload)
    envelope["payload_file"] = str(payload_path)
    return envelope


def run_shared_smoke(
    event_type: str,
    payload_file: Path | None = None,
    *,
    project_root: Path | None = None,
    plan_path: Path | None = None,
    contract_file: Path | None = None,
    response_file: Path | None = None,
    checks_file: Path | None = None,
) -> dict:
    payload_path = payload_file or DEFAULT_SHARED_EXAMPLES[event_type]
    event = json.loads(payload_path.read_text(encoding="utf-8"))
    event = apply_runtime_path_overrides(
        event,
        project_root=project_root,
        plan_path=plan_path,
        contract_file=contract_file,
        response_file=response_file,
        checks_file=checks_file,
    )
    envelope = dispatch_event(event)
    envelope["payload_file"] = str(payload_path)
    return envelope


def format_human_envelope(envelope: dict, harness: str | None = None) -> str:
    lines: list[str] = []
    result = envelope["result"]
    normalized_event = envelope.get("normalized_event") or {}
    event_type = envelope.get("event_type") or normalized_event.get("event_type") or "unknown"
    if harness:
        lines.append(f"harness={harness}")
    lines.append(f"event_type={event_type}")
    lines.append(f"payload_file={envelope['payload_file']}")
    lines.append(f"ok={result['ok']}")

    if event_type == "session_start":
        rules = result.get("runtime_contract", {}).get("rules", []) or []
        if rules:
            lines.append(f"rules={','.join(rules)}")
        contract_resolution = result.get("contract_resolution") or {}
        if contract_resolution.get("source"):
            lines.append(f"contract_source={contract_resolution['source']}")
        if contract_resolution.get("path"):
            lines.append(f"contract_path={contract_resolution['path']}")
        domain_contract = result.get("domain_contract") or {}
        if domain_contract.get("name"):
            lines.append(f"domain_contract={domain_contract['name']}")
        preview = result.get("suggested_rules_preview") or []
        if preview:
            lines.append(f"suggested_rules_preview={','.join(preview)}")
        skills = result.get("suggested_skills") or []
        if skills:
            lines.append(f"suggested_skills={','.join(skills)}")
        agent = result.get("suggested_agent")
        if agent:
            lines.append(f"suggested_agent={agent}")
        guidance = result.get("proposal_guidance") or {}
        validators = guidance.get("expected_validators") or []
        if validators:
            lines.append(f"expected_validators={','.join(validators)}")
        evidence = guidance.get("required_evidence") or []
        if evidence:
            lines.append(f"required_evidence={','.join(evidence)}")
    else:
        contract_resolution = result.get("contract_resolution") or {}
        if contract_resolution.get("source"):
            lines.append(f"contract_source={contract_resolution['source']}")
        if contract_resolution.get("path"):
            lines.append(f"contract_path={contract_resolution['path']}")
        domain_contract = result.get("domain_contract") or {}
        if domain_contract.get("name"):
            lines.append(f"domain_contract={domain_contract['name']}")
        if result.get("snapshot"):
            lines.append(f"snapshot={result['snapshot']['snapshot_path']}")

    for warning in result.get("warnings", []):
        lines.append(f"warning: {warning}")
    for error in result.get("errors", []):
        lines.append(f"error: {error}")
    return "\n".join(lines)


def write_outputs(
    *,
    envelope: dict,
    rendered: str,
    output: Path | None = None,
    json_output: Path | None = None,
) -> None:
    if output:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(rendered + "\n", encoding="utf-8")

    if json_output:
        json_output.parent.mkdir(parents=True, exist_ok=True)
        json_output.write_text(json.dumps(envelope, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Run a runtime smoke flow from native payload to governance result.")
    parser.add_argument("--harness", choices=sorted(NORMALIZERS))
    parser.add_argument("--event-type", choices=["session_start", "pre_task", "post_task"], required=True)
    parser.add_argument("--file", "-f", help="Native payload file. Defaults to the documented example.")
    parser.add_argument("--project-root", help="Override project_root in the example payload.")
    parser.add_argument("--plan-path", help="Override plan_path in the example payload.")
    parser.add_argument("--contract", help="Explicit contract.yaml path for the smoke flow.")
    parser.add_argument("--response-file", help="Override response_file in the example payload.")
    parser.add_argument("--checks-file", help="Override checks_file in the example payload.")
    parser.add_argument("--format", choices=["human", "json"], default="human")
    parser.add_argument("--output", help="Write rendered smoke output to a file.")
    parser.add_argument("--json-output", help="Write the full smoke envelope as JSON to a file.")
    args = parser.parse_args()

    if args.event_type == "session_start":
        envelope = run_shared_smoke(
            event_type=args.event_type,
            payload_file=Path(args.file) if args.file else None,
            project_root=Path(args.project_root).resolve() if args.project_root else None,
            plan_path=Path(args.plan_path).resolve() if args.plan_path else None,
            contract_file=Path(args.contract).resolve() if args.contract else None,
            response_file=Path(args.response_file).resolve() if args.response_file else None,
            checks_file=Path(args.checks_file).resolve() if args.checks_file else None,
        )
    else:
        if not args.harness:
            raise SystemExit("--harness is required for harness-based smoke flows")
        envelope = run_smoke(
            harness=args.harness,
            event_type=args.event_type,
            payload_file=Path(args.file) if args.file else None,
            project_root=Path(args.project_root).resolve() if args.project_root else None,
            plan_path=Path(args.plan_path).resolve() if args.plan_path else None,
            contract_file=Path(args.contract).resolve() if args.contract else None,
            response_file=Path(args.response_file).resolve() if args.response_file else None,
            checks_file=Path(args.checks_file).resolve() if args.checks_file else None,
        )

    if args.format == "json":
        rendered = json.dumps(envelope, ensure_ascii=False, indent=2)
    else:
        rendered = format_human_envelope(envelope, harness=args.harness)

    write_outputs(
        envelope=envelope,
        rendered=rendered,
        output=Path(args.output) if args.output else None,
        json_output=Path(args.json_output) if args.json_output else None,
    )

    print(rendered)

    sys.exit(0 if envelope["result"]["ok"] else 1)


if __name__ == "__main__":
    main()
