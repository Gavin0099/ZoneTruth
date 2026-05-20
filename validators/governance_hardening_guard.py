"""
Weak-agent governance hardening guard (Phase E baseline).

Purpose:
- Reduce inference freedom for governance claims.
- Detect forbidden governance shortcuts in pre-task or closeout text.
- Enforce machine-verifiable closeout payload shape.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any


_FORBIDDEN_PATTERNS = (
    (
        "tests_only_completion_claim",
        ("tests passed", "governance complete"),
        "governance completion cannot be inferred from implementation evidence only",
    ),
    (
        "authority_from_file_presence",
        ("agents.md", "therefore authority"),
        "authority cannot be inferred from file existence",
    ),
    (
        "governance_enabled_from_hooks_presence",
        ("runtime_hooks", "governance enabled"),
        "governance enabled cannot be inferred from hook presence",
    ),
)

_REQUIRED_CLOSEOUT_KEYS = (
    "authority_source_verified",
    "runtime_path_executed",
    "pre_task_gate_observed",
    "post_task_advisory_visible",
    "reviewer_surface_present",
    "closeout_artifact_generated",
    "validation_dataset_updated",
    "governance_status",
)

_ALLOWED_GOVERNANCE_STATUS = frozenset(
    {
        "complete",
        "incomplete",
        "blocked",
        "void",
        "manual_review_required",
        "authority_unverified",
        "runtime_unverifiable",
    }
)

CANONICAL_AUTHORITY_FILES = (
    "GOVERNANCE_ENTRY.md",
    "AGENTS.md",
    "PLAN.md",
    "governance/PHASE_D_CLOSE_AUTHORITY.md",
)

PRECEDENCE_ORDER = (
    "constitutional_authority_documents",
    "registered_authority_artifacts",
    "runtime_governance_outputs",
    "reviewer_visible_advisory_surfaces",
    "readme_local_notes_examples",
    "ai_generated_summaries",
    "tests_passed_statements",
)


def detect_forbidden_inference(
    text: str,
    *,
    authority_source_identified: bool,
) -> dict[str, Any]:
    lowered = (text or "").lower()
    violations: list[dict[str, str]] = []

    if "governance pull command" in lowered and not authority_source_identified:
        violations.append(
            {
                "code": "pull_command_before_authority_source",
                "message": "authority source must be identified before pull-command inference",
            }
        )

    for code, required_tokens, message in _FORBIDDEN_PATTERNS:
        if all(token in lowered for token in required_tokens):
            violations.append({"code": code, "message": message})

    blocked = len(violations) > 0
    return {
        "ok": not blocked,
        "blocked": blocked,
        "manual_authority_verification_required": blocked,
        "violations": violations,
    }


def validate_governance_closeout_payload(payload: dict[str, Any]) -> dict[str, Any]:
    missing = [k for k in _REQUIRED_CLOSEOUT_KEYS if k not in payload]
    type_errors = [
        k
        for k in _REQUIRED_CLOSEOUT_KEYS
        if k in payload
        and (
            (k != "governance_status" and not isinstance(payload[k], bool))
            or (k == "governance_status" and not isinstance(payload[k], str))
        )
    ]
    violations: list[str] = []

    if missing:
        violations.append("missing_required_keys")
    if type_errors:
        violations.append("non_boolean_required_fields")

    # Hard rule: governance_status=complete is only valid if all required evidence fields are true.
    if not missing and not type_errors:
        status = str(payload["governance_status"])
        if status not in _ALLOWED_GOVERNANCE_STATUS:
            violations.append("invalid_governance_status")
        prereq_keys = [k for k in _REQUIRED_CLOSEOUT_KEYS if k != "governance_status"]
        all_prereqs_true = all(payload[k] is True for k in prereq_keys)
        if status == "complete" and not all_prereqs_true:
            violations.append("governance_complete_status_without_full_prerequisites")

    blocked = len(violations) > 0
    return {
        "ok": not blocked,
        "blocked": blocked,
        "violations": violations,
        "missing_keys": missing,
        "type_errors": type_errors,
    }


def validate_authority_reference(
    *,
    project_root: Path,
    claimed_authority_file: str,
    claimed_overrides_from: str | None = None,
) -> dict[str, Any]:
    violations: list[str] = []
    valid_authority_files = [str((project_root / rel).resolve()) for rel in CANONICAL_AUTHORITY_FILES]
    claimed_resolved = str((project_root / claimed_authority_file).resolve())

    if claimed_authority_file not in CANONICAL_AUTHORITY_FILES:
        violations.append("non_canonical_authority_reference")
    if not (project_root / claimed_authority_file).exists():
        violations.append("authority_file_missing")
    if claimed_overrides_from and claimed_overrides_from not in PRECEDENCE_ORDER:
        violations.append("unknown_precedence_layer")
    if claimed_overrides_from in {"ai_generated_summaries", "tests_passed_statements"}:
        violations.append("invalid_low_precedence_override")

    blocked = len(violations) > 0
    return {
        "ok": not blocked,
        "blocked": blocked,
        "violations": violations,
        "canonical_authority_files": valid_authority_files,
        "claimed_authority_file": claimed_resolved,
        "precedence_order": list(PRECEDENCE_ORDER),
    }
