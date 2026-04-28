#!/usr/bin/env python3
"""
Curate runtime candidate artifacts into cleaner memory-ready records.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


NOISE_PATTERNS = (
    r"^\s*$",
    r"^\d+\s+passed\b",
    r"^ok\s*=\s*(true|false)\b",
    r"^snapshot\s*=",
    r"^promotion\s*=",
    r"^warning:",
)


def _normalize_text(value: str) -> str:
    return re.sub(r"\s+", " ", value.strip())


def _is_noise(value: str) -> bool:
    text = value.strip()
    if not text:
        return True
    lowered = text.lower()
    return any(re.search(pattern, lowered, re.IGNORECASE) for pattern in NOISE_PATTERNS)


def _infer_type(value: str) -> str:
    lowered = value.lower()
    if any(token in lowered for token in ("must", "rule", "policy", "contract", "boundary", "requires", "forbidden")):
        return "decision"
    if any(token in lowered for token in ("next", "follow-up", "todo", "review", "pending", "later")):
        return "followup"
    return "fact"


def _item_title(item_type: str, content: str) -> str:
    words = content.split()
    short = " ".join(words[:8]).strip()
    prefix = {"decision": "Decision", "followup": "Follow-up", "fact": "Fact"}[item_type]
    return f"{prefix}: {short}" if short else prefix


def _extract_candidate_items(candidate_payload: dict[str, Any]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    kept: list[dict[str, Any]] = []
    dropped: list[dict[str, Any]] = []
    seen: set[str] = set()

    summary = _normalize_text(str(candidate_payload.get("summary", "")))
    if summary:
        item_type = _infer_type(summary)
        kept.append(
            {
                "type": item_type,
                "title": _item_title(item_type, summary),
                "content": summary,
                "reason": "session summary",
                "confidence": "high",
                "source": "summary",
            }
        )
        seen.add(summary.lower())

    runtime_contract = candidate_payload.get("runtime_contract", {}) or {}
    rules = runtime_contract.get("rules", []) or []
    if rules:
        content = f"Active governance rules: {', '.join(rules)}"
        kept.append(
            {
                "type": "fact",
                "title": "Fact: active governance rules",
                "content": content,
                "reason": "governance context",
                "confidence": "high",
                "source": "runtime_contract.rules",
            }
        )
        seen.add(content.lower())

    policy = candidate_payload.get("policy", {}) or {}
    reasons = policy.get("reasons", []) or []
    for reason in reasons:
        content = _normalize_text(str(reason))
        if not content or content.lower() in seen or _is_noise(content):
            dropped.append({"reason": "duplicate or noise", "source": "policy.reasons", "content": content})
            continue
        item_type = _infer_type(content)
        kept.append(
            {
                "type": item_type,
                "title": _item_title(item_type, content),
                "content": content,
                "reason": "promotion policy rationale",
                "confidence": "high",
                "source": "policy.reasons",
            }
        )
        seen.add(content.lower())

    check_errors = candidate_payload.get("checks", {}).get("errors", []) if candidate_payload.get("checks") else []
    for error in check_errors:
        content = _normalize_text(str(error))
        if not content or content.lower() in seen:
            dropped.append({"reason": "duplicate", "source": "checks.errors", "content": content})
            continue
        kept.append(
            {
                "type": "followup",
                "title": _item_title("followup", content),
                "content": content,
                "reason": "runtime check error requires follow-up",
                "confidence": "high",
                "source": "checks.errors",
            }
        )
        seen.add(content.lower())

    public_api_diff = candidate_payload.get("public_api_diff") or {}
    for removed in public_api_diff.get("removed", []) or []:
        content = _normalize_text(f"Public API removed or changed: {removed}")
        if not content or content.lower() in seen:
            dropped.append({"reason": "duplicate", "source": "public_api_diff.removed", "content": content})
            continue
        kept.append(
            {
                "type": "followup",
                "title": _item_title("followup", content),
                "content": content,
                "reason": "public API compatibility risk",
                "confidence": "high",
                "source": "public_api_diff.removed",
            }
        )
        seen.add(content.lower())

    added_entries = public_api_diff.get("added", []) or []
    if added_entries:
        content = _normalize_text(f"Public API additions detected: {len(added_entries)}")
        if content and content.lower() not in seen:
            kept.append(
                {
                    "type": "fact",
                    "title": "Fact: public API additions detected",
                    "content": content,
                    "reason": "public interface audit signal",
                    "confidence": "medium",
                    "source": "public_api_diff.added",
                }
            )
            seen.add(content.lower())

    architecture_impact_preview = candidate_payload.get("architecture_impact_preview") or {}
    for concern in architecture_impact_preview.get("concerns", []) or []:
        content = _normalize_text(f"Architecture impact concern: {concern}")
        if not content or content.lower() in seen:
            dropped.append({"reason": "duplicate", "source": "architecture_impact_preview.concerns", "content": content})
            continue
        kept.append(
            {
                "type": "followup",
                "title": _item_title("followup", content),
                "content": content,
                "reason": "proposal-time architecture concern",
                "confidence": "medium",
                "source": "architecture_impact_preview.concerns",
            }
        )
        seen.add(content.lower())

    required_evidence = architecture_impact_preview.get("required_evidence", []) or []
    if required_evidence:
        content = _normalize_text(f"Expected governance evidence: {', '.join(required_evidence)}")
        if content and content.lower() not in seen:
            kept.append(
                {
                    "type": "fact",
                    "title": "Fact: expected governance evidence",
                    "content": content,
                    "reason": "proposal-time governance forecast",
                    "confidence": "medium",
                    "source": "architecture_impact_preview.required_evidence",
                }
            )
            seen.add(content.lower())

    proposal_summary = candidate_payload.get("proposal_summary") or {}
    proposal_concerns = proposal_summary.get("concerns", []) or []
    if proposal_concerns:
        content = _normalize_text(f"Proposal summary concerns: {', '.join(proposal_concerns)}")
        if content and content.lower() not in seen:
            kept.append(
                {
                    "type": "followup",
                    "title": "Follow-up: proposal summary concerns",
                    "content": content,
                    "reason": "proposal-time governance summary",
                    "confidence": "medium",
                    "source": "proposal_summary.concerns",
                }
            )
            seen.add(content.lower())

    proposal_evidence = proposal_summary.get("required_evidence", []) or []
    if proposal_evidence:
        content = _normalize_text(f"Proposal summary evidence: {', '.join(proposal_evidence)}")
        if content and content.lower() not in seen:
            kept.append(
                {
                    "type": "fact",
                    "title": "Fact: proposal summary evidence",
                    "content": content,
                    "reason": "proposal-time evidence expectation",
                    "confidence": "medium",
                    "source": "proposal_summary.required_evidence",
                }
            )
            seen.add(content.lower())

    proposal_risk = proposal_summary.get("recommended_risk")
    proposal_oversight = proposal_summary.get("recommended_oversight")
    if proposal_risk or proposal_oversight:
        parts = []
        if proposal_risk:
            parts.append(f"risk={proposal_risk}")
        if proposal_oversight:
            parts.append(f"oversight={proposal_oversight}")
        content = _normalize_text(f"Proposal summary recommendation: {', '.join(parts)}")
        if content and content.lower() not in seen:
            kept.append(
                {
                    "type": "decision",
                    "title": "Decision: proposal summary recommendation",
                    "content": content,
                    "reason": "proposal-time governance recommendation",
                    "confidence": "medium",
                    "source": "proposal_summary.recommendation",
                }
            )
            seen.add(content.lower())

    contract_resolution = candidate_payload.get("contract_resolution") or {}
    domain_contract = candidate_payload.get("domain_contract") or {}
    domain_raw = domain_contract.get("raw") or {}
    contract_context_parts = []
    if contract_resolution.get("source"):
        contract_context_parts.append(f"source={contract_resolution['source']}")
    if domain_contract.get("name"):
        contract_context_parts.append(f"name={domain_contract['name']}")
    if domain_raw.get("domain"):
        contract_context_parts.append(f"domain={domain_raw['domain']}")
    if domain_raw.get("plugin_version"):
        contract_context_parts.append(f"plugin_version={domain_raw['plugin_version']}")
    if contract_resolution.get("risk_tier"):
        contract_context_parts.append(f"risk_tier={contract_resolution['risk_tier']}")
    if contract_context_parts:
        content = _normalize_text(f"Domain contract context: {', '.join(contract_context_parts)}")
        if content.lower() not in seen:
            kept.append(
                {
                    "type": "fact",
                    "title": "Fact: domain contract context",
                    "content": content,
                    "reason": "session domain governance context",
                    "confidence": "high",
                    "source": "contract_resolution",
                }
            )
            seen.add(content.lower())

    event_log = candidate_payload.get("event_log", []) or []
    for event in event_log:
        event_type = str(event.get("event_type", "")).strip()
        detail = _normalize_text(str(event.get("summary") or event.get("message") or ""))
        if not detail:
            dropped.append({"reason": "runtime noise", "source": f"event_log.{event_type or 'unknown'}"})
            continue
        if detail.lower() in seen or _is_noise(detail):
            dropped.append({"reason": "duplicate or noise", "source": f"event_log.{event_type or 'unknown'}", "content": detail})
            continue
        item_type = _infer_type(detail)
        kept.append(
            {
                "type": item_type,
                "title": _item_title(item_type, detail),
                "content": detail,
                "reason": "meaningful session event",
                "confidence": "medium",
                "source": f"event_log.{event_type or 'unknown'}",
            }
        )
        seen.add(detail.lower())

    return kept, dropped


def curate_candidate_artifact(candidate_file: Path, output_path: Path | None = None) -> dict[str, Any]:
    candidate_payload = json.loads(candidate_file.read_text(encoding="utf-8"))
    kept, dropped = _extract_candidate_items(candidate_payload)

    review_reasons = []
    if candidate_payload.get("checks", {}).get("errors"):
        review_reasons.append("runtime check errors present")
    if candidate_payload.get("runtime_contract", {}).get("risk") == "high":
        review_reasons.append("high-risk runtime contract")
    if candidate_payload.get("runtime_contract", {}).get("oversight") in {"review-required", "human-approval"}:
        review_reasons.append("oversight requires review")

    result = {
        "session_id": candidate_payload.get("session_id"),
        "curation_status": "CURATED",
        "raw_candidate_count": len(kept) + len(dropped),
        "kept_count": len(kept),
        "dropped_count": len(dropped),
        "items": kept,
        "dropped": dropped,
        "promotion_hint": "REVIEW_REQUIRED" if review_reasons else "PROMOTE_CANDIDATE",
        "needs_review_reason": review_reasons,
    }

    if output_path is not None:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    return result


def main() -> None:
    parser = argparse.ArgumentParser(description="Curate a runtime candidate artifact.")
    parser.add_argument("--candidate-file", required=True)
    parser.add_argument("--output")
    args = parser.parse_args()

    result = curate_candidate_artifact(
        candidate_file=Path(args.candidate_file),
        output_path=Path(args.output) if args.output else None,
    )
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
