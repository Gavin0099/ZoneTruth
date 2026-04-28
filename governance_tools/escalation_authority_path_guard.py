#!/usr/bin/env python3
"""
Static guard: ensure escalation authority artifacts are only written
through governance_tools/escalation_authority_writer.py.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


ALLOWED_WRITER_FILE = "governance_tools/escalation_authority_writer.py"
WRITE_PATTERNS = (
    ".write_text(",
    ".open(",
    "json.dump(",
)
AUTHORITY_PATH_TOKENS = (
    "e1b-phase-b-escalation",
    "authority",
)


def find_direct_write_violations(project_root: Path) -> list[dict[str, str | int]]:
    violations: list[dict[str, str | int]] = []
    scope_roots = [project_root / "governance_tools", project_root / "runtime_hooks"]

    for scope_root in scope_roots:
        if not scope_root.is_dir():
            continue
        for py_file in scope_root.rglob("*.py"):
            rel = py_file.relative_to(project_root).as_posix()
            if rel == ALLOWED_WRITER_FILE:
                continue

            try:
                content = py_file.read_text(encoding="utf-8")
            except OSError:
                continue

            has_authority_path_token = all(token in content for token in AUTHORITY_PATH_TOKENS)
            if not has_authority_path_token:
                continue

            for idx, line in enumerate(content.splitlines(), start=1):
                stripped = line.strip()
                if not stripped or stripped.startswith("#"):
                    continue
                if any(token in stripped for token in AUTHORITY_PATH_TOKENS) and any(
                    pattern in stripped for pattern in WRITE_PATTERNS
                ):
                    violations.append(
                        {
                            "file": rel,
                            "line": idx,
                            "reason": "direct escalation authority artifact write outside authority writer",
                        }
                    )

            # Catch split-line writes in a coarse way (path token elsewhere in file + write API call line).
            if not any(v["file"] == rel for v in violations):
                write_lines = [
                    i + 1
                    for i, l in enumerate(content.splitlines())
                    if any(pattern in l for pattern in WRITE_PATTERNS)
                ]
                if write_lines:
                    path_mentions = [
                        i + 1
                        for i, l in enumerate(content.splitlines())
                        if all(token in l for token in AUTHORITY_PATH_TOKENS)
                    ]
                    if path_mentions and write_lines:
                        violations.append(
                            {
                                "file": rel,
                                "line": write_lines[0],
                                "reason": "potential split-line direct write to escalation authority path outside authority writer",
                            }
                        )

    return violations


def run_guard(project_root: Path) -> dict:
    violations = find_direct_write_violations(project_root)
    return {
        "ok": len(violations) == 0,
        "project_root": str(project_root),
        "allowed_writer_file": ALLOWED_WRITER_FILE,
        "violation_count": len(violations),
        "violations": violations,
    }


def _format_human(result: dict) -> str:
    lines = [
        "[escalation_authority_path_guard]",
        f"ok={result['ok']}",
        f"allowed_writer_file={result['allowed_writer_file']}",
        f"violation_count={result['violation_count']}",
    ]
    for item in result["violations"]:
        lines.append(f"violation={item['file']}:{item['line']}:{item['reason']}")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Detect direct escalation authority artifact writes outside the authority writer.")
    parser.add_argument("--project-root", default=".")
    parser.add_argument("--format", choices=("human", "json"), default="human")
    args = parser.parse_args()

    result = run_guard(Path(args.project_root).resolve())
    if args.format == "json":
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(_format_human(result))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
