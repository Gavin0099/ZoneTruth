#!/usr/bin/env bash

# Boundary regex patterns for closeout fail-close guards.
# Keep patterns centralized to avoid drift between script logic and tests.

# Ignore pure comment lines in grep outputs.
BOUNDARY_COMMENT_FILTER_REGEX='^[^:]+:[0-9]+:[[:space:]]*//'

# App tests must not directly re-test core inference semantics.
APP_TEST_BOUNDARY_REGEX='WeeklyInferenceClassifier\.classify|WeeklyConfidenceSemantics\.calibrated|WeeklyFreshnessSignal\.classify'

# App source must not create/classify inference authority.
APP_SOURCE_BOUNDARY_REGEX='WeeklyInferenceClassifier\.classify|WeeklyAuthorityRendering\.authority|InferenceProvenanceFactory\.weekly|InferenceAuthorityCeiling|MissingEvidence\.(sleep|hrv)'
