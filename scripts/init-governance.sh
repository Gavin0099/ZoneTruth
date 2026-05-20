#!/usr/bin/env bash
# init-governance.sh — Scaffold baseline governance files into a target repo.
#
# Usage:
#   bash scripts/init-governance.sh --target /path/to/repo
#   bash scripts/init-governance.sh --target /path/to/repo --upgrade
#   bash scripts/init-governance.sh --target /path/to/repo --adopt-existing
#   bash scripts/init-governance.sh --target /path/to/repo --refresh-baseline
#   bash scripts/init-governance.sh --target /path/to/repo --dry-run
#
# Lifecycle stages:
#   init              Fresh repo: copy all baseline files, record governance mandate + inventory
#   --adopt-existing  Existing repo: copy only AGENTS.base.md (protected), create missing
#                     overridable files from template, record inventory only (no mandate imposed)
#   --upgrade         Framework version changed: update protected files, show diff for overridable,
#                     preserve existing plan_required_sections, update inventory
#   --refresh-baseline  Repo structure changed (PLAN.md reorganised, files edited) but framework
#                     version unchanged: recompute hashes, update plan_section_inventory,
#                     no files copied, plan_required_sections preserved
#   drift-check       (separate tool) governance_drift_checker.py — detects deviation
#
# What plan_required_sections vs plan_section_inventory mean:
#   plan_required_sections  — governance mandate: these sections MUST exist in PLAN.md
#                             Only written by init (framework defaults) or by the user explicitly.
#   plan_section_inventory  — observed snapshot: the ## headings that exist in PLAN.md right now.
#                             Written by all modes; informational only, not enforced.
#
# Framework root resolution order:
#   1. --framework-root CLI flag   (explicit, highest priority)
#   2. GOVERNANCE_FRAMEWORK_ROOT   env var (user-controlled implicit)
#   3. FRAMEWORK_ROOT              legacy env var (backwards compat)
#   4. Upward scan from script dir (best effort)
#   5. script dir/..               (fallback when running from framework itself)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Framework root auto-discovery ─────────────────────────────────────────────
# Returns the nearest ancestor of $1 that contains governance_tools/, governance/,
# or docs/governance-runtime*. Prints the path if found, nothing if not found.
_discover_framework_root() {
    local current
    current="$(cd "$1" && pwd)"
    while true; do
        if [[ -d "$current/governance_tools" || -d "$current/governance" ]] || \
           compgen -G "$current/docs/governance-runtime*" > /dev/null 2>&1; then
            echo "$current"
            return 0
        fi
        local parent
        parent="$(dirname "$current")"
        if [[ "$parent" == "$current" ]]; then
            return 1
        fi
        current="$parent"
    done
}

# ── Argument Parsing ──────────────────────────────────────────────────────────

TARGET=""
UPGRADE=false
ADOPT_EXISTING=false
REFRESH_BASELINE=false
DRY_RUN=false
AUTO_MERGE=false
_CLI_FRAMEWORK_ROOT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)           TARGET="$2"; shift 2 ;;
        --framework-root)   _CLI_FRAMEWORK_ROOT="$2"; shift 2 ;;
        --upgrade)          UPGRADE=true; shift ;;
        --adopt-existing)   ADOPT_EXISTING=true; shift ;;
        --refresh-baseline) REFRESH_BASELINE=true; shift ;;
        --dry-run)          DRY_RUN=true; shift ;;
        --auto-merge)       AUTO_MERGE=true; shift ;;
        *)                  echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Resolve FRAMEWORK_ROOT following the priority chain.
if [[ -n "$_CLI_FRAMEWORK_ROOT" ]]; then
    FRAMEWORK_ROOT="$(cd "$_CLI_FRAMEWORK_ROOT" && pwd)"
elif [[ -n "${GOVERNANCE_FRAMEWORK_ROOT:-}" ]]; then
    FRAMEWORK_ROOT="$(cd "$GOVERNANCE_FRAMEWORK_ROOT" && pwd)"
