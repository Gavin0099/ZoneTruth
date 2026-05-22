#!/usr/bin/env python3
"""
CodeBurn Phase 1 — Entry Guard (M9)

Prints a mandatory status header to stderr on every CLI invocation.
This ensures the Phase 1 CLOSED status and decision-usage prohibition
are visible regardless of which entry point is used.

Do NOT suppress or remove this header. Its purpose is to make the
Phase 1 governance boundary unavoidable in terminal sessions.
"""
from __future__ import annotations

import sys

_HEADER = (
    "CodeBurn Phase 1 | Status: CLOSED | Decision usage: NOT ALLOWED (analysis_safe_for_decision=false)",
    "See: codeburn/phase1/CODEBURN_PHASE1_STATUS.md",
)


def print_phase1_header() -> None:
    """Write Phase 1 status header to stderr. Called at the start of every CLI main()."""
    for line in _HEADER:
        print(line, file=sys.stderr)
