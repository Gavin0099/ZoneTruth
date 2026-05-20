#!/usr/bin/env python3
"""
plan_summary.py — PLAN.md compressed view (~1,000 tokens)

Generates a compact, agent-readable summary of PLAN.md that contains
only what a session start needs:
  - current phase + gate status
  - open (not-done) sprint items
  - active blockers from Phase E
  - HEAD commit hash
  - backlog open counts (P0/P1/P2)
  - key design decisions (decision table, last 5 entries)

Does NOT include:
  - full G1–G6 sub-sections
  - Phase 2.5 fleet reality assessment detail
  - harness engineering evaluation
  - completed sprint items

Usage:
  python scripts/plan_summary.py
  python scripts/plan_summary.py --plan PLAN.md
  python scripts/plan_summary.py --format json
  python scripts/plan_summary.py --out artifacts/plan-summary.md
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from governance_tools.state_generator import (
    parse_backlog_counts,
    parse_current_phase,
    parse_gate_status,
    parse_header,
    parse_sprint_tasks,
)


# ── helpers ────────────────────────────────────────────────────────────────

def _head_commit(project_root: Path) -> str:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, cwd=project_root, timeout=5,
        )
        return result.stdout.strip() if result.returncode == 0 else "unknown"
    except Exception:
        return "unknown"


def _parse_active_blockers(text: str) -> list[str]:
    """Extract genuinely open (unchecked) lines mentioning blockers from the PLAN."""
    blockers: list[str] = []
    # Only lines starting with - [ ] (unchecked) that mention blocker signals
    for line in text.splitlines():
        stripped = line.strip()
        # must be an open task (not [x])
        if not re.match(r"-\s*\[\s*\]", stripped):
            continue
        if any(marker in stripped for marker in ("❌", "[FAIL]", "Blocker", "NOT_READY", "blocked", "待辦", "未達標")):
            blockers.append(stripped)
    return blockers[:8]


def _parse_open_phase_e_tasks(text: str) -> list[str]:
    """Get not-done [ ] items from Phase E Sprint section."""
    open_tasks: list[str] = []
    in_phase_e_sprint = False
    for line in text.splitlines():
        if re.match(r"^##\s+Phase E Sprint", line):
            in_phase_e_sprint = True
        elif re.match(r"^##\s+", line) and in_phase_e_sprint:
            break
        if in_phase_e_sprint:
            m = re.match(r"\s*-\s*\[\s*\]\s*(.+)", line)
            if m:
                open_tasks.append(m.group(1).strip())
    return open_tasks


def _parse_decision_table_tail(text: str, n: int = 5) -> list[dict]:
    """Extract the last n rows from the decision table."""
    match = re.search(r"##\s*決策紀錄(.*?)(?=\n##|\Z)", text, re.DOTALL)
    if not match:
        return []
    rows: list[dict] = []
    for line in match.group(1).splitlines():
        parts = [p.strip() for p in line.split("|")]
        # markdown table rows have at least 4 parts (empty | date | decision | note | empty)
        if len(parts) >= 4 and parts[1] and not parts[1].startswith("-") and not parts[1].startswith("日"):
            rows.append({"date": parts[1], "decision": parts[2], "note": parts[3]})
    return rows[-n:]


def _parse_sa_layer1_log(text: str) -> list[dict]:
    """Extract the Layer 1 execution log table for SpecAuthority."""
    match = re.search(r"Layer 1 執行紀錄.*?\n(.*?)(?=\n\s*\*\*Layer 1 穩定|\Z)", text, re.DOTALL)
    if not match:
        return []
    rows: list[dict] = []
    for line in match.group(1).splitlines():
        parts = [p.strip() for p in line.split("|")]
        if len(parts) >= 7 and parts[1] and not parts[1].startswith("-") and not parts[1].startswith("次"):
            rows.append({
                "run": parts[1],
                "date": parts[2],
                "session_id": parts[3],
                "artifact_state": parts[5],
                "note": parts[7] if len(parts) > 7 else "",
            })
    return rows


def _parse_sa_layer1_status(text: str) -> str:
    m = re.search(r"\*\*Layer 1 穩定狀態\*\*[：:]\s*(.+)", text)
    return m.group(1).strip() if m else "unknown"


def _parse_phase2_gate_status(text: str) -> list[str]:
    """Extract Phase 2 gate conditions from the G6 five-condition list."""
    # Find the updated gate conditions block (after the lifecycle_active_ratio replacement)
    match = re.search(
        r"Phase 2 readiness gate.*?\*\*五條件\*\*.*?\n((?:\s*-[^\n]+\n){3,8})",
        text, re.DOTALL
    )
    if not match:
        # fallback: find numbered gate lines near 'readiness gate'
        match2 = re.search(r"readiness gate[（(].*?[)）].*?\n((?:.*?\n){1,10})", text, re.DOTALL)
        if not match2:
            return []
        block = match2.group(1)
    else:
        block = match.group(1)
    lines = []
    for line in block.splitlines():
        stripped = line.strip()
        if re.match(r"[-\d]", stripped) and stripped:
            lines.append(stripped)
    return lines[:6]


# ── compression provenance ────────────────────────────────────────────────

# These values are fixed for plan_summary.py output.
# fidelity=summarized: agent sees extracted subset, not full PLAN.md
# origin: which tool produced this view
# summary_kind: deterministic_extract = rule-based extraction, not AI-rewritten narrative
_PLAN_CONTEXT_PROVENANCE: dict = {
    "fidelity": "summarized",
    "origin": "plan_summary.py",
    "summary_kind": "deterministic_extract",
}

# Marker embedded at line 1 of human-format output so session_start.py can
# detect without parsing the full file.
_PROVENANCE_MARKER = (
    "<!-- plan_context_provenance "
    "fidelity=summarized origin=plan_summary.py summary_kind=deterministic_extract -->"
)

_PROVENANCE_SIDECAR_PATH = Path("artifacts") / "runtime" / "plan-context-provenance.json"


# ── main summary builder ───────────────────────────────────────────────────

def build_plan_summary(plan_path: Path, project_root: Path) -> dict:
    text = plan_path.read_text(encoding="utf-8")
    header = parse_header(text)
    phase = parse_current_phase(text)
    gates = parse_gate_status(text)
    sprint = parse_sprint_tasks(text)
    backlogs = parse_backlog_counts(text)

    open_sprint = [t["name"] for t in sprint if not t["done"]]
    open_phase_e = _parse_open_phase_e_tasks(text)
    blockers = _parse_active_blockers(text)
    decisions = _parse_decision_table_tail(text, n=5)
    sa_log = _parse_sa_layer1_log(text)
    sa_status = _parse_sa_layer1_status(text)
    phase2_gate = _parse_phase2_gate_status(text)
    head = _head_commit(project_root)

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "head_commit": head,
        "plan_path": str(plan_path),
        "last_updated": header.get("最後更新") or header.get("last_updated"),
        "owner": header.get("Owner"),
        "current_phase": phase,
        "gate_status": gates,
        "open_sprint_items": open_sprint,
        "open_phase_e_tasks": open_phase_e,
        "active_blockers": blockers,
        "backlog_open": backlogs,
        "sa_layer1_log": sa_log,
        "sa_layer1_stability": sa_status,
        "phase2_gate_conditions": phase2_gate,
        "recent_decisions": decisions,
        # Compression provenance — always present in plan_summary output.
        # Lets session_start and session_end know context was compressed.
        "plan_context_provenance": _PLAN_CONTEXT_PROVENANCE,
    }


def format_human(summary: dict) -> str:
    lines: list[str] = []
    # Provenance marker MUST be line 1 so session_start.py can detect it by
    # reading only the first line of the file (cheap, no full parse needed).
    lines.append(_PROVENANCE_MARKER)
    lines.append("# PLAN.md Compressed View")
    lines.append(f"generated: {summary['generated_at']}  |  HEAD: {summary['head_commit']}")
    lines.append(f"plan: {summary['plan_path']}  |  last_updated: {summary['last_updated']}  |  owner: {summary['owner']}")
    lines.append("")

    # Phase + gates
    phase = summary["current_phase"]
    lines.append(f"## Current Phase: {phase.get('id')} — {phase.get('name')}")
    gate_lines = [f"  {'[x]' if v == 'passed' else '[>]' if v == 'in_progress' else '[ ]'} {k}: {v}"
                  for k, v in summary["gate_status"].items()]
    lines.extend(gate_lines)
    lines.append("")

    # Open sprint
    if summary["open_sprint_items"]:
        lines.append("## Open Sprint Items")
        for item in summary["open_sprint_items"]:
            lines.append(f"  - [ ] {item}")
        lines.append("")

    # Open Phase E tasks
    if summary["open_phase_e_tasks"]:
        lines.append("## Open Phase E Tasks")
        for item in summary["open_phase_e_tasks"]:
            lines.append(f"  - [ ] {item}")
        lines.append("")

    # Active blockers
    if summary["active_blockers"]:
        lines.append("## Active Blockers")
        for b in summary["active_blockers"]:
            lines.append(f"  {b}")
        lines.append("")

    # Backlog counts
    bl = summary["backlog_open"]
    lines.append(f"## Backlog Open: P0={bl.get('P0',0)}  P1={bl.get('P1',0)}  P2={bl.get('P2',0)}")
    lines.append("")

    # SA Layer 1 status
    lines.append(f"## SpecAuthority Layer 1: {summary['sa_layer1_stability']}")
    if summary["sa_layer1_log"]:
        lines.append("  Execution log:")
        for row in summary["sa_layer1_log"]:
            lines.append(f"    {row['run']} | {row['date']} | {row['session_id']} | artifact_state={row['artifact_state']}")
    lines.append("")

    # Phase 2 gate
    if summary["phase2_gate_conditions"]:
        lines.append("## Phase 2 Gate Conditions")
        for c in summary["phase2_gate_conditions"]:
            lines.append(f"  {c}")
        lines.append("")

    # Recent decisions
    if summary["recent_decisions"]:
        lines.append("## Recent Decisions (last 5)")
        for d in summary["recent_decisions"]:
            lines.append(f"  {d['date']} | {d['decision']}")
        lines.append("")

    return "\n".join(lines)


# ── CLI ────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="PLAN.md compressed view (~1,000 tokens)")
    parser.add_argument("--plan", default="PLAN.md", help="Path to PLAN.md")
    parser.add_argument("--format", choices=["human", "json"], default="human")
    parser.add_argument("--out", help="Write output to file instead of stdout")
    args = parser.parse_args()

    plan_path = Path(args.plan)
    if not plan_path.exists():
        print(f"[plan_summary] ERROR: {plan_path} not found", file=sys.stderr)
        sys.exit(1)

    project_root = plan_path.parent.resolve()
    summary = build_plan_summary(plan_path, project_root)

    if args.format == "json":
        output = json.dumps(summary, ensure_ascii=False, indent=2)
    else:
        output = format_human(summary)

    if args.out:
        Path(args.out).write_text(output, encoding="utf-8")
        print(f"[plan_summary] wrote {args.out}")
    else:
        print(output)

    # Always write provenance sidecar so session_end_hook can read it
    # even when plan_summary output goes to stdout (not to a file).
    sidecar_path = project_root / _PROVENANCE_SIDECAR_PATH
    try:
        sidecar_path.parent.mkdir(parents=True, exist_ok=True)
        sidecar_path.write_text(
            json.dumps(_PLAN_CONTEXT_PROVENANCE, ensure_ascii=False),
            encoding="utf-8",
        )
    except OSError:
        pass  # Non-blocking: sidecar write failure must not abort summary output


if __name__ == "__main__":
    main()
