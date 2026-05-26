# Test Responsibility Boundary

## Scope
- Core tests verify inference truth.
- App tests verify rendering safety.
- Closeout guards verify boundary drift.

## Hard Rules
- App tests MUST NOT re-test Core inference classification.
- App tests MUST assert no high-authority rendering from low-authority signals.
- Core tests MUST own freshness, confidence, inference, provenance, and authority-ceiling semantics.

## Intent
Prevent test architecture from reverse-contaminating product architecture boundaries.

## Enforcement Artifacts
- Runtime enforcement entrypoint: `scripts/closeout_workout_evaluation.sh`
- Boundary policy config source: `scripts/closeout_boundary_patterns.json` (`app_test_boundary_rules[*]` + `app_source_boundary_rules[*]`)
- Boundary config schema: `schemas/closeout_boundary_patterns.schema.json`
- Boundary telemetry artifact: `artifacts/runtime/boundary-telemetry/boundary_telemetry_*.json`
- Boundary trend rollup command: `python3 scripts/summarize_boundary_telemetry.py --limit 20 --output artifacts/runtime/boundary-telemetry/summary_latest.json`
- Boundary trend gate (in closeout): window/threshold can be tuned via `BOUNDARY_TREND_WINDOW`, `BOUNDARY_TREND_MAX_FAILURE_EVENTS`, `BOUNDARY_TREND_MAX_RULE_HITS`
- Boundary rollup includes `trendGate` verdict (`pass`/`fail`), and returns exit code `2` when thresholds are exceeded.
- Clean-pilot admissibility is evaluated in closeout and always disclosed; set `CLEAN_PILOT_ADMISSIBILITY_ENFORCE=1` to make non-admissible state fail-close.
- Enforce smoke command: `CLEAN_PILOT_ADMISSIBILITY_ENFORCE=1 bash scripts/closeout_clean_pilot_enforce_smoke.sh` (expects non-zero exit when repo is non-admissible).
