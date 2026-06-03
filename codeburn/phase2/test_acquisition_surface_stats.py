from __future__ import annotations

import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

from codeburn.phase1.claude_log_ingestor import _ensure_schema, ingest
from codeburn.phase2.acquisition_surface_stats import (
    collect_acquisition_surface_stats,
    render_text,
)
from codeburn.phase2.codex_log_ingestor import ingest_codex_session
from codeburn.phase2.copilot_billing_ingestor import _ensure_db, ingest_copilot_csv


PROJECT_ROOT = Path(__file__).resolve().parents[2]


class AcquisitionSurfaceStatsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
        self.tmp.close()
        self.db_path = Path(self.tmp.name)
        self.examples = PROJECT_ROOT / "codeburn"

        conn = sqlite3.connect(str(self.db_path))
        conn.execute("PRAGMA foreign_keys = ON")
        _ensure_schema(conn)
        conn.execute(
            """
            INSERT INTO sessions(session_id, task, created_at, data_quality)
            VALUES('claude-test-session', 'surface_stats_test', '2026-06-03T00:00:00+00:00', 'partial')
            """
        )
        conn.execute(
            """
            INSERT INTO sessions(session_id, task, created_at, data_quality)
            VALUES('codex-test-session', 'surface_stats_test', '2026-06-03T00:00:00+00:00', 'partial')
            """
        )
        conn.commit()
        conn.close()

        ingest(
            self.examples / "phase1" / "examples" / "claude_smoke_fixture.jsonl",
            "claude-test-session",
            self.db_path,
        )

        conn = sqlite3.connect(str(self.db_path))
        conn.execute("PRAGMA foreign_keys = ON")
        _ensure_schema(conn)
        ingest_codex_session(
            str(self.examples / "phase2" / "examples" / "codex_smoke_fixture.jsonl"),
            "codex-test-session",
            conn,
        )
        conn.close()

        conn = _ensure_db(self.db_path)
        ingest_copilot_csv(
            str(self.examples / "phase2" / "examples" / "copilot_smoke_fixture.csv"),
            conn,
        )
        conn.close()

    def tearDown(self) -> None:
        self.db_path.unlink(missing_ok=True)

    def _summary(self) -> dict:
        conn = sqlite3.connect(str(self.db_path))
        try:
            return collect_acquisition_surface_stats(conn)
        finally:
            conn.close()

    def testFixtureStatsSummarizeEachAcquisitionSurface(self) -> None:
        summary = self._summary()
        surfaces = {surface["surface_id"]: surface for surface in summary["surfaces"]}

        self.assertEqual(
            set(surfaces),
            {
                "claude:session_log_ingestion:Class C",
                "codex:session_log_ingestion:Class C",
                "copilot_billing:billing_report_daily_aggregate:Class D",
            },
        )
        self.assertEqual(surfaces["claude:session_log_ingestion:Class C"]["observed_records"], 3)
        self.assertEqual(surfaces["codex:session_log_ingestion:Class C"]["observed_records"], 2)
        self.assertEqual(
            surfaces["copilot_billing:billing_report_daily_aggregate:Class D"]["observed_records"],
            2,
        )
        self.assertEqual(
            surfaces["claude:session_log_ingestion:Class C"]["source_type_counts"],
            {"estimated": 3},
        )
        self.assertEqual(
            surfaces["copilot_billing:billing_report_daily_aggregate:Class D"]["source_type_counts"],
            {"billing_report_preview": 2},
        )

    def testP6ConstraintsRemainExplicitAndDecisionUnsafe(self) -> None:
        summary = self._summary()

        self.assertEqual(summary["analysis_safe_for_decision"], 0)
        self.assertEqual(summary["provider_truthfulness_assumed"], 0)
        self.assertEqual(summary["cross_provider_comparison"], "forbidden")
        self.assertEqual(summary["cost_estimation"], "forbidden")
        self.assertEqual(summary["optimization_decisions"], "forbidden")
        self.assertEqual(set(summary["constraints"]), {"A-1", "T-1", "C-1", "R-1", "O-1", "V-1"})

        for surface in summary["surfaces"]:
            self.assertEqual(surface["analysis_safe_for_decision"], 0)
            self.assertEqual(surface["provider_truthfulness_assumed"], 0)
            self.assertIn("not decision-authoritative", surface["annotation"])
            if surface["epistemic_class"] == "Class C":
                self.assertIn("observer-reconstructed", surface["annotation"])

    def testRenderedDisplayAvoidsCostComparisonEfficiencyAndTokenTotals(self) -> None:
        summary = self._summary()
        rendered = render_text(summary)
        encoded = json.dumps(summary, ensure_ascii=False, sort_keys=True)
        combined = f"{rendered}\n{encoded}"

        forbidden_fragments = [
            "total_tokens",
            "prompt_tokens",
            "completion_tokens",
            "aic_quantity",
            "cost_per",
            "spend",
            "billing estimate",
            "efficiency",
            "ranking",
            "recommendation",
            "optimization opportunity",
            "usage by provider",
        ]
        for fragment in forbidden_fragments:
            self.assertNotIn(fragment, combined)


if __name__ == "__main__":
    unittest.main()
