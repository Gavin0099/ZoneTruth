param(
  [string]$CfuRoot = "E:\BackUp\Git_EE\CFU",
  [string]$FrameworkRoot = "E:\BackUp\Git_EE\ai-governance-framework",
  [string]$WideStartDay = "2026-04-30",
  [string]$WideEndDay = "2026-05-04",
  [string]$SingleDay = "2026-05-04"
)

$ErrorActionPreference = "Stop"

$DbPath = Join-Path $CfuRoot "codeburn_phase1.db"
$SummaryCli = Join-Path $FrameworkRoot "Script\codeburn_phase1_7day_summary.py"
$env:PYTHONPATH = $FrameworkRoot

Write-Host "== DB latest sessions (UTC created_at) =="
python -c "import sqlite3; c=sqlite3.connect(r'$DbPath'); print(c.execute('select session_id, created_at from sessions order by created_at desc limit 5').fetchall())"

Write-Host "== Wide window summary =="
python $SummaryCli --db $DbPath --start-day $WideStartDay --end-day $WideEndDay --runtime-validation-status degraded --runtime-validation-blocker permission_denied_tmp_cache --format json

Write-Host "== Single-day summary =="
python $SummaryCli --db $DbPath --start-day $SingleDay --end-day $SingleDay --runtime-validation-status degraded --runtime-validation-blocker permission_denied_tmp_cache --format json
