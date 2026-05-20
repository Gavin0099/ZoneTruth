#!/usr/bin/env python3
"""
Lightweight consistency check for token telemetry contract layering.

This script verifies that the design contract, runtime-valid contract, and
their transitional interpretation guards remain aligned on the current token
telemetry truth boundary.

Checks
------
1. v0.1 design contract declares provenance disclosure markers.
2. v0.1 design contract carries a transitional reading note for current runtime.
3. runtime-valid contract explicitly says provenance disclosure is not yet enforced.
4. runtime-valid contract defines the transitional interpretation of current
   `token_observability_level = step_level`.

Exit codes
----------
0 — all checks pass
1 — one or more checks failed

Usage
-----
    python scripts/check_token_telemetry_contract_consistency.py
    python scripts/check_token_telemetry_contract_consistency.py --json
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
V01_CONTRACT = REPO_ROOT / "codeburn" / "phase1" / "TOKEN_TELEMETRY_CONTRACT_V0_1.md"
RUNTIME_CONTRACT = REPO_ROOT / "codeburn" / "phase1" / "DATA_VALIDITY_CONTRACT.md"


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _contains(text: str, needle: str) -> bool:
    return needle in text


def _check(results: list[dict[str, object]], check_id: str, ok: bool, message: str) -> None:
    results.append({"id": check_id, "ok": ok, "message": message})


def run_checks() -> list[dict[str, object]]:
    results: list[dict[str, object]] = []

    v01_text = _read_text(V01_CONTRACT)
    runtime_text = _read_text(RUNTIME_CONTRACT)

    _check(
        results,
        "v01_declares_token_source_summary",
        _contains(v01_text, "`token_source_summary`") and _contains(v01_text, "provider | estimated | mixed | unknown"),
        "v0.1 contract declares token_source_summary provenance disclosure.",
    )

    _check(
        results,
        "v01_declares_provenance_warning",
        _contains(v01_text, "`provenance_warning`") and _contains(v01_text, "mixed_sources"),
        "v0.1 contract declares provenance_warning for mixed-source surfaces.",
    )

    _check(
        results,
        "v01_has_transitional_reading_note",
        _contains(v01_text, "TRANSITIONAL READING NOTE:")
        and _contains(v01_text, "current Phase 1/2 runtime and report surfaces do NOT fully implement")
        and _contains(v01_text, "all current token observability SHOULD be treated as"),
        "v0.1 contract warns readers not to project intended semantics onto current runtime surfaces.",
    )

    _check(
        results,
        "runtime_marks_provenance_not_enforced",
        _contains(runtime_text, "NOT currently")
        and _contains(runtime_text, "`provenance_warning`")
        and _contains(runtime_text, "MUST NOT be assumed to provide provenance-complete token"),
        "runtime-valid contract marks provenance disclosure requirements as not yet enforced.",
    )

    _check(
        results,
        "runtime_has_transitional_step_level_rule",
        _contains(runtime_text, "## Transitional Rule")
        and _contains(runtime_text, "`token_observability_level = step_level` MUST be treated as provenance-unverified")
        and _contains(runtime_text, "MUST NOT be interpreted as provider-only"),
        "runtime-valid contract defines transitional interpretation for current step_level surfaces.",
    )

    _check(
        results,
        "runtime_has_absence_guard",
        _contains(runtime_text, "Absence of `provenance_warning` MUST NOT be interpreted as absence of mixed sources."),
        "runtime-valid contract keeps absence of provenance_warning from being misread as provenance purity.",
    )

    return results


def _emit_text(results: list[dict[str, object]]) -> None:
    passed = sum(1 for result in results if result["ok"])
    failed = sum(1 for result in results if not result["ok"])
    print(f"Token telemetry contract consistency check — {passed} passed, {failed} failed\n")
    for result in results:
        prefix = "✓" if result["ok"] else "✗"
        print(f"  {prefix} [{result['id']}] {result['message']}")
    print()
    if failed:
        print("FAIL — contract layering drift detected; design/runtime/transitional truths are out of sync.")
    else:
        print("OK — token telemetry design, runtime, and transitional contract layers are aligned.")


def _emit_json(results: list[dict[str, object]]) -> None:
    passed = sum(1 for result in results if result["ok"])
    failed = sum(1 for result in results if not result["ok"])
    print(
        json.dumps(
            {
                "ok": failed == 0,
                "passed": passed,
                "failed": failed,
                "checks": results,
            },
            indent=2,
        )
    )


def _cli() -> None:
    parser = argparse.ArgumentParser(
        description="Check token telemetry design/runtime/transitional contract consistency."
    )
    parser.add_argument(
        "--json",
        dest="emit_json",
        action="store_true",
        help="Emit machine-readable JSON instead of human text.",
    )
    args = parser.parse_args()

    results = run_checks()
    if args.emit_json:
        _emit_json(results)
    else:
        _emit_text(results)

    failed = sum(1 for result in results if not result["ok"])
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    _cli()