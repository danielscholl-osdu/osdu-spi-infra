# Helm postrender script to apply kustomize patches
# Reads Helm output from stdin, applies kustomize patches, outputs to stdout

$ErrorActionPreference = 'Stop'

# Verify kubectl is available
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Error "kubectl is required but not found in PATH"
    exit 1
}

# Resolve paths relative to this script
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$KustomizeDir = Join-Path $ScriptDir 'kustomize'

if (-not (Test-Path $KustomizeDir)) {
    Write-Error "kustomize directory '$KustomizeDir' does not exist."
    exit 1
}

# Read Helm output from process stdin (not PowerShell pipeline)
$HelmOutput = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($HelmOutput)) {
    Write-Error "No Helm output received on stdin"
    exit 1
}

# Create temporary working directory
$TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $TempDir | Out-Null

try {
    # Copy kustomize directory to temp (avoids concurrent access conflicts)
    Copy-Item -Path "$KustomizeDir/*" -Destination $TempDir -Recurse -Force

    # Write Helm output as all.yaml
    [System.IO.File]::WriteAllText((Join-Path $TempDir 'all.yaml'), $HelmOutput)

    # Apply kustomize patches and output to stdout
    kubectl kustomize $TempDir
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
    Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
}
