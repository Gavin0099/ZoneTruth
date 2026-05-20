#!/usr/bin/env python3
"""
gap_disposition_reader.py — Layer 3 consumer in the MOB Verifier v0.3 architecture.

Reads Layer 1 observation ndjson + Layer 2 YAML annotation, derives consequence
eligibility for each gap_observed record.

Anti-write-back contract (FM-05 — HARD RULE):
  This module MUST NOT write to any Layer 1 ndjson or Layer 2 YAML file.
  All input files are opened in read mode only.
  The only permitted output artifact is the Layer 3 gap_status_report.json.

Three-layer architecture:
  Layer 1  mob_verifier.py → observation.ndjson         (machine output, read-only here)
  Layer 2  reviewer       → mob-gap-disposition.yaml    (human annotation, read-only here)
  Layer 3  this module    → gap_status_report.json      (derived, write-permitted)
"""

from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import yaml


ALLOWED_DISPOSITIONS = frozenset({"confirmed", "rejected", "needs_more_evidence"})

SCHEMA_VERSION = "1.0"


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


# ── Layer 1: load observations ────────────────────────────────────────────────


def load_observations(ndjson_path: Path) -> list[dict[str, Any]]:
    """Read gap_observed records from a Layer 1 ndjson file.

    FM-05 enforcement: opens the file in read-only mode ("r").
    Any attempt to write to Layer 1 from this function is a contract violation.
    """
    records: list[dict[str, Any]] = []
    with ndjson_path.open("r", encoding="utf-8") as fh:  # FM-05: read-only
        for line in fh:
            line = line.strip()
            if not line:
                continue
            record = json.loads(line)
            if record.get("record_type") == "gap_observed":
                records.append(record)
    return records


# ── Layer 2: load annotations ─────────────────────────────────────────────────


def load_yaml_annotations(yaml_path: Path) -> list[dict[str, Any]]:
    """Read Layer 2 YAML annotation file.

    FM-05 enforcement: opens the file in read-only mode ("r").
    FM-01 enforcement: this function never writes YAML; it is strictly read-only on Layer 2.
    """
    with yaml_path.open("r", encoding="utf-8") as fh:  # FM-05: read-only
        data = yaml.safe_load(fh)
    return list(data.get("entries", [])) if data else []


# ── Annotation validation ─────────────────────────────────────────────────────


def validate_annotation(entry: dict[str, Any]) -> dict[str, Any]:
    """Validate and normalize one YAML annotation entry.

    FM-02: disposition=confirmed with empty rationale → downgrade to needs_more_evidence.
    FM-03: consequence_eligible=true requires disposition=confirmed;
           any other combination is a validation error — entry is rejected.

    Returns a normalized copy of the entry (does not mutate input).
    """
    mob_id = entry.get("mob_id", "<unknown>")
    disposition = str(entry.get("disposition", "")).strip()
    rationale = str(entry.get("rationale", "")).strip()
    consequence_eligible = bool(entry.get("consequence_eligible", False))

    # FM-02: confirmed + empty rationale → downgrade
    if disposition == "confirmed" and not rationale:
        disposition = "needs_more_evidence"
        consequence_eligible = False

    # FM-03: consequence_eligible=true only permitted when disposition=confirmed
    if consequence_eligible and disposition != "confirmed":
        raise ValueError(
            f"FM-03 violation for mob_id={mob_id!r}: "
            f"consequence_eligible=true requires disposition='confirmed', "
            f"got disposition={disposition!r}"
        )

    return {
        **entry,
        "disposition": disposition,
        "consequence_eligible": consequence_eligible,
    }


# ── Layer 3: derive status records ───────────────────────────────────────────


def derive_status_records(
    observations: list[dict[str, Any]],
    annotations: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """Derive Layer 3 consequence eligibility from Layer 1 + Layer 2.

    Unmatched observations (no YAML entry) → disposition_pending=true,
    consequence_eligible=false. Prevents unreviewed gaps from entering
    consequence eligibility.
    """
    # Index validated annotations by observed_gap_id (FM-01: index is read-only dict)
    annotation_index: dict[str, dict[str, Any]] = {}
    for entry in annotations:
        validated = validate_annotation(entry)
        gap_id = str(validated.get("observed_gap_id", ""))
        if gap_id:
            annotation_index[gap_id] = validated

    derived_at = _utc_now()
    results: list[dict[str, Any]] = []

    for obs in observations:
        gap_id = str(obs.get("observed_gap_id", ""))
        mob_id = str(obs.get("mob_id", ""))
        observation_status = str(obs.get("record_type", "gap_observed"))

        if gap_id in annotation_index:
            ann = annotation_index[gap_id]
            results.append({
                "observed_gap_id": gap_id,
                "mob_id": mob_id,
                "observation_status": observation_status,
                "disposition": ann.get("disposition"),
                "consequence_eligible": bool(ann.get("consequence_eligible", False)),
                "reviewer": ann.get("reviewer"),
                "reviewed_at": ann.get("reviewed_at"),
                "derived_at": derived_at,
            })
        else:
            # No YAML entry → pending review; never eligible
            results.append({
                "observed_gap_id": gap_id,
                "mob_id": mob_id,
                "observation_status": observation_status,
                "disposition": None,
                "consequence_eligible": False,
                "disposition_pending": True,
                "derived_at": derived_at,
            })

    return results


# ── Layer 3 output ────────────────────────────────────────────────────────────


def write_status_report(output_path: Path, records: list[dict[str, Any]]) -> Path:
    """Write Layer 3 gap_status_report.json.

    This is the ONLY write operation permitted in this module.
    """
    output_path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema_version": SCHEMA_VERSION,
        "generated_at": _utc_now(),
        "record_count": len(records),
        "records": records,
    }
    output_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return output_path


# ── Main entrypoint ───────────────────────────────────────────────────────────


def run(
    *,
    ndjson_path: Path,
    yaml_path: Path,
    output_path: Path,
) -> dict[str, Any]:
    """Read Layer 1 + Layer 2, write Layer 3 gap_status_report.json."""
    observations = load_observations(ndjson_path)
    annotations = load_yaml_annotations(yaml_path) if yaml_path.exists() else []
    records = derive_status_records(observations, annotations)
    write_status_report(output_path, records)
    return {
        "observation_count": len(observations),
        "annotation_count": len(annotations),
        "record_count": len(records),
        "output_path": str(output_path),
    }


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(
        description=(
            "gap_disposition_reader — MOB Verifier v0.3 Layer 3 consumer. "
            "Reads observation ndjson (Layer 1) + review YAML (Layer 2), "
            "writes gap_status_report.json (Layer 3)."
        )
    )
    parser.add_argument("--ndjson", required=True, help="Path to observation ndjson (Layer 1)")
    parser.add_argument("--yaml", required=True, help="Path to mob-gap-disposition.yaml (Layer 2)")
    parser.add_argument("--output", required=True, help="Output path for gap_status_report.json")
    args = parser.parse_args()

    result = run(
        ndjson_path=Path(args.ndjson),
        yaml_path=Path(args.yaml),
        output_path=Path(args.output),
    )
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
