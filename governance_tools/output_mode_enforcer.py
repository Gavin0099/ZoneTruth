#!/usr/bin/env python3
"""
Output mode enforcer.

enforce_output_mode(record, requested_mode) is the first operational choke point
for claim ceiling enforcement under the Closeout Governance Admissibility Layering
Contract (docs/status/closeout-governance-layering-contract-2026-05-16.md).

Trust boundary:
  - record is untrusted input; all fields default safely.
  - This module never performs IO. It is a pure function: same inputs → same output.
  - Callers are responsible for assembling the record from canonical artifacts.

Mode hierarchy (ascending admissibility):
  transparency_observed
  closeout_recorded
  procedural_compliance_observed
  bounded_integrity_discipline
  causal_inference
  governance_adequate

governance_effective: permanently prohibited. No record state authorizes it.

Admissibility record schema (all fields optional; missing fields default to
the most conservative interpretation):

  {
    "admissibility_state": {
      "existence": bool,               # closeout artifact exists
      "eligibility_evaluated": bool,   # memory eligibility was checked
      "compliance_present": bool,      # required artifacts present
      "semantics_reviewed": bool,      # semantic review performed
    },
    "downgrade": {
      "applied": bool,                 # a downgrade was recorded
      "consequence_tier": int,         # 0, 1, or 2 (Consequence Materiality Guard)
      "dependent_path_type": str,      # Dependent Path Taxonomy (see below)
    },
    "causal_chain": {
      "present": bool,                 # causal chain evidence exists
      "cross_layer": bool,             # chain spans multiple layers (for governance_adequate)
    },
  }

Dependent Path Taxonomy (v0.1):
  Controls whether a Tier-2 downgrade constitutes structural governance.

  "informational"  — downstream can see the downgrade but is not required to act
                     differently. Visibility alone. Tier 2 treated as Tier 1.
  "procedural"     — downstream must take an additional step before proceeding.
                     Execution path is materially altered. Tier 2 honored.
  "blocking"       — the downstream path is unavailable until the downgrade is
                     explicitly resolved or accepted. Tier 2 honored.

  Missing or unrecognized dependent_path_type defaults to "informational"
  (conservative). "git diff visible" is informational — it does not make the
  constraint structural.

  Contract rule: N × Tier-1 != Tier-2. Tier 2 requires a dependent_path_type
  of "procedural" or "blocking". Without it, Tier 2 is reclassified as Tier 1.
"""

from __future__ import annotations

from typing import Any

# ──────────────────────────────────────────────────────────────────────────────
# Mode vocabulary
# ──────────────────────────────────────────────────────────────────────────────

_MODE_ORDER: list[str] = [
    "transparency_observed",
    "closeout_recorded",
    "procedural_compliance_observed",
    "bounded_integrity_discipline",
    "causal_inference",
    "governance_adequate",
]

_MODE_RANK: dict[str, int] = {m: i for i, m in enumerate(_MODE_ORDER)}

# Modes that are never admissible regardless of record state.
_PROHIBITED_MODES: frozenset[str] = frozenset({"governance_effective"})

# Dependent path types that constitute a structural constraint (Tier 2 admissible).
# "informational" is excluded: visibility != dependency.
_TIER2_ADMISSIBLE_PATH_TYPES: frozenset[str] = frozenset({"procedural", "blocking"})


# ──────────────────────────────────────────────────────────────────────────────
# Public API
# ──────────────────────────────────────────────────────────────────────────────

