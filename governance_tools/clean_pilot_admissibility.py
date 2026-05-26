#!/usr/bin/env python3
"""
Evaluate whether a repo is admissible for "clean verified pilot" using the
fleet cleaning admissibility policy.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml


@dataclass
class DirtyEntry:
    status: str
    path: str


def _run_git_status(repo: Path) -> list[DirtyEntry]:
    cmd = ["git", "status", "--short", "--untracked-files=all"]
    out = subprocess.run(cmd, cwd=str(repo), capture_output=True, text=True, check=False)
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip() or "git status failed")

    rows: list[DirtyEntry] = []
    for line in out.stdout.splitlines():
        if not line.strip():
            continue
        status = line[:2]
        raw_path = line[3:] if len(line) > 3 else ""
        # Normalize Windows path separators for glob matching.
        norm_path = raw_path.replace("\\", "/")
        rows.append(DirtyEntry(status=status, path=norm_path))
    return rows


def _match_any(path: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatch(path, pat) for pat in patterns)


def evaluate_repo(repo: Path, policy: dict[str, Any]) -> dict[str, Any]:
    repo = repo.resolve()
    dirty = _run_git_status(repo)

    global_cfg = policy.get("global", {})
    repo_cfg = (policy.get("repos", {}) or {}).get(str(repo), {})

    safe_patterns = list(global_cfg.get("generated_safe_to_clean", [])) + list(
        repo_cfg.get("generated_safe_to_clean", [])
    )
    never_patterns = list(global_cfg.get("never_auto_clean", [])) + list(
        repo_cfg.get("never_auto_clean", [])
    )

    never_hits: list[str] = []
    unknown_hits: list[str] = []
    safe_hits: list[str] = []

    for entry in dirty:
        path = entry.path
        if _match_any(path, never_patterns):
            never_hits.append(path)
            continue
        if _match_any(path, safe_patterns):
            safe_hits.append(path)
            continue
        unknown_hits.append(path)

    manual_reasons = list(repo_cfg.get("requires_manual_review", []))
    global_manual = list(global_cfg.get("requires_manual_review", []))
    manual_triggered = bool(never_hits or unknown_hits)

    admissible = (
        len(dirty) > 0
        and not never_hits
        and not unknown_hits
        and not manual_triggered
        and not manual_reasons
    )

    return {
        "repo": str(repo),
        "dirty_count": len(dirty),
        "clean_pilot_admissible": admissible,
        "safe_dirty_paths": safe_hits,
        "never_auto_clean_hits": never_hits,
        "unclassified_dirty_paths": unknown_hits,
        "manual_review_reasons_repo": manual_reasons,
        "manual_review_reasons_global": global_manual,
    }


def _format_human(result: dict[str, Any]) -> str:
    lines = [
        "[clean_pilot_admissibility]",
        f"repo={result['repo']}",
        f"dirty_count={result['dirty_count']}",
        f"clean_pilot_admissible={result['clean_pilot_admissible']}",
    ]
    if result["never_auto_clean_hits"]:
        lines.append(f"never_auto_clean_hits={len(result['never_auto_clean_hits'])}")
    if result["unclassified_dirty_paths"]:
        lines.append(f"unclassified_dirty_paths={len(result['unclassified_dirty_paths'])}")
    if result["manual_review_reasons_repo"]:
        lines.append("manual_review_reasons_repo=" + " | ".join(result["manual_review_reasons_repo"]))
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe clean-pilot admissibility from dirty set + policy.")
    parser.add_argument("--repo", required=True, help="Target repository path.")
    parser.add_argument(
        "--policy",
        default="governance/fleet/cleaning_admissibility_policy.yaml",
        help="Path to cleaning admissibility policy YAML.",
    )
    parser.add_argument("--format", choices=("human", "json"), default="human")
    args = parser.parse_args()

    policy_path = Path(args.policy).resolve()
    policy = yaml.safe_load(policy_path.read_text(encoding="utf-8"))
    result = evaluate_repo(Path(args.repo), policy)
    if args.format == "json":
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(_format_human(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
