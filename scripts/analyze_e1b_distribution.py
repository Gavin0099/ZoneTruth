#!/usr/bin/env python3
"""
E1b Phase 2 — Distribution Analysis Script.

Reads one or more canonical-audit-log.jsonl files, computes per-repo
entropy / signal_ratio / degenerate metrics, and evaluates whether the
accumulated observation pool satisfies the Phase 2 readiness gate.

Purpose
-------
Make Phase 2 "observably waiting" rather than "passively waiting".
Running this script after real sessions accumulate answers:

  - Is the log growing into a usable distribution?
  - Are there low-entropy / degenerate repos dominating the pool?
  - Does the pool have enough repo diversity to build a valid baseline?

Phase 2 readiness gate (all conditions must pass before Phase 3):
  --min-sessions N          total session entries across all repos
  --min-repos   M           distinct contributing repos
  --min-non-stuck-absent-v2 R
                            fraction of repos where lifecycle_class != stuck_absent
  --max-dominance R         max fraction any one repo can occupy
  --min-lifecycle-active R  floor guard on non-stuck lifecycle activity

Legacy note:
  --min-nondegenerate is retained as a deprecated compatibility alias and
  no longer gates readiness. Legacy nondegenerate_ratio remains reporting-only.

Usage
-----
    # Default: read this repo's own log
    python scripts/analyze_e1b_distribution.py

    # Read multiple repo logs (merged view)
    python scripts/analyze_e1b_distribution.py --log-path a.jsonl b.jsonl c.jsonl

    # Override gate thresholds
    python scripts/analyze_e1b_distribution.py --min-sessions 40 --min-repos 5

    # Machine-readable output
    python scripts/analyze_e1b_distribution.py --json

E1b Phase roadmap
-----------------
  Phase 1 (done):     passive observation — entropy + degenerate guard; advisory_only=True
  Phase 2 (this):     distribution understanding — accumulate + analyze real sessions
  Phase 3 (blocked):  trigger design — only after Phase 2 gate passes
"""
from __future__ import annotations

import argparse
import datetime
import json
import math
import sys
from collections import defaultdict
from pathlib import Path

# ── Constants ─────────────────────────────────────────────────────────────────

_E1B_MIN_VALID_ENTROPY: float = 0.3

# Thresholds for lifecycle_class classification (v2 degenerate model).
# Separates "stuck_absent" (adoption failure) from "stable_ok" (healthy convergence).
# A repo is "stuck_absent" when:
#   - dominant state is absent/malformed (not ok)
#   - that state occupies >= _LC_DOMINANT_SHARE_THRESHOLD of all sessions
#   - fingerprint diversity is below _LC_FROZEN_DIVERSITY_THRESHOLD (pattern frozen)
# A repo is "stable_ok" when dominant state is "ok" with high share.
# A repo is "insufficient_evidence" when session_count < _LC_INSUFFICIENT_EVIDENCE_MIN_SESSIONS
#   (not enough data to make any lifecycle classification judgment).
# Otherwise it is "transitioning_active" (genuine state variety with enough data).
# NOTE: "mixed_active" is the deprecated predecessor of "transitioning_active".
#   Any consumer that reads lifecycle_class must treat both as equivalent non-stuck values.
_LC_DOMINANT_SHARE_THRESHOLD: float = 0.90
_LC_FROZEN_DIVERSITY_THRESHOLD: float = 0.10
# Minimum sessions needed before a lifecycle_class judgment is meaningful.
# Below this threshold the repo is classified as "insufficient_evidence" rather than
# attempting a quality judgment on too-small a sample.
_LC_INSUFFICIENT_EVIDENCE_MIN_SESSIONS: int = 3

# Rolling window size for recent_lifecycle_class.
# Mirrors the E8a canonical_audit_trend window.
# Layer 2 stability for newly-wired repos is evaluated on this window,
# not on full historical distribution (which would permanently penalise
# pre-wiring absent entries).
_LC_RECENT_WINDOW: int = 20

# Default Phase 2 readiness gate thresholds.
# These can be overridden via CLI flags.
# The rationale for each:
#   min_sessions=20  — below 20 the entropy estimate is unreliable
#   min_repos=3      — single-repo pool cannot reveal repo-level variance
#   min_nondegenerate=0.7 — conservative pre-empirical governance threshold;
#     NOT derived from observed data. A policy choice to prevent heavily-degenerate
#     pools from anchoring a spurious baseline.
#     Revise downward only after empirical distribution has been established.
#   max_dominance=0.6 — no single repo should supply more than 60% of samples
#   min_lifecycle_active=0.5 — at least 50% of lifecycle-capable repos must be non-stuck-absent.
#     (guards against pseudo-diversity: repos declared lifecycle_capable but never ran lifecycle)
#     Replaces deprecated unique_pattern_ratio which was non-identifiable in a healthy fleet:
#     stable_ok repos converge to (ok,(),False) fingerprint → low ratio even when fleet is healthy.
_PHASE2_MIN_SESSIONS: int = 20
_PHASE2_MIN_REPOS: int = 3
# v2 authoritative threshold: fraction of repos where lifecycle_class != stuck_absent.
_PHASE2_MIN_NON_STUCK_ABSENT_RATIO_V2: float = 0.7
# Deprecated compatibility alias. Keep for older callers / tests, but do not
# use the legacy nondegenerate_ratio metric for gating.
_PHASE2_MIN_NONDEGENERATE_RATIO: float = _PHASE2_MIN_NON_STUCK_ABSENT_RATIO_V2
_PHASE2_MAX_REPO_DOMINANCE: float = 0.6
_PHASE2_MIN_LIFECYCLE_ACTIVE_RATIO: float = 0.5

_DEFAULT_LOG_PATH = (
    Path("artifacts") / "runtime" / "canonical-audit-log.jsonl"
)

_AUDIT_LOG_RELPATH = Path("artifacts") / "runtime" / "canonical-audit-log.jsonl"

# Phase 3 observation-only contract (pre-authority-promote hard boundary).
# The payload surface is defined as an allowlist of RAW observation classes.
# Future field additions must be explicitly placed in one of these classes and
# pass validate_phase3_observation_payload().
_PHASE3_OBSERVATION_ALLOWLIST_BY_CLASS: dict[str, frozenset[str]] = {
    "raw_counts": frozenset({
        "total_sessions",
        "repo_count",
        "repo_session_counts",
        "artifact_state_counts",
    }),
    "raw_ratios": frozenset({
        "repo_session_ratios",
        "artifact_state_ratios",
    }),
    "raw_distributions": frozenset({
        "repo_state_breakdown",
    }),
    "raw_transition_data": frozenset({
        "state_transition_matrix",
    }),
    "raw_repo_partition_data": frozenset({
        "repo_session_counts",
        "repo_session_ratios",
        "repo_state_breakdown",
    }),
}

_PHASE3_OBSERVATION_ALLOWED_FIELDS: frozenset[str] = frozenset().union(
    *_PHASE3_OBSERVATION_ALLOWLIST_BY_CLASS.values()
)
# Interpretive-class token detector (guards alias-based smuggling).
_INTERPRETIVE_KEY_TOKENS: tuple[str, ...] = (
    "trend",
    "direction",
    "correlation",
    "health",
    "quality",
    "readiness",
    "promotion",
    "improv",
    "degrad",
    "stable",
    "stability",
    "mature",
    "alignment",
    "hint",
    "score",
)

_PHASE3_DOWNSTREAM_ALLOWED_USE: tuple[str, ...] = (
    "raw_observation_review",
    "coverage_audit",
    "schema_migration_monitoring",
    "phase2_observation_baseline_tracking",
)

_PHASE3_DOWNSTREAM_FORBIDDEN_USE: tuple[str, ...] = (
    "readiness_inference",
    "promotion_decision_support",
    "trend_quality_verdict",
    "stability_health_summary",
    "policy_threshold_calibration_input",
)

_PHASE3_REVIEWER_ALLOWED_SUMMARY_SCOPE: tuple[str, ...] = (
    "raw_observation_restatement",
    "coverage_gap_note",
    "schema_migration_context",
    "evidence_scope_caveat",
)

_PHASE3_REVIEWER_FORBIDDEN_SUMMARY_CLAIMS: tuple[str, ...] = (
    "readiness_declared",
    "promotion_recommended",
    "stability_conclusion_declared",
    "interpretation_authority_substitution",
)


