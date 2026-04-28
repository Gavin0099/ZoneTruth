"""
expansion_boundary_checker.py

Passive audit tool. Detects signs that the runtime boundary has been crossed
without going through the Expansion Admission Gate.

This is NOT a runtime hook. It does not run during sessions. It does not
affect ok, task_level, risk, or oversight. It is a standalone CLI tool.

Run it as part of CI or manually:
    python -m governance_tools.expansion_boundary_checker

Returns exit code 0 if no violations found, 1 if violations found.
"""

from __future__ import annotations

import ast
import sys
from pathlib import Path
from typing import NamedTuple

# The three core runtime files that must not expand without gate passage.
CORE_HOOKS = [
    "runtime_hooks/core/session_start.py",
    "runtime_hooks/core/pre_task_check.py",
    "runtime_hooks/core/post_task_check.py",
]

# Imports that are explicitly known to be boundary violations if they appear
# in any of the core hooks. Add to this list when a case is rejected.
BOUNDARY_VIOLATING_IMPORTS = [
    "workflow_entry_observer",   # rejected 2026-03-30, see expansion-cases/entry-layer-rejected.md
]

# Keys that are known decision outputs. Any new key in the return dict of a
# core hook that is NOT in this set is flagged for review.
KNOWN_SESSION_START_KEYS = {
    # decision outputs
    "ok",
    "task_level",
    # informational — established before 2026-03-30 baseline
    "architecture_impact_preview",
    "authority_filter",
    "change_proposal",
    "context_aware_rules",
    "contract_resolution",
    "domain_contract",
    "domain_skip_reason",
    "level_decision",
    "pre_task_check",
    "project_root",
    "proposal_guidance",
    "proposal_summary",
    "repo_type",
    "resolved_contract_file",
    "risk_signal",
    "rule_pack_suggestions",
    "runtime_contract",
    "state",
    "suggested_agent",
    "suggested_rules_preview",
    "suggested_skills",
    "task_text",
    "validator_preflight",
    # governance strategy classification admitted 6048f9f / governance-strategy-runtime
    "governance_classification",
    # canonical closeout context injection admitted 2026-04-08 / session-workflow-enhancement
    # Slice 5: reads prior-session canonical closeout for continuity context.
    # Informational only — does not affect ok, task_level, risk, or oversight.
    "closeout_context",
    # plan context provenance admitted 2026-04-15 / plan-summary-compression
    # _detect_plan_context_provenance() returns fidelity/origin/summary_kind;
    # plan_context_provenance carries the whole provenance dict.
    # Informational only — does not affect ok, task_level, risk, or oversight.
    "plan_context_provenance",
    "fidelity",
    "origin",
    "summary_kind",
}

# pre_task_check spreads **active_rules_result so many keys are not literal in
# the return dict. Only the three literal keys are detectable by AST heuristic.
KNOWN_PRE_TASK_KEYS = {
    "active_rules",
    "content_stripped",
    "content_tier",
    # DBL first-slice output admitted into pre_task surface
    "decision_boundary",
    # _evaluate_preconditions() helper returns these keys and the current
    # AST heuristic scans all return-dict literals in the file, not only the
    # top-level run_pre_task_check() result.
    "boundary_effect",
    "preconditions_checked",
    # runtime injection snapshot slice admitted a9af544 / 2babeaf / 6f0dd34
    # _evaluate_runtime_injection_snapshot() returns these; AST scans helpers
    "effect",
    "observations",
    "signals_checked",
    "snapshot",
}

KNOWN_POST_TASK_KEYS = {
    # decision output
    "ok",
    # informational — established before 2026-03-30 baseline
    "checks",
    "compliant",
    "contract_found",
    "contract_resolution",
    "domain_contract",
    "domain_hard_stop_rules",
    "domain_validator_results",
    "driver_evidence",
    "errors",
    "evidence_violations",
    "failure_completeness",
    "fields",
    "memory_mode",
    "policy_violations",
    "public_api_diff",
    "refactor_evidence",
    "resolved_contract_file",
    "rule_packs",
    "rules",
    "snapshot",
    "warnings",
}

