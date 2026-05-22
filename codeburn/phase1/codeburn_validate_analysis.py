#!/usr/bin/env python3
"""
CodeBurn Phase 1 — Analysis Contract Enforcement (M7)

Validates that codeburn_analyze output conforms to CODEBURN_PHASE1_ANALYSIS_CONTRACT.md.
Fail-closed: any violation causes exit 1.

Checks:
  (A) boundary_structure  — analysis_boundary.claims=False, analysis_type=observation,
                            observability_limits declared
  (B) forbidden_phrases   — rendered text output must not contain waste/efficiency claims
  (C) traceability        — retry signals must include derived_from_steps
"""
from __future__ import annotations

import argparse
import contextlib
import io
import json
from pathlib import Path

# Phrases that indicate an efficiency/waste judgment — forbidden in Phase 1 analysis.
# Only literal phrase matches are checked (case-insensitive, substring).
# False-positive risk is low because these phrases are not part of any boundary footer text.
_FORBIDDEN_PHRASES = (
    "waste",
    "inefficient",
    "unnecessary",
    "should optimize",
    "should reduce",
)

# Signals that must carry derived_from_steps traceability.
_TRACED_SIGNALS = frozenset({"retry_pattern_detected", "retry_pattern_inferred"})


def _check_boundary_structure(analysis: dict, violations: list[str]) -> None:
    """(A) Verify analysis_boundary, observability_limits, and misinterpretation guard."""
    boundary = analysis.get("analysis_boundary")
    if not isinstance(boundary, dict):
        violations.append("boundary_structure_missing")
        return
    if boundary.get("claims") is not False:
        violations.append("boundary_claims_not_false")
    if boundary.get("analysis_type") != "observation":
        violations.append("boundary_type_not_observation")
    if boundary.get("interpretation_level") != "low":
        violations.append("boundary_interpretation_level_not_low")

    obs = analysis.get("observability_limits")
    if not isinstance(obs, dict):
        violations.append("observability_limits_missing")
        return
    _VALID_TOKEN_USAGE_LEVELS = {"none", "coarse", "step_level", "unknown"}
    if obs.get("token_usage") not in _VALID_TOKEN_USAGE_LEVELS:
        violations.append("observability_token_usage_not_unknown")
    if obs.get("file_reads") != "unsupported":
        violations.append("observability_file_reads_not_unsupported")
    if obs.get("file_activity") != "git-visible only":
        violations.append("observability_file_activity_not_git_visible_only")

    # M8: misinterpretation guard — must be present and explicitly False
    safe_flag = analysis.get("analysis_safe_for_decision")
    if safe_flag is True:
        violations.append("phase1_invariant_violation:analysis_safe_for_decision_true")
    elif safe_flag is not False:
        violations.append("missing_analysis_safe_for_decision_false")

    # M9: system-level decision guard — must be present and explicitly False
    if analysis.get("decision_usage_allowed") is not False:
        violations.append("missing_decision_usage_allowed_false")


def _check_forbidden_phrases(analysis: dict, violations: list[str]) -> None:
    """(B) Scan rendered text output for forbidden efficiency/waste claims."""
    # Import here to allow this module to be used without codeburn_analyze on sys.path
    # in test contexts; the import will fail loudly if the module is missing.
    from codeburn.phase1.codeburn_analyze import print_analysis_text  # noqa: PLC0415

    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        print_analysis_text(analysis)
    rendered = buf.getvalue().lower()

    for phrase in _FORBIDDEN_PHRASES:
        if phrase in rendered:
            violations.append(f"forbidden_phrase:{phrase}")


def _check_traceability(analysis: dict, violations: list[str]) -> None:
    """(C) Retry signals must carry non-empty derived_from_steps."""
    for sig in analysis.get("signals", []):
        if sig.get("signal") in _TRACED_SIGNALS:
            steps = sig.get("derived_from_steps")
            if not steps:
                violations.append(f"missing_traceability:{sig['signal']}")


def validate_analysis(db_path: Path, session_id: str = "latest") -> dict:
    """
    Run all three contract enforcement checks against the analysis output
    for the given session.

    Returns:
        {
          "ok": bool,
          "session_id": str | None,
          "violation_count": int,
          "violations": [str, ...],
          "checks": {"boundary_structure": "pass|fail", "forbidden_phrases": "pass|fail", "traceability": "pass|fail"}
        }
    """
    from codeburn.phase1.codeburn_analyze import build_analysis  # noqa: PLC0415

    analysis = build_analysis(db_path, session_id)
    if not analysis.get("ok"):
        return {
            "ok": False,
            "session_id": None,
            "violation_count": 1,
            "violations": ["session_not_found"],
            "checks": {
                "boundary_structure": "skip",
                "forbidden_phrases": "skip",
                "traceability": "skip",
            },
        }

    resolved_id = analysis.get("session_id")
    violations: list[str] = []
    check_results: dict[str, list[str]] = {
        "boundary_structure": [],
        "forbidden_phrases": [],
        "traceability": [],
    }

    _check_boundary_structure(analysis, check_results["boundary_structure"])
    _check_forbidden_phrases(analysis, check_results["forbidden_phrases"])
    _check_traceability(analysis, check_results["traceability"])

    for check_violations in check_results.values():
        violations.extend(check_violations)

    return {
        "ok": len(violations) == 0,
        "session_id": resolved_id,
        "violation_count": len(violations),
        "violations": violations,
        "checks": {
            name: ("fail" if vlist else "pass")
            for name, vlist in check_results.items()
        },
    }


def main() -> int:
    from codeburn_phase1_header import print_phase1_header  # noqa: PLC0415
    print_phase1_header()
    parser = argparse.ArgumentParser(
        description="CodeBurn Phase 1 analysis contract enforcement (M7)."
    )
    parser.add_argument("--db", required=True, help="Path to CodeBurn DB")
    parser.add_argument(
        "--session", default="latest", help="Session ID or 'latest' (default)"
    )
    args = parser.parse_args()

    result = validate_analysis(Path(args.db).resolve(), args.session)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
