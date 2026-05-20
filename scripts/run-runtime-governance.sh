#!/usr/bin/env bash
# Shared runtime-governance enforcement entrypoint for local hooks and CI.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/python.sh"

MODE="enforce"
PYTEST_ARGS=()
CONTRACT_PATH=""
PROJECT_ROOT_OVERRIDE=""
PLAN_PATH_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            MODE="$2"
            shift 2
            ;;
        --contract)
            CONTRACT_PATH="$2"
            shift 2
            ;;
        --project-root)
            PROJECT_ROOT_OVERRIDE="$2"
            shift 2
            ;;
        --plan-path)
            PLAN_PATH_OVERRIDE="$2"
            shift 2
            ;;
        --pytest-arg)
            PYTEST_ARGS+=("$2")
            shift 2
            ;;
        *)
            echo "Usage: bash scripts/run-runtime-governance.sh [--mode enforce|smoke|ci] [--contract /path/to/contract.yaml] [--project-root /path/to/repo] [--plan-path /path/to/PLAN.md] [--pytest-arg ARG]"
            exit 1
            ;;
    esac
done

if ! set_python_cmd; then
    print_python_resolution_help "runtime-governance"
    exit 1
fi

run_smoke() {
    local smoke_overrides=()
    if [[ -n "$CONTRACT_PATH" ]]; then
        smoke_overrides+=(--contract "$CONTRACT_PATH")
    fi
    if [[ -n "$PROJECT_ROOT_OVERRIDE" ]]; then
        smoke_overrides+=(--project-root "$PROJECT_ROOT_OVERRIDE")
    fi
    if [[ -n "$PLAN_PATH_OVERRIDE" ]]; then
        smoke_overrides+=(--plan-path "$PLAN_PATH_OVERRIDE")
    fi

    "${PYTHON_CMD[@]}" runtime_hooks/smoke_test.py --harness claude_code --event-type session_start "${smoke_overrides[@]}" --output artifacts/runtime/smoke/claude_session_start.txt --json-output artifacts/runtime/smoke/claude_session_start.json
    "${PYTHON_CMD[@]}" governance_tools/change_control_summary.py --session-start-file artifacts/runtime/smoke/claude_session_start.json --output artifacts/runtime/smoke/claude_change_control_summary.txt
    "${PYTHON_CMD[@]}" runtime_hooks/smoke_test.py --harness claude_code --event-type pre_task "${smoke_overrides[@]}"
    "${PYTHON_CMD[@]}" runtime_hooks/smoke_test.py --harness claude_code --event-type post_task "${smoke_overrides[@]}"
    "${PYTHON_CMD[@]}" runtime_hooks/smoke_test.py --harness codex --event-type session_start "${smoke_overrides[@]}" --output artifacts/runtime/smoke/codex_session_start.txt --json-output artifacts/runtime/smoke/codex_session_start.json
    "${PYTHON_CMD[@]}" governance_tools/change_control_summary.py --session-start-file artifacts/runtime/smoke/codex_session_start.json --output artifacts/runtime/smoke/codex_change_control_summary.txt
    "${PYTHON_CMD[@]}" runtime_hooks/smoke_test.py --harness codex --event-type post_task "${smoke_overrides[@]}"
    "${PYTHON_CMD[@]}" runtime_hooks/smoke_test.py --harness gemini --event-type session_start "${smoke_overrides[@]}" --output artifacts/runtime/smoke/gemini_session_start.txt --json-output artifacts/runtime/smoke/gemini_session_start.json
    "${PYTHON_CMD[@]}" governance_tools/change_control_summary.py --session-start-file artifacts/runtime/smoke/gemini_session_start.json --output artifacts/runtime/smoke/gemini_change_control_summary.txt
    "${PYTHON_CMD[@]}" runtime_hooks/smoke_test.py --harness gemini --event-type post_task "${smoke_overrides[@]}"
    "${PYTHON_CMD[@]}" runtime_hooks/smoke_test.py --event-type session_start "${smoke_overrides[@]}" --output artifacts/runtime/smoke/shared_session_start.txt --json-output artifacts/runtime/smoke/shared_session_start.json
    "${PYTHON_CMD[@]}" governance_tools/change_control_summary.py --session-start-file artifacts/runtime/smoke/shared_session_start.json --output artifacts/runtime/smoke/shared_change_control_summary.txt
    "${PYTHON_CMD[@]}" governance_tools/change_control_index.py --artifacts-dir artifacts/runtime/smoke --output artifacts/runtime/smoke/INDEX.txt
}

run_pytest_suite() {
    if ! "${PYTHON_CMD[@]}" -c "import pytest" >/dev/null 2>&1; then
        echo "[runtime-governance] pytest is required for mode=$MODE"
        echo "[runtime-governance] install it with: ${PYTHON_CMD[*]} -m pip install pytest"
        exit 1
    fi

    "${PYTHON_CMD[@]}" -m pytest \
        tests/test_runtime_smoke_test.py \
        tests/test_runtime_dispatcher.py \
        tests/test_runtime_pre_task_check.py \
        tests/test_runtime_post_task_check.py \
        tests/test_runtime_session_end.py \
        tests/test_memory_curator.py \
        tests/test_rule_pack_loader.py \
        tests/test_state_generator.py \
        tests/test_test_result_ingestor.py \
        tests/test_architecture_drift_checker.py \
        --basetemp .pytest_tmp_runtime \
        "${PYTEST_ARGS[@]}"
}

record_feedback() {
    local smoke_status="$1"
    local pytest_status="$2"
    local framework_root="${PROJECT_ROOT_OVERRIDE:-.}"

    "${PYTHON_CMD[@]}" -m governance_tools.runtime_enforcement_feedback \
        record \
        --framework-root "$framework_root" \
        --mode "$MODE" \
        --smoke-status "$smoke_status" \
        --pytest-status "$pytest_status" \
        --emit-signal
}

case "$MODE" in
    smoke)
        echo "[runtime-governance] mode=smoke"
        smoke_status="pass"
        if ! run_smoke; then
            smoke_status="fail"
        fi
        record_feedback "$smoke_status" "skipped"
        if [[ "$smoke_status" != "pass" ]]; then
            exit 1
        fi
        ;;
    ci)
        echo "[runtime-governance] mode=ci"
        smoke_status="pass"
        pytest_status="skipped"
        if ! run_smoke; then
            smoke_status="fail"
        else
            pytest_status="pass"
            if ! run_pytest_suite; then
                pytest_status="fail"
            fi
        fi
        record_feedback "$smoke_status" "$pytest_status"
        if [[ "$smoke_status" != "pass" || "$pytest_status" == "fail" ]]; then
            exit 1
        fi
        ;;
    enforce)
        echo "[runtime-governance] mode=enforce"
        smoke_status="pass"
        pytest_status="skipped"
        if ! run_smoke; then
            smoke_status="fail"
        else
            pytest_status="pass"
            if ! run_pytest_suite; then
                pytest_status="fail"
            fi
        fi
        record_feedback "$smoke_status" "$pytest_status"
        if [[ "$smoke_status" != "pass" || "$pytest_status" == "fail" ]]; then
            exit 1
        fi
        ;;
    *)
        echo "Unsupported mode: $MODE"
        exit 1
        ;;
esac

echo "[runtime-governance] complete"
