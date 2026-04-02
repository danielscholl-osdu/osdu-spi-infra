#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Resolves OSDU Helm chart versions from the OCI registry and writes osdu-versions.auto.tfvars.

.DESCRIPTION
  Queries the OSDU OCI registry for each service chart and writes resolved versions
  to software/cimpl-stack/osdu-versions.auto.tfvars for Terraform consumption.
  This script is CIMPL-specific — the SPI stack uses a local Helm chart and does
  not need OCI chart version resolution.

  Version modes:
    - Default (no env var)           : Uses "0.0.7-latest" tag (latest main branch CI build)
    - OSDU_CHART_VERSION=0.29.0      : Pins all services to that exact release version
    - OSDU_SERVICE_VERSIONS override  : Per-service version pins (comma-separated key=value)

  Environment variables:
    OSDU_CHART_VERSION          - Default chart version for all services (default: 0.0.7-latest)
    OSDU_SERVICE_VERSIONS       - Per-service overrides, e.g. "partition=0.29.0,entitlements=0.29.2"
    OSDU_SKIP_VERSION_RESOLVE   - Set to "true" to skip resolution entirely

.EXAMPLE
  # Use latest CI builds (default)
  ./scripts/resolve-chart-versions.ps1

  # Pin to a release
  $env:OSDU_CHART_VERSION = "0.29.0"
  ./scripts/resolve-chart-versions.ps1

  # Per-service overrides
  $env:OSDU_SERVICE_VERSIONS = "entitlements=0.29.2,partition=0.29.0"
  ./scripts/resolve-chart-versions.ps1
#>

param(
    [string]$OutputDir = "$PSScriptRoot/../software/cimpl-stack"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Skip gate ---

if ($env:OSDU_SKIP_VERSION_RESOLVE -eq "true") {
    Write-Host "  Skipping OSDU chart version resolution (OSDU_SKIP_VERSION_RESOLVE=true)" -ForegroundColor Yellow
    return
}

# --- Chart registry ---
# Complete OSDU service registry: service_name -> { repository, chart }

$ChartRegistry = [ordered]@{
    # Core platform services
    partition       = @{ repo = "oci://community.opengroup.org:5555/osdu/platform/system/partition/cimpl-helm";                                             chart = "core-plus-partition-deploy" }
    entitlements    = @{ repo = "oci://community.opengroup.org:5555/osdu/platform/security-and-compliance/entitlements/cimpl-helm";                          chart = "core-plus-entitlements-deploy" }
    legal           = @{ repo = "oci://community.opengroup.org:5555/osdu/platform/security-and-compliance/legal/cimpl-helm";                                chart = "core-plus-legal-deploy" }
    schema          = @{ repo = "oci://community.opengroup.org:5555/osdu/platform/system/schema-service/cimpl-helm";                                        chart = "core-plus-schema-deploy" }
    storage         = @{ repo = "oci://community.opengroup.org:5555/osdu/platform/system/storage/cimpl-helm";                                               chart = "core-plus-storage-deploy" }
    file            = @{ repo = "oci://community.opengroup.org:5555/osdu/platform/system/file/cimpl-helm";                                                  chart = "core-plus-file-deploy" }
    dataset         = @{ repo = "oci://community.opengroup.org:5555/osdu/platform/system/dataset/cimpl-helm";                                               chart = "core-plus-dataset-deploy" }
    register        = @{ repo = "oci://community.opengroup.org:5555/osdu/platform/system/register/cimpl-helm";                                              chart = "core-plus-register-deploy" }
    notification    = @{ repo = "oci://community.opengroup.org:5555/osdu/platform/system/notification/cimpl-helm";                                          chart = "core-plus-notification-deploy" }
    indexer         = @{ repo = "oci://community.opengroup.org:5555/osdu/platform/system/indexer-service/cimpl-helm";                                       chart = "core-plus-indexer-deploy" }
    search          = @{ repo = "oci://community.opengroup.org:5555/osdu/platform/system/search-service/cimpl-helm";                                        chart = "core-plus-search-deploy" }
    workflow        = @{ repo = "oci://community.opengroup.org:5555/osdu/platform/data-flow/ingestion/ingestion-workflow/cimpl-helm";                        chart = "core-plus-workflow-deploy" }

    # Security & compliance
    secret          = @{ repo = "oci://community.opengroup.org:5555/osdu/platform/security-and-compliance/secret/cimpl-helm";                               chart = "core-plus-secret-deploy" }
    policy          = @{ repo = "oci://community.opengroup.org:5555/osdu/platform/security-and-compliance/policy/cimpl-helm";                               chart = "core-plus-policy-deploy" }

    # Reference data services
    unit            = @{ repo = "oci://community.opengroup.org:5555/osdu/platform/system/reference/unit-service/cimpl-helm";                                chart = "core-plus-unit-deploy" }
    crs_conversion  = @{ repo = "oci://community.opengroup.org:5555/osdu/platform/system/reference/crs-conversion-service/cimpl-helm";                      chart = "core-plus-crs-conversion-deploy" }
    crs_catalog     = @{ repo = "oci://community.opengroup.org:5555/osdu/platform/system/reference/crs-catalog-service/cimpl-helm";                         chart = "core-plus-crs-catalog-deploy" }

    # Domain services
    wellbore        = @{ repo = "oci://community.opengroup.org:5555/osdu/platform/domain-data-mgmt-services/wellbore/wellbore-domain-services/cimpl-helm";   chart = "core-plus-wellbore-deploy" }
    wellbore_worker = @{ repo = "oci://community.opengroup.org:5555/osdu/platform/domain-data-mgmt-services/wellbore/wellbore-domain-services-worker/cimpl-helm"; chart = "core-plus-wellbore-worker-deploy" }
    eds_dms         = @{ repo = "oci://community.opengroup.org:5555/osdu/platform/data-flow/ingestion/external-data-sources/eds-dms/cimpl-helm";            chart = "core-plus-eds-dms-deploy" }
    oetp_server     = @{ repo = "oci://community.opengroup.org:5555/osdu/platform/domain-data-mgmt-services/reservoir/open-etp-server/cimpl-helm";          chart = "core-plus-oetp-server-deploy" }
}

# --- Parse inputs ---

$DefaultVersion = if ($env:OSDU_CHART_VERSION) { $env:OSDU_CHART_VERSION } else { "0.0.7-latest" }

# Parse per-service overrides: "partition=0.29.0,entitlements=0.29.2"
$ServiceOverrides = @{}
if ($env:OSDU_SERVICE_VERSIONS) {
    foreach ($pair in $env:OSDU_SERVICE_VERSIONS -split ",") {
        $parts = $pair.Trim() -split "=", 2
        if ($parts.Count -eq 2) {
            $ServiceOverrides[$parts[0].Trim()] = $parts[1].Trim()
        }
    }
}

# --- Resolve versions ---

Write-Host ""
Write-Host "  Resolving OSDU chart versions..." -ForegroundColor Cyan
Write-Host "    Default version: $DefaultVersion"
if ($ServiceOverrides.Count -gt 0) {
    Write-Host "    Service overrides: $($ServiceOverrides | ConvertTo-Json -Compress)"
}
Write-Host ""

$ResolvedVersions = [ordered]@{}
$Errors = @()

foreach ($svc in $ChartRegistry.Keys) {
    $entry = $ChartRegistry[$svc]
    $targetVersion = if ($ServiceOverrides.ContainsKey($svc)) { $ServiceOverrides[$svc] } else { $DefaultVersion }

    $chartRef = "$($entry.repo)/$($entry.chart)"

    try {
        $output = helm show chart $chartRef --version $targetVersion 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    WARN: $svc - version $targetVersion not found, skipping" -ForegroundColor Yellow
            $Errors += $svc
            continue
        }

        # Extract version and appVersion from helm output
        $version = ($output | Select-String "^version:\s*(.+)$").Matches[0].Groups[1].Value.Trim()
        $appVersion = ($output | Select-String "^appVersion:\s*(.+)$").Matches[0].Groups[1].Value.Trim()

        $ResolvedVersions[$svc] = $version
        Write-Host "    $($svc.PadRight(20)) -> $version (app: $appVersion)" -ForegroundColor Green
    }
    catch {
        Write-Host "    WARN: $svc - failed to query registry: $_" -ForegroundColor Yellow
        $Errors += $svc
    }
}

