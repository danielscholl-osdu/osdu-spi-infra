# Helm postrender script to apply kustomize patches for a service
# Replaces __SERVICE_NAME__ and __RELEASE_NAMESPACE__ placeholders,
# applies kustomize patches, and strips Namespace resources from output.

param(
    [Parameter(Mandatory)]
    [string]$ServiceName,

    [string]$ReleaseNamespace,

    [string]$NodepoolName,

    [string]$PlatformNamespace
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
        if ($NodepoolName) {
            $content = $content -replace '__NODEPOOL_NAME__', $NodepoolName
        }
        [System.IO.File]::WriteAllText($_.FullName, $content)
    }

    # Run kustomize and filter out Namespace resources
    # Join into single string so cross-line regex replacements work correctly
    $kustomizeOutput = (kubectl kustomize $TempServiceDir) -join "`n"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    # Fix Keycloak cross-namespace references:
    # 1. Rewrite FQDN references from osdu namespace to platform namespace
    # 2. Add internal Keycloak issuer to RequestAuthentication jwtRules
    # 3. Add internal Keycloak issuer to AuthorizationPolicy iss claim checks
    #    so tokens issued via internal FQDN are accepted by Istio
    if ($PlatformNamespace -and $ReleaseNamespace) {
        $internalKeycloak = "keycloak.$PlatformNamespace.svc.cluster.local"
        # Rewrite FQDN references (with or without port) to platform namespace without port
        $kustomizeOutput = $kustomizeOutput -replace "keycloak\.$([regex]::Escape($ReleaseNamespace))\.svc\.cluster\.local(:\d+)?", $internalKeycloak

        # Add internal issuer to RequestAuthentication: inject an additional
        # jwtRule that accepts tokens with the internal Keycloak issuer URL
        $internalIssuer = "http://$internalKeycloak/realms/osdu"
        $internalJwksUri = "http://$internalKeycloak/realms/osdu/protocol/openid-connect/certs"
        $internalRule = @"
  - forwardOriginalToken: true
    issuer: $internalIssuer
    jwksUri: $internalJwksUri
"@
        # Append after the last jwtRule in any RequestAuthentication (with or without port)
        $kustomizeOutput = $kustomizeOutput -replace '(issuer: http://keycloak(:\d+)?/realms/osdu\s+jwksUri: [^\n]+)', "`$1`n$internalRule"

        # Add internal issuer to AuthorizationPolicy iss claim value lists
        $kustomizeOutput = $kustomizeOutput -replace '(- http://keycloak(:\d+)?/realms/osdu)', "`$1`n      - $internalIssuer"
    }

    # Split on YAML document separators and filter out Namespace resources
    $documents = $kustomizeOutput -split '(?m)^---$'
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
