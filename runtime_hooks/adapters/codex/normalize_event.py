#!/usr/bin/env python3
"""
Normalize Codex hook payloads into the shared runtime event contract.
"""

from __future__ import annotations

import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from runtime_hooks.adapters.shared_normalizer import cli_main, normalize_payload as _normalize_payload


def normalize_event(payload: dict, event_type: str) -> dict:
    return _normalize_payload(payload, harness="codex", event_type=event_type)


if __name__ == "__main__":
    cli_main("codex")
