#!/usr/bin/env python3
"""
Runtime post-task governance checks.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from governance_tools.contract_validator import validate_contract
from governance_tools.decision_model_loader import policy_precedence_rows, required_evidence_kinds, violation_verdict_impact
from governance_tools.contract_resolver import resolve_contract
from governance_tools.domain_governance_metadata import domain_risk_tier
from governance_tools.domain_contract_loader import load_domain_contract
from governance_tools.domain_validator_loader import build_domain_validation_payload, run_domain_validators
from governance_tools.assumption_check import evaluate_assumption_check, has_modification_intent
from governance_tools.driver_evidence_validator import validate_driver_evidence
from governance_tools.failure_completeness_validator import validate_failure_completeness
from governance_tools.public_api_diff_checker import check_public_api_diff
from governance_tools.refactor_evidence_validator import validate_refactor_evidence
from governance_tools.rule_pack_loader import available_rule_packs, describe_rule_selection, parse_rule_list
from governance_tools.runtime_phase_policy import build_phase_classification
from governance_tools.runtime_reliability_observation import (
    INCIDENT_LOG,
    safe_append_observation_event,
)
from governance_tools.semantic_observation import observe_semantic_failures
from memory_pipeline.session_snapshot import create_session_snapshot
from runtime_hooks.core.human_summary import build_summary_line, format_contract_summary_label

PUBLIC_API_DIFF_REQUIRED_KEYS = {
    "ok",
    "removed",
    "added",
    "compatibility_risk",
    "breaking_changes",
    "non_breaking_changes",
    "warnings",
    "errors",
}

ADVISORY_SIGNAL_METADATA = {
    "missing_required_evidence": {
        "signal_name": "required_evidence_missing",
        "signal_class": "evidence_advisory",
        "decision_distance": "enforced_elsewhere",
        "summary": "required evidence is incomplete for this decision surface",
        "non_proof": "not behavioral compliance proof",
        "usage": "already handled by evidence-driven escalation or stop logic",
    },
    "assumption_check_missing": {
        "signal_name": "assumption_check_missing",
        "signal_class": "behavioral_advisory",
        "decision_distance": "far",
        "summary": "no explicit assumption validation found before modification",
        "non_proof": "not proof of invalidity; indicates premise-validation trace is missing",
        "usage": "advisory only; do not treat as a gate or blocker",
    }
}

PROTECTED_REPORT_PROVENANCE_FIELDS = {
    "token_source_summary",
    "provenance_warning",
}

PROTECTED_NON_AUTHORITATIVE_FIELDS = {
    "token_count",
    "token_observability_level",
    "token_source_summary",
    "provenance_warning",
    "decision_safety",
}

MACHINE_FACING_PATHS = {
    "analysis",
    "decision",
    "gate",
    "machine",
    "ranking",
    "scoring",
}

FORBIDDEN_CONSUMPTION_USES = {
    "gating",
    "hard_gating",
    "soft_gating",
    "ranking",
    "scoring",
    "prioritization",
    "automatic_review_routing",
    "review_routing",
}

PROMOTION_REQUIRED_FIELDS = (
    "reviewer_confirmed",
    "authority_ref",
    "evidence_ref",
    "promoted_at",
    "promotion_reason",
)


def _is_protected_non_authoritative_field(field_name: str) -> bool:
    normalized = str(field_name or "").strip()
    if not normalized:
        return False
    for protected in PROTECTED_NON_AUTHORITATIVE_FIELDS:
        if normalized == protected or normalized.startswith(f"{protected}."):
            return True
    return False


def _build_post_task_phase_classification(
    *,
    evidence_violations: list[dict],
    assumption_advisories: list[dict],
) -> dict:
    action_ids: list[str] = []
    if assumption_advisories:
        action_ids.append("assumption_check_missing")
    for violation in evidence_violations:
        violation_type = str(violation.get("violation_type", "")).strip()
        if violation_type == "missing_required_evidence":
            action_ids.append("required_evidence_missing")
        elif violation_type == "invalid_evidence_schema":
            action_ids.append("invalid_evidence_schema")
    return build_phase_classification(action_ids=action_ids, hook="post_task_check")


def _merge_runtime_checks(errors: list[str], warnings: list[str], checks: dict | None) -> None:
    if not checks:
        return

    for warning in checks.get("warnings", []):
        warnings.append(f"runtime-check: {warning}")

    for error in checks.get("errors", []):
        errors.append(f"runtime-check: {error}")


def _merge_refactor_evidence_checks(errors: list[str], warnings: list[str], checks: dict | None, rules: list[str]) -> dict | None:
    if "refactor" not in rules:
        return None

    result = validate_refactor_evidence(checks)
    for warning in result["warnings"]:
        warnings.append(f"refactor-evidence: {warning}")
    for error in result["errors"]:
        errors.append(f"refactor-evidence: {error}")
    return result


def _validate_public_api_diff_schema(payload: object) -> str | None:
    if not isinstance(payload, dict):
        return "public-api-diff evidence must be an object"

    missing_keys = sorted(PUBLIC_API_DIFF_REQUIRED_KEYS - set(payload))
    if missing_keys:
        return f"public-api-diff evidence missing keys: {missing_keys}"

    if not isinstance(payload.get("ok"), bool):
        return "public-api-diff evidence field 'ok' must be a boolean"

    for key in ("removed", "added", "breaking_changes", "non_breaking_changes", "warnings", "errors"):
        if not isinstance(payload.get(key), list):
            return f"public-api-diff evidence field '{key}' must be a list"

    if not isinstance(payload.get("compatibility_risk"), str):
        return "public-api-diff evidence field 'compatibility_risk' must be a string"

    return None


def _merge_public_api_diff_checks(
    errors: list[str],
    warnings: list[str],
    checks: dict | None,
    rules: list[str],
    api_before_files: list[Path] | None,
    api_after_files: list[Path] | None,
) -> dict | None:
    if "refactor" not in rules:
        return None

    result = None
    if checks and "public_api_diff" in checks:
        schema_error = _validate_public_api_diff_schema(checks["public_api_diff"])
        if schema_error:
            return None
        result = checks["public_api_diff"]
    elif api_before_files and api_after_files:
        result = check_public_api_diff(api_before_files, api_after_files)
    else:
        return None

    for warning in result.get("warnings", []):
        warnings.append(f"public-api-diff: {warning}")
    for error in result.get("errors", []):
        errors.append(f"public-api-diff: {error}")
    return result


def _merge_failure_completeness_checks(errors: list[str], warnings: list[str], checks: dict | None, rules: list[str]) -> dict | None:
    if not checks:
        return None

    result = validate_failure_completeness(checks, require_cleanup=("refactor" in rules))
    for warning in result["warnings"]:
        warnings.append(f"failure-completeness: {warning}")
    for error in result["errors"]:
        errors.append(f"failure-completeness: {error}")
    return result


def _merge_driver_evidence_checks(errors: list[str], warnings: list[str], checks: dict | None, rules: list[str]) -> dict | None:
    if "kernel-driver" not in rules:
        return None

    result = validate_driver_evidence(checks)
    for warning in result["warnings"]:
        warnings.append(f"driver-evidence: {warning}")
    for error in result["errors"]:
        errors.append(f"driver-evidence: {error}")
    return result


def _observed_runtime_evidence_kinds(
    checks: dict | None,
    *,
    public_api_diff: dict | None,
    driver_evidence: dict | None,
    domain_validator_results: list[dict],
) -> set[str]:
    observed = set(str(kind) for kind in (checks or {}).get("evidence_kinds", []) if str(kind).strip())
    if checks and "public_api_diff" in checks:
        observed.add("public-api-diff")
    elif public_api_diff is not None:
        observed.add("public-api-diff")
    if driver_evidence and driver_evidence.get("ok"):
        observed.add("sdv-text")
    if domain_validator_results:
        observed.add("domain-validator-result")
    return observed


def _classify_invalid_evidence_schema(checks: dict | None) -> list[dict]:
    if not checks or "public_api_diff" not in checks:
        return []

    schema_error = _validate_public_api_diff_schema(checks["public_api_diff"])
    if not schema_error:
        return []

    return [
        {
            "violation_type": "invalid_evidence_schema",
            "evidence_kind": "public-api-diff",
            "detected_by": "runtime evidence validator",
            "verdict_impact": violation_verdict_impact("invalid_evidence_schema", "stop"),
            "message": f"Invalid runtime evidence schema: public-api-diff ({schema_error})",
        }
    ]


def _classify_policy_conflicts(checks: dict | None) -> list[dict]:
    if not checks:
        return []

    policy_conflicts = checks.get("policy_conflicts") or []
    if not isinstance(policy_conflicts, list):
        return []

    precedence_rows = policy_precedence_rows()
    violations = []
    for item in policy_conflicts:
        if not isinstance(item, dict):
            continue
        policy_type = str(item.get("policy_type", "")).strip()
        override_target = str(item.get("override_target", "")).strip()
        scope = str(item.get("scope", "")).strip()
        if not policy_type or not override_target:
            continue

        matched_row = next(
            (
                row
                for row in precedence_rows
                if str(row.get("policy_type")) == policy_type
                and str(row.get("override_target")) == override_target
            ),
            None,
        )

        if matched_row is None:
            violations.append(
                {
                    "violation_type": "policy_conflict",
                    "policy_type": policy_type,
                    "override_target": override_target,
                    "scope": scope,
                    "detected_by": "policy precedence resolver",
                    "verdict_impact": violation_verdict_impact("policy_conflict", "escalate"),
                    "message": f"Unresolved runtime policy conflict: {policy_type} -> {override_target}",
                }
            )
            continue

        if matched_row.get("allowed") is False:
            violations.append(
                {
                    "violation_type": "illegal_override",
                    "policy_type": policy_type,
                    "override_target": override_target,
                    "scope": scope or str(matched_row.get("scope", "")),
                    "detected_by": "ownership and precedence validator",
                    "verdict_impact": violation_verdict_impact("illegal_override", "stop"),
                    "message": f"Illegal runtime policy override: {policy_type} -> {override_target}",
                }
            )
            continue

        violations.append(
            {
                "violation_type": "policy_conflict",
                "policy_type": policy_type,
                "override_target": override_target,
                "scope": scope or str(matched_row.get("scope", "")),
                "detected_by": "policy precedence resolver",
                "verdict_impact": violation_verdict_impact("policy_conflict", "escalate"),
                "message": (
                    f"Runtime policy conflict requires precedence resolution: {policy_type} -> {override_target} "
                    f"({matched_row.get('conflict_resolution')})"
                ),
            }
        )
    return violations


def _classify_domain_policy_inputs(
    results: list[dict],
    *,
    hard_stop_rules: set[str],
) -> list[dict]:
    if not hard_stop_rules:
        return []

    policy_inputs = []
    for item in results:
        matched_rule_ids = sorted(set(str(rule_id) for rule_id in item.get("rule_ids", [])) & hard_stop_rules)
        if not matched_rule_ids:
            continue
        for violation in item.get("violations", []):
            policy_inputs.append(
                {
                    "violation_type": "domain_contract_violation",
                    "policy_type": "domain-contract policy",
                    "override_target": "runtime default verdict",
                    "source": "hard_stop_rules",
                    "validator": item.get("name"),
                    "rule_ids": matched_rule_ids,
                    "detected_by": "domain validator",
                    "verdict_impact": violation_verdict_impact("domain_contract_violation", "stop"),
                    "message": (
                        f"Domain policy stop requested by hard_stop_rules: {item.get('name')} -> {violation} "
                        f"(rules: {','.join(matched_rule_ids)})"
                    ),
                }
            )
    return policy_inputs


def _classify_missing_required_evidence(
    checks: dict | None,
    *,
    public_api_diff: dict | None,
    driver_evidence: dict | None,
    domain_validator_results: list[dict],
) -> list[dict]:
    declared_required = [
        str(kind)
        for kind in (checks or {}).get("required_runtime_evidence", [])
        if str(kind).strip()
    ]
    if not declared_required:
        return []

    known_required = required_evidence_kinds()
    observed = _observed_runtime_evidence_kinds(
        checks,
        public_api_diff=public_api_diff,
        driver_evidence=driver_evidence,
        domain_validator_results=domain_validator_results,
    )
    violations = []
    for evidence_kind in declared_required:
        if evidence_kind not in known_required:
            continue
        if evidence_kind in observed:
            continue
        violations.append(
            {
                "violation_type": "missing_required_evidence",
                "evidence_kind": evidence_kind,
                "detected_by": "runtime evidence validator",
                "verdict_impact": violation_verdict_impact("missing_required_evidence", "escalate"),
                "message": f"Missing required runtime evidence: {evidence_kind}",
            }
        )
    return violations


def _build_provenance_boundary_audit(checks: dict | None) -> dict:
    audit = {
        "status": "no_observation",
        "advisory_only": True,
        "observed_surface": "post_task_check",
        "suspected_consumer": None,
        "protected_field": None,
        "protected_namespace": "report",
        "basis": "report provenance consumption observation",
        "usage_note": "No machine-facing consumption of protected report provenance fields was observed.",
    }
    if not checks:
        return audit

    observations = checks.get("report_provenance_consumption") or []
    if not isinstance(observations, list):
        return audit

    for item in observations:
        if not isinstance(item, dict):
            continue
        consumer_path = str(item.get("consumer_path", "")).strip().lower()
        if consumer_path not in MACHINE_FACING_PATHS:
            continue

        fields = item.get("fields") or []
        if isinstance(fields, str):
            fields = [fields]
        protected = [str(field).strip() for field in fields if _is_protected_non_authoritative_field(str(field).strip())]
        if not protected:
            continue

        audit.update(
            {
                "status": "candidate_violation",
                "suspected_consumer": str(item.get("consumer_name", "")).strip() or None,
                "protected_field": protected[0],
                "violation_type": "non_decisional_signal_used_in_decision",
                "usage_note": (
                    "Candidate violation: machine-facing logic consumed a protected non-authoritative report field. "
                    "Advisory only; must not modify gate behavior."
                ),
            }
        )
        return audit

    return audit


def _build_candidate_violation_promotion_contract(
    provenance_boundary_audit: dict,
    checks: dict | None,
) -> dict:
    contract = {
        "contract_version": "v0.1",
        "notice": "This contract does not authorize automated escalation.",
        "candidate_violation_status": str(provenance_boundary_audit.get("status", "no_observation")),
        "advisory_only": True,
        "auto_block_allowed": False,
        "auto_promotion_allowed": False,
        "promotion_decision": "not_applicable",
        "promotion_eligible": False,
        "promoted_policy_violation": None,
        "missing_requirements": [],
    }

    if contract["candidate_violation_status"] != "candidate_violation":
        return contract

    contract["promotion_decision"] = "pending_authority_path"
    payload = {}
    if checks and isinstance(checks.get("candidate_violation_promotion"), dict):
        payload = checks.get("candidate_violation_promotion") or {}

    reviewer_confirmed = bool(payload.get("reviewer_confirmed"))
    authority_ref = str(payload.get("authority_ref", "") or "").strip()
    evidence_ref = str(payload.get("evidence_ref", "") or "").strip()
    promoted_at = str(payload.get("promoted_at", "") or "").strip()
    promotion_reason = str(payload.get("promotion_reason", "") or "").strip()
    confidence = payload.get("detector_confidence")

    missing = []
    if not reviewer_confirmed:
        missing.append("reviewer_confirmed")
    if not authority_ref:
        missing.append("authority_ref")
    if not evidence_ref:
        missing.append("evidence_ref")
    if not promoted_at:
        missing.append("promoted_at")
    if not promotion_reason:
        missing.append("promotion_reason")

    contract["missing_requirements"] = missing
    contract["promotion_inputs"] = {
        "reviewer_confirmed": reviewer_confirmed,
        "authority_ref": authority_ref or None,
        "evidence_ref": evidence_ref or None,
        "promoted_at": promoted_at or None,
        "promotion_reason": promotion_reason or None,
        "detector_confidence": confidence,
    }
    contract["promotion_eligible"] = len(missing) == 0

    if contract["promotion_eligible"]:
        contract["promotion_decision"] = "promoted_by_authority_path"
        contract["promoted_policy_violation"] = {
            "violation_type": "non_decisional_signal_used_in_decision",
            "detected_by": "candidate-violation promotion contract",
            "authority_ref": authority_ref,
            "evidence_ref": evidence_ref,
            "promoted_at": promoted_at,
            "promotion_reason": promotion_reason,
        }
    else:
        contract["promotion_decision"] = "cannot_promote_missing_requirements"

    return contract


def _build_candidate_violation_consumption_contract(
    *,
    promotion_contract: dict,
    checks: dict | None,
) -> dict:
    contract = {
        "contract_version": "v0.1",
        "notice": "This contract does not authorize automated escalation.",
        "allowed_uses": ["human_review", "diagnostics", "investigation"],
        "forbidden_uses": sorted(FORBIDDEN_CONSUMPTION_USES),
        "enforcement_readiness": False,
        "enforcement_readiness_note": (
            "Presence of promoted_policy_violation does not imply enforcement readiness."
        ),
        "consumption_violation": False,
        "violation_type": None,
        "field": None,
        "consumer": None,
    }

    usage = {}
    if checks and isinstance(checks.get("candidate_violation_consumption"), dict):
        usage = checks.get("candidate_violation_consumption") or {}
    use_type = str(usage.get("use_type", "") or "").strip().lower()
    field = str(usage.get("field", "") or "").strip() or None
    consumer = str(usage.get("consumer", "") or "").strip() or None

    contract["observed_use_type"] = use_type or None
    contract["field"] = field
    contract["consumer"] = consumer

    if use_type in FORBIDDEN_CONSUMPTION_USES:
        contract["consumption_violation"] = True
        contract["violation_type"] = f"used_in_{use_type}"

    return contract


def _build_consumption_pattern_visibility(checks: dict | None) -> dict:
    by_type: dict[str, int] = {}
    by_field: dict[str, int] = {}
    by_consumer: dict[str, int] = {}
    total = 0

    records = []
    if checks and isinstance(checks.get("candidate_violation_consumption_events"), list):
        records = checks.get("candidate_violation_consumption_events") or []
    elif checks and isinstance(checks.get("candidate_violation_consumption"), dict):
        records = [checks.get("candidate_violation_consumption") or {}]

    for item in records:
        if not isinstance(item, dict):
            continue
        use_type = str(item.get("use_type", "") or "").strip().lower()
        field = str(item.get("field", "") or "").strip() or "unknown"
        consumer = str(item.get("consumer", "") or "").strip() or "unknown"

        if use_type not in FORBIDDEN_CONSUMPTION_USES:
            continue

        total += 1
        key = f"used_in_{use_type}"
        by_type[key] = by_type.get(key, 0) + 1
        by_field[field] = by_field.get(field, 0) + 1
        by_consumer[consumer] = by_consumer.get(consumer, 0) + 1

    return {
        "contract_version": "v0.1",
        "total_violations": total,
        "by_type": by_type,
        "by_field": by_field,
        "by_consumer": by_consumer,
        "high_frequency_misuse_triggers_enforcement": False,
        "visibility_only": True,
        "notice": "High frequency misuse does NOT trigger enforcement. Visibility increase only; no blocking, routing, scoring, or automated action.",
    }


def _slim_domain_contract(dc: dict | None) -> dict | None:
    """Return domain_contract with document content elided for the return payload.

    Design principle:
        Heavy execution context may be used during validation, but must not be
        echoed back in return payloads unless it remains semantically necessary
        after execution completes.

    Concretely:
        - run_domain_validators() receives the full domain_contract (full content).
        - The return dict does NOT need file content — callers care about
          domain_validator_results, rule_packs, ok/errors/warnings, not the raw
          document text that was already consumed.
        - content_char_count preserves debuggability: callers can still tell
          whether original content was present and how large it was.

    IMPORTANT: Do not pass the return value of this function back into any
    execution path (validators, build_domain_validation_payload, etc.).  It is
    report-only.
    """
    if dc is None:
        return None

    def _slim_entry(entry: dict) -> dict:
        content = entry.get("content", "")
        slim = dict(entry)
        slim["content"] = ""
        slim["content_elided_for_return"] = True
        slim["content_char_count"] = len(content)
        return slim

    slim = dict(dc)
    slim["documents"] = [_slim_entry(d) for d in dc.get("documents", [])]
    slim["ai_behavior_override"] = [_slim_entry(d) for d in dc.get("ai_behavior_override", [])]
    return slim


def _domain_hard_stop_rules(domain_contract: dict | None) -> set[str]:
    raw = (domain_contract or {}).get("raw") or {}
    values = raw.get("hard_stop_rules") or []
    if isinstance(values, list):
        return {str(value) for value in values if str(value).strip()}
    if values:
        return {str(values)}
    return set()


def _merge_domain_validator_results(
    errors: list[str],
    warnings: list[str],
    results: list[dict],
) -> None:
    for item in results:
        for warning in item.get("warnings", []):
            warnings.append(f"domain-validator:{item['name']}: {warning}")
        for violation in item.get("violations", []):
            warnings.append(f"domain-validator:{item['name']}: {violation}")
        for error in item.get("errors", []):
            errors.append(f"domain-validator:{item['name']}: {error}")


def run_post_task_check(
    response_text: str,
    risk: str,
    oversight: str,
    memory_mode: str | None = None,
    memory_root: Path | None = None,
    snapshot_task: str | None = None,
    snapshot_summary: str | None = None,
    create_snapshot: bool = False,
    checks: dict | None = None,
    api_before_files: list[Path] | None = None,
    api_after_files: list[Path] | None = None,
    contract_file: Path | None = None,
    project_root: Path | None = None,
    evidence_paths: list[Path] | None = None,
) -> dict:
    observed_project_root = (project_root.resolve() if project_root else Path.cwd().resolve())
    contract_resolution = resolve_contract(
        contract_file,
        project_root=project_root,
        extra_paths=evidence_paths,
    )
    resolved_contract_file = contract_resolution.path
    domain_contract = load_domain_contract(resolved_contract_file) if resolved_contract_file else None
    contract_rules_roots = [Path(path) for path in domain_contract.get("rule_roots", [])] if domain_contract else []
    available_rules = available_rule_packs(contract_rules_roots + [Path(__file__).resolve().parents[2] / "governance" / "rules"])
    validation = validate_contract(response_text, available_rules=available_rules if domain_contract else None)
    errors = list(validation.errors)
    warnings = list(validation.warnings)
    assumption_check = evaluate_assumption_check(response_text, require_action_decision=True)
    assumption_advisories: list[dict] = []
    fields = validation.fields
    resolved_memory_mode = memory_mode or fields.get("MEMORY_MODE", "").strip() or "candidate"
    resolved_rules = parse_rule_list(fields.get("RULES", ""))
    snapshot_result = None
    effective_checks = dict(checks or {})

    if not validation.contract_found:
        errors.append("Missing governance contract in task output")

    if risk == "high" and oversight == "auto":
        errors.append("High-risk task completed without required oversight")

    if resolved_memory_mode == "durable" and oversight == "auto":
        errors.append("Durable memory requires oversight != auto")

    if resolved_memory_mode == "durable" and oversight == "review-required":
        warnings.append("Durable memory should typically be promoted after explicit review completion")
    warnings.extend(contract_resolution.warnings)
    if contract_resolution.error:
        errors.append(contract_resolution.error)

    if domain_contract:
        rules_roots = contract_rules_roots + [Path(__file__).resolve().parents[2] / "governance" / "rules"]
        resolved_rule_packs = describe_rule_selection(resolved_rules, rules_roots)
        if not resolved_rule_packs["valid"]:
            errors.append(f"Unknown rule packs: {resolved_rule_packs['missing']}")
    else:
        resolved_rule_packs = None

    _merge_runtime_checks(errors, warnings, effective_checks)
    if has_modification_intent(response_text) and not assumption_check["complete"]:
        missing = ",".join(assumption_check["missing"])
        warning = (
            "Assumption check missing before modification: "
            f"missing={missing}"
        )
        warnings.append(warning)
        assumption_advisories.append(
            {
                "violation_type": "assumption_check_missing",
                "detected_by": "post-task assumption-check observer",
                "message": warning,
                "missing": list(assumption_check["missing"]),
            }
        )
    public_api_diff = _merge_public_api_diff_checks(
        errors,
        warnings,
        effective_checks,
        resolved_rules,
        api_before_files,
        api_after_files,
    )
    if public_api_diff:
        effective_checks["public_api_diff"] = public_api_diff
        effective_checks["interface_stability_verified"] = public_api_diff.get("ok", False)
    failure_completeness = _merge_failure_completeness_checks(errors, warnings, effective_checks, resolved_rules)
    refactor_evidence = _merge_refactor_evidence_checks(errors, warnings, effective_checks, resolved_rules)
    driver_evidence = _merge_driver_evidence_checks(errors, warnings, effective_checks, resolved_rules)
    domain_validator_results = []
    domain_hard_stop_rules = _domain_hard_stop_rules(domain_contract)
    if domain_contract:
        domain_payload = build_domain_validation_payload(
            response_text=response_text,
            checks=effective_checks,
            fields=fields,
            resolved_rules=resolved_rules,
            domain_contract=domain_contract,
            contract_file=resolved_contract_file,
        )
        domain_validator_results = run_domain_validators(
            contract_file=resolved_contract_file,
            payload=domain_payload,
            active_rule_ids=resolved_rules,
        )
        _merge_domain_validator_results(
            errors,
            warnings,
            domain_validator_results,
        )
    evidence_violations = _classify_invalid_evidence_schema(effective_checks)
    evidence_violations.extend(
        _classify_missing_required_evidence(
            effective_checks,
            public_api_diff=public_api_diff,
            driver_evidence=driver_evidence,
            domain_validator_results=domain_validator_results,
        )
    )
    policy_violations = _classify_policy_conflicts(effective_checks)
    policy_violations.extend(
        _classify_domain_policy_inputs(
            domain_validator_results,
            hard_stop_rules=domain_hard_stop_rules,
        )
    )
    provenance_boundary_audit = _build_provenance_boundary_audit(effective_checks)
    candidate_violation_promotion = _build_candidate_violation_promotion_contract(
        provenance_boundary_audit,
        effective_checks,
    )
    candidate_violation_consumption = _build_candidate_violation_consumption_contract(
        promotion_contract=candidate_violation_promotion,
        checks=effective_checks,
    )
    consumption_pattern_visibility = _build_consumption_pattern_visibility(effective_checks)
    semantic_observation = observe_semantic_failures(effective_checks)
    for violation in evidence_violations:
        errors.append(f"runtime-evidence: {violation['message']}")
    for violation in policy_violations:
        errors.append(f"runtime-policy: {violation['message']}")

    if create_snapshot and validation.contract_found and validation.compliant and not errors:
        if memory_root is None:
            errors.append("Snapshot creation requested without memory_root")
        else:
            snapshot_result = create_session_snapshot(
                memory_root=memory_root,
                task=snapshot_task or fields.get("PLAN", "unspecified-task"),
                summary=snapshot_summary or "Post-task candidate memory snapshot",
                source_text=response_text,
                risk=risk,
                oversight=oversight,
            )

    result = {
        "ok": validation.contract_found and validation.compliant and len(errors) == 0,
        "contract_found": validation.contract_found,
        "compliant": validation.compliant,
        "fields": fields,
        "memory_mode": resolved_memory_mode,
        "rules": resolved_rules,
        "snapshot": snapshot_result,
        "checks": effective_checks if effective_checks else None,
        "assumption_check": assumption_check,
        "assumption_advisories": assumption_advisories,
        "resolved_contract_file": str(resolved_contract_file) if resolved_contract_file else None,
        "contract_resolution": {
            "source": contract_resolution.source,
            "path": str(resolved_contract_file) if resolved_contract_file else None,
            "warnings": contract_resolution.warnings,
            "error": contract_resolution.error,
        },
        "public_api_diff": public_api_diff,
        "failure_completeness": failure_completeness,
        "refactor_evidence": refactor_evidence,
        "driver_evidence": driver_evidence,
        "evidence_violations": evidence_violations,
        "policy_violations": policy_violations,
        "provenance_boundary_audit": provenance_boundary_audit,
        "candidate_violation_promotion": candidate_violation_promotion,
        "candidate_violation_consumption": candidate_violation_consumption,
        "consumption_pattern_visibility": consumption_pattern_visibility,
        "semantic_observation": semantic_observation,
        "phase_classification": _build_post_task_phase_classification(
            evidence_violations=evidence_violations,
            assumption_advisories=assumption_advisories,
        ),
        "domain_validator_results": domain_validator_results,
        "domain_hard_stop_rules": sorted(domain_hard_stop_rules),
        "domain_contract": _slim_domain_contract(domain_contract),
        "rule_packs": resolved_rule_packs,
        "errors": errors,
        "warnings": warnings,
    }
    safe_append_observation_event(
        observed_project_root,
        INCIDENT_LOG,
        "post_task_incident_observation",
        {
            "source": "runtime_hooks.core.post_task_check",
            "ok": result["ok"],
            "error_count": len(errors),
            "warning_count": len(warnings),
            "risk": risk,
            "oversight": oversight,
            "policy_violation_count": len(result.get("policy_violations") or []),
            "evidence_violation_count": len(result.get("evidence_violations") or []),
            "semantic_observation_count": len((semantic_observation or {}).get("observations") or []),
        },
    )
    return result


def _render_advisory_violation_line(violation: dict) -> str | None:
    metadata = ADVISORY_SIGNAL_METADATA.get(violation.get("violation_type"))
    if not metadata:
        return None
    return (
        f"advisory_signal: {metadata['signal_name']} -> "
        f"{metadata['signal_class']}; "
        f"{metadata['summary']}; "
        f"decision distance={metadata['decision_distance']}; "
        f"{metadata['non_proof']}; "
        f"{metadata['usage']}"
    )


def format_human_result(result: dict) -> str:
    domain_contract = result.get("domain_contract") or {}
    domain_raw = domain_contract.get("raw") or {}
    contract_label = domain_raw.get("domain") or domain_contract.get("name")
    contract_risk = domain_risk_tier(domain_raw.get("domain") or domain_contract.get("name"))
    lines = [
        "[post_task_check]",
        f"ok={result['ok']}",
        f"contract_found={result['contract_found']}",
        f"compliant={result['compliant']}",
        f"memory_mode={result['memory_mode']}",
    ]
    phase_classification = result.get("phase_classification") or {}
    if phase_classification.get("phase_summary"):
        compact = " | ".join(
            f"{phase}={','.join(actions)}"
            for phase, actions in phase_classification["phase_summary"].items()
        )
        lines.append(f"phase_classification={compact}")
    lines.append(
        build_summary_line(
            f"ok={result['ok']}",
            f"compliant={result['compliant']}",
            f"memory_mode={result['memory_mode']}",
            (
                f"contract={format_contract_summary_label(contract_label, contract_risk)}"
                if contract_label
                else None
            ),
        )
    )
    if result["snapshot"]:
        lines.append(f"snapshot={result['snapshot']['snapshot_path']}")
    if result["public_api_diff"]:
        lines.append(f"public_api_removed={len(result['public_api_diff']['removed'])}")
        lines.append(f"public_api_added={len(result['public_api_diff']['added'])}")
        lines.append(f"public_api_ok={result['public_api_diff']['ok']}")
    if result["failure_completeness"] is not None:
        lines.append(f"failure_completeness_ok={result['failure_completeness']['ok']}")
    if result["refactor_evidence"] is not None:
        lines.append(f"refactor_evidence_ok={result['refactor_evidence']['ok']}")
    if result["driver_evidence"] is not None:
        lines.append(f"driver_evidence_ok={result['driver_evidence']['ok']}")
    assumption_check = result.get("assumption_check") or {}
    if assumption_check:
        lines.append(
            "assumption_check: "
            f"complete={assumption_check.get('complete')} "
            f"assumptions={assumption_check.get('assumptions_present')} "
            f"alternatives={assumption_check.get('alternatives_present')} "
            f"evidence={assumption_check.get('evidence_present')} "
            f"reframe={assumption_check.get('reframe_present')} "
            f"action_decision={assumption_check.get('action_decision')}"
        )
        if assumption_check.get("missing"):
            lines.append(f"assumption_check_missing={','.join(assumption_check['missing'])}")
    if result.get("assumption_advisories"):
        lines.append(f"assumption_advisory_count={len(result['assumption_advisories'])}")
        advisory_line = _render_advisory_violation_line({"violation_type": "assumption_check_missing"})
        if advisory_line:
            lines.append(advisory_line)
    if result.get("evidence_violations"):
        lines.append(f"evidence_violation_count={len(result['evidence_violations'])}")
        for violation in result["evidence_violations"]:
            advisory_line = _render_advisory_violation_line(violation)
            if advisory_line:
                lines.append(advisory_line)
    if result.get("policy_violations"):
        lines.append(f"policy_violation_count={len(result['policy_violations'])}")
    provenance_boundary_audit = result.get("provenance_boundary_audit") or {}
    if provenance_boundary_audit.get("status") == "candidate_violation":
        lines.append(
            "provenance_boundary_audit="
            f"{provenance_boundary_audit['status']} "
            f"field={provenance_boundary_audit.get('protected_field')} "
            f"consumer={provenance_boundary_audit.get('suspected_consumer') or 'unknown'} "
            f"advisory_only={provenance_boundary_audit.get('advisory_only')}"
        )
    promotion = result.get("candidate_violation_promotion") or {}
    if promotion:
        lines.append(
            "candidate_violation_promotion="
            f"{promotion.get('promotion_decision')} "
            f"eligible={promotion.get('promotion_eligible')} "
            f"auto_block_allowed={promotion.get('auto_block_allowed')}"
        )
    consumption = result.get("candidate_violation_consumption") or {}
    if consumption:
        lines.append(
            "candidate_violation_consumption="
            f"violation={consumption.get('consumption_violation')} "
            f"type={consumption.get('violation_type') or 'none'} "
            f"use={consumption.get('observed_use_type') or 'none'}"
        )
    visibility = result.get("consumption_pattern_visibility") or {}
    if visibility:
        lines.append(
            "consumption_pattern_visibility="
            f"total={visibility.get('total_violations', 0)} "
            f"visibility_only={visibility.get('visibility_only')} "
            f"enforcement={visibility.get('high_frequency_misuse_triggers_enforcement')}"
        )
    semantic_observation = result.get("semantic_observation") or {}
    if semantic_observation.get("observations"):
        lines.append(f"semantic_observation_count={len(semantic_observation['observations'])}")
        for hotspot in semantic_observation.get("hotspots", []):
            lines.append(
                "semantic_hotspot="
                f"{hotspot.get('hotspot_id')} "
                f"{hotspot.get('failure_class')} "
                f"risk={hotspot.get('risk_rank')} "
                f"invariant={hotspot.get('invariant_id') or 'none'}"
            )
    if result.get("domain_validator_results"):
        lines.append(f"domain_validator_count={len(result['domain_validator_results'])}")
    if result.get("domain_hard_stop_rules"):
        lines.append(f"domain_hard_stop_rules={','.join(result['domain_hard_stop_rules'])}")
    contract_resolution = result.get("contract_resolution") or {}
    if contract_resolution.get("source"):
        lines.append(f"contract_source={contract_resolution['source']}")
    if contract_resolution.get("path"):
        lines.append(f"contract_path={contract_resolution['path']}")
    if contract_label:
        lines.append(f"contract={contract_label}")
        lines.append(f"contract_risk_tier={contract_risk}")
    if result.get("domain_contract"):
        lines.append(f"domain_contract={result['domain_contract']['name']}")
    for warning in result["warnings"]:
        lines.append(f"warning: {warning}")
    for error in result["errors"]:
        lines.append(f"error: {error}")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description="Run post-task governance checks.")
    parser.add_argument("--file", "-f", help="Response file; defaults to stdin")
    parser.add_argument("--risk", default="medium")
    parser.add_argument("--oversight", default="auto")
    parser.add_argument("--memory-mode")
    parser.add_argument("--memory-root")
    parser.add_argument("--snapshot-task")
    parser.add_argument("--snapshot-summary")
    parser.add_argument("--create-snapshot", action="store_true")
    parser.add_argument("--checks-file")
    parser.add_argument("--api-before", action="append", default=[])
    parser.add_argument("--api-after", action="append", default=[])
    parser.add_argument("--project-root")
    parser.add_argument("--contract")
    parser.add_argument("--format", choices=["human", "json"], default="human")
    args = parser.parse_args()

    if args.file:
        response_text = Path(args.file).read_text(encoding="utf-8")
    else:
        response_text = sys.stdin.read()

    checks = json.loads(Path(args.checks_file).read_text(encoding="utf-8")) if args.checks_file else None

    result = run_post_task_check(
        response_text,
        risk=args.risk,
        oversight=args.oversight,
        memory_mode=args.memory_mode,
        memory_root=Path(args.memory_root) if args.memory_root else None,
        snapshot_task=args.snapshot_task,
        snapshot_summary=args.snapshot_summary,
        create_snapshot=args.create_snapshot,
        checks=checks,
        api_before_files=[Path(path) for path in args.api_before],
        api_after_files=[Path(path) for path in args.api_after],
        project_root=Path(args.project_root).resolve() if args.project_root else None,
        evidence_paths=[Path(path).resolve() for path in [args.file, args.checks_file] if path],
        contract_file=Path(args.contract).resolve() if args.contract else None,
    )

    if args.format == "json":
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(format_human_result(result))

    sys.exit(0 if result["ok"] else 1)


if __name__ == "__main__":
    main()
