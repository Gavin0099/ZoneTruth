#!/usr/bin/env python3
"""CE-1C.3: Compact claim-enforcement receipt read-side validator.

Reads artifacts/claim-enforcement/claim-enforcement-receipts.ndjson and
reports:
- parse errors (malformed NDJSON lines)
- rows missing CE-1B required fields
- rows where source_packet_dir raw packet is present or missing
- rows where policy fields deviate from the CE-1B allowlist
- coverage gaps: raw packet exists but no compact receipt recorded

Does NOT modify any file.
Does NOT change runtime_completeness_audit.py or closeout_audit.py consumers.
"""

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from governance_tools.claim_enforcement_receipt_writer import (
    CE1B_REQUIRED_FIELDS,
    validate_receipt_fields,
)

_RECEIPTS_RELATIVE = "artifacts/claim-enforcement/claim-enforcement-receipts.ndjson"
_RUNTIME_RAW_ROOT_RELATIVE = "artifacts/session/claim-enforcement"
_LEGACY_RAW_ROOT_RELATIVE = "artifacts/claim-enforcement"

ALLOWED_RAW_PACKET_POLICY = {"session_local"}
ALLOWED_REPO_EVIDENCE_STATUS = {"compact_receipt"}
ALLOWED_EVIDENCE_SCOPE = {"session_scoped"}


# ---------------------------------------------------------------------------
# Row-level analysis
# ---------------------------------------------------------------------------


def analyse_row(row: dict, ce_root: Path) -> dict:
    """Return analysis dict for one receipt row."""
    missing_fields = validate_receipt_fields(row)

    policy_deviations: list[str] = []
    if row.get("raw_packet_policy") not in ALLOWED_RAW_PACKET_POLICY:
        policy_deviations.append(
            f"raw_packet_policy={row.get('raw_packet_policy')!r} not in allowlist {ALLOWED_RAW_PACKET_POLICY}"
        )
    if row.get("repo_evidence_status") not in ALLOWED_REPO_EVIDENCE_STATUS:
        policy_deviations.append(
            f"repo_evidence_status={row.get('repo_evidence_status')!r} not in allowlist {ALLOWED_REPO_EVIDENCE_STATUS}"
        )
    if row.get("evidence_scope") not in ALLOWED_EVIDENCE_SCOPE:
        policy_deviations.append(
            f"evidence_scope={row.get('evidence_scope')!r} not in allowlist {ALLOWED_EVIDENCE_SCOPE}"
        )

    source_dir = row.get("source_packet_dir", "")
    raw_packet_path = Path(source_dir) / "claim-enforcement-check.json" if source_dir else None
    raw_packet_present = raw_packet_path.exists() if raw_packet_path else False

    receipt_claims_present = row.get("claim_enforcement_check_present", None)
    presence_mismatch = (
        raw_packet_present != receipt_claims_present
        if receipt_claims_present is not None
        else False
    )

    return {
        "session_id": row.get("session_id", "<unknown>"),
        "missing_fields": missing_fields,
        "policy_deviations": policy_deviations,
        "raw_packet_present": raw_packet_present,
        "receipt_claims_present": receipt_claims_present,
        "presence_mismatch": presence_mismatch,
        "valid": not missing_fields and not policy_deviations and not presence_mismatch,
    }


# ---------------------------------------------------------------------------
# File-level parsing
# ---------------------------------------------------------------------------


