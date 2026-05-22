"""
CodeBurn -- Codex Log Ingestor (P5.3 stub)

Ingests Codex CLI session JSONL logs as Class C (observer-reconstructed) evidence.

Epistemic contract (CODEBURN_CODEX_ARTIFACT_CONTRACT.md):
  - All evidence produced is Class C unconditionally
  - real_time_observed = 0 always (schema also enforces this)
  - analysis_safe_for_decision = 0 always (schema also enforces this)
  - provider_truthfulness_assumed = 0 always (schema also enforces this)
  - total_tokens = NULL always (even when Codex log provides it explicitly)
  - missing token fields → NULL, never 0
  - malformed records → quarantined_records, never silently dropped
  - total_token_usage.* → NEVER stored (IAF-1, cumulative not turn-scoped)
  - reasoning_output_tokens → NEVER stored (IAF-2, Reasoning Separation Principle)
  - cached_input_tokens → NEVER stored (IAF-4, billing computation forbidden)
  - SQLite surface → NEVER used as acquisition path (IAF-8)
  - provider = 'codex', distinct from 'claude' (NST-1 cross-comparability prevention)

Acquisition authority: L1.5 maximum (CODEBURN_ACQUISITION_AUTHORITY_MODEL.md)
This module never wraps, intercepts, or modifies AI runtime invocations.

Status: P5.3 stub -- raises NotImplementedError until implementation.
Negative-path tests in tests/test_codeburn_codex_negative.py are XFAIL until
this stub is replaced with a real implementation.
"""
from __future__ import annotations

import json
import sqlite3
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

# Hard-coded epistemic constants — not configurable
_PROVIDER = "codex"
_EPISTEMIC_CLASS = "Class C"
_ACQUISITION_MODE = "session_log_ingestion"
_REAL_TIME_OBSERVED = 0           # Class C is always post-hoc
_ANALYSIS_SAFE_FOR_DECISION = 0   # permanent per Authority Ceiling Contract AC4
_PROVIDER_TRUTHFULNESS_ASSUMED = 0  # CodeBurn observes reports, not computation


@dataclass
class CodexIngestResult:
    """Result of ingesting one Codex JSONL session file.

    Counts are informational only. They do not imply completeness
    or correctness of the underlying Codex log.
    """
    session_id: str
    source_artifact_path: str
    records_scanned: int = 0
    records_admitted: int = 0
    records_skipped: int = 0      # non-token records (structurally valid, not token_count)
    records_quarantined: int = 0  # malformed token_count records
    step_ids: list[str] = field(default_factory=list)


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _quarantine(
    conn: sqlite3.Connection,
    source_artifact_path: str,
    source_record_line: int,
    source_record_offset: Optional[int],
    reason: str,
    raw_record: Optional[str],
) -> None:
    conn.execute(
        """
        INSERT INTO quarantined_records(
            provider, source_artifact_path, source_record_line, source_record_offset,
            reason, raw_record, created_at
        ) VALUES(?, ?, ?, ?, ?, ?, ?)
        """,
        (
            _PROVIDER,
            source_artifact_path,
            source_record_line,
            source_record_offset,
            reason,
            raw_record[:4096] if raw_record else None,
            _now_iso(),
        ),
    )


def _write_class_c_evidence(
    conn: sqlite3.Connection,
    session_id: str,
    source_artifact_path: str,
    source_record_line: int,
    source_record_offset: Optional[int],
    source_record_timestamp: Optional[str],
    prompt_tokens: Optional[int],
    completion_tokens: Optional[int],
) -> str:
    step_id = str(uuid.uuid4())
    started_at = source_record_timestamp or _now_iso()

    conn.execute(
        """
        INSERT INTO steps(
            step_id, session_id, step_kind, command,
            started_at, provider,
            prompt_tokens, completion_tokens, total_tokens,
            token_source
        ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            step_id,
            session_id,
            "other",
            "codex-log-ingestion:token_count",
            started_at,
            _PROVIDER,
            prompt_tokens,
            completion_tokens,
            None,
            "estimated",
        ),
    )

    conn.execute(
        """
        INSERT INTO step_ingestion_provenance(
            step_id, provider, epistemic_class, acquisition_mode,
            source_artifact_path, source_record_line, source_record_offset,
            real_time_observed, analysis_safe_for_decision,
            provider_truthfulness_assumed, created_at
        ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            step_id,
            _PROVIDER,
            _EPISTEMIC_CLASS,
            _ACQUISITION_MODE,
            source_artifact_path,
            source_record_line,
            source_record_offset,
            _REAL_TIME_OBSERVED,
            _ANALYSIS_SAFE_FOR_DECISION,
            _PROVIDER_TRUTHFULNESS_ASSUMED,
            _now_iso(),
        ),
    )
    return step_id