def _auto_discover_logs(start_dir: Path | None = None) -> list[Path]:
    """
    Scan sibling directories of start_dir for canonical-audit-log.jsonl files.

    Looks in:
      1. start_dir itself (the framework repo)
      2. All direct subdirectories of start_dir.parent (sibling repos)

    Returns all discovered paths that exist, sorted for determinism.
    Falls back to [_DEFAULT_LOG_PATH] if nothing is found.
    """
    if start_dir is None:
        start_dir = Path.cwd()
    parent = start_dir.parent
    candidates: list[Path] = []
    # Check the framework repo itself first
    own = start_dir / _AUDIT_LOG_RELPATH
    if own.exists():
        candidates.append(own)
    # Check siblings
    try:
        for sibling in sorted(parent.iterdir()):
            if sibling == start_dir or not sibling.is_dir():
                continue
            candidate = sibling / _AUDIT_LOG_RELPATH
            if candidate.exists():
                candidates.append(candidate)
    except OSError:
        pass
    return candidates if candidates else [_DEFAULT_LOG_PATH]


# ── Session fingerprint ──────────────────────────────────────────────────────

def _session_fingerprint(entry: dict) -> tuple:
    """
    Compact signature for a single audit-log entry.

    Used to estimate session-level diversity across the pool.
    Two entries with the same fingerprint represent statistically the same
    kind of session — repeated observations of an identical lifecycle pattern.

    Components
    ----------
    artifact_state  — absent / ok / stale / malformed
    signals         — sorted tuple of emitted signal codes
    gate_blocked    — whether the gate was blocked this session

    Not included: repo_name, timestamp, policy_provenance.
    We want to measure lifecycle diversity, not repo identity.

    Limitation (design boundary)
    ----------------------------
    This fingerprint is sufficient as a GATE GUARD against pseudo-diversity.
    It is NOT a session type classifier.

    Two sessions may share the same fingerprint yet have operationally different
    meanings — e.g. (absent, [], False) can represent::
      - transient artifact absence
      - long-running static absent lifecycle
      - post-create deletion tail-state

    If Phase 3 requires pattern-level analysis (transition sequences, lifecycle
    length, state trajectory), this fingerprint must be upgraded before use.
    Do not treat unique_pattern_ratio as proof of lifecycle diversity.
    """
    artifact_state = entry.get("artifact_state", "unknown")
    signals = tuple(sorted(entry.get("signals") or []))
    gate_blocked = bool(entry.get("gate_blocked"))
    return (artifact_state, signals, gate_blocked)


def _normalize_key(key: str) -> str:
    return key.lower().replace("_", "").replace("-", "")


def _looks_interpretive_key(key: str) -> bool:
    k = _normalize_key(key)
    return any(token in k for token in _INTERPRETIVE_KEY_TOKENS)


def _build_state_transition_matrix(entries: list[dict]) -> dict[str, int]:
    """
    Build global state transition counts across repos.

    Output key format: "<from_state>-><to_state>".
    """
    grouped: dict[str, list[dict]] = defaultdict(list)
    for e in entries:
        repo = e.get("repo_name") or "unknown"
        grouped[repo].append(e)

    matrix: dict[str, int] = defaultdict(int)
    for repo_entries in grouped.values():
        # ISO8601 timestamp strings are lexicographically sortable.
        ordered = sorted(repo_entries, key=lambda x: x.get("timestamp") or "")
        for i in range(1, len(ordered)):
            a = ordered[i - 1].get("artifact_state", "unknown")
            b = ordered[i].get("artifact_state", "unknown")
            matrix[f"{a}->{b}"] += 1
    return dict(sorted(matrix.items()))


def _to_ratio_map(counts: dict[str, int], denominator: int) -> dict[str, float]:
    """
    Convert integer count map into a normalized ratio map.

    Ratios are rounded to 4 decimals for stable JSON output.
    """
    if denominator <= 0:
        return {k: 0.0 for k in sorted(counts)}
    return {
        k: round(v / denominator, 4)
        for k, v in sorted(counts.items())
    }


def build_phase3_observation_payload(
    entries: list[dict],
    repo_stats: dict[str, dict],
) -> dict:
    """
    Build raw observation payload for Phase 3 pre-authority mode.

    This payload is intentionally observation-only:
    raw counts, raw distributions, raw transitions.
    No directional or quality interpretation fields are allowed.
    """
    artifact_state_counts: dict[str, int] = defaultdict(int)
    repo_session_counts: dict[str, int] = {}
    repo_state_breakdown: dict[str, dict[str, int]] = {}

    for repo, s in repo_stats.items():
        repo_session_counts[repo] = int(s.get("session_count", 0))
        state_breakdown = dict(sorted((s.get("state_breakdown") or {}).items()))
        repo_state_breakdown[repo] = state_breakdown
        for state, n in state_breakdown.items():
            artifact_state_counts[state] += n

    total_sessions = sum(repo_session_counts.values())

    return {
        "total_sessions": total_sessions,
        "repo_count": len(repo_stats),
        "repo_session_counts": dict(sorted(repo_session_counts.items())),
        "repo_session_ratios": _to_ratio_map(repo_session_counts, total_sessions),
        "artifact_state_counts": dict(sorted(artifact_state_counts.items())),
        "artifact_state_ratios": _to_ratio_map(artifact_state_counts, total_sessions),
        "repo_state_breakdown": dict(sorted(repo_state_breakdown.items())),
        "state_transition_matrix": _build_state_transition_matrix(entries),
    }


def validate_phase3_observation_payload(payload: dict) -> dict:
    """
    Validate observation-only contract and detect interpretation smuggling.

    Returns:
      {
        "valid": bool,
        "violations": [ ... ],
        "non_decision_support": True
      }
    """
    violations: list[dict] = []
    for key in payload.keys():
        if _looks_interpretive_key(key):
            violations.append({
                "key": key,
                "reason": "interpretive_class_forbidden",
            })
            continue
        if key in _PHASE3_OBSERVATION_ALLOWED_FIELDS:
            continue
        else:
            violations.append({
                "key": key,
                "reason": "non_raw_field_forbidden",
            })
    return {
        "valid": len(violations) == 0,
        "violations": violations,
        "non_decision_support": True,
    }


def enforce_phase3_observation_contract(validation: dict) -> None:
    """
    Hard-fail on contract violations to prevent schema drift from widening
    observation payload into interpretive space.
    """
    if validation.get("valid", False):
        return

    violations = validation.get("violations", [])
    details = ", ".join(
        f"{v.get('key', '<unknown>')}:{v.get('reason', 'violation')}"
        for v in violations
    )
    raise ValueError(
        "phase3 observation contract violation: "
        f"{details or 'unknown contract violation'}"
    )


def _normalized_shannon_entropy(state_breakdown: dict[str, int], n: int) -> float:
    """
    Shannon entropy normalized to [0, 1] by log(4).

    Unlike the legacy entropy (distinct_states / session_count), this value does
    NOT decay as session count grows.  A repo with 300 sessions all in state
    'absent' has normalized_state_entropy = 0.0; a repo with 4 equally distributed
    states has 1.0 regardless of sample size.

    Normalization divisor: log(4) — the theoretical maximum for 4 artifact states.
    Using a fixed divisor (not log(K)) makes values comparable across repos.
    Returns 0.0 when n <= 0.
    """
    if n <= 0:
        return 0.0
    h = 0.0
    for count in state_breakdown.values():
        if count > 0:
            p = count / n
            h -= p * math.log(p)
    max_h = math.log(4)  # 4 artifact states: absent, ok, stale, malformed
    return round(h / max_h, 4)


# ── Data loading ──────────────────────────────────────────────────────────────

def is_runtime_eligible(obs: dict) -> bool:
    """
    Return True only for observations that represent agent runtime behaviour.

    Observations with semantic_boundary.represents_agent_behavior=False are
    external analysis artifacts (e.g. Enumd governance_report.json) and must
    NEVER be included in lifecycle_class, E1b, session_count, or Phase 2 gate
    computations.  Including them would falsely inflate session counts and
    corrupt lifecycle statistics.

    Default is True so that legacy entries without a semantic_boundary field
    (pre-dating the Enumd integration) continue to be treated as runtime
    observations.  Only explicit False opt-outs are excluded.

    See also: integrations/enumd/mapping.md — Routing Directives section.
    """
    return obs.get("semantic_boundary", {}).get("represents_agent_behavior", True)


