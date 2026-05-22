"""
CodeBurn — Claude Log Ingestor (P3.2 / P3.3)

Ingests Claude Code .jsonl session logs as Class C (observer-reconstructed) evidence.

Epistemic contract (CODEBURN_CLAUDE_ARTIFACT_CONTRACT.md):
  - All evidence produced is Class C unconditionally
  - real_time_observed = 0 always (schema also enforces this)
  - analysis_safe_for_decision = 0 always (schema also enforces this)
  - provider_truthfulness_assumed = 0 always (schema also enforces this)
  - missing token fields → NULL, never 0
  - malformed records → quarantined_records, never silently dropped
  - no aggregation, no estimation, no billing computation
  - cache token fields (cache_creation_input_tokens, cache_read_input_tokens)
    are not stored — no billing total authorized
  - inadmissible fields (service_tier, inference_geo) are not read or stored

Acquisition authority: L1.5 maximum (CODEBURN_ACQUISITION_AUTHORITY_MODEL.md)
This module never wraps, intercepts, or modifies AI runtime invocations.
"""
from __future__ import annotations

import json
import sqlite3
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

# Hard-coded epistemic constants — not configurable
_PROVIDER = "claude"
_EPISTEMIC_CLASS = "Class C"
_ACQUISITION_MODE = "session_log_ingestion"
_REAL_TIME_OBSERVED = 0          # Class C is always post-hoc
_ANALYSIS_SAFE_FOR_DECISION = 0  # permanent per Authority Ceiling Contract AC4
_PROVIDER_TRUTHFULNESS_ASSUMED = 0  # CodeBurn observes reports, not computation


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _ensure_schema(conn: sqlite3.Connection) -> None:
    schema_path = Path(__file__).resolve().with_name("schema.sql")
    conn.executescript(schema_path.read_text(encoding="utf-8"))
    conn.commit()


def _quarantine(
    conn: sqlite3.Connection,
    source_artifact_path: str,
    source_record_line: int,
    source_record_offset: Optional[int],
    reason: str,
    raw_record: Optional[str],
) -> None:
    """Persist a malformed or inadmissible record to quarantined_records.

    Never silently drop. Quarantine is the only acceptable outcome for records
    that cannot be ingested. The quarantine entry preserves traceability of
    ingestion completeness.
    """
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
            raw_record[:4096] if raw_record else None,  # cap stored size
            _now_iso(),
        ),
    )
    conn.commit()


def _write_class_c_evidence(
    conn: sqlite3.Connection,
    session_id: str,
    source_artifact_path: str,
    source_record_line: int,
    source_record_offset: Optional[int],
    source_record_id: Optional[str],
    source_record_timestamp: Optional[str],
    prompt_tokens: Optional[int],    # NULL if absent from log
    completion_tokens: Optional[int], # NULL if absent from log
) -> str:
    """Write one Class C step + provenance row.

    Returns the new step_id.

    Token fields are written as-is. NULL means absent from the log artifact.
    0 would mean 'zero tokens recorded' — a different epistemic state.
    We never coerce NULL to 0.

    total_tokens is always NULL: we do not compute totals, aggregates, or
    billing estimates. No billing computation is authorized by this contract.
    """
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
            f"claude-log-ingestion:{source_record_id or 'unknown'}",
            started_at,
            _PROVIDER,
            prompt_tokens,     # NULL if absent — invariant I2
            completion_tokens, # NULL if absent — invariant I2
            None,              # total_tokens: never computed — contract §cache
            "estimated",       # Class C evidence is 'estimated', not 'provider'
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
            _EPISTEMIC_CLASS,              # 'Class C' — unconditional, invariant I1
            _ACQUISITION_MODE,
            source_artifact_path,
            source_record_line,            # invariant I4
            source_record_offset,          # invariant I4
            _REAL_TIME_OBSERVED,           # 0 — invariant I5; schema also enforces
            _ANALYSIS_SAFE_FOR_DECISION,   # 0 — invariant I5; schema also enforces
            _PROVIDER_TRUTHFULNESS_ASSUMED, # 0 — invariant I5; schema also enforces
            _now_iso(),
        ),
    )

    conn.commit()
    return step_id


