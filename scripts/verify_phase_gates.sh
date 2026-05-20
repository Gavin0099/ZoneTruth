#!/bin/bash
# verify_phase_gates.sh — 驗證 Phase Gate 條件
#
# 用法:
#   bash scripts/verify_phase_gates.sh
#
# 退出碼:
#   0 = 全部 Gate 通過
#   1 = 至少一項 Gate 未通過
#
# 用途:
#   讓 Phase 完成的宣告從「人工 [✓]」變成「機器可驗證」。
#   建議在 git push 前或 CI 中執行。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/python.sh"

PASS=0
FAIL=0
RELEASE_VERSION="v1.0.0-alpha"

ok()   { echo "  ✅ $1"; }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
info() { echo ""; echo "── $1 ──────────────────────────────"; }

echo "╔══════════════════════════════════════════╗"
echo "║   Phase Gate Verification                ║"
echo "╚══════════════════════════════════════════╝"

if ! set_python_cmd; then
    fail "找不到可用的 Python 解譯器"
    print_python_resolution_help "verify_phase_gates"
    echo ""
    echo "══════════════════════════════════════════"
    TOTAL=$((PASS + FAIL))
    echo "  結果: ${PASS}/${TOTAL} Gates 通過"
    echo "  🚨 $FAIL 項未通過 — 請先安裝或指定 Python"
    exit 1
fi

# ── Gate 1: 單元測試 ─────────────────────────────────────────
info "Gate 1 / 單元測試"
if "${PYTHON_CMD[@]}" -m pytest tests/ -q --tb=short 2>&1; then
    ok "pytest 通過"
    PASS=$((PASS + 1))
else
    fail "pytest 失敗 — 請修復後再宣告 Phase 完成"
fi

# ── Gate 2: PLAN.md 新鮮度 ───────────────────────────────────
info "Gate 2 / PLAN.md 新鮮度"
PLAN_OUTPUT=$("${PYTHON_CMD[@]}" governance_tools/plan_freshness.py --format json) || true
PLAN_STATUS=$(echo "$PLAN_OUTPUT" | "${PYTHON_CMD[@]}" -c \
    "import json,sys; r=json.load(sys.stdin); print(r['status'])")
PLAN_DAYS=$(echo "$PLAN_OUTPUT" | "${PYTHON_CMD[@]}" -c \
    "import json,sys; r=json.load(sys.stdin); print(r.get('days_since_update','?'))")

if [ "$PLAN_STATUS" = "CRITICAL" ] || [ "$PLAN_STATUS" = "ERROR" ]; then
    fail "PLAN.md $PLAN_STATUS (${PLAN_DAYS}d) — 請更新後再宣告完成"
elif [ "$PLAN_STATUS" = "STALE" ]; then
    echo "  ⚠️  PLAN.md STALE (${PLAN_DAYS}d) — 建議更新，但不阻擋"
    ok "Gate 通過（警告）"
    PASS=$((PASS + 1))
else
    ok "PLAN.md $PLAN_STATUS (${PLAN_DAYS}d)"
    PASS=$((PASS + 1))
fi

# ── Gate 3: Governance tools 可執行 ─────────────────────────
info "Gate 3 / 工具可執行性"
TOOLS=(
    "contract_validator.py"
    "example_readiness.py"
    "governance_auditor.py"
    "quickstart_smoke.py"
    "reviewer_handoff_reader.py"
    "reviewer_handoff_publication_reader.py"
    "reviewer_handoff_snapshot.py"
    "reviewer_handoff_summary.py"
    "release_surface_overview.py"
    "release_package_publication_reader.py"
    "release_package_reader.py"
    "release_package_summary.py"
    "release_package_snapshot.py"
    "release_readiness.py"
    "trust_signal_snapshot.py"
    "trust_signal_publication_reader.py"
    "trust_signal_overview.py"
    "plan_freshness.py"
    "memory_janitor.py"
    "state_generator.py"
)
ALL_OK=1
for tool in "${TOOLS[@]}"; do
    if "${PYTHON_CMD[@]}" "governance_tools/$tool" --help > /dev/null 2>&1; then
        ok "$tool"
    else
        fail "$tool --help 失敗"
        ALL_OK=0
    fi
done
if "${PYTHON_CMD[@]}" governance_tools/quickstart_smoke.py --project-root . --plan PLAN.md --contract examples/usb-hub-contract/contract.yaml --format human > /dev/null 2>&1; then
    ok "quickstart_smoke.py onboarding path"
else
    fail "quickstart_smoke.py onboarding path 失敗"
    ALL_OK=0
