#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FIXTURE_PATH="Tests/ZoneTruthAppTests/Fixtures/workout_evaluation_snapshot.json"

semantic_guard="passed"
snapshot_fixture="matched"
working_tree_clean="yes"
ui_smoke="skipped/manual-required"

if ! swift test; then
  semantic_guard="failed"
  echo "semantic_guard: ${semantic_guard}"
  echo "snapshot_fixture: ${snapshot_fixture}"
  echo "working_tree_clean: ${working_tree_clean}"
  echo "ui_smoke: ${ui_smoke}"
  exit 1
fi

if ! swift test --filter PrimitiveBuilder; then
  semantic_guard="failed"
  echo "semantic_guard: ${semantic_guard}"
  echo "snapshot_fixture: ${snapshot_fixture}"
  echo "working_tree_clean: ${working_tree_clean}"
  echo "ui_smoke: ${ui_smoke}"
  exit 1
fi

if ! swift test --filter Zone2Observation; then
  semantic_guard="failed"
  echo "semantic_guard: ${semantic_guard}"
  echo "snapshot_fixture: ${snapshot_fixture}"
  echo "working_tree_clean: ${working_tree_clean}"
  echo "ui_smoke: ${ui_smoke}"
  exit 1
fi

if ! swift test --filter VO2Observation; then
  semantic_guard="failed"
  echo "semantic_guard: ${semantic_guard}"
  echo "snapshot_fixture: ${snapshot_fixture}"
  echo "working_tree_clean: ${working_tree_clean}"
  echo "ui_smoke: ${ui_smoke}"
  exit 1
fi

if ! swift test --filter StrengthObservation; then
  semantic_guard="failed"
  echo "semantic_guard: ${semantic_guard}"
  echo "snapshot_fixture: ${snapshot_fixture}"
  echo "working_tree_clean: ${working_tree_clean}"
  echo "ui_smoke: ${ui_smoke}"
  exit 1
fi

if ! swift test --filter ActivityObservation; then
  semantic_guard="failed"
  echo "semantic_guard: ${semantic_guard}"
  echo "snapshot_fixture: ${snapshot_fixture}"
  echo "working_tree_clean: ${working_tree_clean}"
  echo "ui_smoke: ${ui_smoke}"
  exit 1
fi

if ! swift test --filter testWorkoutEvaluationSnapshotFixture; then
  snapshot_fixture="changed"
  echo "semantic_guard: ${semantic_guard}"
  echo "snapshot_fixture: ${snapshot_fixture}"
  echo "working_tree_clean: ${working_tree_clean}"
  echo "ui_smoke: ${ui_smoke}"
  exit 1
fi

if ! git diff --quiet -- "$FIXTURE_PATH" || ! git diff --quiet --cached -- "$FIXTURE_PATH"; then
  snapshot_fixture="changed"
fi

if ! git diff --quiet -- Tests/ZoneTruthCoreTests/Fixtures || ! git diff --quiet --cached -- Tests/ZoneTruthCoreTests/Fixtures; then
  snapshot_fixture="changed"
fi

if ! git diff --quiet || ! git diff --quiet --cached; then
  working_tree_clean="no"
fi

echo "semantic_guard: ${semantic_guard}"
echo "snapshot_fixture: ${snapshot_fixture}"
echo "working_tree_clean: ${working_tree_clean}"
echo "ui_smoke: ${ui_smoke}"