def _load_entries(log_paths: list[Path]) -> list[dict]:
    """
    Load and merge JSONL entries from one or more log files.

    Non-runtime observations (is_runtime_eligible() == False) are filtered out
    so that external analysis artifacts (e.g. Enumd Mode A observations) never
    reach lifecycle / E1b / Phase 2 gate computations.
    """
    entries: list[dict] = []
    skipped = 0
    for path in log_paths:
        if not path.exists():
            continue
        try:
            for line in path.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if not is_runtime_eligible(entry):
                    skipped += 1
                    continue
                entries.append(entry)
        except OSError:
            continue
    if skipped:
        # Surface as a diagnostic but do not block — the script must remain
        # readable even when external observations land in the same directory.
        import sys as _sys
        print(
            f"  [is_runtime_eligible] filtered {skipped} non-runtime observation(s) "
            f"from lifecycle analysis",
            file=_sys.stderr,
        )
    return entries


# ── Per-repo statistics ───────────────────────────────────────────────────────

def compute_repo_stats(entries: list[dict]) -> dict[str, dict]:
    """
    Compute per-repo statistics from raw audit log entries.

    Metrics
    -------
    session_count      number of entries for this repo
    distinct_states    number of unique artifact_state values seen
    entropy            distinct_states / session_count  (0..1)  [LEGACY]
                       Decays naturally as session count grows — do not use for
                       comparing repos with different session counts.
    is_degenerate      entropy < _E1B_MIN_VALID_ENTROPY            [LEGACY]
                       False-positives: healthy stable_ok repos with many sessions
                       appear degenerate. Use is_degenerate_v2 instead.
    signal_ratio       fraction of entries that recorded at least one signal
    state_breakdown    count per artifact_state value
    gate_blocked_count entries where gate_blocked=True
    first_seen         earliest timestamp in this repo's entries
    last_seen          latest timestamp
    skip_type          'structural' | 'temporary' | None (from policy_provenance)
    lifecycle_capable  True when skip_test_result_check is not set / False when skip=false

    Shadow metrics (v2 — not yet gate-blocking, informational):
    normalized_state_entropy  Shannon entropy / log(4); stable across session counts
    dominant_state            the artifact_state with the highest occurrence count
    dominant_state_share      dominant_state count / session_count
    lifecycle_class           four-way classification for degenerate semantics:
                                stuck_absent         — dominant state is absent/malformed AND
                                                       share >= 0.90 AND fingerprint frozen
                                                       → adoption failure (lifecycle never ran)
                                stable_ok            — dominant state is ok AND share >= 0.90
                                                       → lifecycle healthy; low entropy is EXPECTED
                                insufficient_evidence— session_count < 3; not enough data to judge
                                transitioning_active — enough data, genuine state variety
                                                       (deprecated alias: mixed_active)
                              Note: consumers MUST treat both "transitioning_active" and
                              "mixed_active" as equivalent non-stuck, non-stable values.
    is_degenerate_v2          True only when lifecycle_class == 'stuck_absent'
                              Does NOT misclassify stable_ok repos as degenerate.
    """
    by_repo: dict[str, list[dict]] = defaultdict(list)
    for e in entries:
        repo = e.get("repo_name") or "unknown"
        by_repo[repo].append(e)

    stats: dict[str, dict] = {}
    for repo, repo_entries in by_repo.items():
        try:
            repo_entries.sort(key=lambda e: e.get("timestamp", ""))
        except Exception:  # noqa: BLE001
            pass

        n = len(repo_entries)
        states = [e.get("artifact_state", "unknown") for e in repo_entries]
        distinct = len(set(states))
        entropy = round(distinct / n, 4) if n > 0 else 0.0
        is_degenerate = entropy < _E1B_MIN_VALID_ENTROPY

        signals_count = sum(1 for e in repo_entries if e.get("signals"))
        signal_ratio = round(signals_count / n, 4) if n > 0 else 0.0

        state_breakdown: dict[str, int] = defaultdict(int)
        for s in states:
            state_breakdown[s] += 1

        gate_blocked_count = sum(
            1 for e in repo_entries if e.get("gate_blocked")
        )

        timestamps = [
            e.get("timestamp", "") for e in repo_entries if e.get("timestamp")
        ]

        # skip_type: take the most recent non-null value from policy_provenance.
        skip_type: str | None = None
        for e in reversed(repo_entries):
            prov = e.get("policy_provenance") or {}
            st = prov.get("skip_type")
            if st is not None:
                skip_type = st
                break
        # lifecycle_capable: repo is in entropy analysis pool when no skip is
        # currently declared in gate_policy.yaml.
        #
        # Strategy: use the most recent SCHEMA-AWARE entry to determine the
        # current policy.  A "schema-aware" entry has the "skip_type" KEY
        # present in policy_provenance (value may be null).
        #   - null  → current policy has no skip  → lifecycle_capable = True
        #   - "structural" / "temporary" → skip still declared → False
        #
        # Fall back to has_any_skip only when NO schema-aware entries exist
        # (pre-schema repos that pre-date the skip_type field).
        #
        # This allows repos that cleared their skip declaration (gate_policy.yaml
        # no longer contains skip_type) to correctly re-enter the baseline pool
        # once a new session_end_hook run produces an entry with skip_type=null.
        # Without this, historical "temporary" entries would permanently exclude
        # such repos from lifecycle_capable even after the policy was cleaned.
        has_any_skip = any(
            (e.get("policy_provenance") or {}).get("skip_type") is not None
            for e in repo_entries
        )
        most_recent_aware_skip: str | None = None
        _found_aware_entry: bool = False
        for _e in reversed(repo_entries):
            _prov = _e.get("policy_provenance") or {}
            if "skip_type" in _prov:
                most_recent_aware_skip = _prov.get("skip_type")
                _found_aware_entry = True
                break
        if _found_aware_entry:
            # Post-schema: current declared policy governs.
            lifecycle_capable = most_recent_aware_skip is None
        else:
            # Pre-schema: conservatively fall back to any-skip check.
            lifecycle_capable = not has_any_skip

        # skip_type_entry_count: how many entries carry the skip_type field.
        # Tracks schema migration completeness: old entries pre-date the field.
        # NOTE: check KEY PRESENCE, not non-null value.
        # New entries from lifecycle-capable repos write "skip_type": null —
        # they are schema-aware (key is present) even though the value is null.
        # Old entries (pre-schema) have no "skip_type" key at all.
        # Using `is not None` would incorrectly exclude all lifecycle-capable
        # repos from ERA progress, making CURRENT era unreachable.
        skip_type_entry_count = sum(
            1 for e in repo_entries
            if "skip_type" in (e.get("policy_provenance") or {})
        )
        skip_type_coverage_ratio = (
            round(skip_type_entry_count / n, 4) if n > 0 else 0.0
        )

        # post_skip_lifecycle_count: entries where skip_type was ALREADY set in
        # policy_provenance AND lifecycle activity was observed in the same session.
        # This is the true semantic inconsistency — not pre-policy historical noise.
        # Pre-policy entries (no skip_type in provenance) are intentionally excluded:
        # early signals before policy config are normal adoption sequence.
        post_skip_lifecycle_count = sum(
            1 for e in repo_entries
            if (e.get("policy_provenance") or {}).get("skip_type") is not None
            and (
                bool(e.get("signals"))
                or e.get("artifact_state", "absent") != "absent"
            )
        )

        # fingerprint_diversity: distinct fingerprints / session_count.
        # Proxy for adoption progress in temporary_skip repos.
        # Near-zero = lifecycle pattern completely frozen (adoption dead).
        # > 0.1     = pattern changing, adoption is slow but moving.
        fingerprints_local = [_session_fingerprint(e) for e in repo_entries]
        distinct_fingerprint_count = len(set(fingerprints_local))
        fingerprint_diversity = (
            round(distinct_fingerprint_count / n, 4) if n > 0 else 0.0
        )

        # ── Shadow v2 metrics ─────────────────────────────────────────────────
        # These replace the legacy entropy/is_degenerate pair.
        # They are informational-only; not yet used as gate blockers.

        normalized_state_entropy = _normalized_shannon_entropy(dict(state_breakdown), n)

        dominant_state = (
            max(state_breakdown, key=state_breakdown.get)
            if state_breakdown else "unknown"
        )
        dominant_state_share = (
            round(state_breakdown.get(dominant_state, 0) / n, 4) if n > 0 else 0.0
        )

        # lifecycle_class: separates "stuck_absent" (adoption failure) from
        # "stable_ok" (healthy convergence) — the legacy formula cannot tell them apart.
        # "insufficient_evidence" is new: n < threshold → no quality judgment possible.
        # "transitioning_active" replaces the ambiguous "mixed_active" bucket.
        _STUCK_STATES = {"absent", "malformed", "unknown"}
        if n < _LC_INSUFFICIENT_EVIDENCE_MIN_SESSIONS:
            lifecycle_class = "insufficient_evidence"
        elif (
            dominant_state in _STUCK_STATES
            and dominant_state_share >= _LC_DOMINANT_SHARE_THRESHOLD
            and fingerprint_diversity < _LC_FROZEN_DIVERSITY_THRESHOLD
        ):
            lifecycle_class = "stuck_absent"
        elif (
            dominant_state == "ok"
            and dominant_state_share >= _LC_DOMINANT_SHARE_THRESHOLD
        ):
            lifecycle_class = "stable_ok"
        else:
            lifecycle_class = "transitioning_active"

        is_degenerate_v2 = lifecycle_class == "stuck_absent"

        # ── recent_lifecycle_class (rolling window) ───────────────────────────
        # Computes lifecycle_class over the LAST _LC_RECENT_WINDOW entries only.
        # This is the Layer 2 stability signal for newly-wired repos.
        # Full-history lifecycle_class is kept for audit context; it must NOT
        # be used as the primary Layer 2 acceptance criterion — early absent
        # entries pre-date wiring and would permanently penalise a stable repo.
        recent_entries = repo_entries[-_LC_RECENT_WINDOW:]
        r_n = len(recent_entries)
        r_states = [e.get("artifact_state", "unknown") for e in recent_entries]
        r_state_breakdown: dict[str, int] = defaultdict(int)
        for s in r_states:
            r_state_breakdown[s] += 1
        r_dominant = (
            max(r_state_breakdown, key=r_state_breakdown.get)
            if r_state_breakdown else "unknown"
        )
        r_dominant_share = (
            round(r_state_breakdown.get(r_dominant, 0) / r_n, 4) if r_n > 0 else 0.0
        )
        r_fingerprints = [_session_fingerprint(e) for e in recent_entries]
        r_fp_diversity = (
            round(len(set(r_fingerprints)) / r_n, 4) if r_n > 0 else 0.0
        )
        _STUCK_STATES_R = {"absent", "malformed", "unknown"}
        if r_n < _LC_INSUFFICIENT_EVIDENCE_MIN_SESSIONS:
            recent_lifecycle_class = "insufficient_evidence"
        elif (
            r_dominant in _STUCK_STATES_R
            and r_dominant_share >= _LC_DOMINANT_SHARE_THRESHOLD
            and r_fp_diversity < _LC_FROZEN_DIVERSITY_THRESHOLD
        ):
            recent_lifecycle_class = "stuck_absent"
        elif (
            r_dominant == "ok"
            and r_dominant_share >= _LC_DOMINANT_SHARE_THRESHOLD
        ):
            recent_lifecycle_class = "stable_ok"
        else:
            recent_lifecycle_class = "transitioning_active"
        recent_ok_count = r_state_breakdown.get("ok", 0)
        recent_window_size = r_n

        stats[repo] = {
            "session_count": n,
            "distinct_states": distinct,
            "entropy": entropy,            # [LEGACY] decays with session count
            "is_degenerate": is_degenerate,  # [LEGACY] false-positives stable_ok
            "signal_ratio": signal_ratio,
            "state_breakdown": dict(state_breakdown),
            "gate_blocked_count": gate_blocked_count,
            "first_seen": timestamps[0] if timestamps else "unknown",
            "last_seen": timestamps[-1] if timestamps else "unknown",
            "skip_type": skip_type,
            "lifecycle_capable": lifecycle_capable,
            "skip_type_entry_count": skip_type_entry_count,
            "skip_type_coverage_ratio": skip_type_coverage_ratio,
            # coverage_era: per-repo temporal era label derived from skip_type_coverage_ratio.
            # Downstream consumers MUST check this before citing lifecycle_class or
            # stable_ok conclusions as "proven stable". Low coverage_era means the repo's
            # history is mostly pre-schema and lifecycle trends are not reliably verifiable.
            "coverage_era": (
                "CURRENT"
                if skip_type_coverage_ratio >= _SKIP_TYPE_COVERAGE_CURRENT_THRESHOLD
                else "TRANSITION"
                if skip_type_coverage_ratio >= _SKIP_TYPE_COVERAGE_TRANSITION_THRESHOLD
                else "PRE-SKIP-TYPE-ERA"
            ),
            # pre_era_fraction: fraction of entries that predate skip_type schema.
            # A high value (close to 1.0) means lifecycle_class is based almost entirely
            # on pre-classification data. Any citation of "proven stable" requires this < 0.3.
            "pre_era_fraction": round(1.0 - skip_type_coverage_ratio, 4),
            "post_skip_lifecycle_count": post_skip_lifecycle_count,
            "distinct_fingerprint_count": distinct_fingerprint_count,
            "fingerprint_diversity": fingerprint_diversity,
            # Shadow v2 metrics
            "normalized_state_entropy": normalized_state_entropy,
            "dominant_state": dominant_state,
            "dominant_state_share": dominant_state_share,
            "lifecycle_class": lifecycle_class,
            "is_degenerate_v2": is_degenerate_v2,
            # Rolling-window metrics (Layer 2 directional reference — NOT a verdict)
            # recent_lifecycle_class is a directional reference: it CAN distinguish
            # an improving repo (recent ok convergence) from an oscillating one.
            # It MUST NOT single-handedly drive a promote decision.
            # See docs/e1b-classification-semantic-limits.md — Section 2.
            # lifecycle_class (full-history) is audit context only.
            "recent_lifecycle_class": recent_lifecycle_class,
            "recent_ok_count": recent_ok_count,
            "recent_window_size": recent_window_size,
        }
    return stats


