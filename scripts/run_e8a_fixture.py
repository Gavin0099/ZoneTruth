#!/usr/bin/env python3
"""
scripts/run_e8a_fixture.py
---------------------------
Event-based E8a fixture runner.

Runs a lifecycle scenario against a temporary project root,
recording one EventRecord per time-step into a NDJSON event log.

Design contract
---------------
- One EventRecord per step, regardless of outcome.
- event_id deduplication is done by validate_e8a_entropy.py, not here.
  The runner records everything; the validator decides what counts.
- Artifact state is set BEFORE calling session_end_hook so the hook
  sees the correct filesystem state.
- gate_policy.yaml is rewritten at each step to reflect skip_test_result_check.
- The event log is written to:
    <out_dir>/e8a-event-log-<scenario>.ndjson
- Deterministic: same scenario + same repo name = same event_ids.

Usage
-----
    python scripts/run_e8a_fixture.py --scenario a_normal_ci
    python scripts/run_e8a_fixture.py --scenario all --out-dir /tmp/e8a_out
    python scripts/run_e8a_fixture.py --scenario all --repeats 10
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
from pathlib import Path
from typing import Any

# Make the repo root importable regardless of where the script is invoked from.
_REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_REPO_ROOT))
sys.path.insert(0, str(_REPO_ROOT / "tests"))

from governance_tools.session_end_hook import run_session_end_hook  # noqa: E402
from fixtures.e8a_event_scenarios.base import EventStep, validate_monotonic_timeline  # noqa: E402

# ── Scenario registry ──────────────────────────────────────────────────────────
_SCENARIO_MAP = {
    "a_normal_ci": "fixtures.e8a_event_scenarios.scenario_a_normal_ci",
    "b_broken_pipeline": "fixtures.e8a_event_scenarios.scenario_b_broken_pipeline",
    "c_skip_abuse": "fixtures.e8a_event_scenarios.scenario_c_skip_abuse",
}

_ARTIFACT_RELPATH = Path("artifacts/runtime/test-results/latest.json")
_CLOSEOUT_RELPATH = Path("artifacts/session-closeout.txt")
_GATE_POLICY_RELPATH = Path("governance/gate_policy.yaml")

_MINIMAL_CLOSEOUT = (
    "TASK_INTENT: e8a fixture run\n"
    "WORK_COMPLETED: fixture_step\n"
    "CHECKS_RUN: run_e8a_fixture\n"
    "DECISION: promote\n"
    "RESPONSE: ok\n"
)

_GATE_POLICY_TEMPLATE = """\
version: "1"
fail_mode: permissive
hook_coverage_tier: B
skip_test_result_check: {skip}
blocking_actions:
  - production_fix_required
unknown_treatment:
  mode: block_if_count_exceeds
  threshold: 3
canonical_audit_trend:
  window_size: 20
  signal_threshold_ratio: 0.5
