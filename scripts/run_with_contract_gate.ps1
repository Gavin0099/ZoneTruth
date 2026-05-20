param(
  [Parameter(Mandatory = $true)]
  [string]$RunCommand,

  [Parameter(Mandatory = $true)]
  [string]$ResponseFile,

  [string]$PythonExe = "",
  [switch]$SkipRunCommand
)

$ErrorActionPreference = "Stop"

function Fail($msg) {
  Write-Error $msg
  exit 1
}

function Resolve-Python {
  if (-not [string]::IsNullOrWhiteSpace($PythonExe)) {
    return $PythonExe
  }

  if ($env:AI_GOVERNANCE_PYTHON) {
    return $env:AI_GOVERNANCE_PYTHON
  }

  $candidates = @("python", "python3", "py -3")
  foreach ($c in $candidates) {
    try {
      Invoke-Expression "$c --version" | Out-Null
      if ($LASTEXITCODE -eq 0) {
        return $c
      }
    } catch {
      continue
    }
  }

  Fail "python executable not found. Set --PythonExe or AI_GOVERNANCE_PYTHON."
}

$python = Resolve-Python

if (-not $SkipRunCommand) {
  Invoke-Expression $RunCommand
  $runExit = $LASTEXITCODE
  if ($null -eq $runExit) {
    $runExit = 0
  }
  if ($runExit -ne 0) {
    Fail "run command failed with exit code $runExit"
  }
}

if (-not (Test-Path $ResponseFile)) {
  Fail "response file not found: $ResponseFile"
}

$validatorCmd = "$python governance_tools/contract_validator.py --file `"$ResponseFile`" --format json"
$raw = Invoke-Expression $validatorCmd
$validatorExit = $LASTEXITCODE

if ($validatorExit -ne 0) {
  Fail "governance contract validation failed for $ResponseFile"
}

try {
  $result = $raw | ConvertFrom-Json
} catch {
  Fail "failed to parse validator json output"
}

if (-not $result.contract_found) {
  Fail "missing [Governance Contract] block in response"
}

if (-not $result.compliant) {
  $errorList = @()
  if ($result.errors) {
    $errorList = @($result.errors)
  }
  $joined = ($errorList -join "; ")
  Fail "non-compliant Governance Contract: $joined"
}

Write-Host "[contract-gate] pass: $ResponseFile"
exit 0
