#!/usr/bin/env python3
"""
Cross-platform AI Governance hook installer.

This is the Python equivalent of the hook deployment portion of
scripts/install-hooks.sh. It is intentionally narrow: copy managed hook files,
write the framework-root config without a BOM, and deploy Copilot instructions.
"""

from __future__ import annotations

import argparse
import json
import shutil
from dataclasses import asdict, dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Sequence


FRAMEWORK_MARKER = "AI Governance Framework"
COPILOT_MARKER = "AI Governance Framework: copilot-instructions"
HOOK_NAMES = ("pre-commit", "pre-push")


@dataclass
class HookInstallApplyResult:
    ok: bool
    repo_root: str
    framework_root: str
    installed_files: list[str] = field(default_factory=list)
    changed_files: list[str] = field(default_factory=list)
    backups: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _write_text_if_changed(path: Path, text: str) -> bool:
    if path.exists() and _read_text(path) == text:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")
    return True


def _write_bytes_if_changed(path: Path, payload: bytes) -> bool:
    if path.exists() and path.read_bytes() == payload:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)
    return True


def _has_marker(path: Path, marker: str) -> bool:
    if not path.exists():
        return False
    try:
        return marker in path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False


def _backup_unmanaged(path: Path, marker: str, backups: list[str]) -> None:
    if not path.exists() or _has_marker(path, marker):
        return
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup = path.with_name(f"{path.name}.bak.{timestamp}")
    shutil.copy2(path, backup)
    backups.append(str(backup))


def install_governance_hooks(
    repo_root: Path,
    framework_root: Path,
    *,
    include_copilot: bool = True,
) -> HookInstallApplyResult:
    repo_root = repo_root.resolve()
    framework_root = framework_root.resolve()
    hook_dir = repo_root / ".git" / "hooks"
    source_hook_dir = framework_root / "scripts" / "hooks"
    errors: list[str] = []
    installed: list[str] = []
    changed: list[str] = []
    backups: list[str] = []

    if not (repo_root / ".git").exists():
        errors.append(f"not a git repo: {repo_root}")
    if not source_hook_dir.is_dir():
        errors.append(f"missing framework hooks source: {source_hook_dir}")
    if errors:
        return HookInstallApplyResult(
            ok=False,
            repo_root=str(repo_root),
            framework_root=str(framework_root),
            errors=errors,
        )

    hook_dir.mkdir(parents=True, exist_ok=True)
    for hook_name in HOOK_NAMES:
        source = source_hook_dir / hook_name
        target = hook_dir / hook_name
        if not source.is_file():
            errors.append(f"missing source hook: {source}")
            continue
        _backup_unmanaged(target, FRAMEWORK_MARKER, backups)
        if _write_bytes_if_changed(target, source.read_bytes()):
            changed.append(str(target))
        installed.append(str(target))

    config = hook_dir / "ai-governance-framework-root"
    # Python's utf-8 writer does not emit a BOM. Keep a trailing newline to match
    # shell-created config files while preserving deterministic content.
    if _write_text_if_changed(config, f"{framework_root}\n"):
        changed.append(str(config))
    installed.append(str(config))

    if include_copilot:
        copilot_source = framework_root / "governance" / "copilot-instructions-template.md"
        copilot_target = repo_root / ".github" / "copilot-instructions.md"
        if copilot_source.is_file():
            _backup_unmanaged(copilot_target, COPILOT_MARKER, backups)
            if _write_bytes_if_changed(copilot_target, copilot_source.read_bytes()):
                changed.append(str(copilot_target))
            installed.append(str(copilot_target))
        else:
            errors.append(f"missing copilot instructions template: {copilot_source}")

    return HookInstallApplyResult(
        ok=not errors,
        repo_root=str(repo_root),
        framework_root=str(framework_root),
        installed_files=installed,
        changed_files=changed,
        backups=backups,
        errors=errors,
    )


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Install AI Governance hooks without requiring bash.")
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--framework-root", required=True, type=Path)
    parser.add_argument(
        "--hooks-only",
        action="store_true",
        help="Install only .git/hooks managed files and framework-root config; do not touch tracked Copilot instructions.",
    )
    parser.add_argument("--format", choices=("human", "json"), default="human")
    args = parser.parse_args(argv)

    result = install_governance_hooks(
        args.repo,
        args.framework_root,
        include_copilot=not args.hooks_only,
    )
    if args.format == "json":
        print(json.dumps(asdict(result), ensure_ascii=False, indent=2))
    else:
        print(f"ok={result.ok}")
        print(f"repo_root={result.repo_root}")
        print(f"framework_root={result.framework_root}")
        print(f"changed_files={len(result.changed_files)}")
        for error in result.errors:
            print(f"error: {error}")
    return 0 if result.ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
