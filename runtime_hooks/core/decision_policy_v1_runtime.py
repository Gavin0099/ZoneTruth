from __future__ import annotations

import hashlib
from dataclasses import asdict, dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional


class RiskTier(str, Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    INVALID = "invalid"


class DecisionAction(str, Enum):
    PROCEED = "proceed"
    PROCEED_WITH_ASSUMPTION = "proceed_with_assumption"
    NEED_MORE_INFO = "need_more_info"
    REFRAME = "reframe"
    REJECT = "reject"


class PremiseStatus(str, Enum):
    SUPPORTED = "supported"
    UNKNOWN = "unknown"
    UNSUPPORTED = "unsupported"
    CONTRADICTED = "contradicted"


class EvidenceAlignment(str, Enum):
    STRONG = "strong"
    PARTIAL = "partial"
    WEAK = "weak"
    ABSENT = "absent"


class ExecutionScope(str, Enum):
    LOCAL_REVERSIBLE = "local_reversible"
    LOCAL_IRREVERSIBLE = "local_irreversible"
    SHARED_REVERSIBLE = "shared_reversible"
    SHARED_IRREVERSIBLE = "shared_irreversible"
    EXTERNAL_SIDE_EFFECT = "external_side_effect"


class Reversibility(str, Enum):
    EASY = "easy"
    BOUNDED = "bounded"
    HARD = "hard"


class CorrectnessMode(str, Enum):
    DIRECT_FIX = "direct_fix"
    BOUNDED_TRIAL = "bounded_trial"
    ASK_FOR_EVIDENCE = "ask_for_evidence"
    REFRAME_CLAIM = "reframe_claim"
    HARD_STOP = "hard_stop"


@dataclass
class AlternativeCause:
    layer: str
    hypothesis: str

    @classmethod
    def from_obj(cls, obj: Any) -> "AlternativeCause":
        if isinstance(obj, cls):
            return obj
        if isinstance(obj, dict):
            return cls(
                layer=str(obj.get("layer", "unknown")).strip() or "unknown",
                hypothesis=str(obj.get("hypothesis", "")).strip(),
            )
        return cls(layer="unknown", hypothesis=str(obj).strip())


@dataclass
class EvidenceBlock:
    direct_evidence_found: bool = False
    items: List[str] = field(default_factory=list)

    @classmethod
    def from_obj(cls, obj: Any) -> "EvidenceBlock":
        if isinstance(obj, cls):
            return obj
        if not isinstance(obj, dict):
            return cls()
        items = obj.get("items", []) or []
        return cls(
            direct_evidence_found=bool(obj.get("direct_evidence_found", False)),
            items=[str(x).strip() for x in items if str(x).strip()],
        )


@dataclass
class AssumptionAudit:
    stated_premise: str = ""
    alternative_root_causes: List[AlternativeCause] = field(default_factory=list)
    evidence: EvidenceBlock = field(default_factory=EvidenceBlock)
    action_decision: str = ""
    reframed_task: str = ""

    @classmethod
    def from_obj(cls, obj: Any) -> "AssumptionAudit":
        if isinstance(obj, cls):
            return obj
        if not isinstance(obj, dict):
            return cls()
        alternatives = obj.get("alternative_root_causes", []) or []
        return cls(
            stated_premise=str(obj.get("stated_premise", "")).strip(),
            alternative_root_causes=[AlternativeCause.from_obj(x) for x in alternatives],
            evidence=EvidenceBlock.from_obj(obj.get("evidence", {})),
            action_decision=str(obj.get("action_decision", "")).strip(),
            reframed_task=str(obj.get("reframed_task", "")).strip(),
        )


@dataclass
class ContextSignals:
    destructive_change: bool = False
    shared_interface: bool = False
    external_side_effect: bool = False
    partial_context: bool = False
    user_asserts_root_cause: bool = False
    valid_request: bool = False
    change_surface: str = "local"
    reversibility_hint: str = "easy"
    has_spec: bool = False
    has_trace: bool = False
    has_tests: bool = False
    has_usage_evidence: bool = False
    has_caller_inventory_or_compat_check: bool = False
    has_direct_conflicting_evidence: bool = False
    has_direct_evidence: bool = False

    @classmethod
    def from_obj(cls, obj: Any) -> "ContextSignals":
        if isinstance(obj, cls):
            return obj
        if not isinstance(obj, dict):
            return cls()
        return cls(
            destructive_change=bool(obj.get("destructive_change", False)),
            shared_interface=bool(obj.get("shared_interface", False)),
            external_side_effect=bool(obj.get("external_side_effect", False)),
            partial_context=bool(obj.get("partial_context", False)),
            user_asserts_root_cause=bool(obj.get("user_asserts_root_cause", False)),
            valid_request=bool(obj.get("valid_request", False)),
            change_surface=str(obj.get("change_surface", "local")).strip().lower() or "local",
            reversibility_hint=str(obj.get("reversibility", obj.get("reversibility_hint", "easy"))).strip().lower()
            or "easy",
            has_spec=bool(obj.get("has_spec", False)),
            has_trace=bool(obj.get("has_trace", False)),
            has_tests=bool(obj.get("has_tests", obj.get("has_tests_or_regression_guard", False))),
            has_usage_evidence=bool(obj.get("has_usage_evidence", False)),
            has_caller_inventory_or_compat_check=bool(obj.get("has_caller_inventory_or_compat_check", False)),
            has_direct_conflicting_evidence=bool(obj.get("has_direct_conflicting_evidence", False)),
            has_direct_evidence=bool(obj.get("has_direct_evidence", False)),
        )


@dataclass
class PolicyInput:
    task_text: str
    task_type: str = "unknown"
    assumption_audit: AssumptionAudit = field(default_factory=AssumptionAudit)
    context_signals: ContextSignals = field(default_factory=ContextSignals)

    @classmethod
    def from_obj(cls, obj: Dict[str, Any]) -> "PolicyInput":
        return cls(
            task_text=str(obj.get("task_text", "")).strip(),
            task_type=str(obj.get("task_type", "unknown")).strip() or "unknown",
            assumption_audit=AssumptionAudit.from_obj(obj.get("assumption_audit", {})),
            context_signals=ContextSignals.from_obj(obj.get("context_signals", {})),
        )


@dataclass
class ActionScore:
    action: DecisionAction
    score: float
    reasons: List[str] = field(default_factory=list)


@dataclass
class DecisionPolicyResult:
    risk_tier: RiskTier
    risk_score: float
    premise_status: PremiseStatus
    evidence_alignment: EvidenceAlignment
    execution_scope: ExecutionScope
    reversibility: Reversibility
    correctness_mode: CorrectnessMode
    selected_action: DecisionAction
    ranked_actions: List[ActionScore]
    confidence: float
    reasons: List[str]
    required_followup: List[str]
    fallback_plan: str
    reframed_task: str
    advisory_signals: List[str]

    def to_dict(self) -> Dict[str, Any]:
        out = asdict(self)
        out["risk_tier"] = self.risk_tier.value
        out["premise_status"] = self.premise_status.value
        out["evidence_alignment"] = self.evidence_alignment.value
        out["execution_scope"] = self.execution_scope.value
        out["reversibility"] = self.reversibility.value
        out["correctness_mode"] = self.correctness_mode.value
        out["selected_action"] = self.selected_action.value
        out["ranked_actions"] = [
            {"action": item.action.value, "score": round(item.score, 4), "reasons": item.reasons}
            for item in self.ranked_actions
        ]
        out["confidence"] = round(self.confidence, 4)
        out["risk_score"] = round(self.risk_score, 4)
        return out


class DecisionPolicyV1:
    def __init__(
        self,
        *,
        exploration_rate: float = 0.12,
        enable_soft_exploration: bool = True,
        enable_candidate_pruning: bool = True,
    ) -> None:
        self.exploration_rate = max(0.0, min(1.0, exploration_rate))
        self.enable_soft_exploration = enable_soft_exploration
        self.enable_candidate_pruning = enable_candidate_pruning

    def evaluate(self, policy_input: PolicyInput) -> DecisionPolicyResult:
        premise_status = self._classify_premise(policy_input)
        evidence_alignment = self._classify_evidence_alignment(policy_input)
        execution_scope = self._classify_execution_scope(policy_input)
        reversibility = self._classify_reversibility(policy_input, execution_scope)
        mode = self._select_mode(policy_input, premise_status, evidence_alignment, execution_scope)
        risk_tier, risk_score = self._risk_from_phase_a(
            policy_input, premise_status, evidence_alignment, execution_scope, reversibility
        )

        ranked_actions = self._rank_actions(
            policy_input,
            mode,
            premise_status,
            evidence_alignment,
            execution_scope,
            risk_tier,
        )
        selected_action = self._select_action(policy_input, ranked_actions)
        confidence = self._compute_confidence(ranked_actions)

        reasons = [
            f"risk_tier:{risk_tier.value}",
            f"premise_status:{premise_status.value}",
            f"evidence_alignment:{evidence_alignment.value}",
            f"execution_scope:{execution_scope.value}",
            f"correctness_mode:{mode.value}",
        ]
        if policy_input.context_signals.user_asserts_root_cause:
            reasons.append("user_asserted_root_cause")
        if not policy_input.assumption_audit.evidence.direct_evidence_found:
            reasons.append("assumption_evidence_missing")
        if len(policy_input.assumption_audit.alternative_root_causes) >= 2:
            reasons.append("alternative_causes_available")

        followup: List[str] = []
        if selected_action in {DecisionAction.NEED_MORE_INFO, DecisionAction.REFRAME, DecisionAction.REJECT}:
            followup.extend(["collect_spec_or_trace_evidence", "collect_tests_or_regression_guard"])
            if policy_input.context_signals.destructive_change:
                followup.append("collect_callers_or_usage")
            if policy_input.context_signals.partial_context:
                followup.append("request_full_logs_or_repro")
        if selected_action == DecisionAction.PROCEED_WITH_ASSUMPTION:
            followup.extend(["mark_assumption_explicitly", "prepare_rollback_or_fallback"])

        fallback = ""
        if selected_action == DecisionAction.PROCEED_WITH_ASSUMPTION:
            fallback = "Proceed with bounded local change and explicit rollback plan."

        reframed = policy_input.assumption_audit.reframed_task
        if selected_action in {DecisionAction.REFRAME, DecisionAction.NEED_MORE_INFO} and not reframed:
            reframed = f"Verify premise and evidence before acting on: {policy_input.task_text}"

        advisories: List[str] = []
        if selected_action == DecisionAction.PROCEED_WITH_ASSUMPTION:
            advisories.append("proceeding_under_assumption")
        if policy_input.context_signals.destructive_change and selected_action != DecisionAction.PROCEED:
            advisories.append("destructive_change_requires_review")
        if evidence_alignment in {EvidenceAlignment.WEAK, EvidenceAlignment.ABSENT}:
            advisories.append("assumption_evidence_missing")

        return DecisionPolicyResult(
            risk_tier=risk_tier,
            risk_score=risk_score,
            premise_status=premise_status,
            evidence_alignment=evidence_alignment,
            execution_scope=execution_scope,
            reversibility=reversibility,
            correctness_mode=mode,
            selected_action=selected_action,
            ranked_actions=ranked_actions,
            confidence=confidence,
            reasons=reasons,
            required_followup=followup,
            fallback_plan=fallback,
            reframed_task=reframed,
            advisory_signals=advisories,
        )

    def _has_assumption_forcing_bundle(self, inp: PolicyInput) -> bool:
        lowered = inp.task_text.lower()
        return (
            "[assumption check]" in lowered
            and "alternative root causes" in lowered
            and "reframe:" in lowered
            and len(inp.assumption_audit.alternative_root_causes) >= 2
        )

    def _has_evidence_feedback_marker(self, inp: PolicyInput) -> bool:
        lowered = inp.task_text.lower()
        return (
            "proceed only when evidence aligns with risk" in lowered
            or "evidence: direct evidence available from spec/trace/tests" in lowered
        )

    def _classify_premise(self, inp: PolicyInput) -> PremiseStatus:
        s = inp.context_signals
        if s.has_direct_conflicting_evidence:
            return PremiseStatus.CONTRADICTED
        if s.has_spec or s.has_trace or s.has_tests or s.has_caller_inventory_or_compat_check or s.has_direct_evidence:
            return PremiseStatus.SUPPORTED
        if s.user_asserts_root_cause and not inp.assumption_audit.evidence.direct_evidence_found:
            return PremiseStatus.UNSUPPORTED
        return PremiseStatus.UNKNOWN

    def _classify_evidence_alignment(self, inp: PolicyInput) -> EvidenceAlignment:
        s = inp.context_signals
        kinds = int(s.has_spec) + int(s.has_trace) + int(s.has_tests) + int(s.has_caller_inventory_or_compat_check)
        if kinds >= 2:
            base = EvidenceAlignment.STRONG
        elif kinds == 1 or inp.assumption_audit.evidence.direct_evidence_found:
            base = EvidenceAlignment.PARTIAL
        elif s.partial_context:
            base = EvidenceAlignment.WEAK
        else:
            base = EvidenceAlignment.ABSENT

        # Minimal extractor patch:
        # assumption/evidence feedback markers can downgrade optimistic evidence
        # when direct evidence is still missing under partial context.
        if not inp.assumption_audit.evidence.direct_evidence_found and s.partial_context:
            if self._has_evidence_feedback_marker(inp):
                if base == EvidenceAlignment.STRONG:
                    return EvidenceAlignment.PARTIAL
                if base == EvidenceAlignment.PARTIAL:
                    return EvidenceAlignment.WEAK
            if self._has_assumption_forcing_bundle(inp) and base == EvidenceAlignment.PARTIAL:
                return EvidenceAlignment.WEAK
        return base

    def _classify_execution_scope(self, inp: PolicyInput) -> ExecutionScope:
        s = inp.context_signals
        surface = s.change_surface
        if s.external_side_effect or surface == "external":
            return ExecutionScope.EXTERNAL_SIDE_EFFECT
        if (s.shared_interface or surface == "shared") and s.destructive_change:
            return ExecutionScope.SHARED_IRREVERSIBLE
        if s.shared_interface or surface == "shared":
            return ExecutionScope.SHARED_REVERSIBLE
        if s.destructive_change:
            return ExecutionScope.LOCAL_IRREVERSIBLE
        return ExecutionScope.LOCAL_REVERSIBLE

    def _classify_reversibility(self, inp: PolicyInput, scope: ExecutionScope) -> Reversibility:
        hint = inp.context_signals.reversibility_hint
        if hint == "hard":
            return Reversibility.HARD
        if hint == "bounded":
            return Reversibility.BOUNDED
        if scope in {ExecutionScope.SHARED_IRREVERSIBLE, ExecutionScope.EXTERNAL_SIDE_EFFECT}:
            return Reversibility.HARD
        if scope in {ExecutionScope.LOCAL_IRREVERSIBLE, ExecutionScope.SHARED_REVERSIBLE}:
            return Reversibility.BOUNDED
        return Reversibility.EASY

    def _select_mode(
        self,
        inp: PolicyInput,
        premise: PremiseStatus,
        evidence: EvidenceAlignment,
        scope: ExecutionScope,
    ) -> CorrectnessMode:
        s = inp.context_signals
        has_assumption_forcing = self._has_assumption_forcing_bundle(inp)
        has_direct_evidence = bool(inp.assumption_audit.evidence.direct_evidence_found)

        # Minimal extractor patch:
        # structured assumption forcing under missing direct evidence should keep
        # mode epistemically cautious instead of falling through to direct_fix.
        if has_assumption_forcing and not has_direct_evidence and s.partial_context:
            if premise != PremiseStatus.CONTRADICTED:
                return CorrectnessMode.ASK_FOR_EVIDENCE

        # Premise precedence: unsupported premise cannot execute as proceed/proceed_with_assumption.
        if premise == PremiseStatus.UNSUPPORTED:
            return CorrectnessMode.REFRAME_CLAIM if s.user_asserts_root_cause else CorrectnessMode.ASK_FOR_EVIDENCE
        if s.destructive_change and not s.has_usage_evidence:
            return CorrectnessMode.REFRAME_CLAIM
        if scope == ExecutionScope.EXTERNAL_SIDE_EFFECT and evidence in {EvidenceAlignment.WEAK, EvidenceAlignment.ABSENT}:
            return CorrectnessMode.ASK_FOR_EVIDENCE
        if premise == PremiseStatus.CONTRADICTED:
            return CorrectnessMode.REFRAME_CLAIM
        if premise == PremiseStatus.SUPPORTED and evidence in {EvidenceAlignment.STRONG, EvidenceAlignment.PARTIAL}:
            return CorrectnessMode.DIRECT_FIX
        if scope == ExecutionScope.LOCAL_REVERSIBLE and premise in {PremiseStatus.UNKNOWN, PremiseStatus.UNSUPPORTED}:
            return CorrectnessMode.BOUNDED_TRIAL
        if premise in {PremiseStatus.UNKNOWN, PremiseStatus.UNSUPPORTED}:
            return CorrectnessMode.ASK_FOR_EVIDENCE
        return CorrectnessMode.ASK_FOR_EVIDENCE

    def _risk_from_phase_a(
        self,
        inp: PolicyInput,
        premise: PremiseStatus,
        evidence: EvidenceAlignment,
        scope: ExecutionScope,
        reversibility: Reversibility,
    ) -> tuple[RiskTier, float]:
        premise_score = {
            PremiseStatus.SUPPORTED: 0.5,
            PremiseStatus.UNKNOWN: 1.3,
            PremiseStatus.UNSUPPORTED: 2.2,
            PremiseStatus.CONTRADICTED: 2.8,
        }[premise]
        evidence_score = {
            EvidenceAlignment.STRONG: 0.3,
            EvidenceAlignment.PARTIAL: 0.9,
            EvidenceAlignment.WEAK: 1.7,
            EvidenceAlignment.ABSENT: 2.2,
        }[evidence]
        scope_score = {
            ExecutionScope.LOCAL_REVERSIBLE: 0.3,
            ExecutionScope.LOCAL_IRREVERSIBLE: 1.0,
            ExecutionScope.SHARED_REVERSIBLE: 1.5,
            ExecutionScope.SHARED_IRREVERSIBLE: 2.3,
            ExecutionScope.EXTERNAL_SIDE_EFFECT: 2.8,
        }[scope]
        rev_score = {
            Reversibility.EASY: 0.3,
            Reversibility.BOUNDED: 0.9,
            Reversibility.HARD: 1.8,
        }[reversibility]
        risk_score = premise_score + evidence_score + scope_score + rev_score
        if premise == PremiseStatus.CONTRADICTED:
            return RiskTier.INVALID, risk_score
        if inp.context_signals.destructive_change and not inp.context_signals.has_usage_evidence:
            return RiskTier.INVALID, risk_score
        if risk_score >= 6.2:
            return RiskTier.HIGH, risk_score
        if risk_score >= 4.2:
            return RiskTier.MEDIUM, risk_score
        return RiskTier.LOW, risk_score

    def _rank_actions(
        self,
        inp: PolicyInput,
        mode: CorrectnessMode,
        premise: PremiseStatus,
        evidence: EvidenceAlignment,
        scope: ExecutionScope,
        risk_tier: RiskTier,
    ) -> List[ActionScore]:
        preferred = {
            CorrectnessMode.DIRECT_FIX: DecisionAction.PROCEED,
            CorrectnessMode.BOUNDED_TRIAL: DecisionAction.PROCEED_WITH_ASSUMPTION,
            CorrectnessMode.ASK_FOR_EVIDENCE: DecisionAction.NEED_MORE_INFO,
            CorrectnessMode.REFRAME_CLAIM: DecisionAction.REFRAME,
            CorrectnessMode.HARD_STOP: DecisionAction.REJECT,
        }[mode]
        secondary = {
            CorrectnessMode.DIRECT_FIX: DecisionAction.PROCEED_WITH_ASSUMPTION,
            CorrectnessMode.BOUNDED_TRIAL: DecisionAction.NEED_MORE_INFO,
            CorrectnessMode.ASK_FOR_EVIDENCE: DecisionAction.REFRAME,
            CorrectnessMode.REFRAME_CLAIM: DecisionAction.NEED_MORE_INFO,
            CorrectnessMode.HARD_STOP: DecisionAction.REFRAME,
        }[mode]

        base = {
            DecisionAction.PROCEED: 0.2,
            DecisionAction.PROCEED_WITH_ASSUMPTION: 0.3,
            DecisionAction.NEED_MORE_INFO: 0.4,
            DecisionAction.REFRAME: 0.3,
            DecisionAction.REJECT: 0.1,
        }
        base[preferred] += 1.1
        base[secondary] += 0.4

        # Experimental hard action gates
        disallowed: set[DecisionAction] = set()
        if self.enable_candidate_pruning:
            if scope in {ExecutionScope.SHARED_IRREVERSIBLE, ExecutionScope.EXTERNAL_SIDE_EFFECT} and evidence in {
                EvidenceAlignment.WEAK,
                EvidenceAlignment.ABSENT,
            }:
                disallowed.update({DecisionAction.PROCEED, DecisionAction.PROCEED_WITH_ASSUMPTION})
            if premise == PremiseStatus.CONTRADICTED:
                disallowed.add(DecisionAction.PROCEED)
            if risk_tier in {RiskTier.HIGH, RiskTier.INVALID} and not inp.assumption_audit.evidence.direct_evidence_found:
                disallowed.add(DecisionAction.PROCEED)
            if risk_tier == RiskTier.INVALID:
                disallowed.add(DecisionAction.PROCEED_WITH_ASSUMPTION)

        reasons: Dict[DecisionAction, List[str]] = {k: [] for k in base}
        for action in reasons:
            reasons[action].append(f"mode:{mode.value}")
            reasons[action].append(f"premise:{premise.value}")
            reasons[action].append(f"evidence:{evidence.value}")
            reasons[action].append(f"scope:{scope.value}")
        if inp.assumption_audit.evidence.direct_evidence_found:
            reasons[DecisionAction.PROCEED].append("direct_evidence_present")
        else:
            reasons[DecisionAction.NEED_MORE_INFO].append("direct_evidence_missing")

        ranked = [
            ActionScore(action=action, score=score, reasons=reasons[action])
            for action, score in base.items()
            if action not in disallowed
        ]
        ranked.sort(key=lambda x: x.score, reverse=True)
        return ranked

    def _select_action(self, inp: PolicyInput, ranked: List[ActionScore]) -> DecisionAction:
        if not ranked:
            return DecisionAction.NEED_MORE_INFO
        selected = ranked[0].action
        if not self.enable_soft_exploration or len(ranked) < 2:
            return selected
        key = f"{inp.task_text}|{inp.task_type}|{inp.assumption_audit.stated_premise}"
        h = hashlib.sha256(key.encode("utf-8")).hexdigest()
        draw = int(h[:8], 16) / 0xFFFFFFFF
        margin = ranked[0].score - ranked[1].score
        if draw < self.exploration_rate and margin < 0.25:
            return ranked[1].action
        return selected

    def _compute_confidence(self, ranked: List[ActionScore]) -> float:
        if len(ranked) < 2:
            return 1.0
        margin = max(0.0, ranked[0].score - ranked[1].score)
        return min(1.0, 0.5 + margin)


def build_decision_policy_input(
    task_text: str,
    *,
    assumption_audit: Optional[Dict[str, Any]] = None,
    context_signals: Optional[Dict[str, Any]] = None,
    task_type: str = "unknown",
) -> PolicyInput:
    return PolicyInput.from_obj(
        {
            "task_text": task_text,
            "task_type": task_type,
            "assumption_audit": assumption_audit or {},
            "context_signals": context_signals or {},
        }
    )


def evaluate_decision_policy(
    task_text: str,
    *,
    assumption_audit: Optional[Dict[str, Any]] = None,
    context_signals: Optional[Dict[str, Any]] = None,
    task_type: str = "unknown",
    exploration_rate: float = 0.12,
    enable_soft_exploration: bool = True,
    enable_candidate_pruning: bool = True,
) -> Dict[str, Any]:
    policy_input = build_decision_policy_input(
        task_text,
        assumption_audit=assumption_audit,
        context_signals=context_signals,
        task_type=task_type,
    )
    engine = DecisionPolicyV1(
        exploration_rate=exploration_rate,
        enable_soft_exploration=enable_soft_exploration,
        enable_candidate_pruning=enable_candidate_pruning,
    )
    return engine.evaluate(policy_input).to_dict()
