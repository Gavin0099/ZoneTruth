"""
Phase E / E2 — spec ambiguity validator (minimal executable baseline).

Purpose:
- Detect high-risk ambiguity signals in requirement/spec text.
- Produce machine-readable output for reviewer triage.
- Advisory-first: does not mutate gate decisions directly.
"""

from __future__ import annotations

import re
from typing import Any


AMBIGUOUS_TOKENS = (
    "appropriate",
    "reasonable",
    "as needed",
    "if necessary",
    "etc.",
    "tbd",
    "to be decided",
    "best effort",
)

UNSCOPED_PRONOUNS = (
    "it",
    "this",
    "that",
    "they",
)

ACCEPTANCE_TOKENS = (
    "acceptance criteria",
    "must",
    "shall",
    "pass if",
    "expected output",
    "success condition",
)


def _contains_any(text: str, tokens: tuple[str, ...]) -> bool:
    lowered = text.lower()
    return any(token in lowered for token in tokens)


def _count_regex(text: str, pattern: str) -> int:
    return len(re.findall(pattern, text, flags=re.IGNORECASE))


def evaluate_spec_ambiguity(
    spec_text: str,
    *,
    title: str | None = None,
) -> dict[str, Any]:
    text = (spec_text or "").strip()
    lowered = text.lower()

    ambiguous_token_hits = [token for token in AMBIGUOUS_TOKENS if token in lowered]
    pronoun_hits = sum(_count_regex(lowered, rf"\b{re.escape(token)}\b") for token in UNSCOPED_PRONOUNS)
    has_acceptance_criteria = _contains_any(lowered, ACCEPTANCE_TOKENS)
    has_numeric_constraint = bool(re.search(r"\b\d+(\.\d+)?\b", lowered))
    has_empty_spec = len(text) == 0

    findings: list[str] = []
    severity = "low"

    if has_empty_spec:
        findings.append("empty_spec_text")
        severity = "high"
    if ambiguous_token_hits:
        findings.append("ambiguous_token_present")
        if severity != "high":
            severity = "medium"
    if pronoun_hits >= 4:
        findings.append("high_unspecified_pronoun_density")
        if severity == "low":
            severity = "medium"
    if not has_acceptance_criteria:
        findings.append("missing_acceptance_criteria_signal")
        if severity != "high":
            severity = "medium"

    # Heuristic: strong enough to require reviewer ambiguity triage.
    requires_human_clarification = (
        has_empty_spec
        or len(ambiguous_token_hits) >= 2
        or (not has_acceptance_criteria and not has_numeric_constraint)
    )

    return {
        "ok": not requires_human_clarification,
        "title": title,
        "severity": severity,
        "requires_human_clarification": requires_human_clarification,
        "findings": findings,
        "signals": {
            "ambiguous_token_hits": ambiguous_token_hits,
            "unspecified_pronoun_count": pronoun_hits,
            "has_acceptance_criteria_signal": has_acceptance_criteria,
            "has_numeric_constraint": has_numeric_constraint,
            "empty_spec_text": has_empty_spec,
        },
    }

