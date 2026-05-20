param(
  [Parameter(Mandatory = $true)]
  [string]$RunCommand,

  [Parameter(Mandatory = $true)]
  [string]$AgentLane,

  [Parameter(Mandatory = $true)]
  [string]$Provider,

  [Parameter(Mandatory = $true)]
  [string]$TokenSource,

  [Parameter(Mandatory = $true)]
  [bool]$ProvenanceComplete,

  [Parameter(Mandatory = $true)]
  [bool]$Comparable,

  [string]$RunId = "",
  [string]$Notes = "",
  [string]$ResponseFile = ""
)

$ErrorActionPreference = "Stop"

$startedAt = Get-Date
$exitCode = 0
$contractGateStatus = "skipped"

try {
  Invoke-Expression $RunCommand
  $exitCode = $LASTEXITCODE
  if ($null -eq $exitCode) {
    $exitCode = 0
  }
} catch {
  $exitCode = 1
  Write-Error $_
}

# Auto contract gate when response file is provided.
if (-not [string]::IsNullOrWhiteSpace($ResponseFile)) {
  try {
    & powershell -ExecutionPolicy Bypass -File "scripts/run_with_contract_gate.ps1" `
      -RunCommand "Write-Output noop" `
      -ResponseFile $ResponseFile `
      -SkipRunCommand

    if ($LASTEXITCODE -eq 0) {
      $contractGateStatus = "pass"
    } else {
      $contractGateStatus = "fail"
      $exitCode = 1
    }
  } catch {
    $contractGateStatus = "fail"
    $exitCode = 1
    Write-Error $_
  }
}

$endedAt = Get-Date
$durationMs = [int](($endedAt - $startedAt).TotalMilliseconds)

if ([string]::IsNullOrWhiteSpace($RunId)) {
  $RunId = "run-" + (Get-Date -Format "yyyyMMddTHHmmss")
}

$captureNotes = $Notes
if (-not [string]::IsNullOrWhiteSpace($captureNotes)) {
  $captureNotes = $captureNotes + "; "
}
$captureNotes = $captureNotes + "wrapped_run_exit_code=" + $exitCode + "; duration_ms=" + $durationMs + "; contract_gate=" + $contractGateStatus

python scripts/run_end_observability_capture.py `
  --run-id $RunId `
  --run-ended-at ($endedAt.ToString("o")) `
  --agent-lane $AgentLane `
  --provider $Provider `
  --token-source $TokenSource `
  --provenance-complete $ProvenanceComplete `
  --comparable $Comparable `
  --notes $captureNotes

exit $exitCode
