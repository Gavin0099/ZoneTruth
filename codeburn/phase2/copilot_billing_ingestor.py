#!/usr/bin/env python3
"""
CodeBurn — Copilot AI Credits Billing Ingestor (Class D)

Admission gate: CODEBURN_COPILOT_AI_CREDITS_ADMISSION_GATE.md
Epistemic class: Class D (billing-reported evidence)
Surface: GitHub Copilot AI Credits usage report CSV

Hard constraints (from admission gate — not configurable):
  CP-1: aic_quantity is NOT a token count. No pricing rate may be applied.
  CP-2: Cross-model aic_quantity aggregation is FORBIDDEN.
  CP-3: acquisition_mode = 'billing_report_daily_aggregate' (never session_log_ingestion).
  C-1:  aic_gross_amount is never ingested (cost ingestion forbidden).
  AG-Copilot-1: completions_excluded = 1 on every row (schema-enforced).
  AG-Copilot-2: session_id is NULL/absent (no session identity in billing CSV).
  AG-Copilot-3: is_preview defaults to 1; --mark-final re-ingests as is_preview=0.

Usage:
  python codeburn/phase2/copilot_billing_ingestor.py --csv PATH [--mark-final] [--db PATH]

CSV format (GitHub Copilot usage report, 2026-06-01+ billing):
  Required columns: date, user_login (or login), model, aic_quantity
  Ignored columns:  aic_gross_amount (C-1 violation to ingest)

DB path:
  Env CODEBURN_DB -> override path
  Default: ~/.codeburn/codeburn.db
"""
from __future__ import annotations

import argparse
import csv
import os
import sqlite3
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional


# ---------------------------------------------------------------------------
# Epistemic constants (Class D — not configurable)
# ---------------------------------------------------------------------------

_EPISTEMIC_CLASS = "Class D"
_ACQUISITION_MODE = "billing_report_daily_aggregate"
_REAL_TIME_OBSERVED = 0
_ANALYSIS_SAFE_FOR_DECISION = 0
_PROVIDER_TRUTHFULNESS_ASSUMED = 0
_COMPLETIONS_EXCLUDED = 1  # schema CHECK enforces this; declared here for clarity


# ---------------------------------------------------------------------------
# CP-1 guard: reject any attempt to apply pricing rates
# ---------------------------------------------------------------------------

def _reject_pricing_rate(model_pricing_rate=None):
    """CP-1 enforcement: calling code must not pass a pricing rate."""
    if model_pricing_rate is not None:
        raise ValueError(
            "CP-1 violation: pricing rate application to aic_quantity is FORBIDDEN. "
            "aic_quantity is a billing credit quantity, not a token count."
        )


# ---------------------------------------------------------------------------
# Result dataclass
# ---------------------------------------------------------------------------

@dataclass
class CopilotIngestResult:
    csv_path: str
    rows_scanned: int = 0
    rows_admitted: int = 0
    rows_skipped_duplicate: int = 0
    rows_quarantined: int = 0
    is_preview: int = 1
    mark_final_updated: int = 0
    errors: list[str] = field(default_factory=list)


# ---------------------------------------------------------------------------
# DB helpers
# ---------------------------------------------------------------------------

def _get_db_path() -> Path:
    env = os.environ.get("CODEBURN_DB")
    if env:
        return Path(env)
    return Path.home() / ".codeburn" / "codeburn.db"


def _ensure_db(db_path: Path) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    schema = Path(__file__).parent.parent / "phase1" / "schema.sql"
    conn.executescript(schema.read_text(encoding="utf-8"))
    conn.commit()
    return conn


# ---------------------------------------------------------------------------
# CSV column detection
# ---------------------------------------------------------------------------

_DATE_COLS    = ("date", "report_date", "day")
_LOGIN_COLS   = ("user_login", "login", "username", "user")
_MODEL_COLS   = ("model", "model_name")
_AIC_COLS     = ("aic_quantity", "ai_credits", "credits")
_FORBIDDEN_COLS = ("aic_gross_amount", "gross_amount", "cost", "amount_usd")


