#!/usr/bin/env bash
# install-hooks.sh — 安裝 AI Governance Git Hooks
#
# 用法：
#   bash scripts/install-hooks.sh           # 安裝到當前 repo 的 .git/hooks/
#   bash scripts/install-hooks.sh --target /path/to/other/repo
#   bash scripts/install-hooks.sh --dry-run # 只顯示將執行的操作
#
# 安裝的 hooks：
#   pre-commit  — PLAN.md freshness 檢查（CRITICAL 擋 commit）
#   pre-push    — push 前檢查（含每日 memory fail-closed gate）
#
# 解除安裝：
#   rm .git/hooks/pre-commit .git/hooks/pre-push

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_SRC="$SCRIPT_DIR/hooks"
TARGET_REPO="$SCRIPT_DIR/.."
DRY_RUN=false
VERIFY_AFTER_INSTALL=true

# ── 參數解析 ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)
            TARGET_REPO="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-verify)
            VERIFY_AFTER_INSTALL=false
            shift
            ;;
        *)
            echo "用法: bash scripts/install-hooks.sh [--target /path/to/repo] [--dry-run] [--no-verify]"
            exit 1
            ;;
    esac
done

TARGET_HOOKS_DIR="$TARGET_REPO/.git/hooks"
HOOK_CONFIG="$TARGET_HOOKS_DIR/ai-governance-framework-root"
FRAMEWORK_ROOT="$(realpath "$SCRIPT_DIR/..")"
PYTHON_LIB="$FRAMEWORK_ROOT/scripts/lib/python.sh"
HOOK_VALIDATOR="$FRAMEWORK_ROOT/governance_tools/hook_install_validator.py"

# ── 驗證目標 repo ─────────────────────────────────────────────────────────
if [ ! -d "$TARGET_REPO/.git" ]; then
    echo "❌ 找不到 .git 目錄: $TARGET_REPO"
    echo "   請確認 --target 路徑是 git repo 根目錄"
    exit 1
fi

echo "📂 目標 repo: $(realpath "$TARGET_REPO")"
echo "📁 hooks 來源: $HOOKS_SRC"
echo "🏠 framework root: $FRAMEWORK_ROOT"
if [ "$VERIFY_AFTER_INSTALL" = true ]; then
    echo "🔎 安裝後驗證: 啟用"
else
    echo "🔎 安裝後驗證: 停用 (--no-verify)"
fi
echo ""

# ── 安裝每個 hook ─────────────────────────────────────────────────────────
INSTALLED=0
SKIPPED=0

install_hook() {
    local hook_name="$1"
    local src="$HOOKS_SRC/$hook_name"
    local dst="$TARGET_HOOKS_DIR/$hook_name"

    if [ ! -f "$src" ]; then
        echo "⚠️  跳過 $hook_name（來源不存在: $src）"
        SKIPPED=$((SKIPPED + 1))
        return
    fi

    # 備份現有 hook（若存在且不是我們的）
    if [ -f "$dst" ] && ! grep -q "AI Governance Framework" "$dst" 2>/dev/null; then
        local backup="${dst}.bak.$(date +%Y%m%d_%H%M%S)"
        if [ "$DRY_RUN" = true ]; then
            echo "  [dry-run] 備份現有 hook → $backup"
        else
            cp "$dst" "$backup"
            echo "  💾 備份現有 hook → $(basename "$backup")"
        fi
    fi

    if [ "$DRY_RUN" = true ]; then
        echo "  [dry-run] 安裝 $hook_name → $dst"
    else
        cp "$src" "$dst"
        chmod +x "$dst"
        echo "  ✅ 安裝 $hook_name"
    fi
    INSTALLED=$((INSTALLED + 1))
}

install_hook "pre-commit"
install_hook "pre-push"

if [ "$DRY_RUN" = true ]; then
    echo "  [dry-run] 寫入 framework root 設定 → $HOOK_CONFIG"
    echo "            內容: $FRAMEWORK_ROOT"
else
    printf '%s\n' "$FRAMEWORK_ROOT" > "$HOOK_CONFIG"
    echo "  ✅ 寫入 framework root 設定"
fi

echo ""
if [ "$DRY_RUN" = true ]; then
    echo "[dry-run] 完成（未實際修改）"
    echo "  將安裝: $INSTALLED 個 hooks，跳過: $SKIPPED 個"
else
    echo "✅ 安裝完成"
    echo "   已安裝: $INSTALLED 個 hooks，跳過: $SKIPPED 個"
    echo ""
    if [ "$VERIFY_AFTER_INSTALL" = true ] && [ -f "$PYTHON_LIB" ] && [ -f "$HOOK_VALIDATOR" ]; then
        . "$PYTHON_LIB"
        if set_python_cmd; then
            echo "🔎 驗證 hook 安裝狀態："
            "${PYTHON_CMD[@]}" "$HOOK_VALIDATOR" --repo "$(realpath "$TARGET_REPO")" || true
            echo ""
        else
            echo "⚠️  找不到 Python，略過 hook_install_validator"
            echo ""
        fi
    fi
    
    echo "📋 驗證："
    echo "   cat $TARGET_HOOKS_DIR/pre-commit"
    echo "   $FRAMEWORK_ROOT/governance_tools/hook_install_validator.py --repo $(realpath "$TARGET_REPO")"
    echo ""
    echo "🧪 測試："
    echo "   git commit --allow-empty -m 'test hook'"
    echo ""
    echo "🗑️  解除安裝："
    echo "   rm $TARGET_HOOKS_DIR/pre-commit $TARGET_HOOKS_DIR/pre-push $HOOK_CONFIG"
fi
