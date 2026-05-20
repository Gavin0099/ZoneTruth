"""
Observation-only semantic failure detector.

This module does not provide enforcement authority.
It emits reviewer-facing observations for semantic risk hotspots.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class SemanticObservation:
    failure_id: str
    severity: str
    message: str
    invariant_id: str | None = None

    def as_dict(self) -> dict:
        return {
            "failure_id": self.failure_id,
            "severity": self.severity,
            "message": self.message,
            "invariant_id": self.invariant_id,
        }


def _normalize_lines(value: object) -> list[str]:
    if isinstance(value, str):
        return [value.strip()] if value.strip() else []
    if isinstance(value, list):
        out: list[str] = []
        for item in value:
            text = str(item).strip()
            if text:
                out.append(text)
        return out
    return []


def observe_semantic_failures(checks: dict | None) -> dict:
    """
    Inspect optional runtime `checks` payload and emit semantic observations.

    Supported optional keys:
    - evidence_fragments: list[str]
    - output_claims: list[str]
    - invariant_statements_before: list[str]
    - invariant_statements_after: list[str]
    - topology_targets: list[str]
    - decision_targets: list[str]
    """
    if not checks:
        return {"observations": [], "hotspots": []}

    evidence = _normalize_lines(checks.get("evidence_fragments"))
    claims = _normalize_lines(checks.get("output_claims"))
    inv_before = _normalize_lines(checks.get("invariant_statements_before"))
    inv_after = _normalize_lines(checks.get("invariant_statements_after"))
    topology_targets = set(_normalize_lines(checks.get("topology_targets")))
    decision_targets = set(_normalize_lines(checks.get("decision_targets")))

    observations: list[SemanticObservation] = []

    if claims and not evidence:
        observations.append(
            SemanticObservation(
                failure_id="SF-01",
                severity="S2",
                message="Output claims exist without evidence fragments (unsupported leap candidate).",
                invariant_id="evidence_output_alignment",
            )
        )

    if inv_before and inv_after and set(inv_before) != set(inv_after):
        observations.append(
            SemanticObservation(
                failure_id="SF-07",
                severity="S3",
                message="Invariant statements changed across task without explicit semantic revision contract.",
                invariant_id="observation_not_enforcement",
            )
        )

    if topology_targets and decision_targets and not decision_targets.issubset(topology_targets):
        observations.append(
            SemanticObservation(
                failure_id="SF-04",
                severity="S3",
                message="Decision target set exceeds declared topology target set (topology contradiction candidate).",
                invariant_id="topology_identity_isolation",
            )
        )

    hotspots = []
    for idx, obs in enumerate(observations, start=1):
        hotspots.append(
            {
                "hotspot_id": f"hs-semantic-{idx:03d}",
                "risk_rank": "high" if obs.severity == "S3" else "medium",
                "failure_class": obs.failure_id,
                "invariant_id": obs.invariant_id,
                "ambiguity_zone": obs.message,
                "recommended_review_action": "manual_semantic_review_required",
            }
        )

    return {
        "observations": [item.as_dict() for item in observations],
        "hotspots": hotspots,
    }