# ── Fleet coverage layer ──────────────────────────────────────────────────────

# Stale threshold for temporary_skip repos: if adoption debt is older than
# this many days without being resolved, it is flagged as stale.
_TEMPORARY_SKIP_STALE_DAYS: int = 90

# Fleet representativeness threshold: if lifecycle_capable_ratio falls below
# this value, the entropy baseline may not represent fleet reality even when
# Phase 2 gate passes.
_LIFECYCLE_CAPABLE_MIN_RATIO: float = 0.3

# Temporal era thresholds for skip_type field coverage.
# When a new field is added to the log schema, historical entries lack it.
# Tracking coverage ratio reveals whether the distribution was built in a
# pre-classification era (most entries have no skip_type) or has migrated.
#   CURRENT         >= 0.7  — most entries carry skip_type; classification reliable
#   TRANSITION      >= 0.3  — mix of old + new entries; interpret with care
#   PRE-SKIP-TYPE-ERA < 0.3 — mostly pre-schema entries; classifications are inferred
_SKIP_TYPE_COVERAGE_CURRENT_THRESHOLD: float = 0.7
_SKIP_TYPE_COVERAGE_TRANSITION_THRESHOLD: float = 0.3


def compute_fleet_coverage(repo_stats: dict[str, dict]) -> dict:
    """
    Layer 1: Fleet Coverage summary.

    Reports the structural composition of the fleet without conflating
    governance classification with entropy quality.

    Categories
    ----------
    lifecycle_capable : skip not declared — eligible for entropy analysis
    structural_skip   : skip declared as permanent (non-Python stack, doc repo)
    temporary_skip    : skip declared as provisional (adoption debt)
    unclassified_skip : skip=true but skip_type not declared in log

    Hardening signals
    -----------------
    lifecycle_capable_ratio         : lifecycle_capable_count / total_repos
    baseline_representative         : True when ratio >= _LIFECYCLE_CAPABLE_MIN_RATIO
    fleet_skip_type_coverage_ratio  : entries with skip_type set / total entries
    fleet_era_tag                   : CURRENT / TRANSITION / PRE-SKIP-TYPE-ERA
    structural_skip_inconsistencies : structural repos where post-policy lifecycle
        activity was observed — only flags AFTER skip_type was set in provenance,
        excluding pre-policy noise from normal adoption sequence
    temporary_skip_aging            : per-repo adoption-debt age + activity score
        (fingerprint_diversity distinguishes adoption-slow from adoption-dead)
    """
    total = len(repo_stats)
    lifecycle_capable = [r for r, s in repo_stats.items() if s["lifecycle_capable"]]
    structural_skip = [
        r for r, s in repo_stats.items()
        if not s["lifecycle_capable"] and s["skip_type"] == "structural"
    ]
    temporary_skip = [
        r for r, s in repo_stats.items()
        if not s["lifecycle_capable"] and s["skip_type"] == "temporary"
    ]
    unclassified_skip = [
        r for r, s in repo_stats.items()
        if not s["lifecycle_capable"] and s["skip_type"] is None
    ]

    lifecycle_capable_ratio = round(
        len(lifecycle_capable) / total if total > 0 else 0.0, 4
    )
    baseline_representative = lifecycle_capable_ratio >= _LIFECYCLE_CAPABLE_MIN_RATIO

    # Fleet-wide skip_type coverage ratio: tracks temporal drift from pre-schema era.
    # Old log entries (before skip_type was added to gate_policy schema) have no
    # skip_type in policy_provenance. A low ratio means the distribution was
    # accumulated before classifications existed — interpret with caution.
    total_entries_fleet = sum(s["session_count"] for s in repo_stats.values())
    skip_type_entries_fleet = sum(
        s.get("skip_type_entry_count", 0) for s in repo_stats.values()
    )
    fleet_skip_type_coverage_ratio = round(
        skip_type_entries_fleet / total_entries_fleet
        if total_entries_fleet > 0 else 0.0,
        4,
    )
    if fleet_skip_type_coverage_ratio >= _SKIP_TYPE_COVERAGE_CURRENT_THRESHOLD:
        fleet_era_tag = "CURRENT"
    elif fleet_skip_type_coverage_ratio >= _SKIP_TYPE_COVERAGE_TRANSITION_THRESHOLD:
        fleet_era_tag = "TRANSITION"
    else:
        fleet_era_tag = "PRE-SKIP-TYPE-ERA"

    # Structural skip consistency check — post-policy only.
    # Only flag entries where skip_type was already set in policy_provenance
    # AND lifecycle activity was observed. Pre-policy signals are intentionally
    # excluded: they are normal artifacts of the adoption sequence (repo ran
    # sessions before gate_policy.yaml was written with skip=true).
    structural_skip_inconsistencies: list[dict] = []
    for r in structural_skip:
        s = repo_stats[r]
        if s.get("post_skip_lifecycle_count", 0) > 0:
            structural_skip_inconsistencies.append({
                "repo": r,
                "post_skip_lifecycle_count": s["post_skip_lifecycle_count"],
                "advisory": (
                    "structural_skip declared but post-policy lifecycle activity "
                    "observed; verify skip_type is not used to escape governance"
                ),
            })

    # Temporary skip aging: track adoption debt duration and progress.
    # age_days    — calendar days since first observed session
    # stale       — age > _TEMPORARY_SKIP_STALE_DAYS without becoming lifecycle-capable
    # activity    — 'slow' if fingerprint_diversity > 0.1 (lifecycle pattern changing
    #               even if slowly); 'dead' if completely frozen
    today = datetime.date.today()
    temporary_skip_aging: list[dict] = []
    for r in temporary_skip:
        s = repo_stats[r]
        first = s.get("first_seen", "unknown")
        age_days: int | None = None
        try:
            if first and first != "unknown":
                first_d = datetime.date.fromisoformat(first[:10])
                age_days = (today - first_d).days
        except (ValueError, TypeError):
            pass
        stale = age_days is not None and age_days > _TEMPORARY_SKIP_STALE_DAYS
        fd = s.get("fingerprint_diversity", 0.0)
        activity = "slow" if fd > 0.1 else "dead"
        temporary_skip_aging.append({
            "repo": r,
            "first_seen": first,
            "age_days": age_days,
            "stale": stale,
            "fingerprint_diversity": fd,
            "activity": activity,
        })

    return {
        "total_repos": total,
        "lifecycle_capable": lifecycle_capable,
        "structural_skip": structural_skip,
        "temporary_skip": temporary_skip,
        "unclassified_skip": unclassified_skip,
        "lifecycle_capable_count": len(lifecycle_capable),
        "structural_skip_count": len(structural_skip),
        "temporary_skip_count": len(temporary_skip),
        "unclassified_skip_count": len(unclassified_skip),
        "lifecycle_capable_ratio": lifecycle_capable_ratio,
        "baseline_representative": baseline_representative,
        "fleet_skip_type_coverage_ratio": fleet_skip_type_coverage_ratio,
        "fleet_era_tag": fleet_era_tag,
        "structural_skip_inconsistencies": structural_skip_inconsistencies,
        "temporary_skip_aging": temporary_skip_aging,
    }