def _find_col(headers: list[str], candidates: tuple[str, ...]) -> Optional[str]:
    lower = {h.lower().strip(): h for h in headers}
    for c in candidates:
        if c in lower:
            return lower[c]
    return None


def _check_forbidden_cols(headers: list[str]) -> list[str]:
    """Return list of forbidden column names present in CSV (C-1 guard)."""
    lower = {h.lower().strip() for h in headers}
    return [f for f in _FORBIDDEN_COLS if f in lower]


# ---------------------------------------------------------------------------
# Row validation
# ---------------------------------------------------------------------------

def _validate_row(
    row: dict,
    date_col: str,
    login_col: str,
    model_col: str,
    aic_col: str,
    line_no: int,
) -> tuple[Optional[dict], Optional[str]]:
    """Validate and extract one CSV row. Returns (record, None) or (None, reason)."""

    report_date = row.get(date_col, "").strip()
    user_login  = row.get(login_col, "").strip()
    model       = row.get(model_col, "").strip()
    aic_raw     = row.get(aic_col, "").strip()

    if not report_date:
        return None, f"line {line_no}: empty date"
    if not user_login:
        return None, f"line {line_no}: empty user_login"
    if not model:
        return None, f"line {line_no}: empty model"
    if not aic_raw:
        return None, f"line {line_no}: empty aic_quantity"

    try:
        aic_quantity = float(aic_raw)
    except ValueError:
        return None, f"line {line_no}: non-numeric aic_quantity={aic_raw!r}"

    if aic_quantity < 0:
        return None, f"line {line_no}: negative aic_quantity={aic_quantity}"

    # Normalize date to YYYY-MM-DD
    # Accept YYYY-MM-DD or MM/DD/YYYY or DD/MM/YYYY (best-effort)
    try:
        if len(report_date) == 10 and report_date[4] == "-":
            pass  # already YYYY-MM-DD
        elif "/" in report_date:
            parts = report_date.split("/")
            if len(parts) == 3:
                if len(parts[0]) == 4:
                    report_date = f"{parts[0]}-{parts[1].zfill(2)}-{parts[2].zfill(2)}"
                else:
                    # Assume MM/DD/YYYY
                    report_date = f"{parts[2]}-{parts[0].zfill(2)}-{parts[1].zfill(2)}"
    except Exception:
        return None, f"line {line_no}: unparseable date={report_date!r}"

    return {
        "report_date": report_date,
        "user_login":  user_login,
        "model":       model,
        "aic_quantity": aic_quantity,
    }, None


# ---------------------------------------------------------------------------
# Core ingest logic
# ---------------------------------------------------------------------------

