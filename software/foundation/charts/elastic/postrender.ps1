# Helm postrender script for ECK operator
# Applies kustomize patches to inject health probes for AKS Automatic safeguards compliance

$ErrorActionPreference = 'Stop'

# Verify kubectl is available
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Error "kubectl is required but not found in PATH"
    exit 1
}

# Resolve paths relative to this script
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$KustomizeDir = Join-Path $ScriptDir 'kustomize'

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
    # Write Helm output as all.yaml
    [System.IO.File]::WriteAllText((Join-Path $TempDir 'all.yaml'), $HelmOutput)

    # Create kustomization.yaml that patches the elastic-operator StatefulSet
    $Kustomization = @"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - all.yaml

patches:
  - path: statefulset-probes.yaml
    target:
      kind: StatefulSet
      name: elastic-operator
"@
    [System.IO.File]::WriteAllText((Join-Path $TempDir 'kustomization.yaml'), $Kustomization)

    # Copy the patch file
    Copy-Item -Path (Join-Path $KustomizeDir 'statefulset-probes.yaml') -Destination $TempDir

    # Apply kustomize patches and output to stdout
    kubectl kustomize $TempDir
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
    Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
}
