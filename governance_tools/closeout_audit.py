#!/usr/bin/env python3
"""
Read canonical closeout artifacts and report aggregate closeout health.

Reads from ``artifacts/runtime/closeouts/`` ONLY (canonical artifacts).
Does NOT read closeout_candidates/ or session-index.ndjson.
Does NOT derive new closeout_status values or extend the controlled taxonomy.

Output: aggregation, counts, trends, reviewer summaries.
See docs/closeout-schema.md — Downstream Consumer Rules for authority contract.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from governance_tools.human_summary import build_summary_line

# Controlled closeout_status taxonomy (mirrors closeout-schema.md).
# Do not extend here — extend _canonical_closeout._VALID_STATUSES and the schema doc.
_KNOWN_STATUSES = frozenset(
    {"valid", "missing", "schema_invalid", "content_insufficient", "inconsistent"}
)

# valid_rate below this threshold triggers a quality_review policy flag.
# Drift signal, not hard invariant. A low rate means /wrap-up is not being
# used effectively or candidates are consistently failing validation.
_VALID_RATE_REVIEW_THRESHOLD = 0.50  # 50% of sessions should be valid

# Window for recent_7d_valid_rate calculation.
_RECENT_DAYS = 7

_GENERATED_JSON = Path("docs/status/generated/closeout-audit.json")
_GENERATED_MD = Path("docs/status/closeout-audit.md")


def build_closeout_audit(project_root: Path) -> dict[str, Any]:
    """
    Scan ``artifacts/runtime/closeouts/`` under *project_root* and return
    aggregate closeout health statistics across all recorded sessions.

    Trust boundary: reads canonical closeouts only. Never reads candidates or index.

    Returns a dict with:
    - ok: True (always — never raises; unreadable files are counted separately)
    - session_count: total canonical closeouts read
    - status_distribution: {status_value: count, ...}
    - valid_count / missing_count / content_insufficient_count /
      inconsistent_count / schema_invalid_count: convenience aliases
    - valid_rate: float | None (None if no sessions)
    - recent_7d_valid_rate: float | None (valid rate for last 7 days; None if no recent sessions)
    - has_open_risks_count: sessions with at least one open_risk
    - unknown_statuses: [status_value, ...] values not in controlled taxonomy
    - policy_flags: {
        "quality_review": bool,    — valid_rate below threshold (drift signal)
        "schema_drift": bool,      — any schema_invalid sessions present
        "taxonomy_breach": bool,   — unknown closeout_status values detected
      }
    - policy_ok: bool — True iff no policy_flags are raised
    - unreadable_files: [path_str, ...] files that could not be parsed
    """
    closeouts_dir = project_root / "artifacts" / "runtime" / "closeouts"

    sessions: list[dict[str, Any]] = []
    unreadable: list[str] = []

    if closeouts_dir.exists():
        for path in sorted(closeouts_dir.glob("*.json")):
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
                sessions.append({
                    "session_id": data.get("session_id"),
                    "closed_at": data.get("closed_at") or "",
                    "closeout_status": data.get("closeout_status"),
                    "has_open_risks": bool(data.get("open_risks")),
                })
            except Exception:
                unreadable.append(str(path))

    total = len(sessions)
    now_utc = datetime.now(timezone.utc)
    recent_cutoff = now_utc - timedelta(days=_RECENT_DAYS)

    # Status distribution
    status_counts: dict[str, int] = {}
    for s in sessions:
        st = s.get("closeout_status") or "unknown"
        status_counts[st] = status_counts.get(st, 0) + 1

    # Convenience aliases
    valid_count = status_counts.get("valid", 0)
    missing_count = status_counts.get("missing", 0)
    content_insufficient_count = status_counts.get("content_insufficient", 0)
    inconsistent_count = status_counts.get("inconsistent", 0)
    schema_invalid_count = status_counts.get("schema_invalid", 0)

    valid_rate = round(valid_count / total, 3) if total > 0 else None

    # Recent sessions: filter by closed_at within last 7 days
    recent_sessions = []
    for s in sessions:
        ca = s.get("closed_at", "")
        if not ca:
            continue
        try:
            dt = datetime.fromisoformat(ca)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            if dt >= recent_cutoff:
                recent_sessions.append(s)
        except Exception:
            pass

    recent_total = len(recent_sessions)
    recent_valid = sum(1 for s in recent_sessions if s.get("closeout_status") == "valid")
    recent_7d_valid_rate = round(recent_valid / recent_total, 3) if recent_total > 0 else None

    has_open_risks_count = sum(1 for s in sessions if s.get("has_open_risks"))
    unknown_statuses = sorted(s for s in status_counts if s not in _KNOWN_STATUSES)

    # Policy flags: aggregation-only. No new closeout_status judgments.
    policy_flags = {
        "quality_review": (
            valid_rate is not None and valid_rate < _VALID_RATE_REVIEW_THRESHOLD
        ),
        "schema_drift": schema_invalid_count > 0,
        "taxonomy_breach": len(unknown_statuses) > 0,
    }
    policy_ok = not any(policy_flags.values())

    return {
        "ok": True,
        "policy_ok": policy_ok,
        "project_root": str(project_root),
        "closeouts_dir": str(closeouts_dir),
        "session_count": total,
        "status_distribution": status_counts,
        "valid_count": valid_count,
        "missing_count": missing_count,
        "content_insufficient_count": content_insufficient_count,
        "inconsistent_count": inconsistent_count,
        "schema_invalid_count": schema_invalid_count,
        "valid_rate": valid_rate,
        "recent_7d_session_count": recent_total,
        "recent_7d_valid_rate": recent_7d_valid_rate,
        "has_open_risks_count": has_open_risks_count,
        "unknown_statuses": unknown_statuses,
        "policy_flags": policy_flags,
        "unreadable_files": unreadable,
    }


def format_human_result(result: dict[str, Any]) -> str:
    total = result["session_count"]
    valid_rate = result.get("valid_rate")
    recent_rate = result.get("recent_7d_valid_rate")
    policy_flags = result.get("policy_flags") or {}
    policy_ok = result.get("policy_ok", True)
    status_dist = result.get("status_distribution") or {}

    summary_line = build_summary_line(
        f"ok={result['ok']}",
        f"policy_ok={policy_ok}",
        f"sessions={total}",
        f"valid={result['valid_count']}",
        f"missing={result['missing_count']}",
        f"insufficient={result['content_insufficient_count']}",
        f"inconsistent={result['inconsistent_count']}",
        f"schema_invalid={result['schema_invalid_count']}",
    )

    lines = [
        "[closeout_audit]",
        summary_line,
        f"project_root={result['project_root']}",
        f"closeouts_dir={result['closeouts_dir']}",
        f"session_count={total}",
        f"valid_rate={valid_rate}",
        f"recent_7d_session_count={result['recent_7d_session_count']}",
        f"recent_7d_valid_rate={recent_rate}",
        f"has_open_risks_count={result['has_open_risks_count']}",
    ]

    # Policy flags: show even when all False for reviewer confirmation
    lines.append("[policy_flags]")
    lines.append(
        f"  quality_review={policy_flags.get('quality_review', False)}"
        f"  # drift signal: valid_rate < {_VALID_RATE_REVIEW_THRESHOLD}"
    )
    lines.append(
        f"  schema_drift={policy_flags.get('schema_drift', False)}"
        "  # schema drift: any schema_invalid sessions present"
    )
    lines.append(
        f"  taxonomy_breach={policy_flags.get('taxonomy_breach', False)}"
        "  # unknown closeout_status values detected"
    )

    if status_dist:
        lines.append("[status_distribution]")
        for status, count in sorted(status_dist.items(), key=lambda kv: -kv[1]):
            lines.append(f"  {status}={count}")
    else:
        lines.append("[status_distribution] (none)")

    if result.get("unknown_statuses"):
        lines.append(f"unknown_statuses={','.join(result['unknown_statuses'])}")

    if result.get("unreadable_files"):
        for path in result["unreadable_files"]:
            lines.append(f"unreadable={path}")

    return "\n".join(lines)


def build_status_markdown(result: dict[str, Any]) -> str:
    generated_at = result.get("generated_at")
    lines = [
        "# Closeout Audit",
        "",
        f"- generated_at: `{generated_at}`" if generated_at else "- generated_at: `(not recorded)`",
        f"- project_root: `{result['project_root']}`",
        f"- signal_posture: `aggregation-only`",
        "",
        "## Summary",
        "",
        f"- session_count: `{result['session_count']}`",
        f"- valid_rate: `{result['valid_rate']}`",
        f"- recent_7d_session_count: `{result['recent_7d_session_count']}`",
        f"- recent_7d_valid_rate: `{result['recent_7d_valid_rate']}`",
        f"- has_open_risks_count: `{result['has_open_risks_count']}`",
        "",
        "## Policy Flags",
        "",
        f"- quality_review: `{result['policy_flags']['quality_review']}`",
        f"- schema_drift: `{result['policy_flags']['schema_drift']}`",
        f"- taxonomy_breach: `{result['policy_flags']['taxonomy_breach']}`",
        "",
        "## Status Distribution",
        "",
    ]

    status_dist = result.get("status_distribution") or {}
    if status_dist:
        lines.extend([
            "| Status | Count |",
            "|---|---|",
        ])
        for status, count in sorted(status_dist.items(), key=lambda kv: (-kv[1], kv[0])):
            lines.append(f"| `{status}` | `{count}` |")
    else:
        lines.append("- `(none)`")

    unknown_statuses = result.get("unknown_statuses") or []
    if unknown_statuses:
        lines.extend([
            "",
            "## Unknown Statuses",
            "",
            f"- `{', '.join(unknown_statuses)}`",
        ])

    unreadable_files = result.get("unreadable_files") or []
    if unreadable_files:
        lines.extend([
            "",
            "## Unreadable Files",
            "",
        ])
        for path in unreadable_files:
            lines.append(f"- `{path}`")

    return "\n".join(lines) + "\n"


def write_status_outputs(project_root: Path, result: dict[str, Any]) -> dict[str, str]:
    json_path = project_root / _GENERATED_JSON
    md_path = project_root / _GENERATED_MD
    json_path.parent.mkdir(parents=True, exist_ok=True)
    md_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    md_path.write_text(build_status_markdown(result), encoding="utf-8")
    return {
        "json": str(json_path),
        "markdown": str(md_path),
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Report canonical closeout health across session artifacts."
    )
    parser.add_argument("--project-root", default=".")
    parser.add_argument("--format", choices=("human", "json"), default="human")
    parser.add_argument("--write", action="store_true", help="Write status outputs under docs/status/")
    args = parser.parse_args()

    project_root = Path(args.project_root).resolve()
    result = build_closeout_audit(project_root)
    result["generated_at"] = datetime.now(timezone.utc).isoformat()

    if args.write:
        result["written_outputs"] = write_status_outputs(project_root, result)

    if args.format == "json":
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(format_human_result(result))
        if args.write:
            print(f"written_json={result['written_outputs']['json']}")
            print(f"written_markdown={result['written_outputs']['markdown']}")

    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
