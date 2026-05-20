#!/usr/bin/env python3
"""
scripts/check_enumd_integration_state.py

Lightweight consistency check for the Enumd integration seam.

Verifies that the declared state in PLAN.md is backed by actual repo artifacts.
Does NOT parse PLAN.md. Does NOT require CI. Does NOT modify any state.

Checks
------
1. integrations/enumd/ingestor.py exists
2. integrations/enumd/schema.sample.json exists
3. integrations/enumd/mapping.md exists
4. integrations/enumd/usage.md exists
5. tests/test_enumd_ingestor.py exists
6. ingestor.py contains represents_agent_behavior assertion (routing directive guard)
7. ingestor.py contains calibration_profile in REQUIRED_TOP_LEVEL (provenance root)
8. scripts/analyze_e1b_distribution.py contains is_runtime_eligible (analysis boundary)
9. test file contains the four critical test functions (semantic guard coverage)

Exit codes
----------
0 — all checks pass
1 — one or more checks failed

Usage
-----
    python scripts/check_enumd_integration_state.py
    python scripts/check_enumd_integration_state.py --json
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent.parent

# ─────────────────────────────────────────────────────────────────────────────
# Check definitions
# ─────────────────────────────────────────────────────────────────────────────

def _file_exists(rel: str) -> tuple[bool, str]:
    path = _REPO_ROOT / rel
    if path.exists():
        return True, f"EXISTS  {rel}"
    return False, f"MISSING {rel}"


def _file_contains(rel: str, needle: str, label: str) -> tuple[bool, str]:
    path = _REPO_ROOT / rel
    if not path.exists():
        return False, f"MISSING {rel} (cannot check for {label!r})"
    text = path.read_text(encoding="utf-8")
    if needle in text:
        return True, f"FOUND   {label!r} in {rel}"
    return False, f"ABSENT  {label!r} in {rel}"


def run_checks() -> list[dict]:
    results = []

    def _check(ok: bool, message: str, check_id: str) -> None:
        results.append({"id": check_id, "ok": ok, "message": message})

    # ── Seam file existence ───────────────────────────────────────────────────

    ok, msg = _file_exists("integrations/enumd/ingestor.py")
    _check(ok, msg, "seam_ingestor_exists")

    ok, msg = _file_exists("integrations/enumd/schema.sample.json")
    _check(ok, msg, "seam_schema_sample_exists")

    ok, msg = _file_exists("integrations/enumd/mapping.md")
    _check(ok, msg, "seam_mapping_doc_exists")

    ok, msg = _file_exists("integrations/enumd/usage.md")
    _check(ok, msg, "seam_usage_doc_exists")

    # ── Test guard existence ──────────────────────────────────────────────────

    ok, msg = _file_exists("tests/test_enumd_ingestor.py")
    _check(ok, msg, "p1_test_file_exists")

    # ── Critical content: routing directive assertion in ingestor ─────────────

    ok, msg = _file_contains(
        "integrations/enumd/ingestor.py",
        "represents_agent_behavior",
        "represents_agent_behavior routing guard",
    )
    _check(ok, msg, "ingestor_routing_directive_present")

    ok, msg = _file_contains(
        "integrations/enumd/ingestor.py",
        "calibration_profile",
        "calibration_profile in validation",
    )
    _check(ok, msg, "ingestor_provenance_root_present")

    # ── Analysis boundary: is_runtime_eligible in distribution script ─────────

    ok, msg = _file_contains(
        "scripts/analyze_e1b_distribution.py",
        "is_runtime_eligible",
        "is_runtime_eligible",
    )
    _check(ok, msg, "p2_analysis_boundary_present")

    # ── Critical test function names (4 semantic guards) ─────────────────────

    critical_tests = [
        ("test_valid_sample_pass",                   "T1 valid sample pass"),
        ("test_missing_semantic_boundary_fail",       "T2 missing semantic_boundary"),
        ("test_represents_agent_behavior_true_fail",  "T3 represents_agent_behavior=True"),
        ("test_missing_provenance_field_fail",        "T4 missing provenance field"),
    ]
    for func_name, label in critical_tests:
        ok, msg = _file_contains(
            "tests/test_enumd_ingestor.py",
            f"def {func_name}",
            f"test guard — {label}",
        )
        _check(ok, msg, f"p1_guard_{func_name}")

    return results


# ─────────────────────────────────────────────────────────────────────────────
# Output
# ─────────────────────────────────────────────────────────────────────────────

def _emit_text(results: list[dict]) -> None:
    passed = sum(1 for r in results if r["ok"])
    failed = sum(1 for r in results if not r["ok"])
    print(f"Enumd integration state check — {passed} passed, {failed} failed\n")
    for r in results:
        prefix = "✓" if r["ok"] else "✗"
        print(f"  {prefix} [{r['id']}] {r['message']}")
    print()
    if failed:
        print(f"FAIL — {failed} check(s) failed; integration seam may have drifted from declared state.")
    else:
        print("OK — all checks pass; declared state matches repo artifacts.")


def _emit_json(results: list[dict]) -> None:
    passed = sum(1 for r in results if r["ok"])
    failed = sum(1 for r in results if not r["ok"])
    print(json.dumps({
        "ok": failed == 0,
        "passed": passed,
        "failed": failed,
        "checks": results,
    }, indent=2))


# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

def _cli() -> None:
    parser = argparse.ArgumentParser(
        description="Spot-check that the Enumd integration seam matches declared state in PLAN.md."
    )
    parser.add_argument(
        "--json", dest="emit_json", action="store_true",
        help="Emit machine-readable JSON instead of human text.",
    )
    args = parser.parse_args()

    results = run_checks()

    if args.emit_json:
        _emit_json(results)
    else:
        _emit_text(results)

    failed = sum(1 for r in results if not r["ok"])
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    _cli()
