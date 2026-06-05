param(
    [Parameter(Mandatory = $true)]
    [string]$Repo,
    [string]$ProjectRoot = ".",
    [string]$SubmodulePath = "ai-governance-framework",
    [string]$TargetRef = "origin/main",
    [string]$FetchRemote = "origin",
    [string]$FetchRef = "main",
    [switch]$Apply,
    [switch]$Stage,
    [switch]$Commit,
    [switch]$AllowDetachedTargetCheckout,
    [string]$CommitMessage = "chore(governance): update ai governance submodule",
    [ValidateSet("human", "json")]
    [string]$Format = "human"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$previousPythonPath = $env:PYTHONPATH
if ([string]::IsNullOrWhiteSpace($previousPythonPath)) {
    $env:PYTHONPATH = $resolvedProjectRoot
} else {
    $env:PYTHONPATH = "$resolvedProjectRoot;$previousPythonPath"
}

try {
    $args = @(
        "-m", "governance_tools.external_governance_submodule_updater",
        "--repo", $Repo,
        "--submodule-path", $SubmodulePath,
        "--target-ref", $TargetRef,
        "--fetch-remote", $FetchRemote,
        "--fetch-ref", $FetchRef,
        "--format", $Format
    )

    if ($Apply) {
        $args += "--apply"
    }
    if ($Stage) {
        $args += "--stage"
    }
    if ($Commit) {
        $args += "--commit"
        $args += @("--commit-message", $CommitMessage)
    }
    if ($AllowDetachedTargetCheckout) {
        $args += "--allow-detached-target-checkout"
    }

    python @args
    exit $LASTEXITCODE
} finally {
    $env:PYTHONPATH = $previousPythonPath
}
