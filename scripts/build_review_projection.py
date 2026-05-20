#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def now_utc() -> str:
    return datetime.now(timezone.utc).isoformat()


def read_ndjson(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    out: list[dict[str, Any]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return out


def read_latest_json(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None


def pick_latest_advisory(advisory_dir: Path) -> Path | None:
    if not advisory_dir.exists():
        return None
    cands = sorted(advisory_dir.glob("*.json"))
    return cands[-1] if cands else None


def build_projection(repo_root: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    session_index = repo_root / "artifacts" / "session-index.ndjson"
    rows = read_ndjson(session_index)

    total_sessions = len(rows)
    valid_sessions = sum(1 for r in rows if r.get("closeout_status") == "valid")
    missing_sessions = sum(1 for r in rows if r.get("closeout_status") == "missing")
    runtime_completeness = "COMPLETE" if total_sessions and missing_sessions == 0 else ("PARTIAL" if total_sessions else "MISSING")

    latest_advisory_path = pick_latest_advisory(repo_root / "artifacts" / "runtime" / "advisory")
    latest_advisory = read_latest_json(latest_advisory_path) if latest_advisory_path else None
    claim_drift = bool((latest_advisory or {}).get("claim_drift_detected", False))
    authority_override_required = bool((latest_advisory or {}).get("authority_override_required", False))

    integrity_status = "PASS"
    if missing_sessions > 0:
        integrity_status = "PARTIAL"
    if total_sessions == 0:
        integrity_status = "UNKNOWN"

    high_attention_items: list[str] = []
    if missing_sessions > 0:
        high_attention_items.append("runtime_session_missing")
    if claim_drift:
        high_attention_items.append("claim_drift_detected")
    if authority_override_required:
        high_attention_items.append("authority_override_required")

    coverage_complete = latest_advisory is not None
    omitted_categories: list[str] = []
    if not coverage_complete:
        omitted_categories.append("retrieval_authority_advisory")

    claim_signal_epistemic = "OBSERVED" if latest_advisory else "MISSING"
    claim_signal_severity = "medium" if claim_drift else ("high" if claim_signal_epistemic == "MISSING" else "info")

    summary = {
        "schema_version": "0.1",
        "generated_at_utc": now_utc(),
        "advisory_only": True,
        "projection_non_canonical": True,
        "coverage_complete": coverage_complete,
        "omitted_sections_count": len(omitted_categories),
        "omitted_section_categories": omitted_categories,
        "integrity_status": integrity_status,
        "runtime_completeness": runtime_completeness,
        "claim_drift_detected": claim_drift,
        "authority_override_required": authority_override_required,
        "high_attention_items": high_attention_items,
        "signals": [
            {
                "id": "session_total",
                "severity": "info",
                "epistemic_status": "VERIFIED",
                "value": total_sessions,
                "source_artifact": str(session_index.relative_to(repo_root)).replace("\\", "/"),
                "source_path": "rows[*]",
                "evidence_snippet": f"total_sessions={total_sessions}",
            },
            {
                "id": "runtime_missing_sessions",
                "severity": "high" if missing_sessions > 0 else "low",
                "epistemic_status": "VERIFIED",
                "value": missing_sessions,
                "source_artifact": str(session_index.relative_to(repo_root)).replace("\\", "/"),
                "source_path": "rows[*].closeout_status",
                "evidence_snippet": f"missing_sessions={missing_sessions}",
            },
            {
                "id": "runtime_valid_sessions",
                "severity": "low",
                "epistemic_status": "VERIFIED",
                "value": valid_sessions,
                "source_artifact": str(session_index.relative_to(repo_root)).replace("\\", "/"),
                "source_path": "rows[*].closeout_status",
                "evidence_snippet": f"valid_sessions={valid_sessions}",
            },
            {
                "id": "claim_drift_detected",
                "severity": claim_signal_severity,
                "epistemic_status": claim_signal_epistemic,
                "value": claim_drift,
                "note": "Derived from latest runtime advisory when present; when advisory is missing, this signal is non-authoritative and review attention is required.",
                "source_artifact": str(latest_advisory_path.relative_to(repo_root)).replace("\\", "/") if latest_advisory_path else "",
                "source_path": "claim_drift_detected",
                "evidence_snippet": str(claim_drift),
            },
        ],
        "source_artifacts": [
            str(session_index.relative_to(repo_root)).replace("\\", "/"),
            str(latest_advisory_path.relative_to(repo_root)).replace("\\", "/") if latest_advisory_path else "",
        ],
    }

    sections = {
        "schema_version": "0.1",
        "generated_at_utc": now_utc(),
        "advisory_only": True,
        "projection_non_canonical": True,
        "coverage_complete": coverage_complete,
        "omitted_sections_count": len(omitted_categories),
        "omitted_section_categories": omitted_categories,
        "sections": [
            {
                "id": "runtime",
                "title": "Runtime Session Surface",
                "severity": "high" if missing_sessions > 0 else "low",
                "collapsed": False,
                "epistemic_status": "VERIFIED",
                "source_artifact": str(session_index.relative_to(repo_root)).replace("\\", "/"),
                "source_path": "rows[*]",
                "items": [
                    f"total_sessions={total_sessions}",
                    f"valid_sessions={valid_sessions}",
                    f"missing_sessions={missing_sessions}",
                ],
            },
            {
                "id": "retrieval_authority",
                "title": "Retrieval Authority Advisory",
                "severity": "medium" if (claim_drift or authority_override_required) else "info",
                "collapsed": not (claim_drift or authority_override_required),
                "epistemic_status": "OBSERVED" if latest_advisory else "MISSING",
                "source_artifact": str(latest_advisory_path.relative_to(repo_root)).replace("\\", "/") if latest_advisory_path else "",
                "source_path": "root",
                "items": [
                    f"claim_drift_detected={claim_drift}",
                    f"authority_override_required={authority_override_required}",
                ],
            },
        ],
    }

    return summary, sections


def main() -> int:
    parser = argparse.ArgumentParser(description="Build governance review projection artifacts.")
    parser.add_argument("--repo-root", default=".", help="Repository root path")
    parser.add_argument(
        "--out-dir",
        default="artifacts/runtime/review_projection",
        help="Output directory for review projection artifacts",
    )
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    out_dir = (repo_root / args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    summary, sections = build_projection(repo_root)
    (out_dir / "review-summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (out_dir / "review-sections.json").write_text(
        json.dumps(sections, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"WROTE {out_dir / 'review-summary.json'}")
    print(f"WROTE {out_dir / 'review-sections.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
