#!/usr/bin/env python3
import argparse
import glob
import json
import os
from collections import defaultdict


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Summarize boundary telemetry trend from closeout artifacts.")
    parser.add_argument(
        "--telemetry-dir",
        default="artifacts/runtime/boundary-telemetry",
        help="Directory containing boundary_telemetry_*.json files.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=20,
        help="Number of most recent telemetry files to include.",
    )
    parser.add_argument(
        "--output",
        default="",
        help="Optional output path. If omitted, prints JSON to stdout.",
    )
    return parser.parse_args()


def extract_rule_id(hit_line: str) -> str:
    return hit_line.split("|", 1)[0].strip() if "|" in hit_line else "unknown_rule"


def summarize(files: list[str]) -> dict:
    status_counts: dict[str, int] = defaultdict(int)
    rule_stats: dict[str, dict] = defaultdict(lambda: {"hitCount": 0, "lastHitAtUtc": ""})
    app_test_total = 0
    app_source_total = 0
    app_test_hits = 0
    app_source_hits = 0
    latest_timestamp = ""

    for path in files:
        with open(path, "r", encoding="utf-8") as fh:
            payload = json.load(fh)

        ts = payload.get("generated_at_utc", "")
        status = payload.get("status", "unknown")
        status_counts[status] += 1
        if ts and ts > latest_timestamp:
            latest_timestamp = ts

        app_test_total += int(payload.get("app_test_boundary_rule_total", 0))
        app_source_total += int(payload.get("app_source_boundary_rule_total", 0))
        app_test_hits += int(payload.get("app_test_boundary_hit_count", 0))
        app_source_hits += int(payload.get("app_source_boundary_hit_count", 0))

        for line in payload.get("app_test_boundary_hits", []):
            rid = extract_rule_id(line)
            rule_stats[rid]["hitCount"] += 1
            if ts and ts > rule_stats[rid]["lastHitAtUtc"]:
                rule_stats[rid]["lastHitAtUtc"] = ts

        for line in payload.get("app_source_boundary_hits", []):
            rid = extract_rule_id(line)
            rule_stats[rid]["hitCount"] += 1
            if ts and ts > rule_stats[rid]["lastHitAtUtc"]:
                rule_stats[rid]["lastHitAtUtc"] = ts

    return {
        "windowSize": len(files),
        "latestTelemetryAtUtc": latest_timestamp,
        "statusCounts": dict(sorted(status_counts.items())),
        "aggregate": {
            "appTestRuleTotalSum": app_test_total,
            "appSourceRuleTotalSum": app_source_total,
            "appTestHitCountSum": app_test_hits,
            "appSourceHitCountSum": app_source_hits,
        },
        "ruleHitTrend": [
            {"ruleId": rid, **stats}
            for rid, stats in sorted(rule_stats.items(), key=lambda kv: (-kv[1]["hitCount"], kv[0]))
        ],
    }


def main() -> int:
    args = parse_args()
    pattern = os.path.join(args.telemetry_dir, "boundary_telemetry_*.json")
    files = sorted(glob.glob(pattern))
    if args.limit > 0:
        files = files[-args.limit :]

    result = summarize(files)
    serialized = json.dumps(result, ensure_ascii=False, indent=2) + "\n"

    if args.output:
        out_dir = os.path.dirname(args.output)
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
        with open(args.output, "w", encoding="utf-8") as fh:
            fh.write(serialized)
    else:
        print(serialized, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
