#!/usr/bin/env python3
"""
Manual receipt writer for non-native-hook agents (Copilot, Gemini, etc.).

contract:
  - Reads the admissibility record.
  - Calls enforce_output_mode — does NOT recompute ceiling itself.
  - Writes the receipt with enforcement result embedded.

manual_fallback is NOT a weaker path:
  trigger_mode=manual_fallback uses the same enforcer and same downgrade/block
  semantics as the native_hook path. Missing native hook capability does NOT
  relax enforcement. Any receipt produced here carries enforcement_source=
  output_mode_enforcer and fallback_weakens_enforcement=false.

Trust boundary:
  - record is untrusted; defaults are conservative (enforcement handles it).
  - output_path must be writable by caller.
  - This module performs one IO write; all enforcement logic stays in
    output_mode_enforcer.enforce_output_mode.
"""

from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from typing import Any

from governance_tools.output_mode_enforcer import enforce_output_mode

# Locked constants — not configurable by callers.
_SCHEMA_VERSION = "1.1"
_TRIGGER_MODE = "manual_fallback"
_ENFORCEMENT_SOURCE = "output_mode_enforcer"
_FALLBACK_WEAKENS_ENFORCEMENT = False
_DEFAULT_TRACE_PATH = os.path.join("artifacts", "audit", "session-output-mode-trace.ndjson")


def write_manual_receipt(
    *,
    record: dict[str, Any],
    requested_mode: str,
    output_path: str,
    agent_id: str,
    entrypoint: str,
    closeout_artifact_path: str,
    checksum_of_cleaned_path: str,
    memory_eligibility_evaluated: bool,
    memory_write_required: bool,
    memory_write_performed: bool,
    memory_eligibility_reason: str,
    manual_fallback_reason: str,
    consequence_tier: int | None = None,
    consequence_materiality_reason: str | None = None,
    session_output_mode_trace_path: str | None = None,
    exit_code: int = 0,
) -> dict[str, Any]:
    """
    Produce and write a v1.1 closeout receipt for a non-native-hook agent.

    Returns the receipt dict (identical to what was written to output_path).

    Raises:
      ValueError  — if requested_mode is not a known mode string (block is
                    returned, not raised, for prohibited/unknown modes; ValueError
                    is reserved for caller contract violations like empty agent_id).
      OSError     — if output_path is not writable.
    """
    if not agent_id:
        raise ValueError("agent_id must be a non-empty string")
    if not manual_fallback_reason:
        raise ValueError("manual_fallback_reason is required for manual_fallback receipts")

    # ── Enforcement — single call, no local ceiling logic ─────────────────────
    enforcement = enforce_output_mode(record, requested_mode)

    # ── Build receipt ─────────────────────────────────────────────────────────
    receipt: dict[str, Any] = {
        "schema_version": _SCHEMA_VERSION,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "agent_id": agent_id,
        "trigger_mode": _TRIGGER_MODE,
        "entrypoint": entrypoint,
        "exit_code": exit_code,
        "closeout_artifact_path": closeout_artifact_path,
        "checksum_of_cleaned_path": checksum_of_cleaned_path,
        "memory_eligibility_evaluated": memory_eligibility_evaluated,
        "memory_write_required": memory_write_required,
        "memory_write_performed": memory_write_performed,
        "memory_eligibility_reason": memory_eligibility_reason,
        # Output mode enforcement fields
        "output_mode_requested": enforcement["requested_mode"],
        "output_mode_effective": enforcement["actual_mode"],
        "output_mode_decision": enforcement["enforcement_action"],
        "output_mode_ceiling": enforcement["ceiling"],
        "enforcement_source": _ENFORCEMENT_SOURCE,
        "fallback_weakens_enforcement": _FALLBACK_WEAKENS_ENFORCEMENT,
        "manual_fallback_reason": manual_fallback_reason,
    }

    # Optional materiality fields — only written when provided
    if consequence_tier is not None:
        receipt["consequence_tier"] = consequence_tier
    if consequence_materiality_reason is not None:
        receipt["consequence_materiality_reason"] = consequence_materiality_reason

    # ── Write ─────────────────────────────────────────────────────────────────
    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as fh:
        json.dump(receipt, fh, indent=2)

    _append_session_output_mode_trace(
        receipt=receipt,
        record=record,
        receipt_path=output_path,
        trace_path=session_output_mode_trace_path or _DEFAULT_TRACE_PATH,
    )

    return receipt


