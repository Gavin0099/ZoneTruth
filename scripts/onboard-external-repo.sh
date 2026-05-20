#!/usr/bin/env bash
# onboard-external-repo.sh — install governance hooks, run onboarding checks, and emit a report

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_ROOT="$(realpath "$SCRIPT_DIR/..")"
INSTALL_SCRIPT="$SCRIPT_DIR/install-hooks.sh"
READINESS_TOOL="$FRAMEWORK_ROOT/governance_tools/external_repo_readiness.py"
SMOKE_TOOL="$FRAMEWORK_ROOT/governance_tools/external_repo_smoke.py"
REPORT_TOOL="$FRAMEWORK_ROOT/governance_tools/external_repo_onboarding_report.py"
PYTHON_LIB="$FRAMEWORK_ROOT/scripts/lib/python.sh"

TARGET_REPO=""
CONTRACT_PATH=""
DRY_RUN=false
NO_HOOK_VERIFY=false
OUTPUT_FORMAT="human"
NO_SMOKE=false
REPORT_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)
            TARGET_REPO="$2"
            shift 2
            ;;
        --contract)
            CONTRACT_PATH="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-hook-verify)
            NO_HOOK_VERIFY=true
            shift
            ;;
        --format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        --report-file)
            REPORT_FILE="$2"
            shift 2
            ;;
        --no-smoke)
            NO_SMOKE=true
            shift
            ;;
        *)
            echo "Usage: bash scripts/onboard-external-repo.sh --target /path/to/repo [--contract /path/to/contract.yaml] [--dry-run] [--no-hook-verify] [--no-smoke] [--format human|json] [--report-file /path/to/report.json]"
            exit 1
            ;;
    esac
done

if [ -z "$TARGET_REPO" ]; then
    echo "ERROR: missing --target /path/to/repo"
    exit 1
fi

if [ ! -d "$TARGET_REPO/.git" ]; then
    echo "ERROR: target is not a git repo root: $TARGET_REPO"
    exit 1
fi

echo "== External Repo Onboarding =="
echo "target_repo      = $(realpath "$TARGET_REPO")"
echo "framework_root   = $FRAMEWORK_ROOT"
if [ -n "$CONTRACT_PATH" ]; then
    echo "contract         = $(realpath "$CONTRACT_PATH")"
fi
if [ "$DRY_RUN" = true ]; then
    echo "mode             = dry-run"
else
    echo "mode             = install-and-assess"
fi
if [ "$NO_SMOKE" = true ]; then
    echo "governance_smoke = disabled (--no-smoke)"
else
    echo "governance_smoke = enabled"
fi
if [ -n "$REPORT_FILE" ]; then
    echo "report_file      = $REPORT_FILE"
fi
echo ""

INSTALL_ARGS=(--target "$TARGET_REPO")
if [ "$DRY_RUN" = true ]; then
    INSTALL_ARGS+=(--dry-run)
fi
if [ "$NO_HOOK_VERIFY" = true ]; then
    INSTALL_ARGS+=(--no-verify)
fi

bash "$INSTALL_SCRIPT" "${INSTALL_ARGS[@]}"

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "[dry-run] readiness assessment skipped"
    exit 0
fi

REPORT_DIR="$(realpath "$TARGET_REPO")/memory/governance_onboarding"
if [ -z "$REPORT_FILE" ]; then
    REPORT_FILE="$REPORT_DIR/latest.json"
fi

if [ ! -f "$PYTHON_LIB" ] || [ ! -f "$READINESS_TOOL" ]; then
    echo "WARNING: missing readiness tooling, skipping readiness report"
    exit 0
fi

. "$PYTHON_LIB"
if ! set_python_cmd; then
    echo "WARNING: Python not found, skipping readiness report"
    exit 0
fi

READINESS_ARGS=(--repo "$(realpath "$TARGET_REPO")" --framework-root "$FRAMEWORK_ROOT" --format "$OUTPUT_FORMAT")
if [ -n "$CONTRACT_PATH" ]; then
    READINESS_ARGS+=(--contract "$(realpath "$CONTRACT_PATH")")
fi

echo ""
echo "== External Repo Readiness =="
set +e
readiness_output=$("${PYTHON_CMD[@]}" "$READINESS_TOOL" "${READINESS_ARGS[@]}" 2>&1)
readiness_status=$?
set -e
printf '%s\n' "$readiness_output"

smoke_status=0
if [ "$NO_SMOKE" = false ]; then
    if [ ! -f "$SMOKE_TOOL" ]; then
        echo ""
        echo "WARNING: missing smoke tooling, skipping governance smoke"
    else
        SMOKE_ARGS=(--repo "$(realpath "$TARGET_REPO")" --format "$OUTPUT_FORMAT")
        if [ -n "$CONTRACT_PATH" ]; then
            SMOKE_ARGS+=(--contract "$(realpath "$CONTRACT_PATH")")
        fi

        echo ""
        echo "== Governance Smoke =="
        set +e
        smoke_output=$("${PYTHON_CMD[@]}" "$SMOKE_TOOL" "${SMOKE_ARGS[@]}" 2>&1)
        smoke_status=$?
        set -e
        printf '%s\n' "$smoke_output"
    fi
fi

report_status=0
if [ -f "$REPORT_TOOL" ]; then
    REPORT_ARGS=(--repo "$(realpath "$TARGET_REPO")" --framework-root "$FRAMEWORK_ROOT" --format json --output "$REPORT_FILE" --write-bundle "$REPORT_DIR")
    if [ -n "$CONTRACT_PATH" ]; then
        REPORT_ARGS+=(--contract "$(realpath "$CONTRACT_PATH")")
    fi

    echo ""
    echo "== Onboarding Report =="
    set +e
    report_output=$("${PYTHON_CMD[@]}" "$REPORT_TOOL" "${REPORT_ARGS[@]}" 2>&1)
    report_status=$?
    set -e
    printf '%s\n' "$report_output"
    echo "report_file       = $REPORT_FILE"
else
    echo ""
    echo "WARNING: missing onboarding report tool, skipping report artifact"
fi

if [ "$readiness_status" -ne 0 ] || [ "$smoke_status" -ne 0 ] || [ "$report_status" -ne 0 ]; then
    exit 1
fi