"""


# ── Helpers ────────────────────────────────────────────────────────────────────

def _load_scenario(name: str) -> list[EventStep]:
    import importlib
    module = importlib.import_module(_SCENARIO_MAP[name])
    steps: list[EventStep] = module.STEPS
    validate_monotonic_timeline(steps)
    return steps


def _content_hash(content: str) -> str:
    return hashlib.sha1(content.encode()).hexdigest()


def _apply_action(step: EventStep, artifact_path: Path) -> int:
    """
    Apply the step action to the artifact file.
    Returns mtime as integer (seconds) after the action.
    0 when artifact does not exist.
    """
    if step.action == "delete" or not step.artifact_exists:
        if artifact_path.exists():
            artifact_path.unlink()
        return 0

    elif step.action == "create":
        artifact_path.parent.mkdir(parents=True, exist_ok=True)
        artifact_path.write_text(step.content, encoding="utf-8")
        return int(artifact_path.stat().st_mtime)

    elif step.action == "touch":
        # Write new content (not just utime) to guarantee content_hash changes
        # and avoid sub-second mtime deduplication issues.
        artifact_path.parent.mkdir(parents=True, exist_ok=True)
        artifact_path.write_text(step.content, encoding="utf-8")
        # Sleep 1s to guarantee mtime advances on filesystems with 1s resolution.
        time.sleep(1)
        return int(artifact_path.stat().st_mtime)

    else:  # noop
        mtime = int(artifact_path.stat().st_mtime) if artifact_path.exists() else 0
        # Sleep 1s to distinguish noop steps on the same artifact state.
        # This ensures consecutive noop steps get different timestamps in the
        # wall-clock sense, even if state_hash stays the same.
        time.sleep(1)
        return mtime


def _write_gate_policy(project_root: Path, skip: bool) -> None:
    policy_path = project_root / _GATE_POLICY_RELPATH
    policy_path.parent.mkdir(parents=True, exist_ok=True)
    policy_path.write_text(
        _GATE_POLICY_TEMPLATE.format(skip="true" if skip else "false"),
        encoding="utf-8",
    )


def _write_closeout(project_root: Path) -> None:
    closeout_path = project_root / _CLOSEOUT_RELPATH
    closeout_path.parent.mkdir(parents=True, exist_ok=True)
    closeout_path.write_text(_MINIMAL_CLOSEOUT, encoding="utf-8")


def _run_step(
    step: EventStep,
    project_root: Path,
    repo_name: str,
    repeat_idx: int,
) -> dict[str, Any]:
    """
    Apply one scenario step and return an EventRecord dict.
    """
    artifact_path = project_root / _ARTIFACT_RELPATH

    # 1. Set up gate_policy for this step
    _write_gate_policy(project_root, step.skip_test_result_check)

    # 2. Write closeout so hook can proceed
    _write_closeout(project_root)

    # 3. Apply artifact action
    mtime_floor = _apply_action(step, artifact_path)

    # 4. Compute state_hash AFTER action
    chash = _content_hash(step.content) if step.artifact_exists else _content_hash("")
    state_hash_raw = f"{step.artifact_exists}|{chash}|{mtime_floor}"
    state_hash = hashlib.sha1(state_hash_raw.encode()).hexdigest()

    # 5. Compute event_id (deterministic per repo+scenario+t+state)
    event_id_raw = f"{repo_name}|{step.scenario}|{step.t}|{state_hash}"
    event_id = hashlib.sha1(event_id_raw.encode()).hexdigest()

    # 6. Run session_end_hook
    hook_result = run_session_end_hook(project_root)

    # 7. Extract observed signal
    signals = hook_result.get("canonical_path_audit", {}).get("signals", [])
    observed_signal = len(signals) > 0

    # 8. Return EventRecord
    return {
        "repo": repo_name,
        "scenario": step.scenario,
        "t": step.t,
        "repeat": repeat_idx,
        "event_id": event_id,
        "state_hash": state_hash,
        "artifact": {
            "exists": step.artifact_exists,
            "mtime": mtime_floor,
            "content_hash": chash,
            "path": str(_ARTIFACT_RELPATH),
        },
        "config": {
            "skip_test_result_check": step.skip_test_result_check,
        },
        "action": step.action,
        "expected_signal": step.expected_signal,
        "observed_signal": observed_signal,
        "signals": signals,
        "gate_verdict": hook_result.get("gate_verdict"),
        "description": step.description,
    }


# ── Runner ─────────────────────────────────────────────────────────────────────

def run_scenario(
    scenario_name: str,
    project_root: Path,
    out_dir: Path,
    repeats: int = 1,
) -> Path:
    """
    Run one scenario `repeats` times.
    Each repeat uses the SAME project_root so the canonical-audit-log
    accumulates across repeats (producing real multi-session entropy).
    Returns path to the event log file.
    """
    import tempfile, shutil

    steps = _load_scenario(scenario_name)
    repo_name = project_root.resolve().name

    out_dir.mkdir(parents=True, exist_ok=True)
    log_path = out_dir / f"e8a-event-log-{scenario_name}.ndjson"

    records: list[dict] = []

    for repeat_idx in range(repeats):
        print(f"\n[{scenario_name}] repeat {repeat_idx + 1}/{repeats}")
        for step in steps:
            record = _run_step(step, project_root, repo_name, repeat_idx)
            signal_flag = "▲SIGNAL" if record["observed_signal"] else "·"
            match_flag = "✓" if record["expected_signal"] == record["observed_signal"] else "✗MISMATCH"
            print(
                f"  t={step.t} action={step.action:8s} "
                f"exists={step.artifact_exists} skip={step.skip_test_result_check} "
                f"event_id={record['event_id'][:10]}.. "
                f"state_hash={record['state_hash'][:8]}.. "
                f"{signal_flag} {match_flag}"
            )
            records.append(record)

    # Write NDJSON log
    with log_path.open("w", encoding="utf-8") as fh:
        for r in records:
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")

    print(f"\n  event log written: {log_path}  ({len(records)} records)")
    return log_path


# ── CLI ────────────────────────────────────────────────────────────────────────

def main() -> None:
    import tempfile

    parser = argparse.ArgumentParser(description="Run E8a event-based lifecycle fixtures")
    parser.add_argument(
        "--scenario",
        choices=list(_SCENARIO_MAP.keys()) + ["all"],
        default="all",
        help="Scenario to run (default: all)",
    )
    parser.add_argument(
        "--out-dir",
        default=str(_REPO_ROOT / "artifacts" / "e8a_fixture_output"),
        help="Directory for event log output",
    )
    parser.add_argument(
        "--repeats",
        type=int,
        default=1,
        help="Number of times to repeat each scenario (default: 1)",
    )
    parser.add_argument(
        "--project-root",
        default=None,
        help="Project root for the fixture run (default: fresh tmpdir per scenario)",
    )
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    scenarios = list(_SCENARIO_MAP.keys()) if args.scenario == "all" else [args.scenario]

    all_logs: list[Path] = []
    for scenario_name in scenarios:
        if args.project_root:
            project_root = Path(args.project_root)
            log_path = run_scenario(scenario_name, project_root, out_dir, args.repeats)
            all_logs.append(log_path)
        else:
            # Fresh tmpdir per scenario so canonical-audit-logs don't cross-contaminate
            import tempfile, shutil
            tmp = Path(tempfile.mkdtemp(prefix=f"e8a_{scenario_name}_"))
            try:
                log_path = run_scenario(scenario_name, tmp, out_dir, args.repeats)
                all_logs.append(log_path)
            finally:
                shutil.rmtree(tmp, ignore_errors=True)

    print(f"\n{'='*60}")
    print("All scenarios complete.  Event logs:")
    for p in all_logs:
        print(f"  {p}")
    print(f"\nRun  python scripts/validate_e8a_entropy.py --out-dir {out_dir}")
    print("to compute entropy / effective_entries / signal_ratio.")


if __name__ == "__main__":
    main()
