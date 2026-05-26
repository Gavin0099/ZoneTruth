#!/usr/bin/env python3
"""
Validate GitLab wiki adapter project-scope consistency.

Rule:
- If listPages() supports per-call project override via opts.projectId,
  page-content fetch path must not be hard-wired to constructor-level
  this.projectId only.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path


RULE_ID = "GLA-PS-1"


@dataclass
class ValidationResult:
    valid: bool
    rule_id: str
    file: str
    errors: list[str]
    warnings: list[str]


def _contains_project_override_support(text: str) -> bool:
    return "opts.projectId" in text


def _contains_hardwired_fetch_scope(text: str) -> bool:
    return "/wikis/${encodeURIComponent(slug)}" in text and "this.projectId" in text


def _contains_project_aware_fetch_scope(text: str) -> bool:
    # Accept either a dynamic projectId variable or explicit opts/project map plumbing.
    dynamic_markers = [
        # encodeURIComponent(projectId)} matches local variable only — NOT this.projectId
        "encodeURIComponent(projectId)}/wikis/${encodeURIComponent(slug)}",
        "encodeURIComponent(projectId)}/wikis/${encodeURIComponent(pageId)}",
        "slugToProject",
        "pageIdToProject",
    ]
    return any(marker in text for marker in dynamic_markers)


def _contains_unknown_slug_default_fallback(text: str) -> bool:
    fallback_markers = [
        "?? this.projectId",
        "|| this.projectId",
    ]
    return any(marker in text for marker in fallback_markers)


def validate_adapter_file(path: Path, *, allow_default_project_fallback: bool = False) -> ValidationResult:
    if not path.is_file():
        return ValidationResult(
            valid=False,
            rule_id=RULE_ID,
            file=str(path),
            errors=[f"adapter file not found: {path}"],
            warnings=[],
        )

    text = path.read_text(encoding="utf-8")
    errors: list[str] = []
    warnings: list[str] = []

    supports_override = _contains_project_override_support(text)
    hardwired_scope = _contains_hardwired_fetch_scope(text)
    project_aware_fetch = _contains_project_aware_fetch_scope(text)
    unsafe_default_fallback = _contains_unknown_slug_default_fallback(text)

    if supports_override and hardwired_scope and not project_aware_fetch:
        errors.append(
            "listPages supports opts.projectId but content fetch scope appears fixed to this.projectId"
        )

    if supports_override and unsafe_default_fallback and not allow_default_project_fallback:
        errors.append(
            "unknown slug fallback to default project detected; require explicit scoped fallback instead"
        )

    if not supports_override:
        warnings.append("opts.projectId override support not detected")

    return ValidationResult(
        valid=len(errors) == 0,
        rule_id=RULE_ID,
        file=str(path),
        errors=errors,
        warnings=warnings,
    )


def format_human(result: ValidationResult) -> str:
    lines = [
        "GitLab Adapter Scope Validation",
        "",
        f"valid    = {result.valid}",
        f"rule_id  = {result.rule_id}",
        f"file     = {result.file}",
    ]
    if result.errors:
        lines.append("")
        lines.append(f"errors: {len(result.errors)}")
        for item in result.errors:
            lines.append(f"- {item}")
    if result.warnings:
        lines.append("")
        lines.append(f"warnings: {len(result.warnings)}")
        for item in result.warnings:
            lines.append(f"- {item}")
    return "\n".join(lines)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Validate GitLab wiki adapter project scope consistency."
    )
    parser.add_argument(
        "--adapter-file",
        required=True,
        help="Path to GitLab wiki adapter TypeScript file.",
    )
    parser.add_argument(
        "--allow-default-project-fallback",
        action="store_true",
        help="Allow unknown slug fallback to constructor default project scope.",
    )
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    result = validate_adapter_file(
        Path(args.adapter_file),
        allow_default_project_fallback=args.allow_default_project_fallback,
    )
    print(format_human(result))
    return 0 if result.valid else 1


if __name__ == "__main__":
    raise SystemExit(main())
