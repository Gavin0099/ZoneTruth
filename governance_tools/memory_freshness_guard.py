#!/usr/bin/env python3
"""
Fail-closed structured memory freshness guard.

Checks key structured memory files under memory/ and blocks when stale.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from memory_pipeline.memory_layout import resolve_memory_file


def _age_days(path: Path, now: datetime) -> float:
    mtime = datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc)
    return (now - mtime).total_seconds() / 86400.0


def evaluate(project_root: Path, max_age_days: int) -> dict:
    memory_root = project_root / "memory"
    now = datetime.now(timezone.utc)
    checks = []
    failures = []

    for logical_name in ("active_task", "knowledge_base"):
        path = resolve_memory_file(memory_root, logical_name)
        exists = path.exists()
        age = None
        stale = True
        if exists:
            age = round(_age_days(path, now), 2)
            stale = age > max_age_days
        check = {
            "logical_name": logical_name,
            "path": str(path),
            "exists": exists,
            "age_days": age,
            "max_age_days": max_age_days,
            "stale": stale,
        }
        checks.append(check)
        if (not exists) or stale:
            failures.append(check)

    return {
        "ok": len(failures) == 0,
        "project_root": str(project_root),
        "max_age_days": max_age_days,
        "checks": checks,
        "failures": failures,
    }


def _format_human(result: dict) -> str:
    lines = ["[memory_freshness_guard]", f"ok={result['ok']} max_age_days={result['max_age_days']}"]
    for item in result["checks"]:
        lines.append(
            f"{item['logical_name']}: exists={item['exists']} stale={item['stale']} age_days={item['age_days']} path={item['path']}"
        )
    if result["failures"]:
        lines.append("blocked_reason=structured memory file missing or stale")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Check structured memory freshness.")
    parser.add_argument("--project-root", default=".")
    parser.add_argument("--max-age-days", type=int, default=30)
    parser.add_argument("--format", choices=("human", "json"), default="human")
    args = parser.parse_args()

    result = evaluate(Path(args.project_root).resolve(), args.max_age_days)
    if args.format == "json":
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(_format_human(result))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