def ingest_copilot_csv(
    csv_path: str,
    conn: sqlite3.Connection,
    mark_final: bool = False,
    model_pricing_rate=None,  # CP-1: must remain None
) -> CopilotIngestResult:
    """
    Ingest a GitHub Copilot AI Credits usage report CSV into copilot_billing_events.

    Args:
        csv_path:          Path to the CSV report file.
        conn:              SQLite connection (schema must be initialized).
        mark_final:        If True, update existing preview rows to is_preview=0.
        model_pricing_rate: FORBIDDEN. Must not be passed (CP-1).

    Returns:
        CopilotIngestResult with admission statistics.

    Raises:
        ValueError: If CP-1 is violated (model_pricing_rate is not None).
        FileNotFoundError: If csv_path does not exist.
    """
    _reject_pricing_rate(model_pricing_rate)

    result = CopilotIngestResult(csv_path=csv_path)
    csv_file = Path(csv_path)

    if not csv_file.exists():
        raise FileNotFoundError(f"CSV not found: {csv_path}")

    is_preview_val = 0 if mark_final else 1
    result.is_preview = is_preview_val
    now = datetime.now(timezone.utc).isoformat()

    with open(csv_file, encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames is None:
            result.errors.append("CSV has no headers")
            return result

        headers = list(reader.fieldnames)

        # C-1 guard: warn if forbidden cost columns present (do not ingest them)
        forbidden_present = _check_forbidden_cols(headers)
        if forbidden_present:
            _write_annotation(
                conn, csv_path,
                "c1_guard_forbidden_cols_present",
                f"Columns present but NOT ingested (C-1): {','.join(forbidden_present)}",
                now,
            )

        # Detect required columns
        date_col  = _find_col(headers, _DATE_COLS)
        login_col = _find_col(headers, _LOGIN_COLS)
        model_col = _find_col(headers, _MODEL_COLS)
        aic_col   = _find_col(headers, _AIC_COLS)

        missing = [n for n, c in [("date", date_col), ("user_login", login_col),
                                   ("model", model_col), ("aic_quantity", aic_col)]
                   if c is None]
        if missing:
            result.errors.append(f"Missing required columns: {missing}")
            return result

        # Write structural annotation: completions absent
        _write_annotation(
            conn, csv_path,
            "completions_surface_present",
            "0",
            now,
        )
        _write_annotation(
            conn, csv_path,
            "completions_surface_reason",
            "GitHub_billing_design: completions_do_not_consume_AI_Credits",
            now,
        )

        # Process rows
        for line_no, row in enumerate(reader, start=2):  # header is line 1
            result.rows_scanned += 1

            record, err = _validate_row(row, date_col, login_col, model_col, aic_col, line_no)
            if err:
                result.rows_quarantined += 1
                _quarantine(conn, csv_path, line_no, err, dict(row), now)
                continue

            admitted = _upsert_row(
                conn, record, csv_path, line_no, is_preview_val, now, mark_final, result
            )
            if admitted:
                result.rows_admitted += 1

    conn.commit()
    return result


def _upsert_row(
    conn: sqlite3.Connection,
    record: dict,
    csv_path: str,
    line_no: int,
    is_preview_val: int,
    now: str,
    mark_final: bool,
    result: CopilotIngestResult,
) -> bool:
    """Insert or update a billing event row. Returns True if newly inserted."""
    def _get_existing_is_preview(row) -> int:
        if row is None:
            return -1
        if isinstance(row, sqlite3.Row):
            return int(row["is_preview"])
        # Fallback for default tuple rows: SELECT id, is_preview
        return int(row[1])

    def _get_existing_id(row) -> int:
        if isinstance(row, sqlite3.Row):
            return int(row["id"])
        return int(row[0])

    existing = conn.execute(
        """
        SELECT id, is_preview FROM copilot_billing_events
        WHERE report_date = ? AND user_login = ? AND model = ? AND source_artifact_path = ?
        """,
        (record["report_date"], record["user_login"], record["model"], csv_path),
    ).fetchone()

    if existing:
        if mark_final and _get_existing_is_preview(existing) == 1:
            conn.execute(
                "UPDATE copilot_billing_events SET is_preview = 0 WHERE id = ?",
                (_get_existing_id(existing),),
            )
            result.mark_final_updated += 1
            _write_annotation(
                conn, csv_path,
                "correction_event",
                f"is_preview 1->0 for ({record['report_date']}, {record['user_login']}, {record['model']})",
                now,
            )
        else:
            result.rows_skipped_duplicate += 1
        return False

    conn.execute(
        """
        INSERT INTO copilot_billing_events (
            report_date, user_login, model, aic_quantity,
            completions_excluded, is_preview,
            epistemic_class, acquisition_mode,
            source_artifact_path, source_record_line,
            real_time_observed, analysis_safe_for_decision,
            provider_truthfulness_assumed,
            created_at
        ) VALUES (
            ?, ?, ?, ?,
            1, ?,
            'Class D', 'billing_report_daily_aggregate',
            ?, ?,
            0, 0, 0,
            ?
        )
        """,
        (
            record["report_date"],
            record["user_login"],
            record["model"],
            record["aic_quantity"],
            is_preview_val,
            csv_path,
            line_no,
            now,
        ),
    )
    return True


def _quarantine(
    conn: sqlite3.Connection,
    csv_path: str,
    line_no: int,
    reason: str,
    raw_row: dict,
    now: str,
) -> None:
    import json
    conn.execute(
        """
        INSERT INTO quarantined_records
            (provider, source_artifact_path, source_record_line, reason, raw_record, created_at)
        VALUES ('copilot_billing', ?, ?, ?, ?, ?)
        """,
        (csv_path, line_no, reason, json.dumps(raw_row, ensure_ascii=False), now),
    )


def _write_annotation(
    conn: sqlite3.Connection,
    csv_path: str,
    key: str,
    value: str,
    now: str,
) -> None:
    conn.execute(
        """
        INSERT INTO copilot_surface_annotations
            (source_artifact_path, annotation_key, annotation_value, created_at)
        VALUES (?, ?, ?, ?)
        """,
        (csv_path, key, value, now),
    )


# ---------------------------------------------------------------------------
# Display
# ---------------------------------------------------------------------------

def _display_result(result: CopilotIngestResult) -> None:
    W = 64
    sep = "-" * W
    print()
    print(f"+{sep}+")
    print(f"|  CodeBurn | Copilot Billing Ingest | Class D{' ' * (W - 44)}|")
    print(f"|  billing-reported | not token evidence | not decision-authoritative{' ' * (W - 72)}|")
    print(f"+{sep}+")
    print(f"|  csv      : {Path(result.csv_path).name:<51}|")
    mode = "FINAL (is_preview=0)" if result.is_preview == 0 else "PREVIEW (is_preview=1)"
    print(f"|  mode     : {mode:<51}|")
    print(f"|  scanned  : {result.rows_scanned:<51}|")
    print(f"|  admitted : {result.rows_admitted:<51}|")
    print(f"|  duplicate: {result.rows_skipped_duplicate:<51}|")
    print(f"|  final-upd: {result.mark_final_updated:<51}|")
    print(f"|  quarantnd: {result.rows_quarantined:<51}|")
    if result.errors:
        print(f"+{sep}+")
        for e in result.errors[:3]:
            print(f"|  ERR: {e[:W - 7]:<{W - 1}}|")
    print(f"+{sep}+")
    print(f"|  WARNING: completions_excluded=1 on all rows.{' ' * (W - 47)}|")
    print(f"|  Code completions do NOT appear in this surface.{' ' * (W - 50)}|")
    print(f"|  aic_quantity is credits, NOT tokens (CP-1).{' ' * (W - 46)}|")
    print(f"+{sep}+")
    print()


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="CodeBurn Copilot AI Credits billing ingestor (Class D)"
    )
    parser.add_argument("--csv", required=True, help="Path to GitHub Copilot usage report CSV")
    parser.add_argument(
        "--mark-final",
        action="store_true",
        help="Mark rows as final billing (is_preview=0). Use only after GitHub confirms report.",
    )
    parser.add_argument("--db", help="Path to codeburn.db (overrides CODEBURN_DB env)")
    parser.add_argument("--no-display", action="store_true", help="Suppress summary display")
    args = parser.parse_args()

    db_path = Path(args.db) if args.db else _get_db_path()
    try:
        conn = _ensure_db(db_path)
    except Exception as e:
        print(f"ERROR: Cannot open DB: {e}", file=sys.stderr)
        return 1

    try:
        result = ingest_copilot_csv(
            csv_path=args.csv,
            conn=conn,
            mark_final=args.mark_final,
        )
    except (FileNotFoundError, ValueError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"ERROR: Unexpected failure: {e}", file=sys.stderr)
        return 1
    finally:
        try:
            conn.close()
        except Exception:
            pass

    if not args.no_display:
        _display_result(result)

    return 0 if not result.errors else 1


if __name__ == "__main__":
    sys.exit(main())
