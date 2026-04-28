#!/usr/bin/env python3
"""
Promotion policy for candidate memory.
"""

from __future__ import annotations

from typing import Any


ARCHITECTURE_SENSITIVE_RULES = {"architecture-sensitive", "refactor", "release", "cpp"}

# ── Memory Source Authority (Step 3) ────────────────────────────────────────
# 來源：governance/AUTHORITY.md（Step 1 產出）
# canonical → AUTO_PROMOTE（跳過評估，直接 promote）
# reference → 繼續走現有評估邏輯
# derived   → DO_NOT_PROMOTE（永遠不 promote，只允許 cache）

MEMORY_SOURCE_AUTHORITY: dict[str, str] = {
    # Canonical sources — 直接 promote
    "02_project_facts.md": "canonical",
    "03_decisions.md": "canonical",
    # Reference sources — 評估後 promote，不覆蓋 canonical
    "04_patterns.md": "reference",
    "external_repo_aliases": "reference",
    # Derived sources — cache only，絕不 promote 為 truth
    "reviewer_handoff": "derived",
    "framework_artifact": "derived",
    "session_summary": "derived",
}

PROMOTION_BEHAVIOR: dict[str, str] = {
    "canonical": "promote",    # → AUTO_PROMOTE
    "reference": "evaluate",   # → 現有評估邏輯
    "derived": "cache_only",   # → DO_NOT_PROMOTE
}


def get_source_authority(source_file: str) -> str:
    """
    根據 source 檔案名稱（或路徑末段）回傳 authority 等級。
    未在映射表中的 source 預設為 'reference'（保守策略）。

    Args:
        source_file: memory candidate 的來源檔案路徑或名稱

    Returns:
        "canonical" | "reference" | "derived"
    """
    if not source_file:
        return "reference"

    filename = source_file.replace("\\", "/").split("/")[-1]

    if filename in MEMORY_SOURCE_AUTHORITY:
        return MEMORY_SOURCE_AUTHORITY[filename]

    for prefix, authority in MEMORY_SOURCE_AUTHORITY.items():
        if filename.startswith(prefix):
            return authority

    return "reference"


def get_promotion_behavior(source_file: str) -> str:
    """
    根據 source authority 回傳對應的 promotion 行為。

    Returns:
        "promote" | "evaluate" | "cache_only"
    """
    return PROMOTION_BEHAVIOR[get_source_authority(source_file)]


def _extract_errors(check_result: dict[str, Any] | None) -> list[str]:
    if not check_result:
        return []
    errors = check_result.get("errors", [])
    return errors if isinstance(errors, list) else [str(errors)]


def classify_promotion_policy(
    runtime_contract: dict[str, Any],
    check_result: dict[str, Any] | None = None,
    source_file: str = "",
) -> dict[str, Any]:
    # ── Step 3: Source Authority 前置過濾 ──────────────────────────────────
    # derived source → 永遠不 promote（無論 runtime_contract 如何）
    # canonical source → 直接 AUTO_PROMOTE（跳過後續評估）
    # reference source → 繼續走現有評估邏輯
    if source_file:
        behavior = get_promotion_behavior(source_file)
        if behavior == "cache_only":
            return {
                "decision": "DO_NOT_PROMOTE",
                "reasons": [
                    f"Source '{source_file}' has authority=derived; "
                    "derived sources are cache-only and must not be promoted to durable memory."
                ],
            }
        if behavior == "promote":
            return {
                "decision": "AUTO_PROMOTE",
                "reasons": [
                    f"Source '{source_file}' has authority=canonical; "
                    "canonical sources are promoted directly without further evaluation."
                ],
            }
        # behavior == "evaluate" → fall through to existing logic

    # ── 現有評估邏輯（不動）──────────────────────────────────────────────────
    rules = runtime_contract.get("rules", []) or []
    risk = str(runtime_contract.get("risk", "medium")).strip().lower()
    oversight = str(runtime_contract.get("oversight", "auto")).strip().lower()
    memory_mode = str(runtime_contract.get("memory_mode", "candidate")).strip().lower()
    errors = _extract_errors(check_result)

    if errors:
        return {
            "decision": "DO_NOT_PROMOTE",
            "reasons": ["Runtime checks reported blocking errors."],
        }

    if memory_mode == "stateless":
        return {
            "decision": "DO_NOT_PROMOTE",
            "reasons": ["Session is stateless; durable memory is not allowed."],
        }

    if risk == "high":
        return {
            "decision": "REVIEW_REQUIRED",
            "reasons": ["High-risk sessions require human review before memory promotion."],
        }

    if oversight in {"review-required", "human-approval"}:
        return {
            "decision": "REVIEW_REQUIRED",
            "reasons": [f"Oversight={oversight} requires explicit review before promotion."],
        }

    if memory_mode == "durable":
        return {
            "decision": "REVIEW_REQUIRED",
            "reasons": ["Durable memory must be confirmed through reviewed promotion flow."],
        }

    if any(rule in ARCHITECTURE_SENSITIVE_RULES for rule in rules):
        return {
            "decision": "REVIEW_REQUIRED",
            "reasons": ["Architecture-sensitive rule packs require reviewed memory promotion."],
        }

    if risk == "low" and oversight == "auto" and memory_mode == "candidate":
        return {
            "decision": "AUTO_PROMOTE",
            "reasons": ["Low-risk candidate memory may be auto-promoted."],
        }

    return {
        "decision": "REVIEW_REQUIRED",
        "reasons": ["Default to reviewed promotion when policy is not explicitly auto-safe."],
    }
