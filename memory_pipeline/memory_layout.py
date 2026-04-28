#!/usr/bin/env python3
"""
Resolve canonical memory files with support for repo-specific aliases.
"""

from __future__ import annotations

from pathlib import Path


MEMORY_FILE_ALIASES = {
    "active_task": ["01_active_task.md"],
    "tech_stack": ["02_tech_stack.md", "02_project_facts.md"],
    "knowledge_base": ["03_knowledge_base.md", "03_decisions.md"],
    "review_log": ["04_review_log.md", "04_validation_log.md"],
}


def resolve_memory_file(memory_root: Path, logical_name: str) -> Path:
    names = MEMORY_FILE_ALIASES[logical_name]
    for name in names:
        candidate = memory_root / name
        if candidate.exists():
            return candidate
    return memory_root / names[0]