def enforce_output_mode(
    record: dict[str, Any],
    requested_mode: str,
) -> dict[str, Any]:
    """
    Evaluate whether requested_mode is admissible given record's admissibility state.

    Returns a dict:
      requested_mode: str      — echoed from input
      allowed: bool            — True if requested_mode is within the ceiling
      actual_mode: str         — the mode that IS allowed (may be degraded)
      ceiling: str             — maximum admissible mode computed from record
      enforcement_action: str  — "allow" | "degrade" | "block"
      reason: str              — human-readable causal basis for the decision
    """
    if requested_mode in _PROHIBITED_MODES:
        return _make_result(
            requested_mode=requested_mode,
            allowed=False,
            actual_mode="governance_adequate",
            ceiling="governance_adequate",
            enforcement_action="block",
            reason=(
                f"{requested_mode!r} is permanently prohibited; "
                "no record state can authorize it "
                "(governance_effective is outside the admissible hierarchy)"
            ),
        )

    if requested_mode not in _MODE_RANK:
        return _make_result(
            requested_mode=requested_mode,
            allowed=False,
            actual_mode="transparency_observed",
            ceiling="transparency_observed",
            enforcement_action="block",
            reason=(
                f"unknown mode {requested_mode!r}; "
                f"must be one of: {', '.join(_MODE_ORDER)}"
            ),
        )

    ceiling = _compute_ceiling(record)
    ceiling_rank = _MODE_RANK[ceiling]
    requested_rank = _MODE_RANK[requested_mode]

    if requested_rank <= ceiling_rank:
        return _make_result(
            requested_mode=requested_mode,
            allowed=True,
            actual_mode=requested_mode,
            ceiling=ceiling,
            enforcement_action="allow",
            reason=f"{requested_mode!r} is within ceiling {ceiling!r}",
        )

    return _make_result(
        requested_mode=requested_mode,
        allowed=False,
        actual_mode=ceiling,
        ceiling=ceiling,
        enforcement_action="degrade",
        reason=_degradation_reason(record, requested_mode, ceiling),
    )


# ──────────────────────────────────────────────────────────────────────────────
# Ceiling computation
# ──────────────────────────────────────────────────────────────────────────────

def _compute_ceiling(record: dict[str, Any]) -> str:
    """
    Compute the maximum admissible mode from the record's admissibility state.

    Applies the Layering Table, Negative Admissibility Rules, Consequence
    Materiality Guard, and Compositional Integrity Guard from the contract.
    """
    state = record.get("admissibility_state") or {}
    downgrade = record.get("downgrade") or {}
    causal = record.get("causal_chain") or {}

    # ── Layer 1: Existence ────────────────────────────────────────────────────
    if not state.get("existence"):
        return "transparency_observed"

    # ── Layers 2 + 3: Eligibility + Compliance ───────────────────────────────
    if not state.get("eligibility_evaluated") or not state.get("compliance_present"):
        return "closeout_recorded"

    # ── Layer 4: Semantics ────────────────────────────────────────────────────
    # All 4 layers required before advancing past procedural.
    if not state.get("semantics_reviewed"):
        return "procedural_compliance_observed"

    # ── Consequence Materiality Guard ─────────────────────────────────────────
    downgrade_applied = bool(downgrade.get("applied"))
    consequence_tier = _safe_tier(downgrade.get("consequence_tier"))

    if downgrade_applied:
        if consequence_tier == 0:
            # Tier 0 (cosmetic) = downgrade not consumed.
            # Contract rule: reclassify as "retained but unconsumed".
            # Cap returns to procedural — same as no-downgrade base.
            return "procedural_compliance_observed"
        # Tier 1+: downgrade is consumed; advance to bounded_integrity_discipline
        # at minimum.  Tier 2 additionally requires a structural dependent path.
        # Dependent Path Taxonomy: only "procedural" or "blocking" qualify.
        # "informational" (visibility only) does not constitute constraint.
        if consequence_tier >= 2:
            path_type = str(downgrade.get("dependent_path_type") or "informational").lower()
            if path_type not in _TIER2_ADMISSIBLE_PATH_TYPES:
                # Not structural → treat as Tier 1.
                consequence_tier = 1

    # ── Causal chain evidence ─────────────────────────────────────────────────
    causal_present = bool(causal.get("present"))
    cross_layer = bool(causal.get("cross_layer"))

    # Determine ceiling from (downgrade consumed, causal chain) combination.
    if downgrade_applied and consequence_tier >= 1:
        # Negative evidence properly consumed.
        if causal_present and cross_layer:
            return "governance_adequate"
        if causal_present:
            return "causal_inference"
        return "bounded_integrity_discipline"

    # No downgrade (no negative evidence, or not recorded).
    # Ceiling is driven by causal chain alone.
    if causal_present and cross_layer:
        return "governance_adequate"
    if causal_present:
        return "causal_inference"
    return "procedural_compliance_observed"


