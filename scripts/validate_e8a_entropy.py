#!/usr/bin/env python3
"""
scripts/validate_e8a_entropy.py
---------------------------------
Validates E8a event log files for measurement validity.

Computes:
  - effective_entries : count(distinct event_id)   — deduplicated sample size
  - entropy           : count(distinct state_hash) / total_steps
  - signal_ratio      : steps_with_signal / effective_entries
  - expected_match    : fraction of steps where observed_signal == expected_signal

Verdict:
  VALID   — entropy >= MIN_VALID_ENTROPY and effective_entries > 0
  INVALID — entropy < MIN_VALID_ENTROPY (dataset is degenerate; like "state sampling")
  EMPTY   — no events in log

E1b readiness (per scenario):
  READY   — VALID + effective_entries >= window_size (default 20)
  PARTIAL — VALID but entries < window_size
  NOT_READY — INVALID or EMPTY

Usage
-----
    python scripts/validate_e8a_entropy.py --out-dir artifacts/e8a_fixture_output
    python scripts/validate_e8a_entropy.py --file artifacts/e8a_fixture_output/e8a-event-log-a_normal_ci.ndjson
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_REPO_ROOT))
sys.path.insert(0, str(_REPO_ROOT / "tests"))

from fixtures.e8a_event_scenarios.base import (  # noqa: E402
    MIN_VALID_ENTROPY,
    compute_effective_entries,
    compute_entropy,
    compute_signal_ratio,
)

DEFAULT_WINDOW_SIZE = 20


# ── Validation logic ───────────────────────────────────────────────────────────

def validate_event_log(records: list[dict], window_size: int = DEFAULT_WINDOW_SIZE) -> dict:
    """
    Given a list of EventRecord dicts (from one scenario's NDJSON log),
    compute measurement quality metrics.

    Returns a result dict with:
      raw_entries       : total records in log
      effective_entries : count of distinct event_ids
      distinct_states   : count of distinct state_hashes
      entropy           : distinct_states / raw_entries
      signal_ratio      : signals / effective_entries
      expected_match_ratio: correct predictions / raw_entries
      measurement_valid : entropy >= MIN_VALID_ENTROPY
      e1b_ready         : valid AND effective_entries >= window_size
      verdict           : "VALID" | "INVALID" | "EMPTY"
      e1b_readiness     : "READY" | "PARTIAL" | "NOT_READY"
      notes             : list of human-readable observations
    """
    if not records:
        return {
            "raw_entries": 0,
            "effective_entries": 0,
            "distinct_states": 0,
            "entropy": 0.0,
            "signal_ratio": 0.0,
            "expected_match_ratio": 0.0,
            "measurement_valid": False,
            "e1b_ready": False,
            "verdict": "EMPTY",
            "e1b_readiness": "NOT_READY",
            "notes": ["No events in log."],
        }

    event_ids = [r["event_id"] for r in records]
    state_hashes = [r["state_hash"] for r in records]

    raw_entries = len(records)
    effective_entries = compute_effective_entries(event_ids)
    distinct_states = len(set(state_hashes))
    entropy = compute_entropy(state_hashes)

    # Signal ratio over EFFECTIVE entries (deduplicated)
    # For deduplication: take first occurrence of each event_id
    seen_event_ids: set[str] = set()
    deduped: list[dict] = []
    for r in records:
        if r["event_id"] not in seen_event_ids:
            seen_event_ids.add(r["event_id"])
            deduped.append(r)

    signals_in_deduped = sum(1 for r in deduped if r.get("observed_signal"))
    signal_ratio = compute_signal_ratio(signals_in_deduped, effective_entries)

    # Expected match (over all raw records)
    matches = sum(
        1 for r in records
        if r.get("expected_signal") == r.get("observed_signal")
    )
    expected_match_ratio = round(matches / raw_entries, 4) if raw_entries else 0.0

    measurement_valid = entropy >= MIN_VALID_ENTROPY
    e1b_ready = measurement_valid and effective_entries >= window_size

    if not measurement_valid:
        verdict = "INVALID"
    else:
        verdict = "VALID"

    if e1b_ready:
        e1b_readiness = "READY"
    elif measurement_valid:
        e1b_readiness = "PARTIAL"
    else:
        e1b_readiness = "NOT_READY"

    notes: list[str] = []
    if raw_entries > effective_entries:
        dupes = raw_entries - effective_entries
        notes.append(
            f"{dupes} duplicate event_ids removed "
            f"(raw={raw_entries} → effective={effective_entries})"
        )
    if entropy < MIN_VALID_ENTROPY:
        notes.append(
            f"entropy={entropy:.3f} < threshold={MIN_VALID_ENTROPY} — "
            "dataset is degenerate (state sampling, not event sampling)"
        )
    if expected_match_ratio < 1.0:
        mismatch = raw_entries - matches
        notes.append(
            f"{mismatch} steps had unexpected signal outcome "
            f"(expected_match_ratio={expected_match_ratio})"
        )
    if not notes:
        notes.append("Measurement looks healthy.")

    return {
        "raw_entries": raw_entries,
        "effective_entries": effective_entries,
        "distinct_states": distinct_states,
        "entropy": round(entropy, 4),
        "signal_ratio": signal_ratio,
        "expected_match_ratio": expected_match_ratio,
        "measurement_valid": measurement_valid,
        "e1b_ready": e1b_ready,
        "verdict": verdict,
        "e1b_readiness": e1b_readiness,
        "notes": notes,
    }


def print_report(scenario: str, result: dict) -> None:
    verdict_color = {
        "VALID": "\033[32m",   # green
        "INVALID": "\033[31m", # red
        "EMPTY": "\033[33m",   # yellow
    }.get(result["verdict"], "")
    ready_color = {
        "READY": "\033[32m",
        "PARTIAL": "\033[33m",
        "NOT_READY": "\033[31m",
    }.get(result["e1b_readiness"], "")
    reset = "\033[0m"

    print(f"\n{'─'*60}")
    print(f"Scenario : {scenario}")
    print(f"{'─'*60}")
    print(f"  raw_entries       : {result['raw_entries']}")
    print(f"  effective_entries : {result['effective_entries']}")
    print(f"  distinct_states   : {result['distinct_states']}")
    print(f"  entropy           : {result['entropy']:.4f}  (min={MIN_VALID_ENTROPY})")
    print(f"  signal_ratio      : {result['signal_ratio']:.4f}")
    print(f"  expected_match    : {result['expected_match_ratio']:.4f}")
    print(f"  verdict           : {verdict_color}{result['verdict']}{reset}")
    print(f"  E1b readiness     : {ready_color}{result['e1b_readiness']}{reset}")
    for note in result["notes"]:
        print(f"  ⚠  {note}")


# ── CLI ────────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Validate E8a event log entropy and E1b readiness"
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--out-dir", help="Directory containing e8a-event-log-*.ndjson files")
    group.add_argument("--file", help="Single event log NDJSON file to validate")
    parser.add_argument(
        "--window-size",
        type=int,
        default=DEFAULT_WINDOW_SIZE,
        help=f"E1b window_size threshold (default: {DEFAULT_WINDOW_SIZE})",
    )
    parser.add_argument("--json", action="store_true", help="Output results as JSON")
    args = parser.parse_args()

    files: list[Path] = []
    if args.file:
        files = [Path(args.file)]
    else:
        out_dir = Path(args.out_dir)
        files = sorted(out_dir.glob("e8a-event-log-*.ndjson"))
        if not files:
            print(f"No e8a-event-log-*.ndjson files found in {out_dir}")
            sys.exit(1)

    all_results: dict[str, dict] = {}
    for fpath in files:
        scenario = fpath.stem.replace("e8a-event-log-", "")
        records = []
        for line in fpath.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line:
                try:
                    records.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
        result = validate_event_log(records, args.window_size)
        all_results[scenario] = result

    if args.json:
        print(json.dumps(all_results, indent=2, ensure_ascii=False))
        return

    for scenario, result in all_results.items():
        print_report(scenario, result)

    # Summary
    print(f"\n{'='*60}")
    print("E1b Readiness Summary")
    print(f"{'='*60}")
    e1b_status = {s: r["e1b_readiness"] for s, r in all_results.items()}
    all_ready = all(v == "READY" for v in e1b_status.values())
    for scenario, status in e1b_status.items():
        mark = "✅" if status == "READY" else ("⚠" if status == "PARTIAL" else "❌")
        print(f"  {mark} {scenario:30s} {status}")
    print()
    if all_ready:
        print("✅ All scenarios READY — E1b evaluation can proceed.")
    else:
        not_ready = [s for s, v in e1b_status.items() if v != "READY"]
        print(f"❌ E1b NOT READY — {len(not_ready)} scenario(s) not ready: {not_ready}")
        print("   Run with --repeats N to accumulate more effective entries.")


if __name__ == "__main__":
    main()