KNOWN_KEYS_BY_HOOK = {
    "session_start.py": KNOWN_SESSION_START_KEYS,
    "pre_task_check.py": KNOWN_PRE_TASK_KEYS,
    "post_task_check.py": KNOWN_POST_TASK_KEYS,
}


class Violation(NamedTuple):
    file: str
    kind: str
    detail: str


def _find_project_root() -> Path:
    here = Path(__file__).resolve().parent
    root = here.parent
    return root


def _check_boundary_violating_imports(path: Path, source: str) -> list[Violation]:
    violations = []
    try:
        tree = ast.parse(source, filename=str(path))
    except SyntaxError:
        return violations

    for node in ast.walk(tree):
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            module = ""
            if isinstance(node, ast.Import):
                for alias in node.names:
                    module = alias.name
                    for banned in BOUNDARY_VIOLATING_IMPORTS:
                        if banned in module:
                            violations.append(Violation(
                                file=str(path),
                                kind="banned_import",
                                detail=f"import of '{module}' is a known boundary violation "
                                       f"('{banned}' rejected by Expansion Admission Gate)",
                            ))
            elif isinstance(node, ast.ImportFrom):
                module = node.module or ""
                for alias in node.names:
                    name = alias.name
                    for banned in BOUNDARY_VIOLATING_IMPORTS:
                        if banned in module or banned in name:
                            violations.append(Violation(
                                file=str(path),
                                kind="banned_import",
                                detail=f"import of '{banned}' from '{module}' is a known boundary violation "
                                       f"(rejected by Expansion Admission Gate)",
                            ))
    return violations


def _extract_return_dict_keys(path: Path, source: str) -> set[str]:
    """
    Heuristic: find string literal keys used in dict literals that appear in
    return statements. Not exhaustive — catches the common pattern where the
    return value is a dict literal or a dict built with string keys.
    """
    keys: set[str] = set()
    try:
        tree = ast.parse(source, filename=str(path))
    except SyntaxError:
        return keys

    for node in ast.walk(tree):
        if isinstance(node, ast.Return) and node.value is not None:
            # Direct dict literal: return {"key": value, ...}
            if isinstance(node.value, ast.Dict):
                for k in node.value.keys:
                    if isinstance(k, ast.Constant) and isinstance(k.value, str):
                        keys.add(k.value)
    return keys


def _check_new_return_keys(path: Path, source: str) -> list[Violation]:
    hook_name = path.name
    known = KNOWN_KEYS_BY_HOOK.get(hook_name)
    if known is None:
        return []

    found = _extract_return_dict_keys(path, source)
    new_keys = found - known
    if not new_keys:
        return []

    return [Violation(
        file=str(path),
        kind="new_return_key",
        detail=f"unrecognized key(s) in return dict: {sorted(new_keys)} — "
               f"if these are new decision inputs, they require Expansion Admission Gate passage",
    )]


def run_checks(project_root: Path | None = None) -> list[Violation]:
    if project_root is None:
        project_root = _find_project_root()

    all_violations: list[Violation] = []

    for rel_path in CORE_HOOKS:
        full_path = project_root / rel_path
        if not full_path.exists():
            continue
        source = full_path.read_text(encoding="utf-8")
        all_violations.extend(_check_boundary_violating_imports(full_path, source))
        all_violations.extend(_check_new_return_keys(full_path, source))

    return all_violations


def main() -> int:
    project_root = _find_project_root()
    violations = run_checks(project_root)

    if not violations:
        print("expansion_boundary_checker: no violations found")
        return 0

    print(f"expansion_boundary_checker: {len(violations)} violation(s) found\n")
    for v in violations:
        print(f"  [{v.kind}] {v.file}")
        print(f"    {v.detail}")
        print()

    print("These may indicate that a runtime expansion bypassed the Expansion Admission Gate.")
    print("See: docs/expansion-admission-gate.md")
    return 1


if __name__ == "__main__":
    sys.exit(main())
