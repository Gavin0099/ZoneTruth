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
- Boundary regex config source: `scripts/closeout_boundary_patterns.sh`