elif [[ -n "${FRAMEWORK_ROOT:-}" ]]; then
    FRAMEWORK_ROOT="$(cd "$FRAMEWORK_ROOT" && pwd)"
else
    _discovered="$(_discover_framework_root "$SCRIPT_DIR" 2>/dev/null || true)"
    if [[ -n "$_discovered" ]]; then
        FRAMEWORK_ROOT="$_discovered"
    else
        FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    fi
fi

if [[ -z "$TARGET" ]]; then
    echo "ERROR: --target is required"
    echo "Usage: bash scripts/init-governance.sh --target /path/to/repo [--framework-root /path] [--upgrade|--adopt-existing|--refresh-baseline] [--dry-run]"
    exit 1
fi

TARGET="$(cd "$TARGET" && pwd)"

if [[ ! -d "$TARGET/.git" ]]; then
    echo "ERROR: $TARGET is not a git repository"
    exit 1
fi

if [[ ! -d "$BASELINE_SOURCE" ]]; then
    echo "ERROR: baseline source not found: $BASELINE_SOURCE"
    exit 1
fi

# ── Helper Functions ──────────────────────────────────────────────────────────

sha256_of() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        python3 -c "import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$file"
    fi
}

read_baseline_version() {
    grep -m1 'baseline_version:' "$BASELINE_SOURCE/AGENTS.base.md" \
        | sed 's/.*baseline_version:[[:space:]]*//' \
        | sed 's/[[:space:]]*-->.*//' \
        | tr -d '[:space:]'
}

# Print a post-adoption drift summary by running governance_drift_checker.py.
# Shows only warnings/findings so the user knows exactly what to fill in next.
# Silently skips if Python or the checker script is not available.
print_post_adoption_drift_summary() {
    local repo="$1"
    local py
    py="${AI_GOVERNANCE_PYTHON:-python3}"
    if ! command -v "$py" >/dev/null 2>&1; then
        py=python
    fi
    local checker="$FRAMEWORK_ROOT/governance_tools/governance_drift_checker.py"
    if [[ ! -f "$checker" ]]; then
        return
    fi
    echo ""
    echo "── Drift check (post-adoption) ──────────────────────────────────────"
    local output
    output=$("$py" "$checker" --repo "$repo" --framework-root "$FRAMEWORK_ROOT" \
        --skip-hash --format human 2>/dev/null | tr -d '\r') || true
    # Print only the [checks] block and findings/warnings
    local in_checks=false
    while IFS= read -r line; do
        case "$line" in
            \[checks\])        in_checks=true;  echo "$line" ;;
            "plan_section_inventory"*) in_checks=false ;;
            "findings"*|"warnings"*|"remediation_hints"*) in_checks=false; echo "$line" ;;
            *)
                if $in_checks; then
                    echo "$line"
                elif [[ "$line" == "  -"* ]] || [[ "$line" == "  ["* ]]; then
                    echo "$line"
                fi
                ;;
        esac
    done <<< "$output"
    echo "─────────────────────────────────────────────────────────────────────"
}

source_commit() {
    git -C "$FRAMEWORK_ROOT" rev-parse HEAD 2>/dev/null || echo "unknown"
}

# ── Section Arrays ────────────────────────────────────────────────────────────
#
# PLAN_REQUIRED_SECTIONS  governance mandate: the drift checker enforces these
# PLAN_INVENTORY_SECTIONS observed snapshot: informational, not enforced

PLAN_REQUIRED_SECTIONS=()
PLAN_INVENTORY_SECTIONS=()
# Relative path to PLAN.md within the target repo (default: PLAN.md at root).
# Set by discover_plan_path(); used by detect_plan_sections() and write_baseline_yaml().
PLAN_PATH="PLAN.md"