def _ensure_session_row(conn: sqlite3.Connection, session_id: str) -> None:
    existing = conn.execute(
        "SELECT 1 FROM sessions WHERE session_id = ?",
        (session_id,),
    ).fetchone()
    if existing is not None:
        return
    now = _now_iso()
    conn.execute(
        """
        INSERT INTO sessions(
            session_id, task, created_at, data_quality
        ) VALUES(?, ?, ?, ?)
        """,
        (session_id, "codex_log_ingestion", now, "partial"),
    )


def ingest_codex_session(
    session_jsonl_path: str,
    session_id: str,
    conn: sqlite3.Connection,
) -> CodexIngestResult:
    """Ingest one Codex CLI session JSONL file.

    Parameters
    ----------
    session_jsonl_path:
        Absolute path to the Codex session JSONL file.
    session_id:
        The Codex session UUID. Caller is responsible for extraction
        (from filename UUID portion or session_meta.payload.id).
    conn:
        Open SQLite connection. Schema must already be applied.

    Returns
    -------
    CodexIngestResult
        Ingestion summary. Does not include token values -- callers
        must query the DB directly for token evidence.

    Raises
    ------
    NotImplementedError
        Until P5.3 implementation is complete.
    FileNotFoundError
        If session_jsonl_path does not exist.
    ValueError
        If session_id is empty or session_jsonl_path is not a JSONL file.
    """
    if not session_id or not session_id.strip():
        raise ValueError("session_id must be non-empty")
    if not session_jsonl_path.lower().endswith(".jsonl"):
        raise ValueError("session_jsonl_path must point to a .jsonl file")

    artifact_path = Path(session_jsonl_path)
    if not artifact_path.exists():
        raise FileNotFoundError(session_jsonl_path)

    source_path_str = str(artifact_path.resolve())
    _ensure_session_row(conn, session_id)
    result = CodexIngestResult(
        session_id=session_id,
        source_artifact_path=source_path_str,
    )

    byte_offset = 0
    with artifact_path.open("r", encoding="utf-8", errors="replace") as handle:
        for line_number, raw_line in enumerate(handle, start=1):
            line_offset = byte_offset
            byte_offset += len(raw_line.encode("utf-8", errors="replace"))
            raw_stripped = raw_line.rstrip("\n\r")
            result.records_scanned += 1

            try:
                record = json.loads(raw_stripped)
            except json.JSONDecodeError as exc:
                _quarantine(
                    conn,
                    source_path_str,
                    line_number,
                    line_offset,
                    f"json_parse_error: {exc}",
                    raw_stripped,
                )
                result.records_quarantined += 1
                continue

            if not isinstance(record, dict):
                result.records_skipped += 1
                continue

            if record.get("type") != "event_msg":
                result.records_skipped += 1
                continue

            payload = record.get("payload")
            if not isinstance(payload, dict) or payload.get("type") != "token_count":
                result.records_skipped += 1
                continue

            info = payload.get("info")
            if not isinstance(info, dict):
                _quarantine(
                    conn,
                    source_path_str,
                    line_number,
                    line_offset,
                    "unexpected_structure: payload.info is not a dict",
                    raw_stripped,
                )
                result.records_quarantined += 1
                continue

            last_usage = info.get("last_token_usage")
            if not isinstance(last_usage, dict):
                _quarantine(
                    conn,
                    source_path_str,
                    line_number,
                    line_offset,
                    "unexpected_structure: payload.info.last_token_usage is not a dict",
                    raw_stripped,
                )
                result.records_quarantined += 1
                continue

            prompt_tokens: Optional[int] = None
            completion_tokens: Optional[int] = None
            if isinstance(last_usage.get("input_tokens"), int):
                prompt_tokens = last_usage["input_tokens"]
            if isinstance(last_usage.get("output_tokens"), int):
                completion_tokens = last_usage["output_tokens"]

            step_id = _write_class_c_evidence(
                conn,
                session_id,
                source_path_str,
                line_number,
                line_offset,
                record.get("timestamp"),
                prompt_tokens,
                completion_tokens,
            )
            result.step_ids.append(step_id)
            result.records_admitted += 1

    conn.commit()
    return result
