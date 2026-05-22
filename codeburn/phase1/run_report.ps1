[CmdletBinding(PositionalBinding = $false)]
param(
  [Parameter(Mandatory = $true)]
  [string]$DatabasePath,

  [ValidateSet('text', 'json')]
  [string]$Format = 'text',

  [string]$SessionId = '',
  [string]$PythonExe = ''
)

$ErrorActionPreference = 'Stop'

$phase1Dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$reportScript = Join-Path $phase1Dir 'codeburn_report.py'

function Resolve-PythonCommand {
  param([string]$RequestedPythonExe)

  if ($RequestedPythonExe) {
    return @($RequestedPythonExe)
  }

  $python = Get-Command python -ErrorAction SilentlyContinue
  if ($python) {
    return @($python.Source)
  }

  $py = Get-Command py -ErrorAction SilentlyContinue
  if ($py) {
    return @($py.Source, '-3')
  }

  throw 'No Python interpreter found. Install Python or pass -PythonExe <path>.'
}

$pythonCommand = @(Resolve-PythonCommand -RequestedPythonExe $PythonExe)
$argsList = @($reportScript, '--db', $DatabasePath, '--format', $Format)
if ($SessionId) {
  $argsList += @('--session-id', $SessionId)
}

$oldPythonPathPresent = Test-Path Env:PYTHONPATH
$oldPythonPath = $null
if ($oldPythonPathPresent) {
  $oldPythonPath = $env:PYTHONPATH
}

try {
  Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue
  $pythonExeResolved = $pythonCommand[0]
  $pythonPreArgs = @()
  if ($pythonCommand.Count -gt 1) {
    $pythonPreArgs = $pythonCommand[1..($pythonCommand.Count - 1)]
  }
  & $pythonExeResolved @pythonPreArgs @argsList
  exit $LASTEXITCODE
}
finally {
  if ($oldPythonPathPresent) {
    $env:PYTHONPATH = $oldPythonPath
  }
  else {
    Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue
  }
}