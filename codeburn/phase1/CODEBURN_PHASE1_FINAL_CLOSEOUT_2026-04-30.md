# CodeBurn v2 Phase 1 — Final Closeout (2026-04-30)

> Status: **CLOSED**
> Supersedes: `CODEBURN_PHASE1_CONSOLIDATED_CLOSEOUT_2026-04-30.md`
> Governance contract: `CODEBURN_PHASE1_ANALYSIS_CONTRACT.md` (v1.0.0)

---

## 1. Delivered Capability

| Milestone | Description | Verdict |
|---|---|---|
| M1 | Session lifecycle (start / end / recovery) | PASS |
| M2 | Run wrapper + step data capture + git-visible changes + data validator | PASS |
| M3.5 | Session recovery: `auto_close_previous`, `resume_previous`, `abort_start`, `idle_timeout` | PASS |
| M4 | Report CLI with fixed observability fields (`data_quality`, `token_comparability`, `file_activity`, `file_reads`) | PASS |
| M5 | Advisory retry signals: `retry_pattern_detected`, `retry_pattern_inferred` | PASS |
| M6 | Post-job auto analysis on `session-end`; `--no-analyze` opt-out | PASS |
| M6.5 | Signal traceability: `derived_from_steps` on every signal | PASS |
| M6.6 | Deterministic analysis output (byte-for-byte, ordered queries, no runtime fields) | PASS |
| M7 | Analysis contract enforcement — fail-closed (`codeburn_validate_analysis.py`) | PASS |

All milestones validated via runtime smoke. Full pytest execution degraded in this environment;
validator gate passed and is not equivalent to full pytest pass.

---

## 2. Contract Guarantees

Defined in `CODEBURN_PHASE1_ANALYSIS_CONTRACT.md` (v1.0.0). Summary:

**§2 Semantics** — Analysis is observation-only. No efficiency, correctness, or optimization claims.
Boundary footer is mandatory in both text and JSON output formats.

**§3 Signal** — All signals are `advisory_only=true / can_block=false`.
Retry signals (`retry_pattern_detected`, `retry_pattern_inferred`) must carry `derived_from_steps`.
No "high" confidence level is permitted in Phase 1.

**§4 Determinism** — `build_analysis()` returns byte-for-byte identical output for the same input.
Four SQL ORDER BY rules enforced. No runtime timestamp in output.

**§5 Observability Limits** — Three limits must be declared in every output:
`token_usage: unknown / file_reads: unsupported / file_activity: git-visible only`.
These are not warnings — they define what the system can and cannot observe.

**§6 Non-Claims** — Six categories of claims that Phase 1 does not and must not make:
waste detection, efficiency measurement, correctness evaluation, cross-session comparability,
full test parity, signal completeness.

**§7 Amendment Process** — Contract changes require: named section, stated new guarantee,
recorded evidence, version bump, test result reference.
Silent code changes that contradict contract text = violation regardless of test pass status.

---

## 3. Enforcement Gates

| Gate | Tool | Trigger | Effect |
|---|---|---|---|
| Data validity | `validate_phase1_data.py` | Invalid DB state | exit 1 |
| Signal contract | `validate_phase1_data.py` | `can_block≠0` or `advisory_only≠1` | exit 1 |
| Analysis contract (A) | `codeburn_validate_analysis.py` | boundary structure missing or wrong | exit 1 |
| Analysis contract (B) | `codeburn_validate_analysis.py` | forbidden phrase in rendered output | exit 1 |
| Analysis contract (C) | `codeburn_validate_analysis.py` | retry signal without `derived_from_steps` | exit 1 |
| Combined gate | `validate_phase1_data.py --include-analysis` | any of the above | exit 1 |

**Enforcement is fail-closed.** A violation that does not cause exit 1 is a gate defect, not a policy decision.

---

## 4. Known Limitations

### L1 — Forbidden Phrase Scanner Scope (enforcement boundary)

`codeburn_validate_analysis.py` check (B) scans the full rendered text output,
which includes the user-supplied `task` field.

