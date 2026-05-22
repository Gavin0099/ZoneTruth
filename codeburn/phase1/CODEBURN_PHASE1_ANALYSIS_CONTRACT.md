# CodeBurn Phase 1 Analysis Contract

> Version: 1.0.0
> Effective: 2026-04-30
> Scope: Post-job analysis guarantees for Phase 1 (`codeburn_analyze.py`)
> Status: **OPERATIVE**

---

## 0. Purpose

This contract defines the observable guarantees, interpretation boundaries, and non-claims
for Phase 1 post-job analysis. It is not a feature spec — it is a **governance boundary**.

Phase 2 additions that contradict any section in this contract require an explicit contract
amendment, not a silent code change.

---

## 1. Scope

Covers the following Phase 1 analysis entrypoints:

- `codeburn_analyze.py` — standalone post-job analysis CLI
- `codeburn_session.py session-end` — auto-runs analysis by default
- `codeburn_session.py session-end --no-analyze` — analysis suppressed (opt-out path)

Does NOT cover:

- `codeburn_run.py` (step execution)
- `codeburn_report.py` (report CLI — covered by DATA_VALIDITY_CONTRACT.md)
- Any Phase 2+ analysis extensions (must declare own contract)

---

## 2. Semantics Contract (語意層)

### 2.1 Observation-Only Constraint

Analysis MUST only describe observable execution patterns derived from recorded session data.

Analysis MUST NOT:

- Infer efficiency (e.g., "this step wasted time")
- Infer correctness (e.g., "this step produced wrong output")
- Imply optimization decisions (e.g., "consider removing this step")
- Claim cross-session comparability unless explicitly enabled by a future contract

### 2.2 Mandatory Boundary Footer

All analysis output (text and JSON formats) MUST include an explicit boundary declaration.

**Text format** (required lines in `print_analysis_text()`):

```
Analysis boundary:
  - Observations only
  - No efficiency judgment
  - No correctness judgment
```

**JSON format** (required field in `build_analysis()` return value):

```json
"analysis_boundary": {
  "analysis_type": "observation",
  "interpretation_level": "low",
  "claims": false,
  "notes": [
    "This summary reports observed execution patterns only.",
    "No efficiency or correctness judgment is made."
  ]
}
```

Removing or weakening the boundary footer in either format = contract violation.

---

## 3. Signal Contract (資料層)

### 3.1 Traceability Requirement

Every signal in analysis output MUST include a `derived_from_steps` field.

```json
{
  "signal": "<signal_name>",
  "confidence": "low | medium",
  "source": "phase1_heuristic | phase1_fallback",
  "derived_from_steps": ["<step_id>", ...]
}
```

- `derived_from_steps` MUST be a non-null list
- Empty list (`[]`) is permitted only when `step_id` is absent from the signal record
- Single-element list is permitted when no multi-step window applies

### 3.2 Signal Properties (Invariant)

All Phase 1 signals are advisory-only. No signal may trigger automatic blocking.

| Property | Value | Meaning |
|---|---|---|
| `advisory_only` | `true` | Signal cannot block session or step execution |
| `can_block` | `false` | No enforcement action may be attached |
| `confidence` | `"low"` or `"medium"` | No "high" confidence claims in Phase 1 |
| `source` | `"phase1_heuristic"` or `"phase1_fallback"` | Explicit source classification required |

Adding a Phase 1 signal with `can_block: true` = contract violation.

### 3.3 Defined Signals (Phase 1 Baseline)

| Signal | Source | Condition |
|---|---|---|
| `retry_pattern_detected` | `phase1_heuristic` | `step_kind=retry` or `retry_of` not null, 3-step window all qualify |
| `retry_pattern_inferred` | `phase1_fallback` | Same kind `execution`/`test`, same command, non-zero exit, no retry marker, 3-step window |

New signals added in Phase 2+ must be documented here or in a Phase 2 signal extension.

---

## 4. Output Determinism Contract (系統層)

### 4.1 Deterministic Guarantee

