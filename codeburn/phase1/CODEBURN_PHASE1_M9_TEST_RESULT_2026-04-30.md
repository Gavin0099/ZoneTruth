# CodeBurn v2 Phase 1 - M9 Test Result (2026-04-30)

## Scope
- Repo: `E:\BackUp\Git_EE\ai-governance-framework`
- Target: M9 Entry Guard — mandatory status visibility on every CLI invocation

## Problem Addressed

`CODEBURN_PHASE1_STATUS.md` is a soft authority document — it can be bypassed
by going directly to source files. M9 makes the Phase 1 governance boundary
unavoidable: every CLI invocation surfaces the CLOSED status and decision-usage
prohibition without requiring the caller to read documentation.

## Implementation

### 1. `codeburn_phase1_header.py` — Shared Header Module

New module. Called from every CLI `main()` at the first line.

Output (to stderr — does not contaminate JSON stdout):
```
CodeBurn Phase 1 | Status: CLOSED | Decision usage: NOT ALLOWED (analysis_safe_for_decision=false)
See: codeburn/phase1/CODEBURN_PHASE1_STATUS.md
```

Stderr is used deliberately: JSON-consuming callers receive clean JSON on stdout
while terminal operators see the header on stderr.

### 2. CLI Coverage (all 6 entry points)

| CLI | Header Added |
|---|---|
| `codeburn_analyze.py` | ✓ |
| `codeburn_report.py` | ✓ |
| `codeburn_session.py` | ✓ |
| `codeburn_run.py` | ✓ |
| `codeburn_validate_analysis.py` | ✓ |
| `validate_phase1_data.py` | ✓ |

### 3. Machine-Level Fields in JSON Output

Added to `build_analysis()` and `build_report()`:

```json
"phase": "phase1",
"status": "closed",
"decision_usage_allowed": false
```

Semantic distinction:
- `analysis_safe_for_decision: false` — this specific analysis result cannot be used for decisions
- `decision_usage_allowed: false` — the Phase 1 system itself does not support decision usage

Both fields are required. A downstream integration consuming either output must check
both fields before any decision routing.

### 4. Enforcement Update — Invariant Violation Detection

`codeburn_validate_analysis.py` boundary_structure check (A) now distinguishes:

| State | Violation Code |
|---|---|
| `analysis_safe_for_decision` explicitly `True` | `phase1_invariant_violation:analysis_safe_for_decision_true` |
| `analysis_safe_for_decision` missing or `None` | `missing_analysis_safe_for_decision_false` |
| `decision_usage_allowed` missing or not `False` | `missing_decision_usage_allowed_false` |

All three trigger exit 1. The invariant violation code explicitly names the Phase 1 boundary.

## Runtime Smoke Evidence

```powershell
# Header on stderr, JSON clean on stdout
python codeburn/phase1/codeburn_analyze.py --db ... --format json 2>&1 | head -2
# → CodeBurn Phase 1 | Status: CLOSED | Decision usage: NOT ALLOWED ...
# → See: codeburn/phase1/CODEBURN_PHASE1_STATUS.md

# Machine fields in JSON
python codeburn/phase1/codeburn_analyze.py --db ... --format json 2>/dev/null
# → "phase": "phase1", "status": "closed", "decision_usage_allowed": false

# Enforcement passes (all required fields present)
python codeburn/phase1/codeburn_validate_analysis.py --db ...
# → ok=true, violation_count=0
```

## Execution Boundary
test execution degraded; validator gate passed; not equivalent to full pytest pass

## Verdict
- M9 status: **PASS (entry guard operative across all 6 CLI entry points)**
