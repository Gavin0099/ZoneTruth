#!/usr/bin/env python3
"""
Shared helpers for compact reviewer-first human summaries.
"""

from __future__ import annotations


def format_contract_summary_label(contract_label: str | None, risk_tier: str | None) -> str | None:
    if not contract_label:
        return None
    if risk_tier and risk_tier != "unknown":
        return f"{contract_label}/{risk_tier}"
    return contract_label


def build_summary_line(*parts: str | None) -> str:
    compact = [part for part in parts if part]
    return f"summary={' | '.join(compact)}"
