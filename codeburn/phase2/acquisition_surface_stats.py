#!/usr/bin/env python3
"""
CodeBurn P6 -- Acquisition surface statistics display.

This module renders structural acquisition statistics only:
  - observed record counts per acquisition surface
  - source type counts per surface
  - quarantine counts per provider/surface family

It deliberately does not compute token totals, costs, provider rankings,
efficiency scores, trend claims, or optimization recommendations.
"""
from __future__ import annotations

import argparse
import json
import sqlite3
import sys
import tempfile
from dataclasses import asdict, dataclass, field
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))


P6_CONSTRAINTS = {
    "A-1": "aggregate display only; not decision input",
    "T-1": "no trend inference",
    "C-1": "no cost estimation",
    "R-1": "no replay-derived metrics",
    "O-1": "no optimization decisions",
    "V-1": "explicit epistemic annotation required",
}

ANNOTATION_CLASS_C = (
    "Class C -- observer-reconstructed acquisition surface statistics; "
    "not provider-measured; not decision-authoritative"
)
ANNOTATION_CLASS_D = (
    "Class D -- billing-reported acquisition surface statistics; "
    "not token evidence; not decision-authoritative"
)


@dataclass
class AcquisitionSurfaceStat:
    surface_id: str
    provider: str
    epistemic_class: str
    acquisition_mode: str
    observed_records: int
    source_type_counts: dict[str, int] = field(default_factory=dict)
    quarantined_records: int = 0
    analysis_safe_for_decision: int = 0
    provider_truthfulness_assumed: int = 0
    annotation: str = ""


def _rows_to_count_map(rows: list[sqlite3.Row]) -> dict[str, int]:
    return {str(row["source_type"]): int(row["record_count"]) for row in rows}


def _quarantine_count(conn: sqlite3.Connection, provider: str) -> int:
    row = conn.execute(
        "SELECT COUNT(*) AS record_count FROM quarantined_records WHERE provider = ?",
        (provider,),
    ).fetchone()
    return int(row["record_count"]) if row else 0


def _collect_class_c_surfaces(conn: sqlite3.Connection) -> list[AcquisitionSurfaceStat]:
    rows = conn.execute(
        """
        SELECT
            p.provider,
            p.epistemic_class,
            p.acquisition_mode,
            COUNT(*) AS observed_records,
            MAX(p.analysis_safe_for_decision) AS analysis_safe_for_decision,
            MAX(p.provider_truthfulness_assumed) AS provider_truthfulness_assumed
        FROM step_ingestion_provenance p
        GROUP BY p.provider, p.epistemic_class, p.acquisition_mode
        ORDER BY p.provider, p.acquisition_mode, p.epistemic_class
        """
    ).fetchall()

    surfaces: list[AcquisitionSurfaceStat] = []
    for row in rows:
        provider = str(row["provider"])
        epistemic_class = str(row["epistemic_class"])
        acquisition_mode = str(row["acquisition_mode"])
        source_rows = conn.execute(
            """
            SELECT COALESCE(s.token_source, 'unknown') AS source_type, COUNT(*) AS record_count
            FROM step_ingestion_provenance p
            INNER JOIN steps s ON s.step_id = p.step_id
            WHERE p.provider = ?
              AND p.epistemic_class = ?
              AND p.acquisition_mode = ?
            GROUP BY COALESCE(s.token_source, 'unknown')
            ORDER BY source_type
            """,
            (provider, epistemic_class, acquisition_mode),
        ).fetchall()

        surfaces.append(
            AcquisitionSurfaceStat(
                surface_id=f"{provider}:{acquisition_mode}:{epistemic_class}",
                provider=provider,
                epistemic_class=epistemic_class,
                acquisition_mode=acquisition_mode,
                observed_records=int(row["observed_records"]),
                source_type_counts=_rows_to_count_map(source_rows),
                quarantined_records=_quarantine_count(conn, provider),
                analysis_safe_for_decision=int(row["analysis_safe_for_decision"] or 0),
                provider_truthfulness_assumed=int(row["provider_truthfulness_assumed"] or 0),
                annotation=ANNOTATION_CLASS_C,
            )
        )
    return surfaces


def _collect_copilot_surface(conn: sqlite3.Connection) -> list[AcquisitionSurfaceStat]:
    row = conn.execute(
        """
        SELECT
            epistemic_class,
            acquisition_mode,
            COUNT(*) AS observed_records,
            MAX(analysis_safe_for_decision) AS analysis_safe_for_decision,
            MAX(provider_truthfulness_assumed) AS provider_truthfulness_assumed
        FROM copilot_billing_events
        GROUP BY epistemic_class, acquisition_mode
        """
    ).fetchone()
    if row is None:
        return []

    source_rows = conn.execute(
        """
        SELECT
            CASE
                WHEN is_preview = 1 THEN 'billing_report_preview'
                ELSE 'billing_report_final'
            END AS source_type,
            COUNT(*) AS record_count
        FROM copilot_billing_events
        GROUP BY is_preview
        ORDER BY source_type
        """
    ).fetchall()

    provider = "copilot_billing"
    epistemic_class = str(row["epistemic_class"])
    acquisition_mode = str(row["acquisition_mode"])
    return [
        AcquisitionSurfaceStat(
            surface_id=f"{provider}:{acquisition_mode}:{epistemic_class}",
            provider=provider,
            epistemic_class=epistemic_class,
            acquisition_mode=acquisition_mode,
            observed_records=int(row["observed_records"]),
            source_type_counts=_rows_to_count_map(source_rows),
            quarantined_records=_quarantine_count(conn, provider),
            analysis_safe_for_decision=int(row["analysis_safe_for_decision"] or 0),
            provider_truthfulness_assumed=int(row["provider_truthfulness_assumed"] or 0),
            annotation=ANNOTATION_CLASS_D,
        )
    ]


