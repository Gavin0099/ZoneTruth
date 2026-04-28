#!/usr/bin/env python3
"""
Capture session output into candidate memory.
"""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path


def _ensure_candidate_dir(memory_root: Path) -> Path:
    candidate_dir = memory_root / "candidates"
    candidate_dir.mkdir(parents=True, exist_ok=True)
    return candidate_dir


def create_session_snapshot(
    memory_root: Path,
    task: str,
    summary: str,
    source_text: str,
    risk: str,
    oversight: str,
) -> dict:
    candidate_dir = _ensure_candidate_dir(memory_root)
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    snapshot_path = candidate_dir / f"session_{timestamp}.json"

    payload = {
        "captured_at": datetime.now(timezone.utc).isoformat(),
        "task": task,
        "summary": summary,
        "risk": risk,
        "oversight": oversight,
        "source_text": source_text,
        "status": "candidate",
    }
    snapshot_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    return {
        "snapshot_path": str(snapshot_path),
        "status": "candidate",
        "task": task,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Capture a session snapshot into candidate memory.")
    parser.add_argument("--memory-root", default="memory")
    parser.add_argument("--task", required=True)
    parser.add_argument("--summary", required=True)
    parser.add_argument("--source-file")
    parser.add_argument("--risk", default="medium")
    parser.add_argument("--oversight", default="review-required")
    args = parser.parse_args()

    source_text = Path(args.source_file).read_text(encoding="utf-8") if args.source_file else ""
    result = create_session_snapshot(
        memory_root=Path(args.memory_root),
        task=args.task,
        summary=args.summary,
        source_text=source_text,
        risk=args.risk,
        oversight=args.oversight,
    )
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
