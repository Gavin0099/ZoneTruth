#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/clang-module-cache}"
export SWIFTPM_CACHE_PATH="${SWIFTPM_CACHE_PATH:-$ROOT_DIR/.build/swiftpm-cache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_CACHE_PATH"

overall_status=0
results=()

run_check() {
  local name="$1"
  shift

  echo "[meta-closeout] START ${name}"
  if "$@"; then
    echo "[meta-closeout] PASS  ${name}"
    results+=("PASS ${name}")
  else
    local status=$?
    echo "[meta-closeout] FAIL  ${name} (exit=${status})"
    results+=("FAIL ${name}")
    overall_status=1
  fi
  echo
}

run_check "syntax: closeout_workout_evaluation" \
  bash -n scripts/closeout_workout_evaluation.sh

run_check "syntax: closeout_p3_user_visible" \
  bash -n scripts/closeout_p3_user_visible.sh

run_check "syntax: closeout_clean_pilot_enforce_smoke" \
  bash -n scripts/closeout_clean_pilot_enforce_smoke.sh

run_check "syntax: validate_claim_enforcement_receipts" \
  bash -n scripts/validate_claim_enforcement_receipts.sh

run_check "governance: claim enforcement receipt validator" \
  bash scripts/validate_claim_enforcement_receipts.sh

run_check "governance: runtime smoke" \
  bash scripts/run-runtime-governance.sh --mode smoke

run_check "targeted: GovernanceBoundaryGuardTests" \
  swift test --disable-sandbox --filter GovernanceBoundaryGuardTests

run_check "targeted: WeeklyDashboardView smoke compile" \
  swift test --disable-sandbox --filter testWeeklyDashboardViewSmokeCompiles

echo "[meta-closeout] SUMMARY"
for result in "${results[@]}"; do
  echo "[meta-closeout] ${result}"
done

if [[ "$overall_status" -eq 0 ]]; then
  echo "[meta-closeout] overall: PASS"
else
  echo "[meta-closeout] overall: FAIL"
fi

exit "$overall_status"
