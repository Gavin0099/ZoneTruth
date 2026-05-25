# Inference Policy

## Purpose
Define machine-checkable boundaries for inference production so bounded UI cannot be bypassed by inflated upstream reasoning.

## Allowed Inference Classes
- `direct_observation`: direct measurable signals with no synthesis claim.
- `bounded_synthesis`: constrained pattern synthesis from observed training evidence.
- `sparse_inference`: low-coverage synthesis with explicit insufficiency disclosure.

## Forbidden Inference Escalation
- No causal physiological determination from training-only proxies.
- No intervention recommendation (for example, mandatory rest or workout prescription).
- No authority jump from proxy signal to clinical-like recovery verdict.
- Example forbidden jump: high HR drift -> poor recovery (without sleep/HRV/context evidence).

## Evidence Dependency Disclosure
Every bounded or sparse inference must expose:
- `derived_from` evidence families
- `missing_evidence` domains
- an explicit authority ceiling (`non_interventional`)

Required missing-evidence visibility when unavailable:
- sleep
- HRV

## Authority Ceiling
- Inference outputs must remain `non_interventional`.
- Any change proposing recommendation/prescription authority is governance-risk and release-blocking until explicit policy revision.

## Enforcement
- Runtime closeout scripts must enforce inference-authority guard checks.
- UI-layer compliance is necessary but insufficient; inference-layer checks are mandatory.
