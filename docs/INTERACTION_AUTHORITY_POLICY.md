# Interaction Authority Policy

## Why This Exists
Authority drift is not only a wording problem. Interaction patterns can imply coaching authority even with compliant wording.

## Forbidden Interaction Patterns
- Single-value readiness authority compression (e.g. "Today readiness: 42%")
- Prescriptive daily workout recommendations in primary summary surfaces
- Intervention commands ("you should rest today") in main decision cards
- Single top-line health verdict that hides evidence incompleteness

## Required Interaction Patterns
- Evidence decomposition first
  - Example:
    - 3 consecutive high-intensity sessions
    - reduced low-intensity distribution
    - elevated HR drift
- Coverage always visible
  - Do not hide unknown/unavailable domains behind tooltips only.
- Uncertainty-first rendering order
  - Evidence -> Coverage -> Bounded interpretation

## Surface Risk Heuristic
- High implied authority:
  - readiness score / ring
  - recommendation CTA as primary action
- Lower implied authority:
  - evidence list
  - coverage matrix
  - bounded interpretation text

## Enforcement
- Structural guard checks are required in closeout scripts.
- Keyword lint alone is insufficient for interaction governance.
