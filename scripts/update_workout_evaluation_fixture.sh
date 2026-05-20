#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

UPDATE_WORKOUT_EVAL_FIXTURE=1 swift test --filter testWorkoutEvaluationSnapshotFixture

echo "Updated fixture: Tests/ZoneTruthAppTests/Fixtures/workout_evaluation_snapshot.json"