# ── Phase 2 readiness gate ────────────────────────────────────────────────────

def evaluate_phase2_gate(
    entries: list[dict],
    repo_stats: dict[str, dict],
    min_sessions: int,
    min_repos: int,
    min_nondegenerate_ratio: float,
    max_dominance: float,
    min_lifecycle_active_ratio: float,
    *,
    min_non_stuck_absent_ratio_v2: float | None = None,
) -> dict:
    """
    Evaluate whether the accumulated observation pool satisfies Phase 2 gate.

    IMPORTANT: this gate operates ONLY on lifecycle-capable repos (skip=false).
    Structural/temporary skip repos are excluded from entropy baseline analysis.
    Fleet composition is reported separately in compute_fleet_coverage().

    Phase 3 (trigger design) must not start until this gate is READY.
    """
    # Filter to lifecycle-capable repos only (skip repos excluded from entropy pool).
    lc_stats = {r: s for r, s in repo_stats.items() if s["lifecycle_capable"]}
    lc_entries = [
        e for e in entries
        if (e.get("repo_name") or "unknown") in lc_stats
    ]
    total_sessions = sum(s["session_count"] for s in lc_stats.values())
    repo_count = len(lc_stats)
    degenerate_repos = sum(
        1 for s in lc_stats.values() if s["is_degenerate"]
    )
    nondegenerate_repos = repo_count - degenerate_repos
    nondegenerate_ratio = (
        round(nondegenerate_repos / repo_count, 4) if repo_count > 0 else 0.0
    )

    # V2 readiness basis: non-stuck-absent ratio using lifecycle_class.
    # Fixes the metric-object mismatch in legacy entropy:
    #   distinct_states / session_count decays as session_count grows and can
    #   mark healthy stable_ok fleets as "degenerate".
    # Gate now uses the v2 semantic metric (stuck_absent vs non-stuck).
    # Legacy nondegenerate_ratio stays reporting-only.
    non_stuck_absent_repos_v2 = sum(
        1 for s in lc_stats.values() if s.get("lifecycle_class") != "stuck_absent"
    )
    non_stuck_absent_ratio_v2 = (
        round(non_stuck_absent_repos_v2 / repo_count, 4) if repo_count > 0 else 0.0
    )
    threshold_v2 = (
        min_non_stuck_absent_ratio_v2
        if min_non_stuck_absent_ratio_v2 is not None
        else min_nondegenerate_ratio
    )
    threshold_source = (
        "min_non_stuck_absent_ratio_v2"
        if min_non_stuck_absent_ratio_v2 is not None
        else "deprecated_min_nondegenerate_ratio_alias"
    )
    max_sessions_any = max(
        (s["session_count"] for s in lc_stats.values()), default=0
    )
    max_dominance_actual = (
        round(max_sessions_any / total_sessions, 4) if total_sessions > 0 else 0.0
    )

    # Unique session pattern ratio: distinct fingerprints / total sessions.
    # Guards against pseudo-diversity — 3 repos all running the same lifecycle
    # pattern look like repos=3, but the pool has pattern_ratio near 0.
    fingerprints = [_session_fingerprint(e) for e in lc_entries]
    unique_patterns = len(set(fingerprints))
    unique_pattern_ratio = (
        round(unique_patterns / total_sessions, 4) if total_sessions > 0 else 0.0
    )

    # Degenerate rate interpretation — advisory, not a gate blocker.
    # degenerate_rate near 0 is NOT automatically good:
    #   it may mean broken-pipeline / skip-abuse patterns are never observed.
    degenerate_rate = (
        round(degenerate_repos / repo_count, 4) if repo_count > 0 else 0.0
    )
    if degenerate_rate < 0.05:
        degen_interp = (
            "low (<0.05) — coverage review required: confirm this reflects "
            "genuine stability, not missing broken-pipeline / skip-abuse "
            "observations; absence of degenerate sessions is not inherently bad"
        )
    elif degenerate_rate <= 0.30:
        degen_interp = "expected mixed (0.05–0.30) — normal range"
    else:
        degen_interp = (
            "high (>0.30) — possible systemic instability "
            "or persistently unhealthy lifecycle patterns"
        )

    checks: dict[str, dict] = {
        "min_sessions": {
            "label": "total sessions >= N",
            "required": min_sessions,
            "actual": total_sessions,
            "pass": total_sessions >= min_sessions,
        },
        "min_repos": {
            "label": "distinct repos >= M",
            "required": min_repos,
            "actual": repo_count,
            "pass": repo_count >= min_repos,
        },
        "min_non_stuck_absent_ratio_v2": {
            "label": "non-stuck-absent repos [v2] >= ratio",
            "required": threshold_v2,
            "actual": non_stuck_absent_ratio_v2,
            "pass": non_stuck_absent_ratio_v2 >= threshold_v2,
        },
        "max_repo_dominance": {
            "label": "dominant repo fraction <= limit",
            "required": max_dominance,
            "actual": max_dominance_actual,
            "pass": max_dominance_actual <= max_dominance,
        },
        "lifecycle_active_ratio": {
            "label": "lifecycle-active repos (not stuck_absent) >= ratio",
            "required": min_lifecycle_active_ratio,
            "actual": non_stuck_absent_ratio_v2,
            "pass": non_stuck_absent_ratio_v2 >= min_lifecycle_active_ratio,
        },
    }

    all_pass = all(c["pass"] for c in checks.values())
    return {
        "verdict": "READY" if all_pass else "NOT_READY",
        # Explicitly scope READY to avoid semantic over-read.
        "verdict_scope": "distribution_gate_only",
        "classification_validation": "NOT_EVALUATED",
        "gate_basis_version": "v2",
        "authority_status": "candidate_operational_indicator",
        "phase2_semantic_lock_required": True,
        "phase3_observation_only": True,
        "phase3_interpretation": None,
        "phase3_forbidden_interpretation_fields": [
            "trend_direction",
            "cross_repo_correlation",
            "improving",
            "degrading",
            "stable",
            "unstable",
        ],
        "legacy_nondegenerate_ratio_deprecated": True,
        "legacy_nondegenerate_gate_disabled": True,
        "v2_threshold_source": threshold_source,
        "legacy_note": (
            "legacy nondegenerate_ratio retained for reporting only; "
            "readiness gating uses v2 non-stuck-absent lifecycle semantics"
        ),
        "total_sessions": total_sessions,
        "repo_count": repo_count,
        "degenerate_repos": degenerate_repos,
        "nondegenerate_ratio": nondegenerate_ratio,
        "max_repo_dominance": max_dominance_actual,
        "unique_patterns": unique_patterns,
        "unique_pattern_ratio": unique_pattern_ratio,
        "degenerate_rate": degenerate_rate,
        "degenerate_rate_interpretation": degen_interp,
        "checks": checks,
        "distribution_metrics": {
            "legacy_nondegenerate_ratio": nondegenerate_ratio,
            "non_stuck_absent_ratio_v2": non_stuck_absent_ratio_v2,
        },
        # Informational (not gate-blocking)
        "unique_patterns": unique_patterns,
        "unique_pattern_ratio": unique_pattern_ratio,
        "non_stuck_absent_repos_v2": non_stuck_absent_repos_v2,
        "non_stuck_absent_ratio_v2": non_stuck_absent_ratio_v2,
    }


