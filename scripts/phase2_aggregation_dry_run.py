#!/usr/bin/env python3
"""Machine-like dry run for Phase 2 canonical aggregation scenarios (Case A-D)."""

from __future__ import annotations

import json
import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[1]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from governance_tools.phase2_aggregation_consumer import (
    CANONICAL_CURRENT_STATES,
    WindowSpec,
    aggregate_phase2_state,
)


def _run_case_matrix() -> list[dict]:
    cases: list[tuple[str, dict, str, bool]] = [
        (
            "Case A",
            dict(
                sample_statuses=["not_tested", "not_tested", "not_tested"],
                window=WindowSpec(runs=3, sessions=2),
                historical_observed=False,
            ),
            "insufficient_observation",
            False,
        ),
        (
            "Case B",
            dict(
                sample_statuses=["not_observed_in_window", "not_observed_in_window", "not_observed_in_window"],
                window=WindowSpec(runs=3, sessions=2),
                historical_observed=True,
                remediation_introduced=True,
                covers_original_misuse_path=True,
            ),
            "risk_not_reobserved_yet",
            False,
        ),
        (
            "Case C",
            dict(
                sample_statuses=["not_observed_in_window", "not_observed_in_window"],
                window=WindowSpec(runs=1, sessions=1),
                historical_observed=False,
            ),
            "insufficient_observation",
            False,
        ),
        (
            "Case D",
            dict(
                sample_statuses=["not_observed_in_window", "not_observed_in_window", "not_observed_in_window"],
                window=WindowSpec(runs=3, sessions=2),
                historical_observed=True,
                remediation_introduced=True,
                covers_original_misuse_path=True,
                closure_approval={
                    "approved": True,
                    "reviewer_id": "reviewer-01",
                    "reviewer_role": "human_reviewer",
                    "review_note": "closure verified for promotion entry",
                    "evidence_refs": ["artifacts/phase2/window-2026-04-16.json"],
                },
            ),
            "closure_verified",
            True,
        ),
    ]

    results: list[dict] = []
    for name, payload, expected_state, expected_promote in cases:
        out = aggregate_phase2_state(**payload)
        out["case"] = name
        out["expected_state"] = expected_state
        out["expected_promote"] = expected_promote
        out["state_match"] = out["current_state"] == expected_state
        out["promote_match"] = out["promote_eligible"] == expected_promote
        out["canonical_state"] = out["current_state"] in CANONICAL_CURRENT_STATES
        results.append(out)
    return results


def main() -> int:
    results = _run_case_matrix()
    ok = all(
        r["state_match"] and r["promote_match"] and r["canonical_state"]
        for r in results
    )
    payload = {"ok": ok, "cases": results}
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
