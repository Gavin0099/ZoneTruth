#!/usr/bin/env python3
"""Warning-only detector for manual-promotion runtime ledgers.

This tool detects whether tracked runtime ledgers that are manual-promotion-only
have local changes. It does not modify files, stage files, restore files, or
change hook behavior.
"""

from __future__ import annotations

import argparse
import json
import subprocess
from dataclasses import dataclass
from pathlib import Path


MANUAL_PROMOTION_LEDGERS = (
    "artifacts/claim-enforcement/claim-enforcement-receipts.ndjson",
    "artifacts/session-index.ndjson",
)


@dataclass(frozen=True)
class LedgerStatus:
    path: str
    git_status: str
    staged: bool
    unstaged: bool
    untracked: bool


@dataclass(frozen=True)
class DirtyLedgerResult:
    ok: bool
    mode: str
    dirty_count: int
    ledgers: list[LedgerStatus]
    policy: str
    claim_boundary: str


def _normalize_path(path: str) -> str:
    return path.replace("\\", "/").strip()


def parse_porcelain_status(lines: list[str]) -> list[LedgerStatus]:
    """Parse git porcelain v1 lines for manual-promotion ledgers."""
    targets = set(MANUAL_PROMOTION_LEDGERS)
    results: list[LedgerStatus] = []
    for raw in lines:
        if not raw:
            continue
        status = raw[:2]
        raw_path = raw[3:] if len(raw) > 3 else ""
        # Rename lines are "R  old -> new"; the new path is the relevant one.
        if " -> " in raw_path:
            raw_path = raw_path.split(" -> ", 1)[1]
        path = _normalize_path(raw_path)
        if path not in targets:
            continue
        staged_code = status[0]
        unstaged_code = status[1]
        results.append(
            LedgerStatus(
                path=path,
                git_status=status,
                staged=staged_code not in {" ", "?"},
                unstaged=unstaged_code not in {" ", "?"},
                untracked=status == "??",
            )
        )
    return results


def _git_status(project_root: Path) -> list[str]:
    cmd = [
        "git",
        "-C",
        str(project_root),
        "status",
        "--porcelain=v1",
        "--",
        *MANUAL_PROMOTION_LEDGERS,
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, check=True)
    return [line for line in proc.stdout.splitlines() if line.strip()]


def inspect_ledgers(project_root: Path, *, fail_on_dirty: bool = False) -> DirtyLedgerResult:
    statuses = parse_porcelain_status(_git_status(project_root))
    dirty_count = len(statuses)
    return DirtyLedgerResult(
        ok=(dirty_count == 0 or not fail_on_dirty),
        mode="fail_on_dirty" if fail_on_dirty else "warning_only",
        dirty_count=dirty_count,
        ledgers=statuses,
        policy="manual_promotion_only",
        claim_boundary=(
            "Dirty manual-promotion runtime ledgers must be restored, staged under an "
            "explicit evidence-capture scope, or explicitly included before claiming a clean workspace."
        ),
    )


def format_json(result: DirtyLedgerResult) -> str:
    return json.dumps(
        {
            "ok": result.ok,
            "mode": result.mode,
            "dirty_count": result.dirty_count,
            "policy": result.policy,
            "claim_boundary": result.claim_boundary,
            "ledgers": [
                {
                    "path": item.path,
                    "git_status": item.git_status,
                    "staged": item.staged,
                    "unstaged": item.unstaged,
                    "untracked": item.untracked,
                }
                for item in result.ledgers
            ],
        },
        ensure_ascii=False,
        indent=2,
    )


def format_human(result: DirtyLedgerResult) -> str:
    lines = [
        "[dirty_runtime_ledger_detector]",
        f"ok={str(result.ok).lower()}",
        f"mode={result.mode}",
        f"policy={result.policy}",
        f"dirty_count={result.dirty_count}",
    ]
    if result.ledgers:
        lines.append("[manual_promotion_ledgers]")
        for item in result.ledgers:
            state: list[str] = []
            if item.staged:
                state.append("staged")
            if item.unstaged:
                state.append("unstaged")
            if item.untracked:
                state.append("untracked")
            state_text = ",".join(state) if state else "unknown"
            lines.append(f"- {item.path} status={item.git_status!r} state={state_text}")
        lines.append("[required_next_action]")
        lines.append("- restore, stage under explicit evidence-capture scope, or explicitly include in current scope")
    else:
        lines.append("[manual_promotion_ledgers]")
        lines.append("- clean")
    lines.append("[claim_boundary]")
    lines.append(result.claim_boundary)
    return "\n".join(lines)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Detect dirty manual-promotion runtime ledgers without modifying files."
    )
    parser.add_argument("--project-root", default=".", help="Repository root to inspect.")
    parser.add_argument("--format", choices=("human", "json"), default="human")
    parser.add_argument(
        "--fail-on-dirty",
        action="store_true",
        help="Return non-zero when manual-promotion ledgers are dirty. Default is warning-only.",
    )
    return parser


def main() -> int:
    args = build_parser().parse_args()
    result = inspect_ledgers(Path(args.project_root), fail_on_dirty=args.fail_on_dirty)
    print(format_json(result) if args.format == "json" else format_human(result))
    return 0 if result.ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
