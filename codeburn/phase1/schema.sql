-- CodeBurn v2 Phase 1 schema
-- Observability-first, advisory-only telemetry model.

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS sessions (
  session_id TEXT PRIMARY KEY,
  task TEXT NOT NULL,
  repo_path TEXT,
  git_branch TEXT,
  created_at TEXT NOT NULL,
  ended_at TEXT,
  ended_by TEXT DEFAULT 'manual',
  data_quality TEXT NOT NULL CHECK (data_quality IN ('complete', 'partial', 'recovered', 'invalid')),
  provider_summary TEXT,
  comparability_token INTEGER NOT NULL DEFAULT 0 CHECK (comparability_token IN (0, 1)),
  comparability_duration INTEGER NOT NULL DEFAULT 1 CHECK (comparability_duration IN (0, 1)),
  comparability_change INTEGER NOT NULL DEFAULT 1 CHECK (comparability_change IN (0, 1))
);

CREATE TABLE IF NOT EXISTS steps (
  step_id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  step_kind TEXT NOT NULL CHECK (step_kind IN ('planning', 'execution', 'test', 'retry', 'reflection', 'other')),
  command TEXT NOT NULL,
  provider TEXT,
  started_at TEXT NOT NULL,
  ended_at TEXT,
  duration_ms INTEGER,
  exit_code INTEGER,
  stdout_bytes INTEGER,
  stderr_bytes INTEGER,
  prompt_tokens INTEGER,       -- input_tokens only (non-cached). IAF-4 compliant.
  completion_tokens INTEGER,
  total_tokens INTEGER,        -- always NULL by policy
  -- Rate-limit-relevant token count: input + cache_creation + cache_read.
  -- For rate limit estimation ONLY. NOT for billing or cost computation (IAF-4).
  -- Claude Code uses aggressive prompt caching; cache tokens dominate actual rate limit consumption.
  rate_limit_tokens INTEGER,
  token_source TEXT CHECK (token_source IN ('provider', 'estimated', 'unknown')),
  retry_of TEXT,
  git_status_before TEXT,
  git_status_after TEXT,
  FOREIGN KEY(session_id) REFERENCES sessions(session_id),
  FOREIGN KEY(retry_of) REFERENCES steps(step_id)
);

CREATE TABLE IF NOT EXISTS changed_files (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  step_id TEXT NOT NULL,
  file_path TEXT NOT NULL,
  change_kind TEXT,
  source TEXT NOT NULL DEFAULT 'git_diff_name_only',
  FOREIGN KEY(step_id) REFERENCES steps(step_id)
);

CREATE TABLE IF NOT EXISTS signals (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT NOT NULL,
  step_id TEXT,
  signal TEXT NOT NULL,
  type TEXT NOT NULL,
  advisory_only INTEGER NOT NULL CHECK (advisory_only IN (0, 1)),
  can_block INTEGER NOT NULL CHECK (can_block IN (0, 1)),
  confidence TEXT NOT NULL,
  source TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY(session_id) REFERENCES sessions(session_id),
  FOREIGN KEY(step_id) REFERENCES steps(step_id)
);

CREATE TABLE IF NOT EXISTS recovery_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  previous_session_id TEXT NOT NULL,
  new_session_id TEXT,
  action_taken TEXT NOT NULL CHECK (action_taken IN ('auto_close_previous', 'resume_previous', 'abort_start')),
  reason TEXT NOT NULL,
  operator TEXT,
  created_at TEXT NOT NULL
);

-- P3.1: L1.5 acquisition provenance — Class C (observer-reconstructed) records only.
-- Hard constraints: real_time_observed=0, analysis_safe_for_decision=0,
-- provider_truthfulness_assumed=0.  No row may assert runtime or decision authority.
CREATE TABLE IF NOT EXISTS step_ingestion_provenance (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  step_id TEXT NOT NULL,
  provider TEXT NOT NULL,
  epistemic_class TEXT NOT NULL CHECK (epistemic_class IN ('Class A', 'Class B', 'Class C', 'Class D', 'Class E')),
  acquisition_mode TEXT NOT NULL,
  source_artifact_path TEXT NOT NULL,
  source_record_line INTEGER NOT NULL CHECK (source_record_line >= 1),
  source_record_offset INTEGER,
  real_time_observed INTEGER NOT NULL DEFAULT 0 CHECK (real_time_observed = 0),
  analysis_safe_for_decision INTEGER NOT NULL DEFAULT 0 CHECK (analysis_safe_for_decision = 0),
  provider_truthfulness_assumed INTEGER NOT NULL DEFAULT 0 CHECK (provider_truthfulness_assumed = 0),
  created_at TEXT NOT NULL,
  FOREIGN KEY(step_id) REFERENCES steps(step_id)
);