def ingest(
    artifact_path: "Path | str",
    session_id: str,
    db_path: "Path | str",
) -> dict:
    """Ingest a Claude Code .jsonl session log as Class C evidence.

    Reads the artifact line-by-line. For each line:
    - Non-JSON: quarantine
    - type != 'assistant': skip (not applicable, not an error)
    - type == 'assistant': extract token usage, write Class C evidence

    Token fields absent from the log are written as NULL, never 0.
    Cache token fields are not stored (no billing computation authorized).
    Inadmissible fields (service_tier, inference_geo) are not read or stored.

    Args:
        artifact_path: Path to the Claude Code .jsonl session log.
        session_id: CodeBurn session_id to associate ingested steps with.
        db_path: Path to the CodeBurn SQLite database.

    Returns:
        Summary dict with ingestion outcome — never raises on per-record errors,
        always returns counts of processed/skipped/quarantined.
    """
    artifact_path = Path(artifact_path).resolve()
    db_path = Path(db_path)
    source_path_str = str(artifact_path)

    conn = sqlite3.connect(str(db_path))
    conn.execute("PRAGMA foreign_keys = ON")
    _ensure_schema(conn)

    processed = 0
    skipped = 0
    quarantined = 0

    with open(artifact_path, "r", encoding="utf-8", errors="replace") as f:
        byte_offset = 0
        for line_number, raw_line in enumerate(f, start=1):
            line_byte_offset = byte_offset
            byte_offset += len(raw_line.encode("utf-8", errors="replace"))
            raw_stripped = raw_line.rstrip("\n\r")

            # Step 1: parse JSON — malformed → quarantine (invariant I3)
            try:
                record = json.loads(raw_stripped)
            except json.JSONDecodeError as exc:
                _quarantine(
                    conn,
                    source_path_str,
                    line_number,
                    line_byte_offset,
                    f"json_parse_error: {exc}",
                    raw_stripped,
                )
                quarantined += 1
                continue

            # Step 2: record type filter
            # Only type=assistant carries token evidence (contract §admissible)
            # All other types are structurally not-applicable — not errors
            record_type = record.get("type")
            if record_type != "assistant":
                skipped += 1
                continue

            # Step 3: structural validation
            message = record.get("message")
            if not isinstance(message, dict):
                _quarantine(
                    conn,
                    source_path_str,
                    line_number,
                    line_byte_offset,
                    "unexpected_structure: message is not a dict",
                    raw_stripped,
                )
                quarantined += 1
                continue

            # Step 4: extract admissible fields
            source_record_id = record.get("uuid") or record.get("requestId")
            source_record_timestamp = record.get("timestamp")

            # Step 5: extract token usage — may be absent (valid state)
            usage = message.get("usage")  # None = usage absent from log

            prompt_tokens: Optional[int] = None
            completion_tokens: Optional[int] = None

            if isinstance(usage, dict):
                raw_input = usage.get("input_tokens")
                raw_output = usage.get("output_tokens")
                # Accept only integer values — do not infer or estimate
                # Non-integer values (None, float, str) → remain NULL
                if isinstance(raw_input, int):
                    prompt_tokens = raw_input
                if isinstance(raw_output, int):
                    completion_tokens = raw_output
                # Explicitly NOT reading:
                #   cache_creation_input_tokens — no billing computation authorized
                #   cache_read_input_tokens     — no billing computation authorized
                #   service_tier                — inadmissible (operational metadata)
                #   inference_geo               — inadmissible (operational metadata)

            # Step 6: write Class C evidence
            _write_class_c_evidence(
                conn,
                session_id,
                source_path_str,
                line_number,
                line_byte_offset,
                source_record_id,
                source_record_timestamp,
                prompt_tokens,
                completion_tokens,
            )
            processed += 1

    conn.close()

    return {
        "ok": True,
        "artifact_path": source_path_str,
        "session_id": session_id,
        "processed": processed,
        "skipped": skipped,
        "quarantined": quarantined,
        # Epistemic position — never changes regardless of data quality
        "epistemic_class": _EPISTEMIC_CLASS,
        "real_time_observed": False,
        "analysis_safe_for_decision": False,
        "provider_truthfulness_assumed": False,
    }
