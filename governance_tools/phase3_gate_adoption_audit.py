#!/usr/bin/env python3
"""
Repo-level adoption audit for Phase 3 promotion gate.

Goal:
- Detect parallel/legacy promotion paths outside canonical gate modules
- Provide a deterministic check that promotion logic stays centralized
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

_SCOPES = ("governance_tools", "scripts")
_WORKFLOW_SCOPE = ".github/workflows"
_DOC_SCOPE = "docs"

_ALLOW_CLOSURE_VERIFIED = {
    "governance_tools/phase2_aggregation_consumer.py",
    "governance_tools/phase3_promotion_gate.py",
    "governance_tools/phase3_gate_adoption_audit.py",
    "governance_tools/external_observation_adapter.py",
    "governance_tools/enumd_observe_only_probe.py",
    "scripts/phase2_aggregation_dry_run.py",
}

_ALLOW_PHASE3_ENTRY_ALLOWED = {
    "governance_tools/phase3_promotion_gate.py",
    "governance_tools/phase3_gate_adoption_audit.py",
    "governance_tools/external_observation_adapter.py",
    "governance_tools/enumd_observe_only_probe.py",
}

_ALLOW_PARALLEL_DECISION_SCAN = {
    "governance_tools/phase3_promotion_gate.py",
    "governance_tools/phase3_gate_adoption_audit.py",
    "governance_tools/external_observation_adapter.py",
    "governance_tools/enumd_observe_only_probe.py",
    "scripts/phase2_aggregation_dry_run.py",
}


def _iter_python_files(repo_root: Path) -> list[Path]:
    out: list[Path] = []
    for scope in _SCOPES:
        base = repo_root / scope
        if not base.exists():
            continue
        out.extend(sorted(base.rglob("*.py")))
    return out


def _iter_text_files(repo_root: Path, base: str, pattern: str) -> list[Path]:
    root = repo_root / base
    if not root.exists():
        return []
    return sorted(root.rglob(pattern))


def _read_text_fallback(path: Path) -> str:
    for enc in ("utf-8", "cp950", "latin-1"):
        try:
            return path.read_text(encoding=enc)
        except UnicodeDecodeError:
            continue
    # Last resort: replace undecodable bytes.
    return path.read_text(encoding="utf-8", errors="replace")


def audit_phase3_gate_adoption(repo_root: Path) -> dict[str, Any]:
    files = _iter_python_files(repo_root)
    workflow_files = _iter_text_files(repo_root, _WORKFLOW_SCOPE, "*.yml")
    doc_files = _iter_text_files(repo_root, _DOC_SCOPE, "*.md")
    violations: list[dict[str, str]] = []

    for fpath in files:
        rel = fpath.relative_to(repo_root).as_posix()
        text = fpath.read_text(encoding="utf-8")

        if "closure_verified" in text and rel not in _ALLOW_CLOSURE_VERIFIED:
            violations.append(
                {
                    "path": rel,
                    "rule": "closure_verified_outside_canonical_modules",
                    "detail": "closure_verified token found in non-allowlisted module",
                }
            )

        if "phase3_entry_allowed" in text and rel not in _ALLOW_PHASE3_ENTRY_ALLOWED:
            violations.append(
                {
                    "path": rel,
                    "rule": "phase3_entry_allowed_defined_outside_gate",
                    "detail": "phase3_entry_allowed should be produced only by phase3_promotion_gate.py",
                }
            )

        # Detect potential parallel phase3 decision logic:
        # a module referencing both core decision keys plus promotion terms.
        if rel not in _ALLOW_PARALLEL_DECISION_SCAN:
            has_core_keys = ("current_state" in text) and ("promote_eligible" in text)
            has_promotion_terms = ("phase3" in text.lower()) or ("promotion" in text.lower())
            if has_core_keys and has_promotion_terms:
                violations.append(
                    {
                        "path": rel,
                        "rule": "potential_parallel_phase3_decision_logic",
                        "detail": (
                            "module references current_state/promote_eligible with phase3/promotion "
                            "terms outside canonical gate"
                        ),
                    }
                )

    # Workflow-level adoption proof:
    # if workflow references phase3 promotion authority terms, it must route via canonical gate module.
    for wf in workflow_files:
        rel = wf.relative_to(repo_root).as_posix()
        text = _read_text_fallback(wf)
        mentions_phase3_terms = any(
            token in text for token in ("phase3_entry_allowed", "promote_eligible", "closure_verified")
        )
        if mentions_phase3_terms and "phase3_promotion_gate.py" not in text:
            violations.append(
                {
                    "path": rel,
                    "rule": "workflow_phase3_terms_without_canonical_gate",
                    "detail": "workflow references phase3 promotion terms but does not route via phase3_promotion_gate.py",
                }
            )

    # Docs-level bypass check for explicit manual bypass instructions.
    _BYPASS_PATTERNS = (
        "skip phase3 gate",
        "bypass phase3 gate",
        "manual promote override",
        "direct promote without gate",
    )
    for doc in doc_files:
        rel = doc.relative_to(repo_root).as_posix()
        lower = _read_text_fallback(doc).lower()
        for pat in _BYPASS_PATTERNS:
            if pat in lower:
                violations.append(
                    {
                        "path": rel,
                        "rule": "doc_mentions_promotion_bypass",
                        "detail": f"documentation contains bypass phrase: {pat!r}",
                    }
                )

    return {
        "ok": len(violations) == 0,
        "checked_files": len(files),
        "checked_workflows": len(workflow_files),
        "checked_docs": len(doc_files),
        "violations": violations,
        "policy_source": "phase3_gate_adoption_audit.v1",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit Phase 3 promotion gate adoption consistency.")
    parser.add_argument("--project-root", default=".", help="Repository root")
    parser.add_argument("--format", choices=("human", "json"), default="human")
    args = parser.parse_args()

    result = audit_phase3_gate_adoption(Path(args.project_root).resolve())
    if args.format == "json":
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print("[phase3_gate_adoption_audit]")
        print(f"ok={result['ok']}")
        print(f"checked_files={result['checked_files']}")
        if result["violations"]:
            for v in result["violations"]:
                print(f"  [VIOLATION] {v['rule']} {v['path']}: {v['detail']}")
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
