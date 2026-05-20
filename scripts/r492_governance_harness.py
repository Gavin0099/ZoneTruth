#!/usr/bin/env python3
"""
R49.2 Governance Harness v0.1 — Deterministic Reviewer Profile Substitution

Harness interpretation: A — deterministic governance reviewer profiles
Boundary: reviewer = deterministic governance lens (not human, not LLM)
          LLM reviewer substitution is explicitly deferred.

CLI:
    --scenario    <SCN-RUNTIME | SCN-AUDIT | SCN-PRODUCT>
    --seed        <350101 | 350102 | 350103>
    --reviewer    <runtime | audit | product>   (substituted reviewer)
    --observe-only                               (required flag)
    --output      <path>                         (optional; default: stdout)

Output: JSON with 5 R49.2 metrics + evaluator provenance.
        Harness does NOT interpret results — interpretation is PS1's responsibility.
        Harness self-reports evaluator_confidence (SA-04 requirement).

MIP-04 note:
    reviewer_override_frequency requires a per-claim event log.
    v0.1 does not produce an event log.
    Output includes event_log_absent: true and event_log_absent_null_type: NT-06.
    This field MUST be checked before using reviewer_override_frequency in any claim.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Violation code registry
# ---------------------------------------------------------------------------

# Each profile detects violations within its own scope.
_RUNTIME_SCOPE = frozenset(["V-RT-01", "V-RT-02", "V-RT-03", "V-RT-04"])
_AUDIT_SCOPE = frozenset(["V-AU-01", "V-AU-02", "V-AU-03", "V-AU-04"])
_PRODUCT_SCOPE = frozenset(["V-PR-01", "V-PR-02", "V-PR-04"])
# V-PR-03 (ambiguous boundary) → NT-03 semantic null, not counted as violation

_PROFILE_SCOPE: dict[str, frozenset] = {
    "runtime_reviewer_profile": _RUNTIME_SCOPE,
    "audit_reviewer_profile":   _AUDIT_SCOPE,
    "product_reviewer_profile": _PRODUCT_SCOPE,
}

# The "unsupported" violation code per profile — used for unsupported_count
_PROFILE_UNSUPPORTED_CODE: dict[str, str] = {
    "runtime_reviewer_profile": "V-RT-04",   # non-observable state claim
    "audit_reviewer_profile":   "V-AU-01",   # claim without evidence_refs
    "product_reviewer_profile": "V-PR-02",   # unaddressed required property
}

# Short-name → full profile ID (PS1 dataset uses short names)
_PROFILE_ALIASES: dict[str, str] = {
    "runtime":                  "runtime_reviewer_profile",
    "audit":                    "audit_reviewer_profile",
    "product":                  "product_reviewer_profile",
    "runtime_reviewer_profile": "runtime_reviewer_profile",
    "audit_reviewer_profile":   "audit_reviewer_profile",
    "product_reviewer_profile": "product_reviewer_profile",
}

# Original owner per scenario (used to derive baseline for claim_discipline_drift)
_SCENARIO_ORIGINAL_OWNER: dict[str, str] = {
    "SCN-RUNTIME": "runtime_reviewer_profile",
    "SCN-AUDIT":   "audit_reviewer_profile",
    "SCN-PRODUCT": "product_reviewer_profile",
}

# ---------------------------------------------------------------------------
# Scenario claim definitions
# Each claim is a dict: {claim_id: str, violations: frozenset[str]}
# Different seeds select different claim sets for reproducibility testing.
# Claim sets encode which violation codes are present in each claim.
# A reviewer profile only detects violations within its own scope.
# ---------------------------------------------------------------------------

def _c(claim_id: str, *violations: str) -> dict:
    return {"claim_id": claim_id, "violations": frozenset(violations)}


_SCENARIOS: dict[str, dict[int, list[dict]]] = {
    # SCN-RUNTIME: home scenario for runtime_reviewer_profile
    # Claims surface: authority boundary (V-RT-01/02/03/04)
    # Cross-profile: audit lens finds evidence gaps; product lens finds scope issues
    "SCN-RUNTIME": {
        350101: [
            _c("RT-001", "V-RT-01"),           # authority exceeded
            _c("RT-002", "V-RT-02"),           # callback contract broken
            _c("RT-003", "V-RT-03"),           # state mutation outside context
            _c("RT-004", "V-RT-04"),           # non-observable state claim
            _c("RT-005", "V-AU-01"),           # runtime doc references no evidence
            _c("RT-006", "V-AU-03"),           # high confidence without evidence
            _c("RT-007"),                       # clean claim
            _c("RT-008"),                       # clean claim
        ],
        350102: [
            _c("RT-001", "V-RT-01"),
            _c("RT-002", "V-RT-03"),
            _c("RT-003", "V-AU-01"),
            _c("RT-004", "V-PR-01"),
            _c("RT-005"),
            _c("RT-006"),
        ],
        350103: [
            _c("RT-001", "V-RT-01"),
            _c("RT-002", "V-RT-02"),
            _c("RT-003", "V-RT-03"),
            _c("RT-004", "V-RT-04"),
            _c("RT-005", "V-AU-01"),
            _c("RT-006", "V-AU-01"),
            _c("RT-007", "V-AU-03"),
            _c("RT-008", "V-PR-01"),
            _c("RT-009", "V-PR-04"),
            _c("RT-010"),
        ],
    },
    # SCN-AUDIT: home scenario for audit_reviewer_profile
    # Claims surface: evidence lineage (V-AU-01/02/03/04)
    # Cross-profile: runtime lens finds authority issues; product lens finds scope issues
    "SCN-AUDIT": {
        350101: [
            _c("AU-001", "V-AU-01"),           # no evidence reference
            _c("AU-002", "V-AU-01"),           # no evidence reference
            _c("AU-003", "V-AU-03"),           # confidence overreach
            _c("AU-004", "V-AU-04"),           # missing provenance
            _c("AU-005", "V-RT-04"),           # runtime scope issue surfacing in audit
            _c("AU-006", "V-RT-02"),           # callback issue surfacing in audit doc
            _c("AU-007", "V-PR-01"),           # out-of-scope claim in audit doc
            _c("AU-008"),                       # clean
        ],
        350102: [
            _c("AU-001", "V-AU-01"),
            _c("AU-002", "V-AU-03"),
            _c("AU-003", "V-AU-01"),
            _c("AU-004", "V-RT-04"),
            _c("AU-005", "V-PR-02"),
            _c("AU-006"),
        ],
        350103: [
            _c("AU-001", "V-AU-01"),
            _c("AU-002", "V-AU-01"),
            _c("AU-003", "V-AU-02"),
            _c("AU-004", "V-AU-03"),
            _c("AU-005", "V-AU-04"),
            _c("AU-006", "V-RT-01"),
            _c("AU-007", "V-RT-04"),
            _c("AU-008", "V-PR-01"),
            _c("AU-009", "V-PR-04"),
            _c("AU-010"),
        ],
    },
    # SCN-PRODUCT: home scenario for product_reviewer_profile
    # Claims surface: scope containment (V-PR-01/02/04)
    # Cross-profile: audit lens finds evidence gaps; runtime lens finds authority issues
    "SCN-PRODUCT": {
        350101: [
            _c("PR-001", "V-PR-01"),           # out of scope
            _c("PR-002", "V-PR-02"),           # unaddressed required property
            _c("PR-003", "V-PR-04"),           # implicit scope expansion
            _c("PR-004", "V-AU-01"),           # no evidence in product claim
            _c("PR-005", "V-AU-03"),           # confidence overreach in product claim
            _c("PR-006", "V-RT-04"),           # non-observable state claim in product doc
            _c("PR-007"),                       # clean
            _c("PR-008"),                       # clean
        ],
        350102: [
            _c("PR-001", "V-PR-01"),
            _c("PR-002", "V-PR-01"),
            _c("PR-003", "V-PR-02"),
            _c("PR-004", "V-AU-01"),
            _c("PR-005", "V-RT-03"),
            _c("PR-006"),
            _c("PR-007"),
        ],
        350103: [
            _c("PR-001", "V-PR-01"),
            _c("PR-002", "V-PR-01"),
            _c("PR-003", "V-PR-02"),
            _c("PR-004", "V-PR-04"),
            _c("PR-005", "V-PR-04"),
            _c("PR-006", "V-AU-01"),
            _c("PR-007", "V-AU-03"),
            _c("PR-008", "V-RT-04"),
            _c("PR-009"),
            _c("PR-010"),
        ],
    },
}

# ---------------------------------------------------------------------------
# Metric computation
# ---------------------------------------------------------------------------

def _detect(claims: list[dict], profile_id: str) -> frozenset[str]:
    """Return claim_ids flagged by this profile."""
    scope = _PROFILE_SCOPE[profile_id]
    return frozenset(c["claim_id"] for c in claims if c["violations"] & scope)


def _compute_metrics(
    claims: list[dict],
    original_profile: str,
    substituted_profile: str,
) -> dict:
    total = len(claims)

    if total == 0:
        return {
            "claim_discipline_drift": None,
            "unsupported_count": None,
            "replay_deterministic": None,
            "reviewer_override_frequency": None,
            "intervention_entropy": None,
            "drift_result": "not_measured",
            "null_type_claim_discipline_drift": "NT-02",
            "null_type_unsupported_count": "NT-02",
            "null_type_replay_deterministic": "NT-02",
            "null_type_intervention_entropy": "NT-02",
            "event_log_absent": True,
            "event_log_absent_null_type": "NT-06",
        }

    original_flagged = _detect(claims, original_profile)
    subst_flagged = _detect(claims, substituted_profile)

    # claim_discipline_drift: abs delta in detection rate
    # [0.0, 1.0]: 0.0 = identical rate; higher = more divergence
    # NOTE: same rate does not mean same violations (forbidden_interpretation applies)
    original_rate = len(original_flagged) / total
    subst_rate = len(subst_flagged) / total
    claim_discipline_drift = round(abs(original_rate - subst_rate), 4)

    # unsupported_count: violations under substituted profile's "unsupported" code
    unsupported_code = _PROFILE_UNSUPPORTED_CODE[substituted_profile]
    subst_scope = _PROFILE_SCOPE[substituted_profile]
    unsupported_count = sum(
        1 for c in claims
        if unsupported_code in c["violations"] and bool(c["violations"] & subst_scope)
    )

    # replay_deterministic: guaranteed True by deterministic design (v0.1)
    # No stochastic elements — same inputs always produce same outputs.
    # MIP-03 requires cross-seed verification from actual runs before this can be claimed
    # as "evidence of reproducibility" rather than "design guarantee".
    replay_deterministic = True

    # reviewer_override_frequency: requires per-claim event log
    # v0.1 does not produce an event log — MIP-04 not yet satisfied.
    # Tag event_log_absent: true so downstream cannot use this metric for causal claims.
    reviewer_override_frequency = None

    # intervention_entropy: Shannon entropy of violation type distribution
    # under substituted reviewer profile.
    # NT-02 if fewer than 2 distinct intervention points (entropy undefined on empty/singleton set).
    violation_type_counts: dict[str, int] = {}
    for c in claims:
        for v in c["violations"] & subst_scope:
            violation_type_counts[v] = violation_type_counts.get(v, 0) + 1

    total_interventions = sum(violation_type_counts.values())

    if total_interventions < 2:
        intervention_entropy = None
        entropy_null_type = "NT-02"
    else:
        h = 0.0
        for count in violation_type_counts.values():
            p = count / total_interventions
            h -= p * math.log2(p)
        intervention_entropy = round(h, 4)
        entropy_null_type = None

    result: dict = {
        "claim_discipline_drift": claim_discipline_drift,
        "unsupported_count": unsupported_count,
        "replay_deterministic": replay_deterministic,
        "reviewer_override_frequency": reviewer_override_frequency,
        "intervention_entropy": intervention_entropy,
        "drift_result": "measured",
        "event_log_absent": True,
        "event_log_absent_null_type": "NT-06",
    }
    if entropy_null_type:
        result["null_type_intervention_entropy"] = entropy_null_type

    return result

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="R49.2 Governance Harness — Deterministic Reviewer Profile Substitution"
    )
    parser.add_argument("--scenario", required=True)
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--reviewer", required=True, help="Substituted reviewer (short: runtime|audit|product)")
    parser.add_argument("--observe-only", action="store_true")
    parser.add_argument("--output", help="Output file path (default: stdout)")
    args = parser.parse_args()

    # Resolve profile IDs (accept short names from PS1 dataset)
    substituted_profile = _PROFILE_ALIASES.get(args.reviewer)
    if substituted_profile is None:
        print(json.dumps({"error": f"Unknown reviewer profile: {args.reviewer}"}), file=sys.stderr)
        sys.exit(1)

    # Validate scenario
    if args.scenario not in _SCENARIOS:
        print(json.dumps({"error": f"Unknown scenario: {args.scenario}"}), file=sys.stderr)
        sys.exit(1)

    # Validate seed
    if args.seed not in _SCENARIOS[args.scenario]:
        print(json.dumps({"error": f"Unknown seed {args.seed} for {args.scenario}"}), file=sys.stderr)
        sys.exit(1)

    # Derive original owner from scenario (do not require as CLI arg to keep PS1 interface stable)
    original_profile = _SCENARIO_ORIGINAL_OWNER[args.scenario]

    claims = _SCENARIOS[args.scenario][args.seed]
    metrics = _compute_metrics(claims, original_profile, substituted_profile)

    # Build output: flat metric schema + provenance (as PS1 Invoke-HarnessRun expects)
    _METRIC_KEYS = {
        "claim_discipline_drift", "unsupported_count", "replay_deterministic",
        "reviewer_override_frequency", "intervention_entropy", "drift_result",
    }
    output: dict = {
        "adapter_smoke": False,
        "harness_version": "r492-v0.1",
        "harness_interpretation": "A_deterministic_reviewer_profile_substitution",
        "scenario_id": args.scenario,
        "seed": args.seed,
        "original_reviewer": original_profile,
        "substituted_reviewer": substituted_profile,
        "observe_only": args.observe_only,
        # R49.2 metrics (flat — PS1 reads these directly)
        **{k: v for k, v in metrics.items() if k in _METRIC_KEYS},
        # MIP-04 event log provenance marker
        "event_log_absent": metrics["event_log_absent"],
        "event_log_absent_null_type": metrics["event_log_absent_null_type"],
        # Metric-level null type annotations
        **{k: v for k, v in metrics.items() if k.startswith("null_type_")},
        # SA-04: evaluator self-reports confidence and provenance
        "evaluator_confidence": "medium",
        "evaluator_confidence_provenance": "harness_self_reported",
    }

    json_str = json.dumps(output, indent=2, ensure_ascii=False)

    if args.output:
        Path(args.output).write_text(json_str, encoding="utf-8")
        print(f"[R49.2 harness] output → {args.output}", file=sys.stderr)
    else:
        print(json_str)

    sys.exit(0)


if __name__ == "__main__":
    main()
