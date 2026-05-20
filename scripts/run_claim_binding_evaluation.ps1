param(
  [Parameter(Mandatory = $true)]
  [string]$ProjectRoot,

  [Parameter(Mandatory = $true)]
  [string]$BaselineBefore,

  [string]$Since = "",
  [string]$OutputDir = "artifacts/claim-binding-eval",
  [double]$OverrideRateMax = 0.2
)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$frameworkRoot = Split-Path -Parent $scriptRoot
$completenessTool = Join-Path $frameworkRoot 'governance_tools/runtime_completeness_audit.py'
$closeoutTool = Join-Path $frameworkRoot 'governance_tools/closeout_audit.py'

$outRoot = Join-Path $ProjectRoot $OutputDir
New-Item -ItemType Directory -Path $outRoot -Force | Out-Null

$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd_HHmmss')
$jsonOut = Join-Path $outRoot ("claim-binding-eval-$stamp.json")
$mdOut = Join-Path $outRoot ("claim-binding-eval-$stamp.md")

$compArgs = @(
  $completenessTool,
  '--project-root', $ProjectRoot,
  '--baseline-before', $BaselineBefore,
  '--only-new-sessions',
  '--format', 'json'
)
if ($Since) {
  $compArgs += @('--since', $Since)
}
$compRaw = & python @compArgs
$completeness = $compRaw | ConvertFrom-Json

$closeoutRaw = & python $closeoutTool --project-root $ProjectRoot --require-claim-binding --format json
$closeout = $closeoutRaw | ConvertFrom-Json

$blockers = New-Object System.Collections.Generic.List[string]

$windowIntegrityPass = ($completeness.new_window_integrity_ok -eq $true -and [int]$completeness.new_window_silent_drop_count -eq 0)
if (-not $windowIntegrityPass) {
  $blockers.Add('window_integrity_failed')
}

$pipelineExistencePass = ([int]$closeout.claim_enforcement_check_count -gt 0)
if (-not $pipelineExistencePass) {
  $blockers.Add('claim_enforcement_check_count_zero')
}

$driftRate = $closeout.drift_rate
$downgradeRate = $closeout.downgrade_rate
$blockedRate = $closeout.blocked_rate
$overrideRate = $closeout.override_rate
$invalidOverrideRate = $closeout.invalid_override_rate

$decisionActivationPass = $false
if ($null -ne $driftRate -and $null -ne $downgradeRate -and $null -ne $blockedRate) {
  $decisionActivationPass = (($driftRate -gt 0) -and (($downgradeRate -gt 0) -or ($blockedRate -gt 0)))
}
if (-not $decisionActivationPass) {
  $blockers.Add('decision_activation_not_observed')
}

$overrideDisciplinePass = $false
if ($null -ne $overrideRate -and $null -ne $invalidOverrideRate) {
  $overrideDisciplinePass = (($overrideRate -lt $OverrideRateMax) -and ($invalidOverrideRate -eq 0))
}
if (-not $overrideDisciplinePass) {
  $blockers.Add('override_discipline_not_met')
}

$finalVerdict = if ($blockers.Count -eq 0) { 'default_on_ready' } else { 'not_ready' }

$result = [ordered]@{
  generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
  project_root = $ProjectRoot
  baseline_before = $BaselineBefore
  since = if ($Since) { $Since } else { $null }
  trust_boundary_note = 'historical data: pre-claim-binding (non-comparable)'
  window_integrity = [ordered]@{
    pass = $windowIntegrityPass
    new_window_integrity_ok = $completeness.new_window_integrity_ok
    new_window_silent_drop_count = $completeness.new_window_silent_drop_count
    historical_silent_drop_count = $completeness.historical_silent_drop_count
  }
  pipeline_existence = [ordered]@{
    pass = $pipelineExistencePass
    claim_enforcement_check_count = $closeout.claim_enforcement_check_count
  }
  decision_activation = [ordered]@{
    pass = $decisionActivationPass
    drift_rate = $driftRate
    downgrade_rate = $downgradeRate
    blocked_rate = $blockedRate
  }
  override_discipline = [ordered]@{
    pass = $overrideDisciplinePass
    override_rate = $overrideRate
    invalid_override_rate = $invalidOverrideRate
    override_rate_max = $OverrideRateMax
  }
  source_metrics = [ordered]@{
    closeout_claim_binding_valid = $closeout.closeout_claim_binding_valid
    claim_binding_required_violation = $closeout.claim_binding_required_violation
    require_claim_binding = $closeout.require_claim_binding
  }
  final_verdict = $finalVerdict
  blocker_reasons = @($blockers)
}

($result | ConvertTo-Json -Depth 8) + "`n" | Set-Content $jsonOut

$md = @(
  "# Claim Binding Evaluation",
  "",
  "- generated_at_utc: ``$($result.generated_at_utc)``",
  "- project_root: ``$($result.project_root)``",
  "- baseline_before: ``$($result.baseline_before)``",
  "- trust_boundary_note: $($result.trust_boundary_note)",
  "",
  "## Window Integrity",
  "- pass: ``$($result.window_integrity.pass)``",
  "- new_window_integrity_ok: ``$($result.window_integrity.new_window_integrity_ok)``",
  "- new_window_silent_drop_count: ``$($result.window_integrity.new_window_silent_drop_count)``",
  "- historical_silent_drop_count: ``$($result.window_integrity.historical_silent_drop_count)``",
  "",
  "## Pipeline Existence",
  "- pass: ``$($result.pipeline_existence.pass)``",
  "- claim_enforcement_check_count: ``$($result.pipeline_existence.claim_enforcement_check_count)``",
  "",
  "## Decision Activation",
  "- pass: ``$($result.decision_activation.pass)``",
  "- drift_rate: ``$($result.decision_activation.drift_rate)``",
  "- downgrade_rate: ``$($result.decision_activation.downgrade_rate)``",
  "- blocked_rate: ``$($result.decision_activation.blocked_rate)``",
  "",
  "## Override Discipline",
  "- pass: ``$($result.override_discipline.pass)``",
  "- override_rate: ``$($result.override_discipline.override_rate)``",
  "- invalid_override_rate: ``$($result.override_discipline.invalid_override_rate)``",
  "- override_rate_max: ``$($result.override_discipline.override_rate_max)``",
  "",
  "## Final Verdict",
  "- final_verdict: ``$($result.final_verdict)``",
  "- blocker_reasons: ``$(([string]::Join(', ', $result.blocker_reasons)))``"
)
$md -join "`n" | Set-Content $mdOut

Write-Output "written_json=$jsonOut"
Write-Output "written_markdown=$mdOut"
Write-Output "final_verdict=$finalVerdict"
