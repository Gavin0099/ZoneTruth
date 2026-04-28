#!/usr/bin/env python3
"""
payload_audit_logger.py — captures session_start payloads for token-cost analysis.

Writes one JSON entry per invocation to docs/payload-audit/<session-type>-<date>.jsonl.
Token estimates use the 4-chars-per-token heuristic (GPT/Claude prose baseline).
"""

from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


# ---------------------------------------------------------------------------
# Token estimation
# ---------------------------------------------------------------------------

CHARS_PER_TOKEN = 4  # conservative prose estimate


def _estimate_tokens(value: Any) -> int:
    """Recursively estimate token count for a JSON-serialisable value."""
    if value is None:
        return 0
    if isinstance(value, bool):
        return 1
    if isinstance(value, (int, float)):
        return 1
    if isinstance(value, str):
        return max(1, len(value) // CHARS_PER_TOKEN)
    if isinstance(value, list):
        return sum(_estimate_tokens(item) for item in value)
    if isinstance(value, dict):
        return sum(_estimate_tokens(k) + _estimate_tokens(v) for k, v in value.items())
    # fallback: serialise and measure
    return max(1, len(json.dumps(value, default=str)) // CHARS_PER_TOKEN)


def _field_token_map(d: dict) -> dict[str, int]:
    """Return {field: estimated_tokens} for every top-level key in d."""
    return {k: _estimate_tokens(v) for k, v in d.items()}


# ---------------------------------------------------------------------------
# Session-type detection
# ---------------------------------------------------------------------------

def _infer_session_type(risk: str, rules: str, task_text: str = "") -> str:
    """
    Classify the session type based on risk + rules + task_text:

      L0         — low risk, rules = common (or empty)
      L1         — medium/high risk OR explicit non-common rules
      onboarding — 'onboarding' in rules string OR task_text
    """
    combined = f"{rules or ''} {task_text or ''}".lower()
    if "onboard" in combined:
        return "onboarding"
    if (risk or "low").lower() == "low" and (rules or "common") in ("common", ""):
        return "L0"
    return "L1"


def resolve_session_type(
    *,
    task_level: str = "",
    task_type: str = "",
    risk: str = "medium",
    rules: str = "common",
    task_text: str = "",
) -> str:
    """
    Resolve the audit lane for a session.

    `task_type=onboarding` should keep a distinct onboarding lane even when the
    runtime task level is L1, because onboarding cost is tracked separately from
    generic L1 implementation sessions.
    """
    if (task_type or "").lower() == "onboarding":
        return "onboarding"
    normalized_level = (task_level or "").upper()
    if normalized_level in ("L0", "L1", "L2"):
        return normalized_level
    return _infer_session_type(risk, rules, task_text)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def log_session_payload(
    result: dict,
    *,
    project_root: Path,
    task_type: str = "general",
    risk: str = "medium",
    rules: str = "common",
    task_text: str = "",
    format_mode: str = "json",
    rendered_output: str = "",
) -> Path:
    """
    Append one audit entry to docs/payload-audit/<session_type>-<YYYY-MM-DD>.jsonl.

    Returns the path of the log file written.
    """
    task_level = result.get("task_level") or ""
    session_type = resolve_session_type(
        task_level=task_level,
        task_type=task_type,
        risk=risk,
        rules=rules,
        task_text=task_text,
    )
    now = datetime.now(tz=timezone.utc)
    date_str = now.strftime("%Y-%m-%d")
    ts_str = now.isoformat()

    # Token breakdown
    field_tokens = _field_token_map(result)
    total_tokens = sum(field_tokens.values())
    rendered_tokens = _estimate_tokens(rendered_output)
    top_consumers = sorted(field_tokens.items(), key=lambda x: x[1], reverse=True)[:5]

    # Runtime contract snapshot
    runtime_contract = result.get("runtime_contract") or {}
    active_rules = runtime_contract.get("rules") or []

    entry = {
        "ts": ts_str,
        "session_type": session_type,
        "task_level": task_level,
        "task_type": task_type,
        "ok": result.get("ok"),
        "risk_input": risk,
        "rules_input": rules,
        "active_rules": active_rules,
        "task_text_preview": (task_text or "")[:120],
        "format_mode": format_mode,
        "tokens": {
            "result_dict_total": total_tokens,
            "rendered_output": rendered_tokens,
            "combined_estimate": total_tokens + rendered_tokens,
            "field_breakdown": dict(top_consumers),
        },
        "warnings": result.get("pre_task_check", {}).get("warnings", []),
        "errors": result.get("pre_task_check", {}).get("errors", []),
        "suggested_rules_preview": result.get("suggested_rules_preview", []),
        "suggested_agent": result.get("suggested_agent"),
    }

    # Ensure output directory exists
    audit_dir = project_root / "docs" / "payload-audit"
    audit_dir.mkdir(parents=True, exist_ok=True)

    log_file = audit_dir / f"{session_type}-{date_str}.jsonl"
    with log_file.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(entry, ensure_ascii=False) + "\n")

    return log_file


def load_audit_log(log_file: Path) -> list[dict]:
    """Read a .jsonl audit log and return all entries as a list of dicts."""
    if not log_file.exists():
        return []
    entries = []
    for line in log_file.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line:
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return entries


def summarise_audit_dir(audit_dir: Path) -> dict:
    """
    Aggregate all .jsonl files in audit_dir into a summary dict.

    Returns:
        {
          "total_sessions": int,
          "by_session_type": { L0: N, L1: N, onboarding: N },
          "token_stats": {
              "max_combined": int,
              "min_combined": int,
              "avg_combined": float,
          },
          "top_token_fields": [(field, avg_tokens), ...],  # top 3
          "warnings_seen": [str, ...],
          "errors_seen": [str, ...],
        }
    """
    all_entries: list[dict] = []
    for jl in sorted(audit_dir.glob("*.jsonl")):
        all_entries.extend(load_audit_log(jl))

    if not all_entries:
        return {"total_sessions": 0}

    by_type: dict[str, int] = {}
    combined_totals: list[int] = []
    field_accum: dict[str, list[int]] = {}
    all_warnings: list[str] = []
    all_errors: list[str] = []

    for e in all_entries:
        st = e.get("session_type", "unknown")
        by_type[st] = by_type.get(st, 0) + 1
        tok = e.get("tokens", {})
        combined = tok.get("combined_estimate", 0)
        combined_totals.append(combined)
        for field, count in (tok.get("field_breakdown") or {}).items():
            field_accum.setdefault(field, []).append(count)
        all_warnings.extend(e.get("warnings", []))
        all_errors.extend(e.get("errors", []))

    avg_per_field = {
        f: sum(vals) / len(vals) for f, vals in field_accum.items()
    }
    top_fields = sorted(avg_per_field.items(), key=lambda x: x[1], reverse=True)[:3]

    return {
        "total_sessions": len(all_entries),
        "by_session_type": by_type,
        "token_stats": {
            "max_combined": max(combined_totals),
            "min_combined": min(combined_totals),
            "avg_combined": round(sum(combined_totals) / len(combined_totals), 1),
        },
        "top_token_fields": top_fields,
        "warnings_seen": list(set(all_warnings)),
        "errors_seen": list(set(all_errors)),
    }