fi
if "${PYTHON_CMD[@]}" runtime_hooks/smoke_test.py --event-type session_start --contract examples/usb-hub-contract/contract.yaml --format human > /dev/null 2>&1; then
    ok "smoke_test.py contract-aware session_start"
else
    fail "smoke_test.py contract-aware session_start 失敗"
    ALL_OK=0
fi
if "${PYTHON_CMD[@]}" runtime_hooks/dispatcher.py --file runtime_hooks/examples/shared/session_start.shared.json --contract examples/usb-hub-contract/contract.yaml --format human > /dev/null 2>&1; then
    ok "dispatcher.py contract-aware session_start"
else
    fail "dispatcher.py contract-aware session_start 失敗"
    ALL_OK=0
fi
if "${PYTHON_CMD[@]}" governance_tools/example_readiness.py --format human > /dev/null 2>&1; then
    ok "example_readiness.py example inventory"
else
    fail "example_readiness.py example inventory 失敗"
    ALL_OK=0
fi
if bash scripts/run-runtime-governance.sh --mode smoke --contract examples/usb-hub-contract/contract.yaml --project-root . --plan-path PLAN.md > /dev/null 2>&1; then
    ok "run-runtime-governance.sh contract-aware smoke"
else
    fail "run-runtime-governance.sh contract-aware smoke 失敗"
    ALL_OK=0
fi
if "${PYTHON_CMD[@]}" governance_tools/release_readiness.py --version "$RELEASE_VERSION" --format human > /dev/null 2>&1; then
    ok "release_readiness.py $RELEASE_VERSION"
else
    fail "release_readiness.py $RELEASE_VERSION 失敗"
    ALL_OK=0
fi
if "${PYTHON_CMD[@]}" governance_tools/release_package_summary.py --version "$RELEASE_VERSION" --format human > /dev/null 2>&1; then
    ok "release_package_summary.py $RELEASE_VERSION"
else
    fail "release_package_summary.py $RELEASE_VERSION 失敗"
    ALL_OK=0
fi
if "${PYTHON_CMD[@]}" governance_tools/release_package_snapshot.py --version "$RELEASE_VERSION" --write-bundle artifacts/release-package/phase-gate-smoke --format human > /dev/null 2>&1; then
    ok "release_package_snapshot.py $RELEASE_VERSION"
else
    fail "release_package_snapshot.py $RELEASE_VERSION 失敗"
    ALL_OK=0
fi
if "${PYTHON_CMD[@]}" governance_tools/release_package_reader.py --version "$RELEASE_VERSION" --file artifacts/release-package/phase-gate-smoke/MANIFEST.json --format human > /dev/null 2>&1; then
    ok "release_package_reader.py $RELEASE_VERSION"
else
    fail "release_package_reader.py $RELEASE_VERSION 失敗"
    ALL_OK=0
fi
if "${PYTHON_CMD[@]}" governance_tools/release_package_publication_reader.py --file artifacts/release-package/phase-gate-smoke/PUBLICATION_MANIFEST.json --format human > /dev/null 2>&1; then
    ok "release_package_publication_reader.py $RELEASE_VERSION"
else
    fail "release_package_publication_reader.py $RELEASE_VERSION 失敗"
    ALL_OK=0
fi
if "${PYTHON_CMD[@]}" governance_tools/release_surface_overview.py --version "$RELEASE_VERSION" --bundle-manifest artifacts/release-package/phase-gate-smoke/MANIFEST.json --publication-manifest artifacts/release-package/phase-gate-smoke/PUBLICATION_MANIFEST.json --format human > /dev/null 2>&1; then
    ok "release_surface_overview.py $RELEASE_VERSION"
else
    fail "release_surface_overview.py $RELEASE_VERSION 失敗"
    ALL_OK=0
fi
if "${PYTHON_CMD[@]}" governance_tools/reviewer_handoff_summary.py --project-root . --plan PLAN.md --release-version "$RELEASE_VERSION" --contract examples/usb-hub-contract/contract.yaml --release-bundle-manifest artifacts/release-package/phase-gate-smoke/MANIFEST.json --release-publication-manifest artifacts/release-package/phase-gate-smoke/PUBLICATION_MANIFEST.json --format human > /dev/null 2>&1; then
    ok "reviewer_handoff_summary.py $RELEASE_VERSION"
else
    fail "reviewer_handoff_summary.py $RELEASE_VERSION 失敗"
    ALL_OK=0
