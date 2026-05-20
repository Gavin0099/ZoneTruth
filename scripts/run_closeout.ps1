$ErrorActionPreference = "Stop"

if (!(Test-Path "artifacts/session-closeout.txt")) {
  Write-Host "[closeout] skipped: missing artifacts/session-closeout.txt"
  exit 2
}

# Fail-closed memory guard before session_end hook.
python -m governance_tools.daily_memory_guard --project-root . --format human --enforce
if ($LASTEXITCODE -ne 0) {
  Write-Host "[closeout] blocked: daily memory guard failed"
  exit 1
}

# Fail-closed PLAN freshness guard.
python -m governance_tools.plan_freshness --file PLAN.md --format human
if ($LASTEXITCODE -ne 0) {
  Write-Host "[closeout] blocked: PLAN freshness check failed"
  exit 1
}

python -m governance_tools.session_end_hook --project-root .
if ($LASTEXITCODE -ne 0) {
  Write-Host "[closeout] failed: session_end_hook returned non-zero"
  exit 1
}

Write-Host "[closeout] completed"
