from __future__ import annotations

from collections.abc import Iterable, Mapping


def _row_value(row: Mapping[str, object], key: str) -> object:
    try:
        return row[key]
    except (KeyError, IndexError, TypeError):
        return None


def token_observability_level(rows: Iterable[Mapping[str, object]]) -> str:
    has_step_level_signal = False
    has_coarse_signal = False

    for row in rows:
        token_source = str(_row_value(row, "token_source") or "").strip()
        prompt_tokens = _row_value(row, "prompt_tokens")
        completion_tokens = _row_value(row, "completion_tokens")
        total_tokens = _row_value(row, "total_tokens")

        # Step-level means per-step breakdown exists (prompt/completion granularity).
        if prompt_tokens is not None or completion_tokens is not None:
            has_step_level_signal = True

        if token_source in {"provider", "estimated"} and total_tokens is not None:
            has_coarse_signal = True

    if has_step_level_signal:
        return "step_level"
    if has_coarse_signal:
        return "coarse"
    return "none"
