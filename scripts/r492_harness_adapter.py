#!/usr/bin/env python3
"""
R49.2 Harness Adapter — Adapter Smoke Only

Boundary:
    This script validates the R49.2 harness CONTRACT SHAPE.
    It does NOT collect real reviewer substitution evidence.
    It does NOT constitute R49.2 evidence collection.

    adapter validates R49.2 harness contract shape, not real reviewer substitution evidence

Purpose:
    Verify that the PS1 runner (run_r492_reviewer_substitution.ps1) correctly
    interprets the harness output schema — specifically:
      - NT-05 path: missing evaluator_confidence → untrusted_evaluator
      - Normal path: evaluator_confidence with harness_self_reported provenance
      - NT-01 path: not tested here (use existing governance_harness.py mismatch)

CLI contract (mirrors what PS1 Invoke-HarnessRun sends):
    --scenario  <scenario_id>
    --seed      <int>
    --reviewer  <owner_name>
    --observe-only
    --case      nt05 | normal  (default: normal)

Exit codes:
    0 = adapter ran, JSON written to stdout
    1 = argument error

Output (stdout, JSON):
    All R49.2 metric fields + optional evaluator_confidence fields.
    Includes adapter_smoke: true marker so downstream cannot mistake
    this output for real governance evidence.

Smoke cases:
    normal  — emits evaluator_confidence + evaluator_confidence_provenance
              → PS1 reads as harness_self_reported → normal interpretation
    nt05    — omits evaluator_confidence field entirely
              → PS1 defaults "medium" with provenance harness_default_NT-05
              → Get-SubstitutionInterpretation returns untrusted_evaluator
"""

from __future__ import annotations

import argparse
import json
import sys

# ---------------------------------------------------------------------------
# Stub metric values
# NOT real measurements — shape-only for contract verification.
# drift_result = "not_measured" because no real harness ran.
# ---------------------------------------------------------------------------
_STUB_METRICS: dict = {
    "claim_discipline_drift": 0.0,
    "unsupported_count": 0,
    "replay_deterministic": True,
    "reviewer_override_frequency": 0,
    "intervention_entropy": 0.35,
    "drift_result": "not_measured",
}

_VALID_CASES = ("normal", "nt05")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="R49.2 Harness Adapter — Adapter Smoke Only"
    )
    parser.add_argument("--scenario", required=True, help="Scenario ID")
    parser.add_argument("--seed", type=int, required=True, help="Seed integer")
    parser.add_argument("--reviewer", required=True, help="Substituted owner name")
    parser.add_argument("--observe-only", action="store_true", help="Observation-only flag")
    parser.add_argument(
        "--case",
        choices=_VALID_CASES,
        default="normal",
        help=(
            "normal: emit evaluator_confidence with harness_self_reported provenance. "
            "nt05: omit evaluator_confidence field (triggers NT-05 / untrusted_evaluator in PS1)."
        ),
    )
    args = parser.parse_args()

    # Base output — always present
    output: dict = {
        # Marker: downstream must not treat this as governance evidence
        "adapter_smoke": True,
        "adapter_case": args.case,
        "scenario_id": args.scenario,
        "seed": args.seed,
        "reviewer": args.reviewer,
        "observe_only": args.observe_only,
        # R49.2 metric schema
        **_STUB_METRICS,
    }

    if args.case == "normal":
        # Harness self-reports confidence — PS1 reads as real provenance.
        # NT-05 guard in PS1 will NOT fire.
        output["evaluator_confidence"] = "low"
        output["evaluator_confidence_provenance"] = "harness_self_reported"

    # case == "nt05":
    #   evaluator_confidence field is absent.
    #   PS1 Invoke-HarnessRun detects $hasOwnConfidence == false,
    #   sets evaluator_confidence = "medium", provenance = "harness_default_NT-05".
    #   Get-SubstitutionInterpretation returns "untrusted_evaluator".

    print(json.dumps(output, ensure_ascii=False))
    sys.exit(0)


if __name__ == "__main__":
    main()
