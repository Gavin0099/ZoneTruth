"""
CodeBurn -- Provenance Identity Helper (P4.1)

Provides _provenance_identity() to construct the canonical tuple that
identifies a unique source location within a .jsonl artifact.

Contract (CODEBURN_CLAUDE_REPLAY_PROVENANCE_CONTRACT.md):
  Provenance Identity = (source_artifact_path, source_record_line, source_record_offset)

  This tuple is:
  - Deterministic: same file + same line + same byte offset => same tuple
  - Stable across replay: re-ingesting the same file yields the same tuples
  - NOT an idempotency guarantee: row count can grow on repeated ingestion

This helper is used by:
  - P4.2 replay tests for valid records
  - P4.3 replay tests for quarantine records
  - P4.4 non-idempotency verification
  - P4.5 replay smoke command
"""
from __future__ import annotations

from pathlib import Path
from typing import Optional


def provenance_identity(
    artifact_path: "Path | str",
    source_record_line: int,
    source_record_offset: Optional[int],
) -> tuple:
    """Return the canonical provenance identity tuple for a source location.

    Args:
        artifact_path: Absolute path to the .jsonl artifact file.
                       If relative, it is resolved against cwd.
        source_record_line: 1-indexed line number within the artifact.
        source_record_offset: Byte offset from start of file (utf-8).
                              None is a valid state (offset not recorded).

    Returns:
        (str, int, int|None) -- (resolved_path_str, line, offset)

    The returned path string is always the resolved absolute path,
    consistent with how claude_log_ingestor.py stores source_artifact_path.
    """
    resolved = str(Path(artifact_path).resolve())
    return (resolved, source_record_line, source_record_offset)


def extract_provenance_identities_from_db(
    conn,
    table: str,
    artifact_path: "Path | str",
) -> list[tuple]:
    """Query provenance identity tuples from a DB table for a given artifact.

    Works for both step_ingestion_provenance and quarantined_records,
    which share the (source_artifact_path, source_record_line, source_record_offset) schema.

    Returns a list of (source_artifact_path, source_record_line, source_record_offset) tuples,
    sorted for deterministic comparison in tests.
    """
    resolved = str(Path(artifact_path).resolve())
    rows = conn.execute(
        f"""
        SELECT source_artifact_path, source_record_line, source_record_offset
        FROM {table}
        WHERE source_artifact_path = ?
        ORDER BY source_record_line, source_record_offset
        """,
        (resolved,),
    ).fetchall()
    return [(r[0], r[1], r[2]) for r in rows]
