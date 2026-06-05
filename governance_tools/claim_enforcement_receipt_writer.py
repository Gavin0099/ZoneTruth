#!/usr/bin/env python3
"""CE-1C.1: Compact claim-enforcement receipt writer.

Appends one compact receipt row to
artifacts/claim-enforcement/claim-enforcement-receipts.ndjson
according to the CE-1B minimum field contract defined in
governance/CLAIM_ENFORCEMENT_EVIDENCE_POLICY.md.

This module ONLY writes compact receipts. It does NOT:
- modify raw session-* packets
- change .gitignore rules
- alter runtime_completeness_audit.py or closeout_audit.py consumers
"""

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


RECEIPT_FILE_RELATIVE = "artifacts/claim-enforcement/claim-enforcement-receipts.ndjson"
RAW_PACKET_RUNTIME_ROOT_RELATIVE = "artifacts/session/claim-enforcement"
SCHEMA_VERSION = "0.1"
ARTIFACT_TYPE = "claim-enforcement-receipt"
RAW_PACKET_POLICY_DEFAULT = "session_local"
REPO_EVIDENCE_STATUS_DEFAULT = "compact_receipt"
EVIDENCE_SCOPE_DEFAULT = "session_scoped"


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


def build_receipt(
    session_id: str,
    source_packet_dir: str,
    claim_enforcement_check_present: bool,
    recorded_at: str | None = None,
    raw_packet_policy: str = RAW_PACKET_POLICY_DEFAULT,
    repo_evidence_status: str = REPO_EVIDENCE_STATUS_DEFAULT,
    evidence_scope: str = EVIDENCE_SCOPE_DEFAULT,
) -> dict:
    if recorded_at is None:
        recorded_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return {
        "schema_version": SCHEMA_VERSION,
        "artifact_type": ARTIFACT_TYPE,
        "session_id": session_id,
        "recorded_at": recorded_at,
        "claim_enforcement_check_present": claim_enforcement_check_present,
        "source_packet_dir": source_packet_dir,
        "raw_packet_policy": raw_packet_policy,
        "repo_evidence_status": repo_evidence_status,
        "evidence_scope": evidence_scope,
    }


def append_receipt(receipt: dict, receipts_path: Path) -> None:
    receipts_path.parent.mkdir(parents=True, exist_ok=True)
    line = json.dumps(receipt, ensure_ascii=False, separators=(",", ":"))
    with receipts_path.open("a", encoding="utf-8") as fh:
        fh.write(line + "\n")


def write_receipt_for_session(
    session_id: str,
    repo_root: Path | None = None,
    recorded_at: str | None = None,
) -> dict:
    if repo_root is None:
        repo_root = _find_repo_root(Path(__file__))

    receipts_path = repo_root / RECEIPT_FILE_RELATIVE
    raw_runtime_root = repo_root / RAW_PACKET_RUNTIME_ROOT_RELATIVE
    source_packet_dir = str(raw_runtime_root / session_id)
    check_file = raw_runtime_root / session_id / "claim-enforcement-check.json"
    present = check_file.exists()

    receipt = build_receipt(
        session_id=session_id,
        source_packet_dir=source_packet_dir,
        claim_enforcement_check_present=present,
        recorded_at=recorded_at,
    )
    append_receipt(receipt, receipts_path)
    return receipt


CE1B_REQUIRED_FIELDS = {
    "schema_version",
    "artifact_type",
    "session_id",
    "recorded_at",
    "claim_enforcement_check_present",
    "source_packet_dir",
    "raw_packet_policy",
    "repo_evidence_status",
    "evidence_scope",
}


def validate_receipt_fields(receipt: dict) -> list[str]:
    return sorted(CE1B_REQUIRED_FIELDS - set(receipt.keys()))


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Append a compact CE-1B receipt row for a claim-enforcement session."
    )
    parser.add_argument("--session-id", required=True, help="Session identifier")
    parser.add_argument(
        "--repo-root",
        default=None,
        help="Repository root (auto-detected if omitted)",
    )
    parser.add_argument(
        "--recorded-at",
        default=None,
        help="ISO-8601 UTC timestamp (default: now)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the receipt row without writing",
    )
    args = parser.parse_args()

    repo_root = Path(args.repo_root) if args.repo_root else None

    if repo_root is None:
        try:
            repo_root = _find_repo_root(Path(__file__))
        except RuntimeError as exc:
            print(f"[claim_enforcement_receipt_writer] error: {exc}", file=sys.stderr)
            sys.exit(1)

    raw_runtime_root = repo_root / RAW_PACKET_RUNTIME_ROOT_RELATIVE
    source_packet_dir = str(raw_runtime_root / args.session_id)
    check_file = raw_runtime_root / args.session_id / "claim-enforcement-check.json"
    present = check_file.exists()

    receipt = build_receipt(
        session_id=args.session_id,
        source_packet_dir=source_packet_dir,
        claim_enforcement_check_present=present,
        recorded_at=args.recorded_at,
    )

    missing = validate_receipt_fields(receipt)
    if missing:
        print(
            f"[claim_enforcement_receipt_writer] error: missing fields: {missing}",
            file=sys.stderr,
        )
        sys.exit(1)

    if args.dry_run:
        print(json.dumps(receipt, ensure_ascii=False, indent=2))
        return

    receipts_path = repo_root / RECEIPT_FILE_RELATIVE
    append_receipt(receipt, receipts_path)
    print(f"[claim_enforcement_receipt_writer] appended receipt for {args.session_id}")
    print(f"  -> {receipts_path}")


if __name__ == "__main__":
    main()