# ── Percentile helper ─────────────────────────────────────────────────────────

def _percentile(values: list[float], pct: int) -> float:
    if not values:
        return 0.0
    sorted_v = sorted(values)
    idx = min(int(len(sorted_v) * pct / 100), len(sorted_v) - 1)
    return round(sorted_v[idx], 4)


# ── Human-readable output ─────────────────────────────────────────────────────

def _print_human(
    stats: dict[str, dict],
    fleet: dict,
    gate: dict,
    log_paths: list[Path],
) -> None:
    sep = "─" * 72

    print(sep)
    print("  E1b Phase 2 — Distribution Analysis")
    print(sep)
    print(f"  log source(s) : {', '.join(str(p) for p in log_paths)}")
    print(
        f"  total entries : {sum(s['session_count'] for s in stats.values())}"
    )
    print(f"  distinct repos: {len(stats)}")

    # ── Migration-blocked banner ──────────────────────────────────────────────
    # When no audit log entries carry skip_type in policy_provenance, all
    # skip_type-based classifications are unavailable — not zero, unavailable.
    # The control plane (gate_policy.yaml) may already be updated, but the
    # data plane (audit log) has not yet been written by a post-schema session.
    # Displaying per-repo structural/temporary/lifecycle_capable counts in this
    # state is misleading: they reflect pre-schema semantics, not current policy.
    era_tag = fleet.get("fleet_era_tag", "PRE-SKIP-TYPE-ERA")
    cov = fleet.get("fleet_skip_type_coverage_ratio", 0.0)
    if era_tag == "PRE-SKIP-TYPE-ERA":
        print()
        print("  ╔══ [MIGRATION BLOCKED] " + "═" * 49 + "╗")
        print("  ║  skip_type schema not yet reflected in audit log.            ║")
        print(f"  ║  skip_type_coverage = {cov:.4f} — all entries predate schema.   ║")
        print("  ║                                                               ║")
        print("  ║  skip_type-based classifications are UNAVAILABLE, not zero:  ║")
        print("  ║    structural_skip / temporary_skip / lifecycle_capable       ║")
        print("  ║    post_skip consistency / temporary aging / activity score   ║")
        print("  ║                                                               ║")
        print("  ║  Actionable: record at least one new post-schema session on:   ║")
        print("  ║    1+ structural skip repo (e.g. Kernel-Driver-Contract)     ║")
        print("  ║    1+ temporary skip repo  (e.g. Enumd or SpecAuthority)     ║")
        print("  ║    1+ lifecycle-capable repo (e.g. Bookstore-Scraper)        ║")
        print("  ║  to generate the first post-schema entries.                  ║")
        print("  ╚" + "═" * 65 + "╝")
    elif era_tag == "TRANSITION":
        print()
        print(f"  [TRANSITION] skip_type_coverage={cov:.4f} — partial schema migration.")
        print(f"  Interpret structural/temporary/lifecycle_capable distributions")
        print(f"  with caution: {round((1-cov)*100):.0f}% of entries still carry pre-schema semantics.")
    print()

    # ── Layer 1: Fleet Coverage ───────────────────────────────────────────────
    lc_ratio = fleet["lifecycle_capable_ratio"]
    era_tag = fleet["fleet_era_tag"]
    era_note = {
        "CURRENT": "",
        "TRANSITION": "  [ADVISORY] <70% entries carry skip_type; temporal drift present",
        "PRE-SKIP-TYPE-ERA": "  [ADVISORY] <30% entries carry skip_type; distribution predates classification",
    }[era_tag]
    print("  ┌── Layer 1: Fleet Coverage ─────────────────────────────────────┐")
    print(f"  │  total repos              : {fleet['total_repos']}")
    print(
        f"  │  lifecycle_capable        : {fleet['lifecycle_capable_count']}  "
        f"{fleet['lifecycle_capable']}"
    )
    print(
        f"  │  lifecycle_capable_ratio  : {lc_ratio:.4f}  "
        + ("[OK]" if fleet["baseline_representative"] else
           f"[LOW] < {_LIFECYCLE_CAPABLE_MIN_RATIO}: baseline not representative of fleet")
    )
    cov_r = fleet["fleet_skip_type_coverage_ratio"]
    print(
        f"  │  skip_type_coverage       : {cov_r:.4f}  [{era_tag}]{era_note}"
    )
    if fleet["structural_skip"]:
        print(
            f"  │  structural_skip          : {fleet['structural_skip_count']}  "
            f"{fleet['structural_skip']}"
        )
    else:
        print(f"  │  structural_skip          : 0")
    if fleet["temporary_skip"]:
        print(
            f"  │  temporary_skip           : {fleet['temporary_skip_count']}  "
            f"{fleet['temporary_skip']}"
        )
    else:
        print(f"  │  temporary_skip           : 0")
    if fleet["unclassified_skip"]:
        print(
            f"  │  unclassified_skip        : {fleet['unclassified_skip_count']}  "
            f"{fleet['unclassified_skip']}  <- add skip_type to gate_policy.yaml"
        )
    # structural_skip consistency advisory (post-policy only — excludes pre-policy
    # adoption-sequence signals that are expected and non-actionable)
    if fleet["structural_skip_inconsistencies"]:
        print("  │")
        print("  │  [ADVISORY] structural_skip inconsistencies (post-policy activity):")
        for item in fleet["structural_skip_inconsistencies"]:
            print(
                f"  │    {item['repo']}: post_skip_lifecycle_count="
                f"{item['post_skip_lifecycle_count']}"
            )
            print(f"  │      -> {item['advisory']}")
    # temporary_skip aging table with adoption activity score
    if fleet["temporary_skip_aging"]:
        print("  │")
        print("  │  temporary_skip aging (adoption debt tracker):")
        for item in fleet["temporary_skip_aging"]:
            age_str = f"{item['age_days']}d" if item["age_days"] is not None else "?"
            stale_tag = "  [STALE >90d]" if item["stale"] else ""
            fd = item.get("fingerprint_diversity", 0.0)
            act = item.get("activity", "?")
            print(
                f"  │    {item['repo']:<30} age={age_str}  "
                f"activity=[{act}]  diversity={fd:.4f}{stale_tag}"
            )
    print("  └────────────────────────────────────────────────────────────────┘")
    print()

    # ── Layer 2: Entropy Quality (lifecycle-capable repos only) ───────────────
    lc_stats = {r: s for r, s in stats.items() if s["lifecycle_capable"]}
    excluded = len(stats) - len(lc_stats)
    excluded_note = (
        f" ({excluded} repo{'s' if excluded != 1 else ''} with "
        f"structural/temporary skip excluded)"
        if excluded > 0 else ""
    )
    print(
        f"  ┌── Layer 2: Entropy Quality (lifecycle-capable repos only){excluded_note}"
    )
    print("  │")

    if not lc_stats:
        print("  │  (no lifecycle-capable repos in pool)")
        print("  └────────────────────────────────────────────────────────────────┘")
    else:
        # Per-repo table (lifecycle-capable only)
        col_w = max((len(r) for r in lc_stats), default=4) + 2
        col_w = max(col_w, 20)
        hdr = (
            f"  │  {'repo':<{col_w}} {'sessions':>8} {'ns_ent[v2]':>10} "
            f"{'sig_ratio':>9} {'lifecycle[v2]':>14}  {'degen[L]':>9}  states"
        )
        print(hdr)
        print(
            f"  │  {'─'*col_w} {'─'*8} {'─'*10} {'─'*9} {'─'*14}  {'─'*9}  {'─'*20}"
        )
        for repo, s in sorted(
            lc_stats.items(), key=lambda kv: kv[1]["session_count"], reverse=True
        ):
            degen_mark = "YES!![L]" if s["is_degenerate"] else "no[L]"
            lc = s.get("lifecycle_class", "unknown")
            ns_ent = s.get("normalized_state_entropy", 0.0)
            state_str = "  ".join(
                f"{k}:{v}" for k, v in sorted(s["state_breakdown"].items())
            )
            print(
                f"  │  {repo:<{col_w}} {s['session_count']:>8} {ns_ent:>10.4f} "
                f"{s['signal_ratio']:>9.4f} {lc:>14}  {degen_mark:>9}  {state_str}"
            )
        print("  │")
        print("  │  Legend: ns_ent=normalized Shannon entropy (stable across session counts)")
        print("  │          lifecycle[v2]: stuck_absent=adoption failure  stable_ok=converged healthy")
        print("  │                        transitioning_active=genuine variety  insufficient_evidence=n<3")
        print("  │          degen[L]: legacy metric (distinct_states/n < 0.3) — false-positives stable_ok")

        entropies = [s["entropy"] for s in lc_stats.values()]
        ns_entropies = [s.get("normalized_state_entropy", 0.0) for s in lc_stats.values()]
        signal_ratios = [s["signal_ratio"] for s in lc_stats.values()]
        degenerate_count = sum(1 for s in lc_stats.values() if s["is_degenerate"])
        degenerate_pct = int(degenerate_count / len(lc_stats) * 100)
        lifecycle_classes = [s.get("lifecycle_class", "unknown") for s in lc_stats.values()]
        stuck_count = lifecycle_classes.count("stuck_absent")
        stable_ok_count = lifecycle_classes.count("stable_ok")
        transitioning_count = lifecycle_classes.count("transitioning_active")
        insuf_count = lifecycle_classes.count("insufficient_evidence")
        print("  │")
        print("  │  Distribution (lifecycle-capable repos):")
        print(
            f"  │    entropy[L]  — median={_percentile(entropies, 50):.4f}  "
            f"p90={_percentile(entropies, 90):.4f}  "
            f"p95={_percentile(entropies, 95):.4f}  (legacy)"
        )
        print(
            f"  │    ns_ent[v2]  — median={_percentile(ns_entropies, 50):.4f}  "
            f"p90={_percentile(ns_entropies, 90):.4f}  "
            f"p95={_percentile(ns_entropies, 95):.4f}"
        )
        print(
            f"  │    sig_ratio   — median={_percentile(signal_ratios, 50):.4f}  "
            f"p90={_percentile(signal_ratios, 90):.4f}  "
            f"p95={_percentile(signal_ratios, 95):.4f}"
        )
        print(
            f"  │    degenerate[L]:  {degenerate_count}/{len(lc_stats)} ({degenerate_pct}%)  (legacy)"
        )
        print(
            f"  │    lifecycle[v2]:  stuck_absent={stuck_count}  "
            f"stable_ok={stable_ok_count}  transitioning_active={transitioning_count}  "
            f"insufficient_evidence={insuf_count}  "
            f"(non-stuck={len(lc_stats)-stuck_count}/{len(lc_stats)})"
        )
        print(
            f"  │    unique patterns : {gate['unique_patterns']}/{gate['total_sessions']} "
            f"(ratio={gate['unique_pattern_ratio']:.4f})"
        )
        degen_interp = gate.get("degenerate_rate_interpretation", "")
        if degen_interp:
            print(
                f"  │    degenerate_rate : {gate['degenerate_rate']:.4f}  [{degen_interp}]"
            )
        print("  │")

        # Phase 2 readiness gate
        verdict = gate["verdict"]
        verdict_label = (
            "READY (distribution gate only)"
            if verdict == "READY"
            else "NOT_READY (distribution gate only)"
        )
        verdict_marker = "[OK]" if verdict == "READY" else "[NO]"
        print(f"  │  Phase 2 Readiness Gate — {verdict_marker} {verdict_label}")
        print(
            "  │    distribution_gate="
            f"{verdict}  "
            "classification_validation="
            f"{gate.get('classification_validation', 'NOT_EVALUATED')}"
        )
        print(
            f"  │    gate_basis_version={gate.get('gate_basis_version', 'unknown')}"
            f"  threshold_source={gate.get('v2_threshold_source', 'unknown')}"
        )
        print(
            "  │    authority_status="
            f"{gate.get('authority_status', 'unknown')}  "
            "phase3_observation_only="
            f"{gate.get('phase3_observation_only', True)}"
        )
        if gate.get("phase2_semantic_lock_required"):
            print(
                "  │    [INFO] Phase 2 READY is a policy-proxy result, "
                "not final semantic authority."
            )
        if gate.get("legacy_nondegenerate_ratio_deprecated"):
            print(
                "  │    [INFO] legacy nondegenerate_ratio is reporting-only; "
                "not used for gate verdict"
            )
        if verdict == "READY":
            print(
                "  │    [NOTE] READY = quantitative conditions met (policy proxy)."
            )
            print(
                "  │           READY != classification validated across diverse contexts."
            )
            print(
                "  │           See docs/e1b-classification-semantic-limits.md"
            )
        for check in gate["checks"].values():
            mark = "  │    [OK]" if check["pass"] else "  │    [NO]"
            print(
                f"{mark}  {check['label']:<36} "
                f"required={check['required']}  "
                f"actual={check['actual']}"
            )
        # Shadow v2 gate comparison line
        # informational only — unique_pattern_ratio is no longer a gate blocker
        # (non-identifiable: stable_ok fleets converge to (ok,(),False) fingerprint)
        up_ratio = gate.get("unique_pattern_ratio", 0.0)
        up_count = gate.get("unique_patterns", 0)
        print(
            f"  │    [INFO]  unique patterns   : {up_count}/{gate['total_sessions']} "
            f"(ratio={up_ratio:.4f})  [non-blocking — see design note]"
        )
        # baseline representativeness advisory (post-gate)
        if not fleet["baseline_representative"]:
            print("  │")
            lc_r = fleet["lifecycle_capable_ratio"]
            lc_n = fleet["lifecycle_capable_count"]
            tot = fleet["total_repos"]
            print(
                f"  │  [ADVISORY] lifecycle_capable_ratio={lc_r:.4f} "
                f"< {_LIFECYCLE_CAPABLE_MIN_RATIO:.2f}:"
            )
            print(
                f"  │    only {lc_n}/{tot} repos are lifecycle-capable;"
            )
            print(
                "  │    a READY verdict here reflects quality of a narrow subset,"
            )
            print(
                "  │    not fleet-wide lifecycle health. "
                "E1b != adoption completeness."
            )
        print("  └────────────────────────────────────────────────────────────────┘")
    print(sep)


# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> int:
    parser = argparse.ArgumentParser(
        description="E1b Phase 2: Distribution Analysis + Readiness Gate",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  python scripts/analyze_e1b_distribution.py\n"
            "  python scripts/analyze_e1b_distribution.py --json\n"
            "  python scripts/analyze_e1b_distribution.py \\\n"
            "    --log-path ../repo-a/artifacts/runtime/canonical-audit-log.jsonl \\\n"
            "               ../repo-b/artifacts/runtime/canonical-audit-log.jsonl\n"
        ),
    )
    parser.add_argument(
        "--log-path",
        nargs="+",
        metavar="PATH",
        help=(
            f"Path(s) to canonical-audit-log.jsonl "
            f"(default: {_DEFAULT_LOG_PATH})"
        ),
    )
    parser.add_argument(
        "--min-sessions",
        type=int,
        default=_PHASE2_MIN_SESSIONS,
        metavar="N",
        help=f"Min total sessions for Phase 2 gate (default: {_PHASE2_MIN_SESSIONS})",
    )
    parser.add_argument(
        "--min-repos",
        type=int,
        default=_PHASE2_MIN_REPOS,
        metavar="M",
        help=f"Min distinct repos for Phase 2 gate (default: {_PHASE2_MIN_REPOS})",
    )
    parser.add_argument(
        "--min-non-stuck-absent-v2",
        type=float,
        default=None,
        metavar="R",
        help=(
            f"Min v2 non-stuck-absent repo fraction for readiness gate "
            f"(default: {_PHASE2_MIN_NON_STUCK_ABSENT_RATIO_V2})"
        ),
    )
    parser.add_argument(
        "--min-nondegenerate",
        type=float,
        default=None,
        metavar="R",
        help=(
            "DEPRECATED compatibility alias for --min-non-stuck-absent-v2. "
            "Legacy nondegenerate_ratio is reporting-only."
        ),
    )
    parser.add_argument(
        "--max-dominance",
        type=float,
        default=_PHASE2_MAX_REPO_DOMINANCE,
        metavar="R",
        help=(
            f"Max fraction any one repo can hold (default: "
            f"{_PHASE2_MAX_REPO_DOMINANCE})"
        ),
    )
    parser.add_argument(
        "--min-lifecycle-active",
        type=float,
        default=_PHASE2_MIN_LIFECYCLE_ACTIVE_RATIO,
        metavar="R",
        help=(
            f"Min ratio of lifecycle-active (not stuck_absent) repos in lifecycle_capable pool "
            f"(default: {_PHASE2_MIN_LIFECYCLE_ACTIVE_RATIO})"
        ),
    )
    parser.add_argument(
        "--auto-discover",
        action="store_true",
        dest="auto_discover",
        help=(
            "Scan sibling directories for canonical-audit-log.jsonl files. "
            "Mutually exclusive with --log-path."
        ),
    )
    parser.add_argument(
        "--json",
        action="store_true",
        dest="emit_json",
        help="Emit machine-readable JSON output",
    )
    args = parser.parse_args()

    if args.auto_discover and args.log_path:
        print(
            "error: --auto-discover and --log-path are mutually exclusive",
            file=sys.stderr,
        )
        return 1

    if args.auto_discover:
        log_paths = _auto_discover_logs(Path.cwd())
        if not args.emit_json:
            print(f"  auto-discovered {len(log_paths)} log file(s)")
    elif args.log_path:
        log_paths = [Path(p) for p in args.log_path]
    else:
        log_paths = [_DEFAULT_LOG_PATH]

    entries = _load_entries(log_paths)

    if not entries:
        if args.emit_json:
            print(json.dumps({"repos": {}, "phase2_gate": {
                "verdict": "NOT_READY",
                "total_sessions": 0,
                "repo_count": 0,
                "note": "no entries found",
            }}, indent=2))
        else:
            print("No entries found. Log is empty or all paths missing.")
            print(f"  searched: {', '.join(str(p) for p in log_paths)}")
        return 0

    repo_stats = compute_repo_stats(entries)
    fleet = compute_fleet_coverage(repo_stats)
    phase3_observation = build_phase3_observation_payload(entries, repo_stats)
    phase3_validation = validate_phase3_observation_payload(phase3_observation)
    try:
        enforce_phase3_observation_contract(phase3_validation)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    # Threshold resolution for v2 readiness basis.
    threshold_v2 = _PHASE2_MIN_NON_STUCK_ABSENT_RATIO_V2
    use_deprecated_alias = False
    if args.min_non_stuck_absent_v2 is not None:
        threshold_v2 = args.min_non_stuck_absent_v2
    if args.min_nondegenerate is not None:
        if (
            args.min_non_stuck_absent_v2 is not None
            and args.min_nondegenerate != args.min_non_stuck_absent_v2
        ):
            print(
                "error: --min-nondegenerate and --min-non-stuck-absent-v2 "
                "provided with different values",
                file=sys.stderr,
            )
            return 1
        if args.min_non_stuck_absent_v2 is None:
            threshold_v2 = args.min_nondegenerate
            use_deprecated_alias = True

    gate = evaluate_phase2_gate(
        entries,
        repo_stats,
        min_sessions=args.min_sessions,
        min_repos=args.min_repos,
        min_nondegenerate_ratio=(
            args.min_nondegenerate
            if args.min_nondegenerate is not None
            else _PHASE2_MIN_NONDEGENERATE_RATIO
        ),
        max_dominance=args.max_dominance,
        min_lifecycle_active_ratio=args.min_lifecycle_active,
        min_non_stuck_absent_ratio_v2=(
            None if use_deprecated_alias else threshold_v2
        ),
    )

    if args.emit_json:
        era = fleet.get("fleet_era_tag", "PRE-SKIP-TYPE-ERA")
        cov = fleet.get("fleet_skip_type_coverage_ratio", 0.0)
        if era == "PRE-SKIP-TYPE-ERA":
            reason_code = "skip_type_not_observed_in_audit_log"
            note = "skip_type-based classifications unavailable: all entries predate schema"
        elif era == "TRANSITION":
            reason_code = "skip_type_partial_coverage"
            note = "partial schema migration: interpret distributions with caution"
        else:
            reason_code = None
            note = "schema migration complete"
        migration_state = {
            "era_tag": era,
            "skip_type_coverage_ratio": cov,
            "classifications_interpretable": era == "CURRENT",
            "reason_code": reason_code,
            "note": note,
        }
        print(json.dumps(
            {
                "migration_state": migration_state,
                "repos": repo_stats,
                "fleet_coverage": fleet,
                "phase2_gate": gate,
                "phase3_observation": phase3_observation,
                "phase3_observation_contract": {
                    "non_decision_support": True,
                    "must_not_infer": [
                        "readiness",
                        "promotion",
                        "trend_quality",
                        "stability_verdict",
                    ],
                    "downstream_reuse_contract": {
                        "allowed_use": list(_PHASE3_DOWNSTREAM_ALLOWED_USE),
                        "forbidden_use": list(_PHASE3_DOWNSTREAM_FORBIDDEN_USE),
                        "interpretation_requires_separate_phase_contract": True,
                        "required_phase_contract": "phase3_interpretation_contract",
                    },
                    "reviewer_interpretation_boundary": {
                        "human_authored_commentary_non_authoritative": True,
                        "allowed_summary_scope": list(
                            _PHASE3_REVIEWER_ALLOWED_SUMMARY_SCOPE
                        ),
                        "forbidden_summary_claims": list(
                            _PHASE3_REVIEWER_FORBIDDEN_SUMMARY_CLAIMS
                        ),
                        "interpretation_requires_explicit_phase_transition": True,
                    },
                    "validation": phase3_validation,
                },
            },
            indent=2,
        ))
        return 0

    _print_human(repo_stats, fleet, gate, log_paths)
    return 0


if __name__ == "__main__":
    sys.exit(main())
