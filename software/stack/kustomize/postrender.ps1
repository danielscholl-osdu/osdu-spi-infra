# Helm postrender script to apply kustomize patches for a service
# Replaces __SERVICE_NAME__ and __RELEASE_NAMESPACE__ placeholders,
# applies kustomize patches, and strips Namespace resources from output.

param(
    [Parameter(Mandatory)]
    [string]$ServiceName,

    [string]$ReleaseNamespace
)

$ErrorActionPreference = 'Stop'

# Verify kubectl is available
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Error "kubectl is required but not found in PATH"
    exit 1
}

# Resolve paths relative to this script
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$KustomizeRoot = $ScriptDir
$ServiceDir = Join-Path $KustomizeRoot "services/$ServiceName"

if (-not (Test-Path $ServiceDir)) {
    Write-Error "kustomize service directory '$ServiceDir' does not exist."
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
    # Create directory structure in temp
    $TempComponents = Join-Path $TempDir 'components'
    $TempServiceDir = Join-Path $TempDir "services/$ServiceName"
    New-Item -ItemType Directory -Path $TempComponents -Force | Out-Null
    New-Item -ItemType Directory -Path $TempServiceDir -Force | Out-Null

    # Copy components and service-specific kustomize files
    $ComponentsSource = Join-Path $KustomizeRoot 'components'
    if (Test-Path $ComponentsSource) {
        Copy-Item -Path "$ComponentsSource/*" -Destination $TempComponents -Recurse -Force
    }
    Copy-Item -Path "$ServiceDir/*" -Destination $TempServiceDir -Recurse -Force

    # Write Helm output as all.yaml
    [System.IO.File]::WriteAllText((Join-Path $TempServiceDir 'all.yaml'), $HelmOutput)

    # Perform template substitution on all YAML files
    Get-ChildItem -Path $TempDir -Recurse -Filter '*.yaml' | ForEach-Object {
        $content = [System.IO.File]::ReadAllText($_.FullName)
        $content = $content -replace '__SERVICE_NAME__', $ServiceName
        if ($ReleaseNamespace) {
            $content = $content -replace '__RELEASE_NAMESPACE__', $ReleaseNamespace
        }
        [System.IO.File]::WriteAllText($_.FullName, $content)
    }

    # Run kustomize and filter out Namespace resources
    $kustomizeOutput = kubectl kustomize $TempServiceDir
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    # Split on YAML document separators and filter out Namespace resources
    $documents = ($kustomizeOutput -join "`n") -split '(?m)^---$'
    foreach ($doc in $documents) {
        if ([string]::IsNullOrWhiteSpace($doc)) { continue }
        if ($doc -match '(?m)^kind:\s*Namespace\s*$') { continue }
        Write-Output '---'
        Write-Output $doc.TrimEnd()
    }
}
finally {
    Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
}