def collect_acquisition_surface_stats(conn: sqlite3.Connection) -> dict:
    """Return P6-bounded acquisition surface statistics.

    The returned shape intentionally excludes token totals, cost fields,
    provider ranking fields, trend fields, and optimization fields.
    """
    conn.row_factory = sqlite3.Row
    surfaces = _collect_class_c_surfaces(conn) + _collect_copilot_surface(conn)
    return {
        "display_name": "CodeBurn P6 acquisition surface statistics",
        "scope": "structural observation only",
        "analysis_safe_for_decision": 0,
        "provider_truthfulness_assumed": 0,
        "cross_provider_comparison": "forbidden",
        "cost_estimation": "forbidden",
        "optimization_decisions": "forbidden",
        "constraints": P6_CONSTRAINTS,
        "surfaces": [asdict(surface) for surface in surfaces],
    }


def render_text(summary: dict) -> str:
    lines = [
        "CodeBurn P6 acquisition surface statistics",
        "scope: structural observation only",
        "analysis_safe_for_decision: 0",
        "provider_truthfulness_assumed: 0",
        "cross_provider_comparison: forbidden",
        "cost_estimation: forbidden",
        "optimization_decisions: forbidden",
        "",
        "constraints: A-1, T-1, C-1, R-1, O-1, V-1",
        "",
    ]
    for surface in summary["surfaces"]:
        source_types = ", ".join(
            f"{key}={value}" for key, value in sorted(surface["source_type_counts"].items())
        ) or "none"
        lines.extend(
            [
                f"surface: {surface['surface_id']}",
                f"  provider: {surface['provider']}",
                f"  epistemic_class: {surface['epistemic_class']}",
                f"  acquisition_mode: {surface['acquisition_mode']}",
                f"  observed_records: {surface['observed_records']}",
                f"  source_types: {source_types}",
                f"  quarantined_records: {surface['quarantined_records']}",
                f"  annotation: {surface['annotation']}",
                "",
            ]
        )
    return "\n".join(lines).rstrip() + "\n"


def _build_demo_fixture_db(db_path: Path) -> sqlite3.Connection:
    from codeburn.phase1.claude_log_ingestor import _ensure_schema, ingest
    from codeburn.phase2.codex_log_ingestor import ingest_codex_session
    from codeburn.phase2.copilot_billing_ingestor import _ensure_db, ingest_copilot_csv

    conn = sqlite3.connect(str(db_path))
    conn.execute("PRAGMA foreign_keys = ON")
    _ensure_schema(conn)
    conn.execute(
        """
        INSERT OR IGNORE INTO sessions(session_id, task, created_at, data_quality)
        VALUES('claude-surface-demo', 'surface_stats_demo', '2026-06-03T00:00:00+00:00', 'partial')
        """
    )
    conn.execute(
        """
        INSERT OR IGNORE INTO sessions(session_id, task, created_at, data_quality)
        VALUES('codex-surface-demo', 'surface_stats_demo', '2026-06-03T00:00:00+00:00', 'partial')
        """
    )
    conn.commit()
    conn.close()

    examples = PROJECT_ROOT / "codeburn"
    ingest(
        examples / "phase1" / "examples" / "claude_smoke_fixture.jsonl",
        "claude-surface-demo",
        db_path,
    )

    conn = sqlite3.connect(str(db_path))
    conn.execute("PRAGMA foreign_keys = ON")
    _ensure_schema(conn)
    ingest_codex_session(
        str(examples / "phase2" / "examples" / "codex_smoke_fixture.jsonl"),
        "codex-surface-demo",
        conn,
    )
    conn.close()

    conn = _ensure_db(db_path)
    ingest_copilot_csv(
        str(examples / "phase2" / "examples" / "copilot_smoke_fixture.csv"),
        conn,
    )
    return conn


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Display CodeBurn P6 acquisition surface statistics."
    )
    parser.add_argument("--db", help="Path to existing CodeBurn SQLite DB")
    parser.add_argument(
        "--demo-fixtures",
        action="store_true",
        help="Build a temporary DB from bundled CodeBurn smoke fixtures.",
    )
    parser.add_argument("--json", action="store_true", help="Emit JSON instead of text.")
    args = parser.parse_args()

    if not args.db and not args.demo_fixtures:
        parser.error("provide --db or --demo-fixtures")

    temp_path: Path | None = None
    if args.demo_fixtures:
        tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
        tmp.close()
        temp_path = Path(tmp.name)
        conn = _build_demo_fixture_db(temp_path)
    else:
        conn = sqlite3.connect(str(Path(args.db).resolve()))

    try:
        summary = collect_acquisition_surface_stats(conn)
        if args.json:
            print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
        else:
            print(render_text(summary), end="")
        return 0
    finally:
        conn.close()
        if temp_path is not None:
            try:
                temp_path.unlink(missing_ok=True)
            except Exception:
                pass


if __name__ == "__main__":
    raise SystemExit(main())
