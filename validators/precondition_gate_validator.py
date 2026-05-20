"""
Executable pre-task precondition gate validator (minimal v1).

This validator is advisory-first: it emits machine-readable findings and a
recommended mode downgrade. It does not hard-stop by itself.
"""

from __future__ import annotations

import re
from typing import Any


RULE_REFS = {
    "missing_reset_definition": "precondition.reset_definition",
    "missing_interface_or_handshake_definition": "precondition.interface_handshake_definition",
}


def _contains_any(text: str, tokens: tuple[str, ...]) -> bool:
    lowered = text.lower()
    return any(token in lowered for token in tokens)


def _matches_any_regex(text: str, patterns: tuple[str, ...]) -> bool:
    return any(re.search(pattern, text, flags=re.IGNORECASE) for pattern in patterns)


def _structured_flag(structured_fields: dict[str, Any] | None, *keys: str) -> bool:
    if not structured_fields:
        return False
    for key in keys:
        val = structured_fields.get(key)
        if isinstance(val, bool):
            if val:
                return True
        elif isinstance(val, str):
            if val.strip():
                return True
        elif val is not None:
            return True
    return False


def evaluate_precondition_gate(
    task_text: str,
    *,
    structured_fields: dict[str, Any] | None = None,
) -> dict[str, Any]:
    lowered = (task_text or "").lower()

    wants_synthesizable_rtl = _contains_any(
        lowered,
        (
            "verilog",
            "systemverilog",
            "synthesizable",
            "rtl",
            "always_ff",
            "always_comb",
            "module ",
            "state machine",
            "fsm",
            "codegen",
            "generate rtl",
        ),
    )
    wants_control_interface_logic = _contains_any(
        lowered,
        (
            "handshake",
            "ready/valid",
            "valid/ready",
            "req/ack",
            "req ack",
            "backpressure",
            "latency",
            "throughput",
            "interface",
            "bus protocol",
            "arbiter",
        ),
    )

    reset_positive_patterns = (
        r"\b(rst_n|rst)\b",
        r"\b(active[- ]low|active[- ]high)\s+reset\b",
        r"\b(synchronous|asynchronous)\s+reset\b",
        r"\breset\s+polarity\b",
        r"\breset\s+(?:is\s+)?(?:defined|specified)\b",
        r"\bwith\s+(?:an?\s+)?reset\b",
    )
    reset_negative_patterns = (
        r"\bno\s+reset(?:\s+(?:definition|signal|polarity|type|behavior|handling))?(?:\s+is)?\s+(?:defined|specified|provided)\b",
        r"\bwithout\s+reset(?:\s+(?:definition|signal|polarity|type|behavior|handling))?\b",
        r"\bmissing\s+reset(?:\s+(?:definition|signal|polarity|type|behavior|handling))?\b",
        r"\breset\s+(?:is\s+)?not\s+(?:defined|specified|provided)\b",
        r"\breset\s+(?:definition|signal|polarity|type|behavior|handling)\s+(?:is\s+)?(?:missing|undefined|absent|not\s+specified)\b",
    )

    handshake_positive_patterns = (
        r"\bready\s*/\s*valid\b",
        r"\bvalid\s*/\s*ready\b",
        r"\breq\s*/\s*ack\b",
        r"\bhandshake\s+(?:is\s+)?(?:defined|specified)\b",
        r"\bbackpressure\b",
        r"\blatency\b",
    )
    handshake_negative_patterns = (
        r"\bno\s+(?:ready\s*/\s*valid|valid\s*/\s*ready|req\s*/\s*ack|handshake|backpressure)\b",
        r"\bwithout\s+(?:ready\s*/\s*valid|valid\s*/\s*ready|req\s*/\s*ack|handshake|backpressure)\b",
        r"\bmissing\s+(?:ready\s*/\s*valid|valid\s*/\s*ready|req\s*/\s*ack|handshake|backpressure)\b",
        r"\b(?:handshake|backpressure|latency)\s+(?:(?:is|are)\s+)?not\s+(?:defined|specified|provided)\b",
        r"\b(?:handshake|backpressure|latency|protocol\s+timing|protocol\s+timing\s*/\s*backpressure)\s+"
        r"(?:definition|definitions|behavior|behaviors|semantics|details)?\s*"
        r"(?:(?:is|are)\s+)?(?:missing|undefined|absent|not\s+specified|not\s+provided)\b",
        r"\bno\s+protocol\s+timing(?:\s*/\s*backpressure)?\b",
    )

    reset_structured = _structured_flag(
        structured_fields,
        "reset_polarity",
        "reset_type",
        "reset_signal",
        "has_reset_definition",
    )
    handshake_structured = _structured_flag(
        structured_fields,
        "handshake_type",
        "latency_budget",
        "backpressure_behavior",
        "interface_protocol",
        "has_handshake_definition",
    )

    reset_positive = _matches_any_regex(lowered, reset_positive_patterns)
    reset_negative = _matches_any_regex(lowered, reset_negative_patterns)
    handshake_positive = _matches_any_regex(lowered, handshake_positive_patterns)
    handshake_negative = _matches_any_regex(lowered, handshake_negative_patterns)

    reset_defined = reset_structured or (reset_positive and not reset_negative)
    handshake_defined = handshake_structured or (handshake_positive and not handshake_negative)

    missing_preconditions: list[str] = []
    forbidden_claims: list[str] = []
    rule_refs: list[str] = []

    if wants_synthesizable_rtl and not reset_defined:
        missing_preconditions.append("missing_reset_definition")
        forbidden_claims.append("claim_reset_safe_codegen")
        rule_refs.append(RULE_REFS["missing_reset_definition"])

    if wants_control_interface_logic and not handshake_defined:
        missing_preconditions.append("missing_interface_or_handshake_definition")
        forbidden_claims.append("claim_interface_correctness_codegen")
        rule_refs.append(RULE_REFS["missing_interface_or_handshake_definition"])

    if "missing_interface_or_handshake_definition" in missing_preconditions:
        recommended_mode = "allow_analysis_only"
    elif "missing_reset_definition" in missing_preconditions:
        recommended_mode = "allow_draft_with_assumptions"
    elif wants_synthesizable_rtl:
        recommended_mode = "allow_draft_with_assumptions"
    else:
        recommended_mode = "allow_analysis_only"

    # Combined missing preconditions on a codegen intent should restrict output surface.
    if len(missing_preconditions) >= 2 and wants_synthesizable_rtl:
        recommended_mode = "restrict_codegen"

    return {
        "ok": len(missing_preconditions) == 0,
        "missing_preconditions": missing_preconditions,
        "recommended_mode": recommended_mode,
        "forbidden_claims": forbidden_claims,
        "rule_refs": rule_refs,
        "signals": {
            "wants_synthesizable_rtl": wants_synthesizable_rtl,
            "wants_control_interface_logic": wants_control_interface_logic,
            "has_reset_definition": reset_defined,
            "has_handshake_definition": handshake_defined,
            "reset_negative_detected": reset_negative,
            "handshake_negative_detected": handshake_negative,
        },
    }