def parse_receipts(receipts_path: Path) -> tuple[list[dict], list[dict]]:
    """
    Parse the NDJSON file.

    Returns (rows, parse_errors) where parse_errors are dicts with
    {line_number, raw, error}.
    """
    rows: list[dict] = []
    parse_errors: list[dict] = []

    if not receipts_path.exists():
        return rows, parse_errors

    for line_no, raw in enumerate(
        receipts_path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        raw = raw.strip()
        if not raw:
            continue
        try:
            rows.append(json.loads(raw))
        except json.JSONDecodeError as exc:
            parse_errors.append({"line_number": line_no, "raw": raw, "error": str(exc)})

    return rows, parse_errors


# ---------------------------------------------------------------------------
# Coverage gap detection
# ---------------------------------------------------------------------------


def detect_unreceipted_packets(
    ce_root: Path,
    receipted_session_ids: set,
    raw_packet_roots: "list[Path] | None" = None,
) -> list[str]:
    """
    Return session IDs where a raw claim-enforcement-check.json exists
    but no compact receipt has been recorded.

    ce_root is the repo evidence root (artifacts/claim-enforcement/).
    raw_packet_roots is the ordered list of directories to scan for raw session
    packets. If None, falls back to scanning ce_root only (legacy behaviour).

    CE-1D.2: callers should pass raw_packet_roots=[new_runtime_root, ce_root]
    to cover both the gitignored runtime path and the legacy repo-facing path.

    Only scans directories that contain claim-enforcement-check.json.
    Does not scan checker-tests/.
    """
    if raw_packet_roots is None:
        raw_packet_roots = [ce_root]

    unreceipted: list[str] = []
    seen: set[str] = set()

    for root in raw_packet_roots:
        if not root.exists():
            continue
        for child in root.iterdir():
            if not child.is_dir():
                continue
            if child.name == "checker-tests":
                continue
            if child.name in seen:
                continue
            seen.add(child.name)
            check_file = child / "claim-enforcement-check.json"
            if check_file.exists() and child.name not in receipted_session_ids:
                unreceipted.append(child.name)

    return sorted(unreceipted)


# ---------------------------------------------------------------------------
# Main validation function
# ---------------------------------------------------------------------------


def validate_receipts(
    receipts_path: Path,
    ce_root: Path,
    raw_packet_roots: "list[Path] | None" = None,
) -> dict:
    """
    Run full validation and return a structured report dict.

    ce_root is the repo evidence root (artifacts/claim-enforcement/).
    raw_packet_roots controls which directories are scanned for unreceipted raw
    packets. Defaults to [ce_root] for backward compatibility (legacy behaviour).
    CE-1D.2 callers should pass raw_packet_roots=[new_runtime_root, ce_root].

    Keys:
      receipts_path       — str path checked
      file_present        — bool
      parse_errors        — list of {line_number, raw, error}
      total_rows          — int
      valid_rows          — int
      invalid_rows        — list of row analyses with issues
      unreceipted_packets — list of session IDs with raw packet but no receipt
      overall_valid       — bool (no parse errors, no invalid rows, no unreceipted)
    """
    file_present = receipts_path.exists()
    rows, parse_errors = parse_receipts(receipts_path)

    row_analyses = [analyse_row(row, ce_root) for row in rows]
    invalid_rows = [a for a in row_analyses if not a["valid"]]
    valid_count = len(row_analyses) - len(invalid_rows)

    receipted_ids = {a["session_id"] for a in row_analyses}
    unreceipted = detect_unreceipted_packets(ce_root, receipted_ids, raw_packet_roots)

    return {
        "receipts_path": str(receipts_path),
        "raw_packet_roots": [str(p) for p in raw_packet_roots] if raw_packet_roots else [str(ce_root)],
        "file_present": file_present,
        "parse_errors": parse_errors,
        "total_rows": len(rows),
        "valid_rows": valid_count,
        "invalid_rows": invalid_rows,
        "unreceipted_packets": unreceipted,
        "overall_valid": (
            file_present
            and not parse_errors
            and not invalid_rows
            and not unreceipted
        ),
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _find_repo_root(start: Path) -> Path:
    candidate = start.resolve()
    for _ in range(20):
        if (candidate / ".git").exists():
            return candidate
        parent = candidate.parent
        if parent == candidate:
            break
        candidate = parent
    raise RuntimeError(f"Could not locate repository root from {start}")


def default_raw_packet_roots(repo_root: Path) -> list[Path]:
    """
    Return the CE-1D dual-read raw packet roots for command-line validation.

    The CLI should mirror the current runtime evidence split:
    - artifacts/session/claim-enforcement/ for new gitignored runtime packets
    - artifacts/claim-enforcement/ for legacy historical packets and compact receipts

    Library callers that omit raw_packet_roots retain legacy ce_root-only behavior.
    """
    return [
        repo_root / _RUNTIME_RAW_ROOT_RELATIVE,
        repo_root / _LEGACY_RAW_ROOT_RELATIVE,
    ]


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Validate compact claim-enforcement receipts (CE-1D dual-root aware)."
    )
    parser.add_argument("--repo-root", default=None)
    parser.add_argument(
        "--format",
        choices=["human", "json"],
        default="human",
    )
    parser.add_argument(
        "--fail-on-unreceipted",
        action="store_true",
        help="Exit non-zero if unreceipted raw packets are detected",
    )
    args = parser.parse_args()

    repo_root = Path(args.repo_root) if args.repo_root else _find_repo_root(Path(__file__))
    receipts_path = repo_root / _RECEIPTS_RELATIVE
    ce_root = repo_root / "artifacts" / "claim-enforcement"
    raw_packet_roots = default_raw_packet_roots(repo_root)

    report = validate_receipts(receipts_path, ce_root, raw_packet_roots=raw_packet_roots)

    if args.format == "json":
        print(json.dumps(report, indent=2, ensure_ascii=False))
    else:
        print(f"[claim_enforcement_receipt_validator]")
        print(f"  receipts file:    {'present' if report['file_present'] else 'MISSING'}")
        print(f"  raw roots:        {len(report['raw_packet_roots'])}")
        print(f"  total rows:       {report['total_rows']}")
        print(f"  valid rows:       {report['valid_rows']}")
        print(f"  parse errors:     {len(report['parse_errors'])}")
        print(f"  invalid rows:     {len(report['invalid_rows'])}")
        print(f"  unreceipted:      {len(report['unreceipted_packets'])}")
        print(f"  overall valid:    {report['overall_valid']}")
        if report["parse_errors"]:
            print("  PARSE ERRORS:")
            for e in report["parse_errors"]:
                print(f"    line {e['line_number']}: {e['error']}")
        if report["invalid_rows"]:
            print("  INVALID ROWS:")
            for r in report["invalid_rows"]:
                print(f"    session={r['session_id']}")
                if r["missing_fields"]:
                    print(f"      missing_fields: {r['missing_fields']}")
                if r["policy_deviations"]:
                    print(f"      policy_deviations: {r['policy_deviations']}")
                if r["presence_mismatch"]:
                    print(
                        f"      presence_mismatch: receipt claims present={r['receipt_claims_present']}"
                        f" but disk={r['raw_packet_present']}"
                    )
        if report["unreceipted_packets"]:
            print("  UNRECEIPTED PACKETS (raw exists, no compact receipt):")
            for sid in report["unreceipted_packets"]:
                print(f"    {sid}")

    fail = not report["overall_valid"] and (
        report["parse_errors"]
        or report["invalid_rows"]
        or (args.fail_on_unreceipted and report["unreceipted_packets"])
    )
    sys.exit(1 if fail else 0)


if __name__ == "__main__":
    main()
