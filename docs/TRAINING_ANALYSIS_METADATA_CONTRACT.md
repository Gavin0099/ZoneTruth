---
audience: agent-runtime
authority: implementation-contract
status: draft
last_updated: 2026-06-10
depends_on:
  - docs/TRAINING_ANALYSIS_META_SPEC.md
  - docs/TRAINING_ESTIMATOR_EVIDENCE_MAP.md
  - docs/APPLE_HEALTH_TRAINING_DATA_ROLE_MATRIX.md
---

# Training Analysis Metadata Contract

## Purpose

This contract defines when training-analysis analyzer, importer, and display
metadata must carry `spec_resolution.evidence_layer` and
`spec_resolution.source_role_layer`.

It is an implementation-facing contract. It does not add new analyzer behavior,
UI surfaces, HealthKit permissions, or claim authority.

## Layer Definitions

`spec_resolution.evidence_layer` points to the evidence authority that decides
what the metric can safely claim.

Current allowed value:

```text
TRAINING_ESTIMATOR_EVIDENCE_MAP
```

`spec_resolution.source_role_layer` points to the source-specific matrix that
decides what an imported data source is allowed to contribute.

Current allowed values:

```text
none
APPLE_HEALTH_TRAINING_DATA_ROLE_MATRIX
future_source_matrix
```

Core rule:

```text
source_role_layer may narrow or cap evidence authority, but must not upgrade it.
```

## Required Metadata Shape

Analyzer, importer, or display metadata that participates in training-analysis
claims should converge on this shape:

```yaml
spec_resolution:
  evidence_layer: TRAINING_ESTIMATOR_EVIDENCE_MAP
  source_role_layer: none | APPLE_HEALTH_TRAINING_DATA_ROLE_MATRIX | future_source_matrix
  source_role_reason: string | null
```

`source_role_reason` is optional but recommended when the source-role layer is
not `none`.

Examples:

```yaml
source_role_reason: apple_health_vo2max_product_reference
source_role_reason: apple_health_resting_hr_initial_zone2_range
source_role_reason: apple_health_power_external_load_context
```

## Analyzer Metadata Contract

Analyzer outputs must include `spec_resolution.evidence_layer` when they produce
or expose any of these:

- method tier
- claim ceiling
- confidence level
- downgrade reason
- user-facing summary text
- metric disclosure item
- classification claim

Default analyzer value:

```yaml
spec_resolution:
  evidence_layer: TRAINING_ESTIMATOR_EVIDENCE_MAP
  source_role_layer: none
```

Analyzer outputs should use `source_role_layer: none` when the claim is based on
generic workout features rather than source-specific semantics.

Examples:

- Core VO2 interval-quality classifier based on heart-rate pattern:
  `source_role_layer: none`
- Core Zone 2 analysis using policy bounds without source-specific display:
  `source_role_layer: none`
- Core strength-pattern analysis based on workout category and HR shape:
  `source_role_layer: none`

Analyzer outputs must not infer Apple Health role semantics unless Apple Health
data materially affects ingestion, confidence, copy, or display.

## Importer Metadata Contract

Importer metadata must include `spec_resolution.source_role_layer` when imported
data carries source-specific meaning that affects claim ceiling, confidence, or
display.

Apple Health importer examples:

| Imported Data | Required Source Role Layer | Reason |
|---|---|---|
| `vo2Max` | `APPLE_HEALTH_TRAINING_DATA_ROLE_MATRIX` | Apple-produced product estimate |
| `restingHeartRate` used for Zone 2 bounds | `APPLE_HEALTH_TRAINING_DATA_ROLE_MATRIX` | weak heuristic input for initial reference range |
| `runningPower` / `cyclingPower` | `APPLE_HEALTH_TRAINING_DATA_ROLE_MATRIX` | external-load field-estimator input |
| `workoutRoute` | `APPLE_HEALTH_TRAINING_DATA_ROLE_MATRIX` | context-only terrain signal |
| HRV SDNN | `APPLE_HEALTH_TRAINING_DATA_ROLE_MATRIX` | bounded recovery/autonomic context |

Importer metadata may use `source_role_layer: none` when:

- imported data is treated as raw local fixture data
- source provenance is unknown
- no source-specific claim or display logic is applied

Unknown provenance must not default to Apple Health semantics.

## Display Metadata Contract

Display metadata must include `spec_resolution.source_role_layer` when
user-facing text depends on a source-specific role.

Required cases:

- showing Apple Health VO2 max as a product estimate
- explaining Apple Health Resting HR as an initial Zone 2 reference input
- using Apple Health power to explain external-load context
- using Apple Health route to explain terrain or pace distortion
- showing Apple Health swim HR with a confidence cap
- showing Apple Health strength data as pattern/context only

Display metadata may use `source_role_layer: none` when:

- rendering generic analyzer results
- rendering non-source-specific metric disclosures
- rendering manually entered values without source-role semantics

Display text must resolve claim authority in this order:

1. Evidence layer claim ceiling.
2. Source-role layer cap or caveat.
3. Local UI wording constraints.

If those disagree, choose the narrowest claim.

## Source-Role Upgrade Ban

Source-role metadata must not upgrade an output beyond the evidence layer.

Forbidden examples:

- Apple Health `vo2Max` upgrading `estimate_only` to `measured`.
- Apple Health `restingHeartRate` upgrading `initial_reference_range` to
  `personalized_calibrated_threshold`.
- Apple Health `runningPower` or `cyclingPower` upgrading field support into
  `LT1_found` or `VT1_found`.
- Apple Health workout category or HR shape upgrading strength context into
  `direct_1RM`.

## Future Source Matrices

When adding Garmin, Strava, COROS, manual lab imports, or another source:

- do not reuse `APPLE_HEALTH_TRAINING_DATA_ROLE_MATRIX` by analogy
- add a dedicated source-role matrix when source semantics materially affect
  claim ceiling, confidence, or display
- use `future_source_matrix` only as a temporary placeholder in docs, not as a
  production value

## Implementation Acceptance

This contract is satisfied when:

- analyzer-facing metadata has an explicit evidence layer
- source-backed importer/display metadata has an explicit source-role layer
- generic analyzer metadata uses `source_role_layer: none`
- Apple Health-specific copy and confidence caps point to the Apple Health role
  matrix
- no source-role layer can upgrade evidence-layer authority
