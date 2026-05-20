#!/usr/bin/env bash
# Shared Python interpreter resolution for local scripts and hooks.

PYTHON_CMD=()

set_python_cmd() {
    if [ -n "${AI_GOVERNANCE_PYTHON:-}" ]; then
        if command -v "$AI_GOVERNANCE_PYTHON" >/dev/null 2>&1; then
            PYTHON_CMD=("$AI_GOVERNANCE_PYTHON")
            return 0
        fi
        if [ -x "$AI_GOVERNANCE_PYTHON" ]; then
            PYTHON_CMD=("$AI_GOVERNANCE_PYTHON")
            return 0
        fi
    fi

    if [ -n "${PYTHON_CMD_OVERRIDE:-}" ]; then
        if command -v "$PYTHON_CMD_OVERRIDE" >/dev/null 2>&1; then
            PYTHON_CMD=("$PYTHON_CMD_OVERRIDE")
            return 0
        fi
        if [ -x "$PYTHON_CMD_OVERRIDE" ]; then
            PYTHON_CMD=("$PYTHON_CMD_OVERRIDE")
            return 0
        fi
    fi

    local candidate
    for candidate in python python3 py; do
        if command -v "$candidate" >/dev/null 2>&1; then
            if [ "$candidate" = "py" ]; then
                PYTHON_CMD=("py" "-3")
            else
                PYTHON_CMD=("$candidate")
            fi
            return 0
        fi
    done

    return 1
}

print_python_resolution_help() {
    local context="${1:-AI Governance scripts}"
    echo "[$context] no usable Python interpreter was found"
    echo "[$context] set AI_GOVERNANCE_PYTHON=/path/to/python, or add python/python3/py to PATH"
}
