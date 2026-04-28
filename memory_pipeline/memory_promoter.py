#!/usr/bin/env python3
"""
Promote reviewed candidate memory into durable project memory.
"""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

from memory_pipeline.memory_layout import resolve_memory_file


def _ensure_memory_files(memory_root: Path) -> tuple[Path, Path]:
    memory_root.mkdir(parents=True, exist_ok=True)
    active_task = resolve_memory_file(memory_root, "active_task")
    knowledge_base = resolve_memory_file(memory_root, "knowledge_base")
    review_log = resolve_memory_file(memory_root, "review_log")
    archive_dir = memory_root / "archive"
    archive_dir.mkdir(parents=True, exist_ok=True)
    if not active_task.exists():
        active_task.write_text("# Active Task\n\n## Progress\n\n", encoding="utf-8")
    if not knowledge_base.exists():
        knowledge_base.write_text("# Knowledge Base\n\n", encoding="utf-8")
    if not review_log.exists():
        review_log.write_text("# Review Log\n\n", encoding="utf-8")
    return active_task, knowledge_base, review_log, archive_dir / "promotion_manifest.json"


def promote_candidate(
    memory_root: Path,
    candidate_file: Path,
    approved_by: str,
    title: str | None = None,
) -> dict:
    payload = json.loads(candidate_file.read_text(encoding="utf-8"))
    active_task, knowledge_base, review_log, manifest_path = _ensure_memory_files(memory_root)

    heading = title or payload["task"]
    entry = (
        f"## {heading}\n"
        f"- Captured: {payload['captured_at']}\n"
        f"- Approved by: {approved_by}\n"
        f"- Risk: {payload['risk']}\n"
        f"- Oversight: {payload['oversight']}\n"
        f"- Summary: {payload['summary']}\n\n"
    )

    with knowledge_base.open("a", encoding="utf-8") as fh:
        fh.write(entry)

    with active_task.open("a", encoding="utf-8") as fh:
        fh.write(f"- [x] Promoted memory: {heading}\n")

    with review_log.open("a", encoding="utf-8") as fh:
        fh.write(
            f"## Promotion: {heading}\n"
            f"- Approved by: {approved_by}\n"
            f"- Candidate: {candidate_file}\n"
            f"- Risk: {payload['risk']}\n"
            f"- Oversight: {payload['oversight']}\n\n"
        )

    manifest = {"promotions": []}
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    manifest["promotions"].append(
        {
            "promoted_at": datetime.now(timezone.utc).isoformat(),
            "candidate_file": str(candidate_file),
            "approved_by": approved_by,
            "title": heading,
        }
    )
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    payload["status"] = "promoted"
    candidate_file.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    return {
        "active_task": str(active_task),
        "knowledge_base": str(knowledge_base),
        "review_log": str(review_log),
        "manifest_path": str(manifest_path),
        "title": heading,
        "status": "promoted",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Promote candidate memory into durable memory.")
    parser.add_argument("--memory-root", default="memory")
    parser.add_argument("--candidate-file", required=True)
    parser.add_argument("--approved-by", required=True)
    parser.add_argument("--title")
    args = parser.parse_args()

    result = promote_candidate(
        memory_root=Path(args.memory_root),
        candidate_file=Path(args.candidate_file),
        approved_by=args.approved_by,
        title=args.title,
    )
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
