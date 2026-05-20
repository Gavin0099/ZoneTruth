# P1i Migration Gate Checklist

Status: draft
Scope: observation-to-policy migration gate (no runtime path switch in this phase)

## Purpose

Define when intentional semantic change is allowed while preventing accidental drift.

## Gate Conditions (all required)

1. Primitive snapshots stable
- `PrimitiveBuilder` tests pass.
- No unexpected diff under `Tests/ZoneTruthCoreTests/Fixtures/`.

2. Observation snapshots stable
- Zone2/VO2/Strength/Activity observation snapshot tests all pass.
- No unexpected fixture diff.

3. Evaluation snapshot stable
- `testWorkoutEvaluationSnapshotFixture` passes.
- No diff in `Tests/ZoneTruthAppTests/Fixtures/workout_evaluation_snapshot.json` unless explicitly annotated.

4. Policy input independence
- Policy can consume observation outputs directly.
- No new dependency on legacy `AnalysisResult` for policy decisions.

5. Fallback path preserved
- Legacy path remains callable and documented.
- Rollback steps can be executed in one commit.

## Change-Intent Annotation (required for intentional diffs)

For any fixture update, include:
- Why the change is intentional
- Expected behavior shift
- Affected intents
- Rollback strategy

## Migration Mode

- `observe_only`: collect and validate observation contracts only
- `dual_run`: run legacy and observation-driven policy in parallel, compare outputs
- `policy_primary`: observation-driven policy is authoritative, legacy path fallback only

## Closeout Command Sequence

```bash
swift test
swift test --filter PrimitiveBuilder
swift test --filter Zone2Observation
swift test --filter VO2Observation
swift test --filter StrengthObservation
swift test --filter ActivityObservation
swift test --filter testWorkoutEvaluationSnapshotFixture
git diff -- Tests/ZoneTruthAppTests/Fixtures/workout_evaluation_snapshot.json
git diff -- Tests/ZoneTruthCoreTests/Fixtures/
```