Given identical session data and session ID, `build_analysis()` MUST return an identical
result on every invocation (byte-for-byte when serialized to JSON).

### 4.2 Required Query Ordering

All SQL queries in `codeburn_analyze.py` MUST include a deterministic ORDER BY clause:

| Query target | Required ORDER BY |
|---|---|
| `steps` | `ORDER BY started_at ASC, step_id ASC` |
| `changed_files` | `ORDER BY file_path ASC` |
| `signals` | `ORDER BY id ASC, step_id ASC` |
| `latest` session resolution | `ORDER BY created_at DESC, session_id DESC LIMIT 1` |

### 4.3 Forbidden Runtime Fields

Analysis output MUST NOT include:

- Current timestamp (wall clock at analysis time)
- Runtime environment metadata (hostname, OS, Python version)
- Any field that varies between two identical invocations

Adding a runtime timestamp to the JSON output = contract violation.

---

## 5. Observability Limit Contract (觀測邊界層)

### 5.1 Declared Limits (Mandatory)

Analysis MUST explicitly declare the following observability limits in output.

**Text format** (required lines):

```
Observability limits:
  - Token usage: unknown
  - File reads: unsupported
  - File activity: git-visible only
```

**JSON format** (required field):

```json
"observability_limits": {
  "token_usage": "unknown",
  "file_reads": "unsupported",
  "file_activity": "git-visible only"
}
```

### 5.2 Interpretation of Limits

| Limit | Meaning |
|---|---|
| `token_usage: unknown` | No token count data is captured or reported in Phase 1 |
| `file_reads: unsupported` | Files read (not written) during steps are not tracked |
| `file_activity: git-visible only` | Changed files are captured via git diff; non-git changes are invisible |

Phase 2 extensions that unlock token visibility MUST update this field — they may NOT
silently change the value without a contract amendment.

### 5.3 Downstream Interpretation Rule

Any system consuming Phase 1 analysis output MUST interpret `observability_limits` before
drawing conclusions. Specifically:

- `token_usage: unknown` means no token-based efficiency comparison is valid
- `file_activity: git-visible only` means absence of file changes does NOT mean no work occurred

---

## 6. Non-Claims (防 drift 邊界)

Phase 1 analysis does NOT claim:

1. **Waste detection** — no step is labeled wasteful or redundant
2. **Efficiency measurement** — no step time is normalized or compared across sessions
3. **Correctness evaluation** — exit code ≠ 0 is recorded, not interpreted as failure of intent
4. **Cross-session comparability** — sessions are analyzed independently
5. **Full test parity** — this environment has degraded pytest execution; runtime smoke validates behavior
6. **Signal completeness** — `signals: []` means no signals were detected by Phase 1 heuristics, not that no patterns exist

Violating any of these in Phase 2 without an explicit contract amendment = governance drift.

---

## 7. Amendment Process

To modify this contract:

1. **Name the change** — which section is being amended and why
2. **State the new guarantee** — what replaces the old text
3. **Record evidence** — what operational finding necessitated the change
4. **Update this file** — bump version, record effective date
5. **Reference in test result** — link the amendment in the Phase 2 test result document

Silent code changes that contradict contract text = violation regardless of test pass status.

---

## 8. Evidence Anchors (Phase 1 Baseline)

| Milestone | Contract Section | Evidence File |
|---|---|---|
| M6 post-job analysis | §2, §5 | `CODEBURN_PHASE1_M6_TEST_RESULT_2026-04-30.md` |
| M6.5 signal traceability | §3.1 | `CODEBURN_PHASE1_M6_TEST_RESULT_2026-04-30.md` |
| M6.6 deterministic output | §4 | `CODEBURN_PHASE1_M66_TEST_RESULT_2026-04-30.md` |
| M4 observability fields | §5 | `CODEBURN_PHASE1_M35_M4_TEST_RESULT_2026-04-30.md` |
| M5 retry signals | §3.3 | `CODEBURN_PHASE1_M5_TEST_RESULT_2026-04-30.md` |

---

*This contract is operative as of 2026-04-30. Phase 2 extensions must reference this document.*