def _safe_tier(raw: Any) -> int:
    """Coerce consequence_tier to 0, 1, or 2; any invalid value → 0."""
    try:
        val = int(raw)
    except (TypeError, ValueError):
        return 0
    return max(0, min(2, val))


# ──────────────────────────────────────────────────────────────────────────────
# Degradation reason builder
# ──────────────────────────────────────────────────────────────────────────────

def _degradation_reason(
    record: dict[str, Any],
    requested_mode: str,
    ceiling: str,
) -> str:
    """
    Return a causal explanation for why requested_mode was degraded to ceiling.
    Maps each degradation path to its basis in the layering contract.
    """
    state = record.get("admissibility_state") or {}
    downgrade = record.get("downgrade") or {}
    causal = record.get("causal_chain") or {}

    if not state.get("existence"):
        return (
            "existence layer not satisfied: closeout artifact absent; "
            f"ceiling is {ceiling!r}"
        )
    if not state.get("eligibility_evaluated"):
        return (
            "eligibility layer not satisfied: memory eligibility was not evaluated; "
            f"ceiling is {ceiling!r}"
        )
    if not state.get("compliance_present"):
        return (
            "compliance layer not satisfied: required artifacts not present; "
            f"ceiling is {ceiling!r}"
        )
    if not state.get("semantics_reviewed"):
        return (
            f"{requested_mode!r} requires semantics layer; "
            "semantic review not performed; "
            f"ceiling is {ceiling!r}"
        )

    downgrade_applied = bool(downgrade.get("applied"))
    consequence_tier = _safe_tier(downgrade.get("consequence_tier"))

    if downgrade_applied and consequence_tier == 0:
        return (
            "downgrade recorded at Tier 0 (cosmetic); "
            "Tier 0 does not constitute consumption (contract: reclassify as unconsumed); "
            f"ceiling remains {ceiling!r}"
        )

    if downgrade_applied and consequence_tier >= 2:
        path_type = str(downgrade.get("dependent_path_type") or "informational").lower()
        if path_type not in _TIER2_ADMISSIBLE_PATH_TYPES:
            return (
                f"Tier 2 downgrade requires dependent_path_type 'procedural' or 'blocking'; "
                f"got {path_type!r} (informational = visibility only, not structural constraint); "
                f"Tier 2 reclassified as Tier 1; ceiling is {ceiling!r}"
            )

    causal_present = bool(causal.get("present"))
    cross_layer = bool(causal.get("cross_layer"))

    if requested_mode in ("causal_inference", "governance_adequate") and not causal_present:
        return (
            f"{requested_mode!r} requires causal chain evidence; "
            "causal_chain.present is False; "
            f"ceiling is {ceiling!r}"
        )
    if requested_mode == "governance_adequate" and not cross_layer:
        return (
            "governance_adequate requires cross-layer causal chain reconstruction; "
            "causal_chain.cross_layer is False; "
            f"ceiling is {ceiling!r}"
        )

    return (
        f"{requested_mode!r} exceeds ceiling {ceiling!r}; "
        "record does not satisfy the required admissibility conditions for this mode"
    )


# ──────────────────────────────────────────────────────────────────────────────
# Internal result builder
# ──────────────────────────────────────────────────────────────────────────────

def _make_result(
    *,
    requested_mode: str,
    allowed: bool,
    actual_mode: str,
    ceiling: str,
    enforcement_action: str,
    reason: str,
) -> dict[str, Any]:
    return {
        "requested_mode": requested_mode,
        "allowed": allowed,
        "actual_mode": actual_mode,
        "ceiling": ceiling,
        "enforcement_action": enforcement_action,
        "reason": reason,
    }