# Search for PLAN.md in common locations; set PLAN_PATH to the first match.
# Falls back to "PLAN.md" (root) if nothing found — caller decides whether to create it.
discover_plan_path() {
    local target="$1"
    local candidates=("PLAN.md" "governance/PLAN.md" "memory/PLAN.md" "docs/PLAN.md")
    for p in "${candidates[@]}"; do
        if [[ -f "$target/$p" ]]; then
            PLAN_PATH="$p"
            return
        fi
    done
    PLAN_PATH="PLAN.md"  # default; will be created from template if still missing
}

# Read plan_path recorded in an existing baseline.yaml → PLAN_PATH
# Used by --refresh-baseline so it re-hashes the same file that was recorded at adoption.
read_plan_path_from_baseline() {
    local target="$1"
    local recorded
    recorded=$(grep -m1 '^plan_path:' "$target/.governance/baseline.yaml" 2>/dev/null \
        | sed 's/plan_path:[[:space:]]*//' | tr -d '[:space:]')
    PLAN_PATH="${recorded:-PLAN.md}"
}

# Detect ## headings in PLAN.md (at path PLAN_PATH) → PLAN_INVENTORY_SECTIONS
detect_plan_sections() {
    local target="$1"
    PLAN_INVENTORY_SECTIONS=()
    if [[ -f "$target/$PLAN_PATH" ]]; then
        while IFS= read -r line; do
            PLAN_INVENTORY_SECTIONS+=("$line")
        done < <(grep '^## ' "$target/$PLAN_PATH" 2>/dev/null | head -20 | sed 's/[[:space:]]*$//')
    fi
}

# Read plan_required_sections from an existing baseline.yaml → PLAN_REQUIRED_SECTIONS
# Used by --upgrade and --refresh-baseline to preserve the governance mandate.
preserve_plan_required_sections() {
    local target="$1"
    PLAN_REQUIRED_SECTIONS=()
    local in_section=false
    while IFS= read -r line; do
        if [[ "$line" == "plan_required_sections:" ]]; then
            in_section=true
            continue
        fi
        if [[ "$in_section" == true ]]; then
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]] ]]; then
                local val
                val=$(printf '%s' "$line" | sed "s/^[[:space:]]*-[[:space:]]//;s/^[\"']//;s/[\"'][[:space:]]*$//")
                PLAN_REQUIRED_SECTIONS+=("$val")
            else
                in_section=false
            fi
        fi
    done < "$target/.governance/baseline.yaml"
}