def _append_session_output_mode_trace(
    *,
    receipt: dict[str, Any],
    record: dict[str, Any],
    receipt_path: str,
    trace_path: str,
) -> None:
    """
    Append a session-level output-mode trace event.

    This is a pure trace surface; it does not re-run compliance or alter
    enforcement decisions from the receipt.
    """
    session_id = str(record.get("session_id") or "unknown")
    record_id = str(record.get("record_id") or receipt.get("checksum_of_cleaned_path") or "unknown")
    entry = {
        "session_id": session_id,
        "agent_type": _infer_agent_type(record=record, agent_id=receipt.get("agent_id", "")),
        "trigger_mode": receipt.get("trigger_mode"),
        "record_id": record_id,
        "output_mode_requested": receipt.get("output_mode_requested"),
        "output_mode_effective": receipt.get("output_mode_effective"),
        "output_mode_decision": receipt.get("output_mode_decision"),
        "output_mode_ceiling": receipt.get("output_mode_ceiling"),
        "consequence_tier": receipt.get("consequence_tier"),
        "receipt_path": receipt_path,
        "enforcement_source": receipt.get("enforcement_source"),
    }
    os.makedirs(os.path.dirname(os.path.abspath(trace_path)), exist_ok=True)
    with open(trace_path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(entry, ensure_ascii=True) + "\n")


def _infer_agent_type(*, record: dict[str, Any], agent_id: str) -> str:
    """
    Normalize agent type to constrained values for session trace records.
    """
    candidate = str(record.get("agent_type") or "").strip().lower()
    if candidate in {"copilot", "gemini", "native", "unknown"}:
        return candidate
    lowered_id = str(agent_id or "").lower()
    if "copilot" in lowered_id:
        return "copilot"
    if "gemini" in lowered_id:
        return "gemini"
    if "native" in lowered_id:
        return "native"
    return "unknown"


def is_compliant_for_non_native_agent(receipt: dict[str, Any]) -> tuple[bool, str]:
    """
    Check whether a receipt meets the minimum compliance bar for a non-native agent.

    A receipt is non-compliant if:
      - trigger_mode != manual_fallback (native path, not this checker's concern)
        → returns (True, "not_manual_fallback") — out of scope, treat as compliant
      - enforcement_source field absent or wrong
      - fallback_weakens_enforcement is not literally False
      - output_mode_decision is "block" (enforcer blocked the requested mode)
      - output_mode_requested or output_mode_effective absent

    Returns (compliant: bool, reason: str).
    """
    if receipt.get("trigger_mode") != _TRIGGER_MODE:
        return True, "not_manual_fallback"

    if receipt.get("enforcement_source") != _ENFORCEMENT_SOURCE:
        return False, "enforcement_source_absent_or_wrong: receipt ceiling may not have gone through output_mode_enforcer"

    if receipt.get("fallback_weakens_enforcement") is not False:
        return False, "fallback_weakens_enforcement must be false: enforcement parity not established"

    if not receipt.get("output_mode_requested"):
        return False, "output_mode_requested absent: enforcement record incomplete"

    if not receipt.get("output_mode_effective"):
        return False, "output_mode_effective absent: enforcement record incomplete"

    if receipt.get("output_mode_decision") == "block":
        return False, (
            f"output_mode_decision=block: requested mode {receipt.get('output_mode_requested')!r} "
            "was blocked by enforcer; session is non-compliant"
        )

    return True, "ok"