If a task name contains a forbidden word (e.g., task = "reduce noise in test suite"),
the scanner will trigger a false positive.

**This is a scanner scope limitation, not a semantic limitation.**
The contract guarantee (§2.1) remains correct — no analysis claim of waste/efficiency is made.
The scanner is a lexical tripwire, not a semantic validator.

**Required before expanding semantic validation in Phase 2:**
Exclude user-supplied metadata fields (`task`, `command`, `file_path`) from phrase scan scope.
Until this is resolved, phrase scanner should be read as:
"no forbidden phrase detected in analysis-generated text" (not: "no forbidden phrase anywhere in output").

### L2 — Test Execution Environment

`.pytest_tmp*` and `pytest-cache-files-*` directories accumulate due to Windows permission
constraints. Test logic is correct; execution environment blocks temp path cleanup.
Full pytest parity must be confirmed in a clean runner before Phase 2 promotion.

### L3 — Token Observability

Token usage is `unknown` for all Phase 1 sessions. No token count is captured or reported.
Any token-based analysis in Phase 2 requires a new observability contract and must update
`observability_limits.token_usage` from `"unknown"` to a declared value.

### L4 — File Activity Scope

`file_activity: git-visible only` means non-git changes (e.g., in-memory operations, temp files)
are invisible to the analysis. This is a structural limit of the Phase 1 design, not a defect.

---

## 5. Phase 2 Entry Criteria

Phase 2 may begin only after all of the following are satisfied:

### P1 — Pytest Environment Unblocked (required before promoting readiness)
- `tests/test_codeburn_phase1_run.py` — full pass
- `tests/test_codeburn_phase1_session_recovery.py` — full pass
- `tests/test_codeburn_phase1_report.py` — full pass
- `tests/test_codeburn_phase1_retry_signal.py` — full pass
- `tests/test_codeburn_phase1_analyze.py` — full pass
- `tests/test_codeburn_phase1_analyze_deterministic.py` — full pass
- `tests/test_codeburn_phase1_validate_analysis.py` — full pass

### P2 — Limitation L1 Resolved Before Semantic Expansion
Forbidden phrase scanner (B) must exclude user metadata fields before any expansion
of semantic validation scope. Resolving L1 is a prerequisite for:
- Adding new forbidden phrases
- Expanding phrase scan to new analysis fields
- Claiming "no forbidden phrase in analysis output" (vs. "no forbidden phrase in non-metadata output")

### P3 — Contract Amendment for Any Phase 2 Extension
Any Phase 2 feature that touches analysis output must reference §7 amendment process.
Specifically:
- New signals → add to §3.3 or create Phase 2 Signal Extension document
- Token visibility → amend §5 with new `token_usage` value and observability contract
- New analysis fields → confirm no forbidden phrases in scanner scope before enabling

### P4 — Enforcement Gate Coverage
`validate_phase1_data.py --include-analysis` must be the standard pre-promotion gate.
Phase 2 CI must call this gate and fail on exit 1.

---

## Evidence Anchors

| Milestone | Evidence File |
|---|---|
| M1 | (session lifecycle embedded in M2 evidence) |
| M2 | `CODEBURN_PHASE1_M2_TEST_RESULT_2026-04-30.md` |
| M3.5 + M4 | `CODEBURN_PHASE1_M35_M4_TEST_RESULT_2026-04-30.md` |
| M5 | `CODEBURN_PHASE1_M5_TEST_RESULT_2026-04-30.md` |
| M6 + M6.5 | `CODEBURN_PHASE1_M6_TEST_RESULT_2026-04-30.md` |
| M6.6 | `CODEBURN_PHASE1_M66_TEST_RESULT_2026-04-30.md` |
| M7 | `CODEBURN_PHASE1_M7_TEST_RESULT_2026-04-30.md` |
| Governance contract | `CODEBURN_PHASE1_ANALYSIS_CONTRACT.md` |

---

*Phase 1 is closed. Phase 2 entry requires P1–P4 above.*