fi
if "${PYTHON_CMD[@]}" governance_tools/reviewer_handoff_snapshot.py --project-root . --plan PLAN.md --release-version "$RELEASE_VERSION" --contract examples/usb-hub-contract/contract.yaml --release-bundle-manifest artifacts/release-package/phase-gate-smoke/MANIFEST.json --release-publication-manifest artifacts/release-package/phase-gate-smoke/PUBLICATION_MANIFEST.json --write-bundle artifacts/reviewer-handoff/phase-gate-smoke/"$RELEASE_VERSION" --publish-status-dir artifacts/reviewer-handoff/phase-gate-smoke/published --publication-root artifacts/reviewer-handoff/phase-gate-smoke --format human > /dev/null 2>&1; then
    ok "reviewer_handoff_snapshot.py $RELEASE_VERSION"
else
    fail "reviewer_handoff_snapshot.py $RELEASE_VERSION 失敗"
    ALL_OK=0
fi
if "${PYTHON_CMD[@]}" governance_tools/reviewer_handoff_reader.py --release-version "$RELEASE_VERSION" --file artifacts/reviewer-handoff/phase-gate-smoke/"$RELEASE_VERSION"/MANIFEST.json --format human > /dev/null 2>&1; then
    ok "reviewer_handoff_reader.py $RELEASE_VERSION"
else
    fail "reviewer_handoff_reader.py $RELEASE_VERSION 失敗"
    ALL_OK=0
fi
if "${PYTHON_CMD[@]}" governance_tools/reviewer_handoff_publication_reader.py --release-version "$RELEASE_VERSION" --file artifacts/reviewer-handoff/phase-gate-smoke/PUBLICATION_MANIFEST.json --format human > /dev/null 2>&1; then
    ok "reviewer_handoff_publication_reader.py $RELEASE_VERSION"
else
    fail "reviewer_handoff_publication_reader.py $RELEASE_VERSION 失敗"
    ALL_OK=0
fi
if "${PYTHON_CMD[@]}" governance_tools/governance_auditor.py --project-root . --release-version "$RELEASE_VERSION" --format human > /dev/null 2>&1; then
    ok "governance_auditor.py release-aware self-audit"
else
    fail "governance_auditor.py release-aware self-audit 失敗"
    ALL_OK=0
fi
if "${PYTHON_CMD[@]}" governance_tools/trust_signal_overview.py --project-root . --plan PLAN.md --release-version "$RELEASE_VERSION" --contract examples/usb-hub-contract/contract.yaml --format human > /dev/null 2>&1; then
    ok "trust_signal_overview.py release-facing overview"
else
    fail "trust_signal_overview.py release-facing overview 失敗"
    ALL_OK=0
fi
if "${PYTHON_CMD[@]}" governance_tools/trust_signal_snapshot.py --project-root . --plan PLAN.md --release-version "$RELEASE_VERSION" --contract examples/usb-hub-contract/contract.yaml --write-bundle artifacts/trust-signals/phase-gate-smoke --publish-status-dir artifacts/trust-signals/phase-gate-smoke/published --format human > /dev/null 2>&1; then
    ok "trust_signal_snapshot.py bundle publishing"
else
    fail "trust_signal_snapshot.py bundle publishing 失敗"
    ALL_OK=0
fi
if "${PYTHON_CMD[@]}" governance_tools/trust_signal_publication_reader.py --file artifacts/trust-signals/phase-gate-smoke/PUBLICATION_MANIFEST.json --format human > /dev/null 2>&1; then
    ok "trust_signal_publication_reader.py publication manifest"
else
    fail "trust_signal_publication_reader.py publication manifest 失敗"
    ALL_OK=0
fi
if [ "$ALL_OK" -eq 1 ]; then
    PASS=$((PASS + 1))
fi

# ── Gate 4: 治理文件完整性 ───────────────────────────────────
info "Gate 4 / 治理文件完整性"
DOCS=(
    "governance/SYSTEM_PROMPT.md"
    "governance/AGENT.md"
    "governance/ARCHITECTURE.md"
    "governance/HUMAN-OVERSIGHT.md"
    "governance/REVIEW_CRITERIA.md"
    "governance/TESTING.md"
    "governance/NATIVE-INTEROP.md"
    "governance/PLAN.md"
    "PLAN.md"
)
DOCS_OK=1
for doc in "${DOCS[@]}"; do
    if [ -f "$doc" ]; then
        ok "$doc 存在"
    else
        fail "$doc 缺失"
        DOCS_OK=0
    fi
done
if [ "$DOCS_OK" -eq 1 ]; then
    PASS=$((PASS + 1))
fi

# ── 摘要 ─────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════"
TOTAL=$((PASS + FAIL))
echo "  結果: ${PASS}/${TOTAL} Gates 通過"

if [ "$FAIL" -eq 0 ]; then
    echo "  🎉 全部通過 — Phase 完成條件滿足"
    exit 0
else
    echo "  🚨 $FAIL 項未通過 — 請修復後再宣告 Phase 完成"
    exit 1
fi
