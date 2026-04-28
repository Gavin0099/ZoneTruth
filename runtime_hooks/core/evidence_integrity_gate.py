from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any, Dict, List


NO_EVIDENCE_SOURCES = {
    "explicit_no_evidence_marker",
    "no_direct_evidence",
    "user_assertion_not_evidence",
    "assumption_evidence_not_promoted",
    "partial_context_not_evidence",
}

POSITIVE_EVIDENCE_REASONS = {"direct_evidence_present"}

WEAK_OR_NON_EVIDENCE_REASONS = {
    "request_marked_valid",
    "user_asserted_root_cause",
    "alternative_causes_available",
}


@dataclass
class GateViolation:
    code: str
    message: str
    path: str

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class GateResult:
    ok: bool
    gate: str
    violations: List[GateViolation]
    summary: Dict[str, Any]

    def to_dict(self) -> Dict[str, Any]:
        return {
            "ok": self.ok,
            "gate": self.gate,
            "violations": [v.to_dict() for v in self.violations],
            "summary": self.summary,
        }


def _iter_candidates(decision: Dict[str, Any]) -> List[Dict[str, Any]]:
    return list(decision.get("decision_candidates", []) or [])


def evaluate_evidence_integrity_gate(case_record: Dict[str, Any]) -> GateResult:
    violations: List[GateViolation] = []

    case_id = str(case_record.get("case_id", "runtime_task"))
    kind = str(case_record.get("kind", "unknown"))
    phase = str(case_record.get("phase", "final"))
    decision = case_record.get("decision", {}) or {}

    ground_truth = case_record.get("ground_truth_direct_evidence")
    has_ground_truth = isinstance(ground_truth, bool)
    ground_truth_direct_evidence = bool(ground_truth) if has_ground_truth else None

    evidence_source = str(decision.get("evidence_source", ""))
    direct_evidence_frozen = bool(decision.get("direct_evidence_frozen", False))
    selected_action = str(decision.get("action", ""))
    candidates = _iter_candidates(decision)

    # Rule E1 / E3
    for idx, cand in enumerate(candidates):
        reasons = set(cand.get("reasons", []) or [])
        if reasons & POSITIVE_EVIDENCE_REASONS:
            if evidence_source in NO_EVIDENCE_SOURCES or not direct_evidence_frozen:
                violations.append(
                    GateViolation(
                        code="EVIDENCE_REASON_MISMATCH",
                        message="Candidate claims direct evidence while frozen evidence/source does not permit it.",
                        path=f"decision_candidates[{idx}].reasons",
                    )
                )

    # Rule E2 (only when benchmark ground truth is available)
    if kind == "wrong" and has_ground_truth and ground_truth_direct_evidence is False:
        if selected_action == "proceed":
            violations.append(
                GateViolation(
                    code="WRONG_PROCEED_SELECTED",
                    message="Selected action is proceed on a wrong/no-evidence case.",
                    path="action",
                )
            )
        for idx, cand in enumerate(candidates):
            if cand.get("action") == "proceed" and (
                evidence_source in NO_EVIDENCE_SOURCES or not direct_evidence_frozen
            ):
                violations.append(
                    GateViolation(
                        code="WRONG_PROCEED_CANDIDATE_PRESENT",
                        message="Proceed candidate exists on wrong/no-evidence case under invalid evidence conditions.",
                        path=f"decision_candidates[{idx}]",
                    )
                )

    # Rule E4
    for idx, cand in enumerate(candidates):
        if cand.get("action") != "proceed":
            continue
        reasons = set(cand.get("reasons", []) or [])
        if reasons and reasons.issubset(WEAK_OR_NON_EVIDENCE_REASONS):
            violations.append(
                GateViolation(
                    code="PROCEED_SUPPORTED_BY_NON_EVIDENCE_ONLY",
                    message="Proceed is justified only by weak/non-evidence reasons.",
                    path=f"decision_candidates[{idx}].reasons",
                )
            )

    hard_fail_codes = {
        "WRONG_PROCEED_SELECTED",
        "WRONG_PROCEED_CANDIDATE_PRESENT",
        "EVIDENCE_REASON_MISMATCH",
    }
    return GateResult(
        ok=(len(violations) == 0),
        gate="evidence_integrity_gate",
        violations=violations,
        summary={
            "case_id": case_id,
            "kind": kind,
            "phase": phase,
            "violation_count": len(violations),
            "hard_fail": any(v.code in hard_fail_codes for v in violations),
        },
    )
