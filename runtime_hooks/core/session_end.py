#!/usr/bin/env python3
"""
Runtime session-end lifecycle closeout.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from memory_pipeline.memory_curator import curate_candidate_artifact
from memory_pipeline.memory_layout import MEMORY_FILE_ALIASES
from memory_pipeline.memory_promoter import promote_candidate
from memory_pipeline.promotion_policy import classify_promotion_policy
from memory_pipeline.session_snapshot import create_session_snapshot
from governance_tools.decision_model_loader import build_runtime_policy_ref, final_verdict_owner, runtime_decision_source, violation_verdict_impact
from governance_tools.domain_governance_metadata import domain_risk_tier
from governance_tools.execution_surface_coverage import build_execution_surface_coverage
from governance_tools.runtime_phase_policy import aggregate_phase_classifications, build_phase_classification
from governance_tools.runtime_surface_manifest import build_runtime_surface_manifest
from runtime_hooks.core._canonical_closeout import (
    build_canonical_closeout,
    pick_latest_candidate,
    write_canonical_closeout,
)


def _ensure_runtime_artifact_dirs(project_root: Path) -> tuple[Path, Path, Path, Path, Path]:
    runtime_root = project_root / "artifacts" / "runtime"
    candidates_dir = runtime_root / "candidates"
    curated_dir = runtime_root / "curated"
    summaries_dir = runtime_root / "summaries"
    verdicts_dir = runtime_root / "verdicts"
    traces_dir = runtime_root / "traces"
    candidates_dir.mkdir(parents=True, exist_ok=True)
    curated_dir.mkdir(parents=True, exist_ok=True)
    summaries_dir.mkdir(parents=True, exist_ok=True)
    verdicts_dir.mkdir(parents=True, exist_ok=True)
    traces_dir.mkdir(parents=True, exist_ok=True)
    return candidates_dir, curated_dir, summaries_dir, verdicts_dir, traces_dir


def _append_session_index(canonical: dict[str, Any], project_root: Path) -> None:
    """
    Append a summary line to artifacts/session-index.ndjson (Slice 4).

    Append-only; write failure is non-fatal (silently swallowed).
    This file is NOT the source of truth — canonical closeout artifacts are.
    It exists for fast scanning without reading individual closeout files.
    """
    try:
        index_path = project_root / "artifacts" / "session-index.ndjson"
        index_path.parent.mkdir(parents=True, exist_ok=True)
        entry = {
            "session_id": canonical["session_id"],
            "closed_at": canonical["closed_at"],
            "closeout_status": canonical["closeout_status"],
            "task_intent": canonical.get("task_intent"),
            "has_open_risks": bool(canonical.get("open_risks")),
        }
        with index_path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except Exception:
        pass  # non-fatal: index is a cache, not the authority


def _write_json(path: Path, payload: dict[str, Any]) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _build_post_task_phase_classification_from_checks(checks: dict[str, Any]) -> dict[str, Any]:
    action_ids: list[str] = []
    for error in checks.get("errors", []) or []:
        if "Missing required" in str(error):
            action_ids.append("required_evidence_missing")
            break
    if checks.get("required_runtime_evidence"):
        action_ids.append("required_evidence_missing")
    if checks.get("public_api_diff") and not isinstance(checks.get("public_api_diff"), dict):
        action_ids.append("invalid_evidence_schema")
    return build_phase_classification(action_ids=action_ids, hook="post_task_check")


def _build_session_end_phase_classification(
    *,
    memory_mode: str,
    snapshot_result: dict[str, Any] | None,
    promotion_result: dict[str, Any] | None,
    decision: str,
    checks: dict[str, Any],
) -> dict[str, Any]:
    action_ids = ["canonical_closeout"]
    if memory_mode != "stateless":
        action_ids.append("daily_memory_append")
    if snapshot_result is not None:
        action_ids.append("memory_candidate_snapshot")
    if snapshot_result is not None or promotion_result is not None:
        action_ids.append("memory_promotion_candidate")
    if decision == "REVIEW_REQUIRED":
        action_ids.append("reviewer_promotion_decision")
    if checks.get("cross_repo_drift_analysis"):
        action_ids.append("cross_repo_drift_analysis")
    return build_phase_classification(action_ids=action_ids, hook="session_end")


def _current_local_date() -> str:
    return datetime.now().astimezone().date().isoformat()


def _resolve_head_commit(project_root: Path) -> str:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            cwd=project_root,
            capture_output=True,
            text=True,
            check=True,
        )
    except Exception:
        return "UNCOMMITTED"

    commit = result.stdout.strip()
    return commit or "UNCOMMITTED"


def _default_next_step(
    *,
    decision: str,
    promoted: bool,
    open_risks: list[str],
    canonical_closeout: dict[str, Any],
) -> str:
    if open_risks:
        return open_risks[0]
    if decision == "REVIEW_REQUIRED":
        return "Review the session outcome and decide whether to promote durable memory."
    if not promoted:
        return "Continue the next session from the recorded closeout and pending memory state."
    return (
        "Resume from the latest canonical closeout state"
        f" (status={canonical_closeout.get('closeout_status', 'unknown')})."
    )


def _build_daily_memory_record(
    *,
    project_root: Path,
    session_id: str,
    task: str,
    decision: str,
    summary: str,
    promoted: bool,
    snapshot_created: bool,
    canonical_closeout: dict[str, Any],
) -> dict[str, str]:
    open_risks = [str(item).strip() for item in canonical_closeout.get("open_risks", []) if str(item).strip()]
    summary_text = summary.strip() or "Session closeout recorded without an explicit summary."
    return {
        "what_changed": (
            f"session_end auto-closeout recorded for `{task}` "
            f"(session={session_id}, decision={decision}, snapshot_created={snapshot_created}, promoted={promoted}). "
            f"Summary: {summary_text}"
        ),
        "commit": _resolve_head_commit(project_root),
        "test_evidence": (
            f"`session_end` => canonical_closeout_status={canonical_closeout.get('closeout_status', 'unknown')}, "
            f"snapshot_created={snapshot_created}, promoted={promoted}, open_risk_count={len(open_risks)}"
        ),
        "next_step": _default_next_step(
            decision=decision,
            promoted=promoted,
            open_risks=open_risks,
            canonical_closeout=canonical_closeout,
        ),
    }


def _append_daily_memory_entry(
    *,
    project_root: Path,
    session_id: str,
    task: str,
    decision: str,
    summary: str,
    promoted: bool,
    snapshot_created: bool,
    canonical_closeout: dict[str, Any],
) -> Path:
    memory_root = project_root / "memory"
    memory_root.mkdir(parents=True, exist_ok=True)
    daily_path = memory_root / f"{_current_local_date()}.md"
    if not daily_path.exists():
        daily_path.write_text(f"# {_current_local_date()}\n\n", encoding="utf-8")

    record = _build_daily_memory_record(
        project_root=project_root,
        session_id=session_id,
        task=task,
        decision=decision,
        summary=summary,
        promoted=promoted,
        snapshot_created=snapshot_created,
        canonical_closeout=canonical_closeout,
    )
    entry = (
        f"- what_changed: {record['what_changed']}\n"
        f"  commit: {record['commit']}\n"
        f"  test_evidence: {record['test_evidence']}\n"
        f"  next_step: {record['next_step']}\n"
    )
    with daily_path.open("a", encoding="utf-8") as fh:
        if daily_path.stat().st_size > 0:
            fh.write("\n")
        fh.write(entry)
    return daily_path


def _force_runtime_failure_if_requested(checks: dict[str, Any], stage: str) -> None:
    if checks.get("force_runtime_failure_stage") == stage:
        raise RuntimeError(f"forced runtime failure at stage: {stage}")


def _normalize_session_start_payload(payload: dict[str, Any]) -> dict[str, Any]:
    if payload.get("event_type") == "session_start" and isinstance(payload.get("result"), dict):
        return payload["result"]
    return payload


def _normalize_runtime_contract(runtime_contract: dict[str, Any]) -> dict[str, Any]:
    return {
        "task": runtime_contract.get("task", "unspecified-task"),
        "rules": runtime_contract.get("rules", []) or [],
        "risk": runtime_contract.get("risk", "medium"),
        "oversight": runtime_contract.get("oversight", "auto"),
        "memory_mode": runtime_contract.get("memory_mode", "candidate"),
    }


def _contract_identity(contract_resolution: dict[str, Any], domain_contract: dict[str, Any]) -> dict[str, Any]:
    domain_raw = domain_contract.get("raw") or {}
    return {
        "source": contract_resolution.get("source"),
        "path": contract_resolution.get("path"),
        "name": domain_contract.get("name"),
        "domain": domain_raw.get("domain"),
        "plugin_version": domain_raw.get("plugin_version"),
        "risk_tier": contract_resolution.get("risk_tier"),
    }


def _structured_decision_path(*steps: str) -> list[dict[str, Any]]:
    return [
        {
            "index": index,
            "step": step,
        }
        for index, step in enumerate(steps, start=1)
    ]


def _memory_schema_complete(project_root: Path) -> bool:
    memory_root = project_root / "memory"
    for names in MEMORY_FILE_ALIASES.values():
        if not any((memory_root / name).exists() for name in names):
            return False
    return True


def _classify_governance_strategy(
    project_root: Path,
    checks: dict[str, Any],
    initial_agent_class: str | None = None,
) -> dict[str, Any]:
    """
    Derive governance classification from observable session-end evidence.

    Conservative: classify down when uncertain.
    See docs/governance-strategy-runtime.md for decision rules and field specs.
    See docs/classification-evidence-semantics.md for what each evidence field can
    and cannot represent.

    ``initial_agent_class``: class recorded at session_start, used to compute
    transition fields.  Pass None when not available (no transition comparison).
    """
    # Tool gate: session_end hook is executing — active and observed
    # Note: proves closeout boundary only; does NOT prove full pre/post gate coverage.
    tool_gate = "active"
    tool_gate_source = "observed"

    # File access: session_end runs with file I/O — confirmed observed
    # Note: host/runtime capability, NOT agent surface capability.
    has_file_access = True
    file_access_source = "observed"

    # Instruction loaded: check for CLAUDE.md or AGENTS.md in project root or framework root
    # Note: presence evidence only — proves surface exists, NOT that agent consumed it.
    framework_root = Path(__file__).resolve().parents[2]
    instruction_candidates = [
        project_root / "CLAUDE.md",
        project_root / "AGENTS.md",
        framework_root / "CLAUDE.md",
    ]
    instruction_found = any(f.exists() for f in instruction_candidates)
    instruction_loaded = "true" if instruction_found else "unknown"
    instruction_source = "observed" if instruction_found else "assumed"

    # Context integrity: look for degradation signals in post-task checks dict.
    # Default is "unknown", NOT "full": absence of degradation signal ≠ confirmed full.
    # Only set to "degraded" on affirmative degradation signal; never set to "full"
    # without a positive affirmative observation.
    context_integrity = "unknown"
    context_source = "assumed"
    if checks:
        _warnings = checks.get("warnings") or []
        _errors = checks.get("errors") or []
        _all_messages = " ".join(str(m) for m in _warnings + _errors).lower()
        if any(sig in _all_messages for sig in ("truncat", "context_degraded", "token_budget", "token_warning")):
            context_integrity = "degraded"
            context_source = "observed"

    classification_evidence = {
        "has_file_access": {"value": has_file_access, "source": file_access_source},
        "instruction_loaded": {"value": instruction_loaded, "source": instruction_source},
        "context_integrity": {"value": context_integrity, "source": context_source},
        "tool_gate": {"value": tool_gate, "source": tool_gate_source},
    }

    # Classification decision: conservative (classify down when uncertain)
    # Mirrors the decision rules in docs/governance-strategy-runtime.md
    if tool_gate == "missing":
        effective_agent_class = "wrapper_only"
    elif context_integrity == "degraded" or instruction_loaded == "false":
        effective_agent_class = "instruction_limited"
    elif (
        has_file_access
        and instruction_loaded in ("true", "unknown")
        and context_integrity in ("full", "unknown")
        and tool_gate == "active"
    ):
        effective_agent_class = "instruction_capable"
    else:
        effective_agent_class = "instruction_limited"  # conservative default

    _strategy_map = {
        "instruction_capable": "injection+enforcement",
        "instruction_limited": "minimal_injection+enforcement",
        "wrapper_only": "no_injection+strict_enforcement",
    }
    governance_strategy = _strategy_map[effective_agent_class]

    # Transition tracking: compare with session_start classification.
    # classification_changed is only meaningful when initial_agent_class is available.
    # Allowed reclassification_reason values are a controlled taxonomy:
    # "context_degraded" | "instruction_load_failed" | "tool_gate_missing" |
    # "conservative_downgrade" | "classification_anomaly_upgrade"
    # See docs/classification-transition-semantics.md for full rules.
    _class_order = {"wrapper_only": 0, "instruction_limited": 1, "instruction_capable": 2}
    classification_changed: bool | None = None
    reclassification_reason: str | None = None
    if initial_agent_class is not None:
        classification_changed = initial_agent_class != effective_agent_class
        if classification_changed:
            initial_order = _class_order.get(initial_agent_class, 1)
            effective_order = _class_order.get(effective_agent_class, 1)
            if effective_order > initial_order:
                # Upgrade within a session: proxy signals are inconsistent.
                # Session capability should only degrade, never improve.
                reclassification_reason = "classification_anomaly_upgrade"
            elif tool_gate == "missing":
                reclassification_reason = "tool_gate_missing"
            elif context_integrity == "degraded":
                reclassification_reason = "context_degraded"
            elif instruction_loaded == "false":
                reclassification_reason = "instruction_load_failed"
            else:
                reclassification_reason = "conservative_downgrade"

    return {
        "classification_evidence": classification_evidence,
        "initial_agent_class": initial_agent_class,
        "effective_agent_class": effective_agent_class,
        "classification_changed": classification_changed,
        "reclassification_reason": reclassification_reason,
        "governance_strategy": governance_strategy,
        "injection_reliance": "none",  # invariant: enforcement never depends on injection
    }


def _build_decision_context(
    project_root: Path,
    memory_mode: str,
    checks: dict[str, Any] | None = None,
    initial_agent_class: str | None = None,
) -> dict[str, Any]:
    framework_root = Path(__file__).resolve().parents[2]
    try:
        manifest = build_runtime_surface_manifest(framework_root)
        consistency = manifest["consistency"]
        surface_validity = (
            "complete"
            if not (
                consistency["unknown_surfaces"]
                or consistency["orphan_surfaces"]
                or consistency["evidence_surface_mismatch"]
            )
            else "partial"
        )
    except Exception:
        surface_validity = "unknown"

    try:
        coverage = build_execution_surface_coverage(framework_root)["coverage"]
        coverage_completeness = (
            "complete"
            if not (
                coverage["missing_hard_required"]
                or coverage["missing_soft_required"]
                or coverage["dead_surfaces"]["never_observed"]
                or coverage["dead_surfaces"]["never_required"]
            )
            else "partial"
        )
    except Exception:
        coverage_completeness = "missing"

    if memory_mode == "stateless":
        memory_integrity = "not_applicable"
    else:
        memory_integrity = "complete" if _memory_schema_complete(project_root) else "partial"

    result: dict[str, Any] = {
        "surface_validity": surface_validity,
        "coverage_completeness": coverage_completeness,
        "memory_integrity": memory_integrity,
    }
    result.update(_classify_governance_strategy(project_root, checks or {}, initial_agent_class))
    return result


def _build_policy_summary(policy: dict[str, Any]) -> dict[str, Any]:
    reasons = [str(reason) for reason in policy.get("reasons", []) if str(reason).strip()]
    return {
        "decision": str(policy.get("decision", "unknown")),
        "reason_count": len(reasons),
        "reasons": reasons,
        "reasoning_fragments": [
            {
                "kind": "promotion-policy-reason",
                "text": reason,
            }
            for reason in reasons
        ],
    }


def _detect_memory_candidate_signals(
    *,
    checks: dict[str, Any],
    errors: list[str],
    warnings: list[str],
    architecture_impact_preview: dict[str, Any],
    proposal_summary: dict[str, Any],
) -> list[str]:
    signals: list[str] = []

    lowered_errors = " ".join(errors).lower()
    lowered_warnings = " ".join(warnings).lower()

    if any(token in lowered_errors for token in ("runtime_failure", "crash", "exception", "traceback")):
        signals.append("crash_or_runtime_failure")

    public_api_diff = checks.get("public_api_diff") if checks else None
    if isinstance(public_api_diff, dict) and (
        public_api_diff.get("removed") or public_api_diff.get("added") or public_api_diff.get("breaking_changes")
    ):
        signals.append("public_api_change")

    if architecture_impact_preview.get("concerns"):
        signals.append("architecture_boundary_risk")

    if proposal_summary.get("concerns") or proposal_summary.get("required_evidence"):
        signals.append("proposal_risk_or_required_evidence")

    if "regression" in lowered_errors or "regression" in lowered_warnings:
        signals.append("regression_fix")

    return signals


def _build_memory_closeout(
    *,
    contract: dict[str, Any],
    policy: dict[str, Any],
    snapshot_result: dict[str, Any] | None,
    promotion_result: dict[str, Any] | None,
    candidate_signals: list[str],
    warnings: list[str],
    errors: list[str],
) -> dict[str, Any]:
    reasons = [str(reason) for reason in policy.get("reasons", []) if str(reason).strip()]
    if errors and any(error.startswith("runtime_failure:") for error in errors):
        primary_reason = next((error for error in errors if error.startswith("runtime_failure:")), errors[0])
    elif reasons:
        primary_reason = reasons[0]
    elif snapshot_result is None and contract.get("memory_mode") != "stateless":
        primary_reason = "candidate snapshot not created"
    else:
        primary_reason = "no explicit closeout reason"

    if contract.get("memory_mode") == "stateless":
        primary_reason = "memory_mode=stateless disables durable memory closeout"
    elif snapshot_result is None and "Session-end completed without response_text; candidate snapshot was skipped." in warnings:
        primary_reason = "response_text missing; candidate snapshot skipped"

    return {
        "candidate_detected": bool(candidate_signals),
        "candidate_signals": candidate_signals,
        "promotion_considered": contract.get("memory_mode") != "stateless",
        "snapshot_created": snapshot_result is not None,
        "decision": str(policy.get("decision", "unknown")),
        "promoted": promotion_result is not None,
        "reason": primary_reason,
    }


def _build_verdict_artifact(
    *,
    session_id: str,
    now: str,
    contract: dict[str, Any],
    checks: dict[str, Any],
    decision: str,
    errors: list[str],
    warnings: list[str],
    contract_resolution: dict[str, Any],
    domain_contract: dict[str, Any],
    decision_context: dict[str, str],
) -> dict[str, Any]:
    override_present = bool(checks.get("override_trace") or checks.get("reviewer_override"))
    escalation_present = decision == "REVIEW_REQUIRED" or contract.get("oversight") != "auto"

    # Governance escalation: any classification change (downgrade or anomaly upgrade)
    # warrants explicit reviewer attention beyond the normal session verdict signal.
    # governance_escalation_type distinguishes the two fundamentally different events:
    #   "classification_downgrade"      — agent capability degraded; strategy tightened
    #   "classification_anomaly_upgrade" — proxy signals inconsistent; classifier suspect
    # See docs/classification-reaction-policy.md for escalation type semantics.
    governance_escalation_present = decision_context.get("classification_changed") is True
    governance_escalation_type: str | None = None
    if governance_escalation_present:
        escalation_present = True
        _escalation_reason = decision_context.get("reclassification_reason")
        if _escalation_reason == "classification_anomaly_upgrade":
            governance_escalation_type = "classification_anomaly_upgrade"
        else:
            governance_escalation_type = "classification_downgrade"

    return {
        "schema_version": "1.0",
        "artifact_type": "runtime-verdict",
        "session_id": session_id,
        "generated_at": now,
        "policy_ref": build_runtime_policy_ref(),
        "verdict": {
            "decision": decision,
            "ok": len(errors) == 0,
            "risk": contract.get("risk"),
            "oversight": contract.get("oversight"),
            "memory_mode": contract.get("memory_mode"),
        },
        "contract_identity": _contract_identity(contract_resolution, domain_contract),
        "decision_governance": {
            "decision_source": runtime_decision_source(),
            "decision_owner": final_verdict_owner(),
            "policy_source": "memory_pipeline.promotion_policy.classify_promotion_policy",
        },
        "decision_context": decision_context,
        "evidence_summary": {
            "check_keys": sorted(str(key) for key in checks.keys()),
            "public_api_diff_present": checks.get("public_api_diff") is not None,
            "error_count": len(errors),
            "warning_count": len(warnings),
        },
        "override_or_escalation": {
            "override_present": override_present,
            "escalation_present": escalation_present,
            "governance_escalation_present": governance_escalation_present,
            "governance_escalation_type": governance_escalation_type,
        },
    }


def _build_runtime_failure_trace_artifact(
    *,
    session_id: str,
    now: str,
    contract: dict[str, Any],
    checks: dict[str, Any],
    contract_resolution: dict[str, Any],
    domain_contract: dict[str, Any],
    stage: str,
    failure_message: str,
    decision_context: dict[str, str],
) -> dict[str, Any]:
    return {
        "schema_version": "1.0",
        "artifact_type": "runtime-failure-trace",
        "session_id": session_id,
        "generated_at": now,
        "policy_ref": build_runtime_policy_ref(),
        "contract_identity": _contract_identity(contract_resolution, domain_contract),
        "runtime_contract": contract,
        "decision_governance": {
            "decision_source": runtime_decision_source(),
            "decision_owner": final_verdict_owner(),
            "policy_source": "memory_pipeline.promotion_policy.classify_promotion_policy",
        },
        "decision_context": decision_context,
        "decision_path": _structured_decision_path(
            "normalize runtime contract",
            "runtime failure interception",
            "emit fail-closed trace artifact",
        ),
        "evidence_summary": {
            "check_keys": sorted(str(key) for key in checks.keys()),
            "check_ok": checks.get("ok"),
        },
        "result": {
            "decision": "RUNTIME_FAILURE",
            "policy": {
                "decision": "STOP",
                "reason_count": 1,
                "reasons": [failure_message],
                "reasoning_fragments": [
                    {
                        "kind": "runtime-failure",
                        "text": failure_message,
                    }
                ],
            },
            "errors": [f"runtime_failure: {failure_message}"],
            "warnings": [],
        },
        "runtime_failure": {
            "violation_type": "runtime_failure",
            "detected_by": "runtime execution wrapper",
            "verdict_impact": violation_verdict_impact("runtime_failure", "stop"),
            "stage": stage,
            "message": failure_message,
        },
        "override_or_escalation": {
            "override_present": bool(checks.get("override_trace") or checks.get("reviewer_override")),
            "escalation_present": True,
        },
    }


def _build_trace_artifact(
    *,
    session_id: str,
    now: str,
    contract: dict[str, Any],
    checks: dict[str, Any],
    decision: str,
    policy: dict[str, Any],
    errors: list[str],
    warnings: list[str],
    contract_resolution: dict[str, Any],
    domain_contract: dict[str, Any],
    decision_context: dict[str, str],
) -> dict[str, Any]:
    return {
        "schema_version": "1.0",
        "artifact_type": "runtime-trace",
        "session_id": session_id,
        "generated_at": now,
        "policy_ref": build_runtime_policy_ref(),
        "contract_identity": _contract_identity(contract_resolution, domain_contract),
        "runtime_contract": contract,
        "decision_governance": {
            "decision_source": runtime_decision_source(),
            "decision_owner": final_verdict_owner(),
            "policy_source": "memory_pipeline.promotion_policy.classify_promotion_policy",
        },
        "decision_context": decision_context,
        "decision_path": _structured_decision_path(
            "normalize runtime contract",
            "evaluate promotion policy",
            "summarize evidence keys",
            "emit verdict and trace artifacts",
        ),
        "evidence_summary": {
            "check_keys": sorted(str(key) for key in checks.keys()),
            "check_ok": checks.get("ok"),
        },
        "result": {
            "decision": decision,
            "policy": _build_policy_summary(policy),
            "errors": errors,
            "warnings": warnings,
        },
        "override_or_escalation": {
            "override_present": bool(checks.get("override_trace") or checks.get("reviewer_override")),
            "escalation_present": decision == "REVIEW_REQUIRED" or contract.get("oversight") != "auto",
        },
    }


def run_session_end(
    project_root: Path,
    session_id: str,
    runtime_contract: dict[str, Any],
    checks: dict[str, Any] | None = None,
    architecture_impact_preview: dict[str, Any] | None = None,
    proposal_summary: dict[str, Any] | None = None,
    contract_resolution: dict[str, Any] | None = None,
    domain_contract: dict[str, Any] | None = None,
    event_log: list[dict[str, Any]] | None = None,
    response_text: str = "",
    summary: str = "",
    approved_by_auto: str = "governance-auto",
    initial_agent_class: str | None = None,
    session_start_phase_classification: dict[str, Any] | None = None,
) -> dict[str, Any]:
    contract = _normalize_runtime_contract(runtime_contract)
    checks = checks or {}
    architecture_impact_preview = architecture_impact_preview or {}
    proposal_summary = proposal_summary or {}
    contract_resolution = dict(contract_resolution or {})
    domain_contract = domain_contract or {}
    if not contract_resolution.get("risk_tier"):
        contract_resolution["risk_tier"] = domain_risk_tier((domain_contract.get("raw") or {}).get("domain"))
    event_log = event_log or []
    errors: list[str] = []
    warnings: list[str] = []

    if not session_id.strip():
        errors.append("session_id is required")

    required_fields = ("task", "rules", "risk", "oversight", "memory_mode")
    missing_fields = [field for field in required_fields if not contract.get(field)]
    if missing_fields:
        errors.append(f"runtime_contract missing required fields: {missing_fields}")

    if checks and checks.get("ok") is False:
        warnings.append("Session ended with failing runtime checks.")

    public_api_diff = (checks or {}).get("public_api_diff") if checks else None

    snapshot_result = None
    curated_result = None
    promotion_result = None
    daily_memory_path: Path | None = None
    daily_memory_record: dict[str, str] | None = None
    policy = classify_promotion_policy(contract, check_result=checks)
    decision = policy["decision"]
    decision_context = _build_decision_context(project_root, contract["memory_mode"], checks, initial_agent_class)

    # ── Governance classification change warnings ─────────────────────────
    # Emit advisory warnings when classification transitions are detected.
    # See docs/classification-transition-semantics.md for transition rules.
    if decision_context.get("classification_changed"):
        _reason = decision_context.get("reclassification_reason") or "unknown"
        _initial = decision_context.get("initial_agent_class")
        _effective = decision_context.get("effective_agent_class")
        _strategy = decision_context.get("governance_strategy")
        if _reason == "classification_anomaly_upgrade":
            warnings.append(
                f"governance: classification_anomaly — agent class upgraded from "
                f"{_initial!r} to {_effective!r} within session; "
                "upgrades are unexpected and may indicate proxy inconsistency"
            )
        else:
            warnings.append(
                f"governance: classification_downgrade — {_initial!r} → {_effective!r} "
                f"(reason: {_reason}); governance_strategy tightened to {_strategy!r}"
            )

    memory_root = project_root / "memory"
    if contract["memory_mode"] != "stateless" and response_text:
        snapshot_result = create_session_snapshot(
            memory_root=memory_root,
            task=contract["task"],
            summary=summary or "Session-end candidate memory snapshot",
            source_text=response_text,
            risk=contract["risk"],
            oversight=contract["oversight"],
        )
    elif contract["memory_mode"] != "stateless":
        warnings.append("Session-end completed without response_text; candidate snapshot was skipped.")

    candidate_signals = _detect_memory_candidate_signals(
        checks=checks,
        errors=errors,
        warnings=warnings,
        architecture_impact_preview=architecture_impact_preview,
        proposal_summary=proposal_summary,
    )

    if decision == "AUTO_PROMOTE" and snapshot_result is not None:
        promotion_result = promote_candidate(
            memory_root=memory_root,
            candidate_file=Path(snapshot_result["snapshot_path"]),
            approved_by=approved_by_auto,
            title=contract["task"],
        )
    elif decision == "AUTO_PROMOTE" and snapshot_result is None:
        warnings.append("AUTO_PROMOTE policy resolved without a candidate snapshot.")

    memory_closeout = _build_memory_closeout(
        contract=contract,
        policy=policy,
        snapshot_result=snapshot_result,
        promotion_result=promotion_result,
        candidate_signals=candidate_signals,
        warnings=warnings,
        errors=errors,
    )

    now = datetime.now(timezone.utc).isoformat()

    # ── Canonical closeout — orchestration layer input collection ─────────────
    # build_canonical_closeout() is a pure function; all IO is collected here
    # by the caller so the function itself remains deterministic and replayable.
    _closeout_candidate = pick_latest_candidate(session_id, project_root)
    _artifacts_referenced = (_closeout_candidate or {}).get("artifacts_referenced") or []
    # WEAK SIGNAL: existence check only. Proves the path exists on disk; does
    # NOT prove the file was created by this session, that the AI summary is
    # accurate, or that any tool actually operated on it.
    # See docs/closeout-schema.md — "Signal strength" for full semantics.
    _existing_artifacts = frozenset(
        p for p in _artifacts_referenced
        if p and (project_root / p).exists()
    )
    # tools_executed: raw tool names from event_log["tool"] entries.
    # Taxonomy is frozen in _canonical_closeout._VERIFIABLE_TOOLS.
    # Names are matched case-insensitively; normalization (pytest vs python -m
    # pytest) is NOT done here — callers that want normalized names must
    # pre-normalize before passing event_log.
    _tools_executed = [
        entry["tool"] for entry in event_log
        if isinstance(entry, dict) and entry.get("tool")
    ]
    _runtime_signals: dict[str, Any] = {"tools_executed": _tools_executed} if _tools_executed else {}
    canonical_closeout = build_canonical_closeout(
        session_id=session_id,
        closed_at=now,
        candidate_payload=_closeout_candidate,
        existing_artifacts=_existing_artifacts,
        runtime_signals=_runtime_signals,
    )
    if contract["memory_mode"] != "stateless":
        daily_memory_record = _build_daily_memory_record(
            project_root=project_root,
            session_id=session_id,
            task=contract["task"],
            decision=decision,
            summary=summary,
            promoted=promotion_result is not None,
            snapshot_created=snapshot_result is not None,
            canonical_closeout=canonical_closeout,
        )

    candidate_artifact, curated_artifact, summary_artifact, verdict_artifact_dir, trace_artifact_dir = _ensure_runtime_artifact_dirs(project_root)
    candidate_path = candidate_artifact / f"{session_id}.json"
    curated_path = curated_artifact / f"{session_id}.json"
    summary_path = summary_artifact / f"{session_id}.json"
    verdict_path = verdict_artifact_dir / f"{session_id}.json"
    trace_path = trace_artifact_dir / f"{session_id}.json"
    governance_artifact_dir = project_root / "artifacts" / "governance"
    governance_artifact_dir.mkdir(parents=True, exist_ok=True)
    runtime_phase_summary_path = governance_artifact_dir / "runtime_phase_summary.json"
    pre_task_phase_classification = session_start_phase_classification or {}
    post_task_phase_classification = _build_post_task_phase_classification_from_checks(checks)
    session_end_phase_classification = _build_session_end_phase_classification(
        memory_mode=contract["memory_mode"],
        snapshot_result=snapshot_result,
        promotion_result=promotion_result,
        decision=decision,
        checks=checks,
    )
    runtime_phase_summary = aggregate_phase_classifications(
        phase_classifications={
            "pre_task_check": pre_task_phase_classification,
            "post_task_check": post_task_phase_classification,
            "session_end": session_end_phase_classification,
        }
    )
    closeout_path: Path | None = None

    try:
        _force_runtime_failure_if_requested(checks, "artifact_emission")

        candidate_payload = {
            "session_id": session_id,
            "closed_at": now,
            "runtime_contract": contract,
            "checks": checks,
            "architecture_impact_preview": architecture_impact_preview,
            "proposal_summary": proposal_summary,
            "contract_resolution": contract_resolution,
            "domain_contract": domain_contract,
            "public_api_diff": public_api_diff,
            "event_log": event_log,
            "snapshot": snapshot_result,
            "policy": policy,
            "promotion": promotion_result,
            "warnings": warnings,
            "errors": errors,
            "phase_classification": session_end_phase_classification,
        }
        summary_payload = {
            "session_id": session_id,
            "closed_at": now,
            "task": contract["task"],
            "decision": decision,
            "risk": contract["risk"],
            "oversight": contract["oversight"],
            "memory_mode": contract["memory_mode"],
            "rules": contract["rules"],
            "architecture_impact_present": bool(architecture_impact_preview),
            "architecture_impact_concern_count": len(architecture_impact_preview.get("concerns", []) or []),
            "architecture_impact_boundary_risk": architecture_impact_preview.get("boundary_risk"),
            "architecture_impact_recommended_risk": architecture_impact_preview.get("recommended_risk"),
            "architecture_impact_recommended_oversight": architecture_impact_preview.get("recommended_oversight"),
            "proposal_summary_present": bool(proposal_summary),
            "proposal_summary_recommended_risk": proposal_summary.get("recommended_risk"),
            "proposal_summary_recommended_oversight": proposal_summary.get("recommended_oversight"),
            "proposal_summary_concern_count": len(proposal_summary.get("concerns", []) or []),
            "proposal_summary_expected_validator_count": len(proposal_summary.get("expected_validators", []) or []),
            "contract_resolution_present": bool(contract_resolution),
            "contract_source": contract_resolution.get("source"),
            "contract_path": contract_resolution.get("path"),
            "contract_name": domain_contract.get("name"),
            "contract_domain": (domain_contract.get("raw") or {}).get("domain"),
            "contract_plugin_version": (domain_contract.get("raw") or {}).get("plugin_version"),
            "contract_risk_tier": contract_resolution.get("risk_tier"),
            "public_api_diff_present": public_api_diff is not None,
            "public_api_removed_count": len(public_api_diff.get("removed", [])) if public_api_diff else 0,
            "public_api_added_count": len(public_api_diff.get("added", [])) if public_api_diff else 0,
            "snapshot_created": snapshot_result is not None,
            "promoted": promotion_result is not None,
            "daily_memory_path": str(daily_memory_path) if daily_memory_path else None,
            "daily_memory_record": daily_memory_record,
            "memory_closeout": memory_closeout,
            "phase_classification": session_end_phase_classification,
            "runtime_phase_summary_path": str(runtime_phase_summary_path),
            "warning_count": len(warnings),
            "error_count": len(errors),
            "decision_context": decision_context,
        }
        verdict_payload = _build_verdict_artifact(
            session_id=session_id,
            now=now,
            contract=contract,
            checks=checks,
            decision=decision,
            errors=errors,
            warnings=warnings,
            contract_resolution=contract_resolution,
            domain_contract=domain_contract,
            decision_context=decision_context,
        )
        trace_payload = _build_trace_artifact(
            session_id=session_id,
            now=now,
            contract=contract,
            checks=checks,
            decision=decision,
            policy=policy,
            errors=errors,
            warnings=warnings,
            contract_resolution=contract_resolution,
            domain_contract=domain_contract,
            decision_context=decision_context,
        )

        _write_json(candidate_path, candidate_payload)
        curated_result = curate_candidate_artifact(candidate_path, output_path=curated_path)
        _write_json(summary_path, summary_payload)
        _write_json(verdict_path, verdict_payload)
        _write_json(trace_path, trace_payload)
        _write_json(runtime_phase_summary_path, runtime_phase_summary)
        closeout_path = write_canonical_closeout(canonical_closeout, project_root)
        _append_session_index(canonical_closeout, project_root)
        if contract["memory_mode"] != "stateless":
            daily_memory_path = _append_daily_memory_entry(
                project_root=project_root,
                session_id=session_id,
                task=contract["task"],
                decision=decision,
                summary=summary,
                promoted=promotion_result is not None,
                snapshot_created=snapshot_result is not None,
                canonical_closeout=canonical_closeout,
            )
    except Exception as exc:
        closeout_path = None
        failure_message = str(exc)
        errors.append(f"runtime_failure: {failure_message}")
        decision = "RUNTIME_FAILURE"
        policy = {"decision": "STOP", "reason": "runtime_failure"}
        failure_trace_payload = _build_runtime_failure_trace_artifact(
            session_id=session_id,
            now=now,
            contract=contract,
            checks=checks,
            contract_resolution=contract_resolution,
            domain_contract=domain_contract,
            stage="artifact_emission",
            failure_message=failure_message,
            decision_context=decision_context,
        )
        _write_json(trace_path, failure_trace_payload)

    return {
        "ok": len(errors) == 0,
        "session_id": session_id,
        "decision": decision,
        "policy": policy,
        "curated": curated_result,
        "snapshot": snapshot_result,
        "promotion": promotion_result,
        "memory_closeout": memory_closeout,
        "candidate_artifact": str(candidate_path),
        "curated_artifact": str(curated_path),
        "summary_artifact": str(summary_path),
        "verdict_artifact": str(verdict_path),
        "trace_artifact": str(trace_path),
        "runtime_phase_summary_artifact": str(runtime_phase_summary_path),
        "phase_classification": session_end_phase_classification,
        "daily_memory_path": str(daily_memory_path) if daily_memory_path else None,
        "canonical_closeout_artifact": str(closeout_path) if closeout_path else None,
        "canonical_closeout": canonical_closeout,
        "decision_context": decision_context,
        "warnings": warnings,
        "errors": errors,
    }


def format_human_result(result: dict[str, Any]) -> str:
    lines = [
        f"ok={result['ok']}",
        f"session_id={result['session_id']}",
        f"decision={result['decision']}",
        f"candidate_artifact={result['candidate_artifact']}",
        f"curated_artifact={result['curated_artifact']}",
        f"summary_artifact={result['summary_artifact']}",
        f"verdict_artifact={result['verdict_artifact']}",
        f"trace_artifact={result['trace_artifact']}",
        f"runtime_phase_summary_artifact={result['runtime_phase_summary_artifact']}",
    ]
    if result.get("daily_memory_path"):
        lines.append(f"daily_memory_path={result['daily_memory_path']}")
    summary_payload = json.loads(Path(result["summary_artifact"]).read_text(encoding="utf-8"))
    if summary_payload.get("contract_resolution_present"):
        lines.append(f"contract_source={summary_payload.get('contract_source')}")
        lines.append(f"contract_path={summary_payload.get('contract_path')}")
        lines.append(f"contract_name={summary_payload.get('contract_name')}")
        lines.append(f"contract_domain={summary_payload.get('contract_domain')}")
        lines.append(f"contract_plugin_version={summary_payload.get('contract_plugin_version')}")
        lines.append(f"contract_risk_tier={summary_payload.get('contract_risk_tier')}")
    if summary_payload.get("decision_context"):
        dc = summary_payload["decision_context"]
        lines.append(f"surface_validity={dc.get('surface_validity')}")
        lines.append(f"coverage_completeness={dc.get('coverage_completeness')}")
        lines.append(f"memory_integrity={dc.get('memory_integrity')}")
        if dc.get("effective_agent_class"):
            lines.append(f"effective_agent_class={dc.get('effective_agent_class')}")
            lines.append(f"governance_strategy={dc.get('governance_strategy')}")
        if dc.get("initial_agent_class") is not None and dc.get("classification_changed") is not None:
            lines.append(f"initial_agent_class={dc.get('initial_agent_class')}")
            lines.append(f"classification_changed={dc.get('classification_changed')}")
            if dc.get("reclassification_reason"):
                lines.append(f"reclassification_reason={dc.get('reclassification_reason')}")
    phase_classification = summary_payload.get("phase_classification") or {}
    if phase_classification.get("phase_summary"):
        compact = " | ".join(
            f"{phase}={','.join(actions)}"
            for phase, actions in phase_classification["phase_summary"].items()
        )
        lines.append(f"phase_classification={compact}")
    memory_closeout = summary_payload.get("memory_closeout") or {}
    if memory_closeout:
        lines.append(f"memory_candidate_detected={memory_closeout.get('candidate_detected')}")
        candidate_signals = memory_closeout.get("candidate_signals") or []
        if candidate_signals:
            lines.append(f"memory_candidate_signals={','.join(candidate_signals)}")
        lines.append(f"memory_promotion_considered={memory_closeout.get('promotion_considered')}")
        lines.append(f"memory_closeout_decision={memory_closeout.get('decision')}")
        lines.append(f"memory_closeout_reason={memory_closeout.get('reason')}")
    if result["snapshot"]:
        lines.append(f"snapshot={result['snapshot']['snapshot_path']}")
    if result["promotion"]:
        lines.append(f"promotion={result['promotion']['status']}")
    for warning in result["warnings"]:
        lines.append(f"warning: {warning}")
    for error in result["errors"]:
        lines.append(f"error: {error}")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description="Close a governance runtime session.")
    parser.add_argument("--project-root", default=".")
    parser.add_argument("--session-id", required=True)
    parser.add_argument("--runtime-contract-file", required=True)
    parser.add_argument("--checks-file")
    parser.add_argument("--impact-preview-file")
    parser.add_argument("--proposal-summary-file")
    parser.add_argument("--session-start-file")
    parser.add_argument("--event-log-file")
    parser.add_argument("--response-file")
    parser.add_argument("--summary", default="")
    parser.add_argument("--approved-by-auto", default="governance-auto")
    parser.add_argument("--format", choices=["human", "json"], default="human")
    args = parser.parse_args()

    runtime_contract = json.loads(Path(args.runtime_contract_file).read_text(encoding="utf-8"))
    checks = json.loads(Path(args.checks_file).read_text(encoding="utf-8")) if args.checks_file else None
    architecture_impact_preview = (
        json.loads(Path(args.impact_preview_file).read_text(encoding="utf-8")) if args.impact_preview_file else None
    )
    proposal_summary = (
        json.loads(Path(args.proposal_summary_file).read_text(encoding="utf-8")) if args.proposal_summary_file else None
    )
    session_start_payload = (
        _normalize_session_start_payload(json.loads(Path(args.session_start_file).read_text(encoding="utf-8")))
        if args.session_start_file
        else {}
    )
    event_log = json.loads(Path(args.event_log_file).read_text(encoding="utf-8")) if args.event_log_file else None
    response_text = Path(args.response_file).read_text(encoding="utf-8") if args.response_file else ""

    # Extract initial_agent_class from session_start governance_classification
    # to enable transition tracking between session_start and session_end.
    _gc = session_start_payload.get("governance_classification") or {}
    initial_agent_class = _gc.get("effective_agent_class") or None

    result = run_session_end(
        project_root=Path(args.project_root).resolve(),
        session_id=args.session_id,
        runtime_contract=runtime_contract,
        checks=checks,
        architecture_impact_preview=architecture_impact_preview,
        proposal_summary=proposal_summary,
        contract_resolution=session_start_payload.get("contract_resolution"),
        domain_contract=session_start_payload.get("domain_contract"),
        event_log=event_log,
        response_text=response_text,
        summary=args.summary,
        approved_by_auto=args.approved_by_auto,
        initial_agent_class=initial_agent_class,
        session_start_phase_classification=(session_start_payload.get("pre_task_check") or {}).get("phase_classification"),
    )

    if args.format == "json":
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(format_human_result(result))

    sys.exit(0 if result["ok"] else 1)


if __name__ == "__main__":
    main()