write_baseline_yaml() {
    local target="$1"
    local baseline_version
    baseline_version="$(read_baseline_version)"
    local commit
    commit="$(source_commit)"
    local now
    now="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || python3 -c 'from datetime import datetime,timezone; print(datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))')"

    local hash_agents hash_plan hash_contract hash_agents_ext
    local plan_file="${PLAN_PATH:-PLAN.md}"
    hash_agents="$(sha256_of "$target/AGENTS.base.md")"
    hash_plan="$(sha256_of "$target/$plan_file" 2>/dev/null || echo "missing")"
    hash_contract="$(sha256_of "$target/contract.yaml")"
    hash_agents_ext="$(sha256_of "$target/AGENTS.md" 2>/dev/null || echo "missing")"

    # Record plan_path only when non-standard (omitting keeps root as default)
    local plan_path_block=""
    if [[ "$plan_file" != "PLAN.md" ]]; then
        plan_path_block="plan_path: $plan_file"$'\n'
    fi

    # Build plan_required_sections block (governance mandate — only if set)
    local required_block=""
    if [[ ${#PLAN_REQUIRED_SECTIONS[@]} -gt 0 ]]; then
        required_block="plan_required_sections:"
        for s in "${PLAN_REQUIRED_SECTIONS[@]}"; do
            required_block+=$'\n'"  - \"$s\""
        done
        required_block+=$'\n'
    fi

    # Build plan_section_inventory block (observed snapshot — always written when non-empty)
    local inventory_block=""
    if [[ ${#PLAN_INVENTORY_SECTIONS[@]} -gt 0 ]]; then
        inventory_block="plan_section_inventory:"
        for s in "${PLAN_INVENTORY_SECTIONS[@]}"; do
            inventory_block+=$'\n'"  - \"$s\""
        done
        inventory_block+=$'\n'
    fi

    mkdir -p "$target/.governance"
    cat > "$target/.governance/baseline.yaml" <<EOF
# .governance/baseline.yaml
# Written by scripts/init-governance.sh — do not edit manually.
# Verified by: python governance_tools/governance_drift_checker.py --repo .
#
# Semantic layers in this file:
#   PROVENANCE  — who generated this baseline and from which commit
#   INTEGRITY   — sha256 hashes + overridability of tracked files
#   CONTRACT    — governance mandates that MUST be satisfied (enforced by drift checker)
#   OBSERVED    — snapshot of repo structure at adoption time (informational, not enforced)

# ── PROVENANCE ────────────────────────────────────────────────────────────────
schema_version: "1"
baseline_version: $baseline_version
source_commit: $commit
framework_root: $FRAMEWORK_ROOT
initialized_at: $now
initialized_by: scripts/init-governance.sh
${plan_path_block}

# ── INTEGRITY ─────────────────────────────────────────────────────────────────
# sha256.<file>: hash recorded at init/refresh time; "protected" files are hash-verified
# overridable.<file>: protected = must not change | overridable = repo may extend freely
sha256.AGENTS.base.md: $hash_agents
sha256.PLAN.md: $hash_plan
sha256.contract.yaml: $hash_contract
sha256.AGENTS.md: $hash_agents_ext
overridable.AGENTS.base.md: protected
overridable.PLAN.md: overridable
overridable.contract.yaml: overridable
overridable.AGENTS.md: overridable

# ── CONTRACT (framework-enforced mandates) ────────────────────────────────────
# Fields listed here are actively checked by drift checker; violations block ci/gate.
# CONTRACT layer policy: only values that affect validation judgments belong here.
#   Do NOT use this layer for metadata, notes, or domain-specific configuration.
# plan_required_sections: ## headings that MUST be present in PLAN.md (governance mandate).
#   Empty = no mandate enforced (adopt-existing default). Set explicitly to harden.
# plan_freshness_threshold_days: CONTRACT OVERRIDE — changes the staleness threshold
#   for plan_freshness check. Setting this is an explicit governance policy decision.
#   The active threshold (override vs PLAN.md policy vs default) is always shown in
#   drift output so deviations from the framework default remain auditable.
#   Default: 7d (sprint) or as declared in PLAN.md Freshness: header.
#   Example: plan_freshness_threshold_days: 14   # bi-weekly cadence
contract_required_fields:
  - name
  - framework_interface_version
  - framework_compatible
  - domain
${required_block}
# ── OBSERVED (repo snapshot — informational only, never enforced) ──────────────
# plan_section_inventory: ## headings detected in PLAN.md at adoption/refresh time.
#   Drift checker surfaces these for visibility but never fails on missing inventory items.
${inventory_block}
EOF
    echo "  Wrote $target/.governance/baseline.yaml"
}

# ── Initial Scaffold ──────────────────────────────────────────────────────────

do_init() {
    echo "Initialising governance baseline in: $TARGET"
    echo "Baseline source: $BASELINE_SOURCE"
    echo ""

    if [[ "$DRY_RUN" == true ]]; then
        echo "[dry-run] Would copy:"
        for f in AGENTS.base.md AGENTS.md PLAN.md contract.yaml; do
            echo "  $BASELINE_SOURCE/$f -> $TARGET/$f"
        done
        echo "[dry-run] Would write: $TARGET/.governance/baseline.yaml"
        echo "[dry-run] plan_required_sections: framework defaults (Current Phase / Active Sprint / Backlog)"
        return
    fi

    for f in AGENTS.base.md AGENTS.md PLAN.md contract.yaml; do
        cp "$BASELINE_SOURCE/$f" "$TARGET/$f"
        echo "  Copied $f"
    done

    # Fresh init: governance mandate = framework defaults
    PLAN_REQUIRED_SECTIONS=("## Current Phase" "## Active Sprint" "## Backlog")
    detect_plan_sections "$TARGET"
    write_baseline_yaml "$TARGET"

    echo ""
    echo "Next steps:"
    echo "  1. Edit $TARGET/PLAN.md — fill in Owner, phases, sprint tasks"
    echo "  2. Edit $TARGET/contract.yaml — replace <repo-name> and <domain>"
    echo "  3. Edit $TARGET/AGENTS.md — add repo-specific risk levels and must-test paths"
    echo "     (see governance:key anchors in AGENTS.md for machine-readable section markers)"
    echo "     (DO NOT edit AGENTS.base.md — it is protected and hash-verified)"
    echo "  4. Commit: git add AGENTS.base.md AGENTS.md PLAN.md contract.yaml .governance/baseline.yaml"
    echo "  5. Verify: python governance_tools/governance_drift_checker.py --repo $TARGET"
}

# ── Adopt Existing ────────────────────────────────────────────────────────────
#
# For repos that already have governance-like files. Only fills gaps; never
# overwrites anything that already exists.
#
# Does NOT set plan_required_sections (no governance mandate is imposed on
# existing repos). Writes plan_section_inventory only, so the repo owner can
# inspect what exists and decide which sections to mandate.

do_adopt_existing() {
    echo "Adopting governance baseline into existing repo: $TARGET"
    echo "Baseline source: $BASELINE_SOURCE"
    echo ""

    # Discover PLAN.md location before any dry-run output
    discover_plan_path "$TARGET"

    if [[ "$DRY_RUN" == true ]]; then
        echo "[dry-run] AGENTS.base.md — always copied (protected baseline)"
        for f in AGENTS.md contract.yaml; do
            if [[ -f "$TARGET/$f" ]]; then
                echo "[dry-run] $f — kept as-is (already exists)"
            else
                echo "[dry-run] $f — would copy from template (missing)"
            fi
        done
        if [[ -f "$TARGET/$PLAN_PATH" ]]; then
            if [[ "$PLAN_PATH" != "PLAN.md" ]]; then
                echo "[dry-run] PLAN.md — found at $PLAN_PATH (non-standard location, will record plan_path)"
            else
                echo "[dry-run] PLAN.md — kept as-is (already exists)"
            fi
        else
            echo "[dry-run] PLAN.md — would copy from template (missing)"
        fi
        detect_plan_sections "$TARGET"
        if [[ ${#PLAN_INVENTORY_SECTIONS[@]} -gt 0 ]]; then
            echo "[dry-run] plan_section_inventory — ${#PLAN_INVENTORY_SECTIONS[@]} heading(s) detected:"
            for s in "${PLAN_INVENTORY_SECTIONS[@]}"; do
                echo "  $s"
            done
        fi
        echo "[dry-run] plan_required_sections — NOT set (no mandate imposed on existing repo)"
        echo "[dry-run] Would write: $TARGET/.governance/baseline.yaml"
        return
    fi

    # Protected files: always copy AGENTS.base.md
    cp "$BASELINE_SOURCE/AGENTS.base.md" "$TARGET/AGENTS.base.md"
    echo "  Copied AGENTS.base.md (protected baseline)"

    # Overridable files: create from template only if missing
    for f in AGENTS.md contract.yaml; do
        if [[ -f "$TARGET/$f" ]]; then
            echo "  $f — kept as-is (already exists)"
        else
            cp "$BASELINE_SOURCE/$f" "$TARGET/$f"
            echo "  $f — copied from template (was missing)"
        fi
    done

    # PLAN.md: use discovered path; create at root from template only if not found anywhere
    if [[ -f "$TARGET/$PLAN_PATH" ]]; then
        if [[ "$PLAN_PATH" != "PLAN.md" ]]; then
            echo "  PLAN.md — found at $PLAN_PATH (non-standard location; plan_path recorded in baseline)"
        else
            echo "  PLAN.md — kept as-is (already exists)"
        fi
    else
        cp "$BASELINE_SOURCE/PLAN.md" "$TARGET/PLAN.md"
        PLAN_PATH="PLAN.md"
        echo "  PLAN.md — copied from template (was missing)"
    fi

    # No governance mandate imposed — only record inventory
    PLAN_REQUIRED_SECTIONS=()
    detect_plan_sections "$TARGET"
    if [[ ${#PLAN_INVENTORY_SECTIONS[@]} -gt 0 ]]; then
        echo ""
        echo "  plan_section_inventory: ${#PLAN_INVENTORY_SECTIONS[@]} heading(s) observed in $PLAN_PATH"
        for s in "${PLAN_INVENTORY_SECTIONS[@]}"; do
            echo "    $s"
        done
        echo "  (recorded as inventory; no sections are enforced until you set plan_required_sections)"
    fi

    write_baseline_yaml "$TARGET"

    print_post_adoption_drift_summary "$TARGET"

    echo ""
    echo "Adoption complete. Next steps:"
    echo "  1. Fix any FAIL/warning items shown above (contract placeholders, empty AGENTS.md sections)"
    echo "  2. When files change later, refresh hashes:"
    echo "     bash scripts/init-governance.sh --target $TARGET --refresh-baseline"
    echo "  3. Optionally harden mandate: add plan_required_sections to .governance/baseline.yaml"
    echo "  4. Commit: git add AGENTS.base.md AGENTS.md PLAN.md contract.yaml .governance/baseline.yaml"
    echo "  5. Verify: python governance_tools/governance_drift_checker.py --repo $TARGET"
}

# ── Refresh Baseline ──────────────────────────────────────────────────────────
#
# Use when the REPO has changed (PLAN.md reorganised, AGENTS.md extended) but
# the framework version has NOT changed. Recomputes file hashes and updates
# plan_section_inventory. Does NOT copy any template files.
#
# Preserves plan_required_sections from the existing baseline so the governance
# mandate is not silently lost.

do_refresh_baseline() {
    echo "Refreshing baseline hashes and section inventory: $TARGET"
    echo ""

    if [[ ! -f "$TARGET/.governance/baseline.yaml" ]]; then
        echo "ERROR: no .governance/baseline.yaml found"
        echo "  Run init or adopt-existing first."
        exit 1
    fi

    # Restore PLAN_PATH from baseline so we re-hash the same file recorded at adoption
    read_plan_path_from_baseline "$TARGET"

    if [[ "$DRY_RUN" == true ]]; then
        detect_plan_sections "$TARGET"
        echo "[dry-run] Would recompute hashes for: AGENTS.base.md AGENTS.md $PLAN_PATH contract.yaml"
        echo "[dry-run] plan_required_sections — preserved from existing baseline.yaml"
        if [[ ${#PLAN_INVENTORY_SECTIONS[@]} -gt 0 ]]; then
            echo "[dry-run] plan_section_inventory — ${#PLAN_INVENTORY_SECTIONS[@]} heading(s) detected:"
            for s in "${PLAN_INVENTORY_SECTIONS[@]}"; do
                echo "  $s"
            done
        fi
        echo "[dry-run] No template files would be copied."
        return
    fi

    # Preserve governance mandate from existing baseline
    preserve_plan_required_sections "$TARGET"
    if [[ ${#PLAN_REQUIRED_SECTIONS[@]} -gt 0 ]]; then
        echo "  Preserved ${#PLAN_REQUIRED_SECTIONS[@]} plan_required_sections from existing baseline"
    fi

    # Detect current inventory
    detect_plan_sections "$TARGET"
    if [[ ${#PLAN_INVENTORY_SECTIONS[@]} -gt 0 ]]; then
        echo "  plan_section_inventory: ${#PLAN_INVENTORY_SECTIONS[@]} heading(s) in PLAN.md"
    fi

    write_baseline_yaml "$TARGET"

    echo ""
    echo "Refresh complete. Verify with:"
    echo "  python governance_tools/governance_drift_checker.py --repo $TARGET"
}

# ── Upgrade ───────────────────────────────────────────────────────────────────

do_upgrade() {
    echo "Upgrading governance baseline in: $TARGET"
    local old_version
    old_version="$(grep 'baseline_version:' "$TARGET/.governance/baseline.yaml" 2>/dev/null | head -1 | awk '{print $2}' || echo '<unknown>')"
    local new_version
    new_version="$(read_baseline_version)"
    echo "  $old_version -> $new_version"
    echo ""

    if [[ "$DRY_RUN" == true ]]; then
        echo "[dry-run] Would overwrite (protected): AGENTS.base.md"
        echo "[dry-run] Would diff (overridable): PLAN.md contract.yaml AGENTS.md"
        echo "[dry-run] plan_required_sections — preserved from existing baseline.yaml"
        return
    fi

    # Protected files: overwrite silently
    cp "$BASELINE_SOURCE/AGENTS.base.md" "$TARGET/AGENTS.base.md"
    echo "  Overwrote AGENTS.base.md (protected)"

    # Overridable files: show diff, overwrite only if --auto-merge
    for f in AGENTS.md PLAN.md contract.yaml; do
        if diff -u "$TARGET/$f" "$BASELINE_SOURCE/$f" > /dev/null 2>&1; then
            echo "  $f unchanged"
        else
            echo ""
            echo "  --- diff for $f (baseline change) ---"
            diff -u "$TARGET/$f" "$BASELINE_SOURCE/$f" || true
            echo "  --- end diff ---"
            if [[ "$AUTO_MERGE" == true ]]; then
                cp "$BASELINE_SOURCE/$f" "$TARGET/$f"
                echo "  Overwrote $f (--auto-merge)"
            else
                echo "  Skipped $f (review diff above, then manually merge or re-run with --auto-merge)"
            fi
        fi
    done

    # Preserve governance mandate; update inventory to current state
    preserve_plan_required_sections "$TARGET"
    detect_plan_sections "$TARGET"

    # Update baseline.yaml with new hashes, version, and inventory
    write_baseline_yaml "$TARGET"

    echo ""
    echo "Upgrade complete. Verify with:"
    echo "  python governance_tools/governance_drift_checker.py --repo $TARGET"
}

# ── Entry Point ───────────────────────────────────────────────────────────────

if [[ "$REFRESH_BASELINE" == true ]]; then
    do_refresh_baseline
elif [[ "$UPGRADE" == true ]]; then
    if [[ ! -f "$TARGET/.governance/baseline.yaml" ]]; then
        echo "ERROR: no existing .governance/baseline.yaml found — run without --upgrade first"
        echo "  If this repo already has governance files, use --adopt-existing instead."
        exit 1
    fi
    do_upgrade
elif [[ "$ADOPT_EXISTING" == true ]]; then
    if [[ -f "$TARGET/.governance/baseline.yaml" ]] && [[ "$DRY_RUN" == false ]]; then
        echo "WARNING: $TARGET/.governance/baseline.yaml already exists."
        echo "  --adopt-existing will overwrite it with refreshed hashes."
        read -r -p "  Continue? [y/N] " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
    fi
    do_adopt_existing
else
    if [[ -f "$TARGET/.governance/baseline.yaml" ]] && [[ "$DRY_RUN" == false ]]; then
        echo "WARNING: $TARGET/.governance/baseline.yaml already exists."
        echo "  Re-initialising will overwrite baseline files. Use --upgrade to preserve overridable files."
        echo "  If this repo already has its own governance files, use --adopt-existing."
        read -r -p "  Continue? [y/N] " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
    fi
    do_init
fi