-- ============================================================
-- Class D: Copilot AI Credits (billing-reported evidence)
-- Admission gate: CODEBURN_COPILOT_AI_CREDITS_ADMISSION_GATE.md
-- MUST NOT be joined with steps or step_ingestion_provenance.
-- MUST NOT be aggregated together with Class C evidence.
-- ============================================================

CREATE TABLE IF NOT EXISTS copilot_billing_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,

  -- Billing aggregate identity (natural key: report_date + user_login + model + source_artifact_path)
  report_date TEXT NOT NULL,           -- YYYY-MM-DD (billing day, not session day)
  user_login  TEXT NOT NULL,           -- GitHub username
  model       TEXT NOT NULL,           -- model name as reported by GitHub CSV

  -- Billing credit quantity.
  -- NOT a token count. Back-calculation to tokens is FORBIDDEN (CP-1, IAF-4).
  -- No pricing rate may be applied to this value.
  -- Cross-model comparison of aic_quantity is FORBIDDEN (CP-2).
  -- model column MUST appear in any query that reads aic_quantity.
  aic_quantity REAL NOT NULL,

  -- aic_gross_amount is EXCLUDED. Cost ingestion is FORBIDDEN (C-1 + IAF-4).

  -- Structural annotation: code completions never appear in this surface.
  -- Enforced by CHECK -- cannot be set to 0.
  completions_excluded INTEGER NOT NULL DEFAULT 1 CHECK (completions_excluded = 1),

  -- Preview vs. final billing (AG-Copilot-3).
  -- Default 1 (conservative). Use --mark-final to set 0 after GitHub confirms.
  is_preview INTEGER NOT NULL DEFAULT 1 CHECK (is_preview IN (0, 1)),

  -- Class D provenance (embedded, not in step_ingestion_provenance).
  epistemic_class     TEXT NOT NULL DEFAULT 'Class D' CHECK (epistemic_class = 'Class D'),
  acquisition_mode    TEXT NOT NULL DEFAULT 'billing_report_daily_aggregate'
                           CHECK (acquisition_mode = 'billing_report_daily_aggregate'),
  source_artifact_path TEXT NOT NULL,  -- path to the CSV file
  source_record_line   INTEGER NOT NULL CHECK (source_record_line >= 1),
  -- source_record_offset is NULL: CSV rows have no byte-level identity (AG-Copilot-2)

  -- Epistemic flags (all permanently 0 for Class D).
  real_time_observed          INTEGER NOT NULL DEFAULT 0 CHECK (real_time_observed = 0),
  analysis_safe_for_decision  INTEGER NOT NULL DEFAULT 0 CHECK (analysis_safe_for_decision = 0),
  provider_truthfulness_assumed INTEGER NOT NULL DEFAULT 0 CHECK (provider_truthfulness_assumed = 0),

  created_at TEXT NOT NULL,

  UNIQUE (report_date, user_login, model, source_artifact_path)
);

-- Metadata per CSV file ingested (surface annotations, correction events).
CREATE TABLE IF NOT EXISTS copilot_surface_annotations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source_artifact_path TEXT NOT NULL,
  annotation_key   TEXT NOT NULL,   -- e.g. 'completions_surface_present', 'correction_event'
  annotation_value TEXT NOT NULL,
  created_at TEXT NOT NULL
);

-- P3.1: Quarantine table for records that cannot be ingested.
-- Malformed or structurally inadmissible records are persisted here rather than
-- silently dropped, preserving auditability of ingestion completeness.
CREATE TABLE IF NOT EXISTS quarantined_records (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  provider TEXT NOT NULL,
  source_artifact_path TEXT NOT NULL,
  source_record_line INTEGER NOT NULL CHECK (source_record_line >= 1),
  source_record_offset INTEGER,
  reason TEXT NOT NULL,
  raw_record TEXT,
  created_at TEXT NOT NULL
);