if ($ResolvedVersions.Count -eq 0) {
    Write-Host ""
    Write-Host "  ERROR: No chart versions could be resolved. Check registry connectivity." -ForegroundColor Red
    exit 1
}

# --- Check if all versions are the same (common case) ---

$UniqueVersions = @($ResolvedVersions.Values | Sort-Object -Unique)
$AllSameVersion = ($UniqueVersions.Count -eq 1)

# --- Write output ---

$OutputFile = Join-Path (Resolve-Path $OutputDir) "osdu-versions.auto.tfvars"

$lines = @()
$lines += "# Auto-generated by resolve-chart-versions.ps1 — do not edit manually"
$lines += "# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC' -AsUTC)"
$lines += "# Mode: $(if ($env:OSDU_CHART_VERSION) { "pinned ($env:OSDU_CHART_VERSION)" } else { "latest (0.0.7-latest)" })"
$lines += ""

if ($AllSameVersion) {
    # All services resolved to the same version — use the default variable
    $lines += "osdu_chart_version = `"$($UniqueVersions[0])`""
    $lines += ""
    $lines += "# All services resolved to the same version — no per-service overrides needed"
    $lines += "osdu_service_versions = {}"
}
else {
    # Find the most common version to use as default, put outliers in overrides
    $versionCounts = $ResolvedVersions.Values | Group-Object | Sort-Object Count -Descending
    $mostCommon = $versionCounts[0].Name

    $lines += "osdu_chart_version = `"$mostCommon`""
    $lines += ""
    $lines += "osdu_service_versions = {"

    foreach ($svc in $ResolvedVersions.Keys) {
        if ($ResolvedVersions[$svc] -ne $mostCommon) {
            # Use display name with hyphens for readability in the key
            $lines += "  $($svc.PadRight(20)) = `"$($ResolvedVersions[$svc])`""
        }
    }

    $lines += "}"
}

$content = $lines -join "`n"
Set-Content -Path $OutputFile -Value $content -NoNewline

Write-Host ""
Write-Host "  Wrote $($ResolvedVersions.Count) service versions to:" -ForegroundColor Cyan
Write-Host "    $OutputFile"

if ($Errors.Count -gt 0) {
    Write-Host ""
    Write-Host "  WARNING: $($Errors.Count) service(s) could not be resolved: $($Errors -join ', ')" -ForegroundColor Yellow
}

Write-Host ""
