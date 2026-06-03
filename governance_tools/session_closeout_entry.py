#!/usr/bin/env python3
"""
session_closeout_entry.py — Agent-agnostic session closeout entrypoint.

This is the single canonical command that executes the governance closeout
pipeline. Every agent integration (Claude, Copilot, Gemini, ChatGPT) calls
this command — or instructs the user to call it manually. The agent adapter
layer decides *when* and *how* this gets triggered; this module defines *what*
happens.

Usage:
    python -m governance_tools.session_closeout_entry --project-root .
    python -m governance_tools.session_closeout_entry --project-root . --format json

Exit codes:
    0  closeout executed (pipeline ran, regardless of closeout content quality)
    1  pipeline failed to run (runtime error, not closeout content failure)

Closeout content quality (missing file, schema invalid, etc.) is reported in
the output but does NOT cause a non-zero exit. The pipeline ran; the verdict
records the quality gap. Failing on content quality would make the stop hook
itself unreliable.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from governance_tools.session_end_hook import run_session_end_hook, format_human_result

ALLOWED_TRIGGER_MODES = {"native_hook", "manual_fallback", "wrapper", "synthetic_smoke", "unknown"}
CLOSEOUT_RECEIPT_SCHEMA_VERSION = "1.0"


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _append_trigger_evidence(
    project_root: Path,
    *,
    agent_id: str,
    trigger_mode: str,
    entrypoint: str,
    exit_code: int,
    closeout_artifact_path: str | None,
) -> Path:
    artifact_dir = project_root / "artifacts" / "runtime"
    artifact_dir.mkdir(parents=True, exist_ok=True)
    evidence_path = artifact_dir / "closeout-trigger-evidence.ndjson"
    record = {
        "timestamp": _utc_now_iso(),
        "agent_id": agent_id,
        "trigger_mode": trigger_mode if trigger_mode in ALLOWED_TRIGGER_MODES else "unknown",
        "entrypoint": entrypoint,
        "exit_code": exit_code,
        "closeout_artifact_path": closeout_artifact_path or "",
    }
    with evidence_path.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, ensure_ascii=False) + "\n")
    return evidence_path


def _checksum_of_path(path: Path | None) -> str:
    if path is None or not path.exists() or not path.is_file():
        return ""
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def _latest_receipt_checksum(project_root: Path) -> str:
    """Return checksum_of_cleaned_path from the most recent closeout receipt, or '' if none.

    Receipts are named closeout_receipt_<timestamp>.json and sort lexicographically by time.
    We walk in reverse to find the most recent non-empty checksum.
    """
    receipt_dir = project_root / "artifacts" / "runtime" / "closeout-receipts"
    if not receipt_dir.is_dir():
        return ""
    receipts = sorted(receipt_dir.glob("closeout_receipt_*.json"))
    for receipt_path in reversed(receipts):
        try:
            data = json.loads(receipt_path.read_text(encoding="utf-8"))
            cs = str(data.get("checksum_of_cleaned_path", ""))
            if cs:
                return cs
        except Exception:
            continue
    return ""

def _resolve_head_commit(project_root: Path) -> str:
    try:
        import subprocess
        result = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=str(project_root),
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:
        pass
    return ""


def _write_closeout_receipt(
    project_root: Path,
    *,
    agent_id: str,
    trigger_mode: str,
    entrypoint: str,
    exit_code: int,
    closeout_artifact_path: str | None,
    memory_eligibility_evaluated: bool,
    memory_write_required: bool,
    memory_write_performed: bool,
    memory_eligibility_reason: str,
) -> Path:
    artifact_dir = project_root / "artifacts" / "runtime" / "closeout-receipts"
    artifact_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    receipt_path = artifact_dir / f"closeout_receipt_{ts}.json"
    closeout_path_obj = Path(closeout_artifact_path).resolve() if closeout_artifact_path else None
    linked_head = _resolve_head_commit(project_root)
    receipt = {
        "schema_version": CLOSEOUT_RECEIPT_SCHEMA_VERSION,
        "timestamp": _utc_now_iso(),
        "agent_id": agent_id,
        "trigger_mode": trigger_mode if trigger_mode in ALLOWED_TRIGGER_MODES else "unknown",
        "entrypoint": entrypoint,
        "exit_code": exit_code,
        "linked_head_commit": linked_head,
        "closeout_artifact_path": str(closeout_path_obj) if closeout_path_obj else "",
        "checksum_of_cleaned_path": _checksum_of_path(closeout_path_obj),
        "memory_eligibility_evaluated": memory_eligibility_evaluated,
        "memory_write_required": memory_write_required,
        "memory_write_performed": memory_write_performed,
        "memory_eligibility_reason": memory_eligibility_reason,
    }
    receipt_path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return receipt_path


def run(project_root: Path) -> dict[str, Any]:
    """
    Execute the closeout pipeline for the given project root.

    This is the single callable entry point for all agent adapters.
    It delegates entirely to session_end_hook.run_session_end_hook, which
    handles: closeout file classification, memory snapshot, promotion policy,
    verdict and trace artifact emission.
    """
    return run_session_end_hook(project_root=project_root)


def _evaluate_memory_eligibility(result: dict[str, Any]) -> tuple[bool, bool, str]:
    memory_closeout = result.get("memory_closeout") or {}
    memory_update_skipped_reason = str(result.get("memory_update_skipped_reason", "")).strip().lower()
    gate_verdict = str(result.get("gate_verdict", "")).strip().upper()
    candidate_signals = memory_closeout.get("candidate_signals") or []
    required_reasons: list[str] = []

    if candidate_signals:
        required_reasons.append("memory_candidate_signals_detected")

    # governance / enforcement behavior changed into non-steady state.
    if gate_verdict in {"BLOCKED", "NON-GATE-FAILURE"}:
        required_reasons.append("governance_or_enforcement_behavior_changed")

    # unresolved next-step state.
    if memory_update_skipped_reason in {"memory_closeout_blocked", "promotion_not_performed"}:
        required_reasons.append("unresolved_next_step_state")

    required = bool(required_reasons)
    reason = ",".join(required_reasons) if required_reasons else "no_eligibility_trigger"
    return True, required, reason


def _apply_stale_duplicate_guard(
    *,
    project_root: Path,
    closeout_artifact_path: str | None,
    memory_write_required: bool,
    memory_eligibility_reason: str,
) -> tuple[bool, str, bool]:
    if not closeout_artifact_path:
        return memory_write_required, memory_eligibility_reason, False
    current_checksum = _checksum_of_path(Path(closeout_artifact_path).resolve())
    previous_checksum = _latest_receipt_checksum(project_root)
    if not current_checksum or current_checksum != previous_checksum:
        return memory_write_required, memory_eligibility_reason, False
    stale_tag = "stale_duplicate_detected"
    if memory_eligibility_reason and memory_eligibility_reason != "no_eligibility_trigger":
        memory_eligibility_reason = f"{stale_tag},{memory_eligibility_reason}"
    else:
        memory_eligibility_reason = stale_tag
    return False, memory_eligibility_reason, True


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Agent-agnostic session closeout entrypoint. "
            "Executes the governance closeout pipeline for the current project. "
            "Called by agent integrations (Claude stop hook, Copilot task, etc.) "
            "or manually at session end."
        )
    )
    parser.add_argument(
        "--project-root",
        default=".",
        help="Path to the project root (default: current directory)",
    )
    parser.add_argument(
        "--format",
        choices=["human", "json"],
        default="human",
        help="Output format (default: human)",
    )
    parser.add_argument(
        "--agent-id",
        default="unknown",
        help="Agent identifier for trigger evidence logging (default: unknown)",
    )
    parser.add_argument(
        "--trigger-mode",
        default="unknown",
        choices=sorted(ALLOWED_TRIGGER_MODES),
        help="Trigger mode for evidence logging (default: unknown)",
    )
    args = parser.parse_args()

    project_root = Path(args.project_root).resolve()

    try:
        result = run(project_root)
        closeout_artifact_path = result.get("canonical_closeout_artifact") or result.get("closeout_file")
        eligibility_evaluated, memory_write_required, memory_eligibility_reason = _evaluate_memory_eligibility(result)
        memory_write_performed = str(result.get("memory_update_result", "")).strip().lower() == "updated"

        # ── Stale-duplicate guard ─────────────────────────────────────────────
        # Stale-duplicate guard: suppress memory promotion when closeout content is unchanged.
        (
            memory_write_required,
            memory_eligibility_reason,
            stale_detected,
        ) = _apply_stale_duplicate_guard(
            project_root=project_root,
            closeout_artifact_path=closeout_artifact_path if isinstance(closeout_artifact_path, str) else None,
            memory_write_required=memory_write_required,
            memory_eligibility_reason=memory_eligibility_reason,
        )
        if stale_detected:
            print(
                "[session_closeout_entry] WARNING: artifacts/session-closeout.txt content "
                "is unchanged from the previous session (SHA256 match). "
                "Memory promotion suppressed. "
                "Update artifacts/session-closeout.txt before ending the session "
                "(see AGENTS.md: MANDATORY CLOSEOUT OBLIGATION).",
                file=sys.stderr,
            )
        evidence_path = _append_trigger_evidence(
            project_root,
            agent_id=args.agent_id,
            trigger_mode=args.trigger_mode,
            entrypoint="governance_tools.session_closeout_entry",
            exit_code=0,
            closeout_artifact_path=closeout_artifact_path if isinstance(closeout_artifact_path, str) else None,
        )
        receipt_path = _write_closeout_receipt(
            project_root,
            agent_id=args.agent_id,
            trigger_mode=args.trigger_mode,
            entrypoint="governance_tools.session_closeout_entry",
            exit_code=0,
            closeout_artifact_path=closeout_artifact_path if isinstance(closeout_artifact_path, str) else None,
            memory_eligibility_evaluated=eligibility_evaluated,
            memory_write_required=memory_write_required,
            memory_write_performed=memory_write_performed,
            memory_eligibility_reason=memory_eligibility_reason,
        )
        result["trigger_evidence_artifact"] = str(evidence_path)
        result["closeout_receipt_artifact"] = str(receipt_path)
    except Exception as exc:
        _append_trigger_evidence(
            project_root,
            agent_id=args.agent_id,
            trigger_mode=args.trigger_mode,
            entrypoint="governance_tools.session_closeout_entry",
            exit_code=1,
            closeout_artifact_path=None,
        )
        _write_closeout_receipt(
            project_root,
            agent_id=args.agent_id,
            trigger_mode=args.trigger_mode,
            entrypoint="governance_tools.session_closeout_entry",
            exit_code=1,
            closeout_artifact_path=None,
            memory_eligibility_evaluated=False,
            memory_write_required=False,
            memory_write_performed=False,
            memory_eligibility_reason="closeout_pipeline_runtime_error",
        )
        if args.format == "json":
            print(json.dumps({"ok": False, "error": str(exc)}, ensure_ascii=False))
        else:
            print(f"[session_closeout_entry] runtime error: {exc}", file=sys.stderr)
        return 1

    if args.format == "json":
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(format_human_result(result))

    # Exit 0 if pipeline ran. Content quality gaps are in the output, not exit code.
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
