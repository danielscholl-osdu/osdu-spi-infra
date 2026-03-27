#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Bootstrap elevated Azure access after core infrastructure provisioning.
.DESCRIPTION
    Applies the optional infra-access Terraform state, which manages:
    - AKS Cluster Admin role assignments
    - Grafana Azure Monitor / Log Analytics access
    - Grafana Admin role assignments
    - ExternalDNS DNS Zone Contributor role assignment

    Run this after `azd provision` when a privileged identity is available.
.EXAMPLE
    ./scripts/bootstrap-access.ps1 -AksAdminPrincipalIds <aad-object-id>
.EXAMPLE
    ./scripts/bootstrap-access.ps1 -AksAdminPrincipalIds <group-id> -GrafanaAdminPrincipalIds <group-id>
.EXAMPLE
    ./scripts/bootstrap-access.ps1 -AksAdminPrincipalIds <aad-object-id> -BestEffort
#>

[CmdletBinding()]
param(
    [string[]]$AksAdminPrincipalIds = @(),
    [string[]]$GrafanaAdminPrincipalIds = @(),
    [switch]$SkipGrafanaMonitorAccess,
    [switch]$SkipExternalDnsZoneAccess,
    [switch]$SkipCnpgProbeExemption,
    [switch]$BestEffort
)

#Requires -Version 7.4

$ErrorActionPreference = "Stop"

function Get-AzdValue {
    param([Parameter(Mandatory)][string]$Name)

    $envValue = [Environment]::GetEnvironmentVariable($Name)
    if (-not [string]::IsNullOrEmpty($envValue)) {
        return $envValue
    }

    $value = azd env get-value $Name 2>$null
    if ($LASTEXITCODE -ne 0) {
        return ""
    }

    return "$value".Trim()
}

function Get-RequiredValue {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Description
    )

    $value = Get-AzdValue -Name $Name
    if ([string]::IsNullOrEmpty($value)) {
        Write-Host "  ERROR: Missing $Name ($Description) in the selected azd environment." -ForegroundColor Red
        Write-Host "  Run 'azd provision' first, or 'azd env select <env>' before retrying." -ForegroundColor Yellow
        exit 1
    }

    return $value
}

function Set-EnvValue {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value
    )

    if ($Value -eq "") {
        azd env set $Name ' ' 2>$null | Out-Null
    }
    else {
        azd env set $Name $Value 2>$null | Out-Null
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  WARNING: Failed to persist $Name via azd env set" -ForegroundColor Yellow
    }
}

function Set-FeatureState {
    param(
        [Parameter(Mandatory)][string]$Prefix,
        [Parameter(Mandatory)][bool]$Enabled,
        [Parameter(Mandatory)][string]$Status,
        [string]$Reason = ""
    )

    Set-EnvValue -Name "${Prefix}_ENABLED" -Value $Enabled.ToString().ToLowerInvariant()
    Set-EnvValue -Name "${Prefix}_STATUS" -Value $Status
    Set-EnvValue -Name "${Prefix}_REASON" -Value $Reason
}

function Test-GuidValue {
    param([Parameter(Mandatory)][string]$Value)

    $parsed = [guid]::Empty
    return [guid]::TryParse($Value, [ref]$parsed)
}

function Assert-GuidValues {
    param(
        [Parameter(Mandatory)][string]$Label,
        [string[]]$Values
    )

    $invalidValues = @()
    foreach ($value in $Values) {
        if ([string]::IsNullOrWhiteSpace($value)) {
            continue
        }

        if (-not (Test-GuidValue -Value $value)) {
            $invalidValues += $value
        }
    }

    if ($invalidValues.Count -eq 0) {
        return
    }

    Write-Host "  ERROR: $Label must contain Azure object IDs in GUID format." -ForegroundColor Red
    foreach ($invalidValue in $invalidValues) {
        Write-Host "    Invalid value: $invalidValue" -ForegroundColor Yellow
    }
    exit 1
}

function Get-BoolValue {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Value,
        [Parameter(Mandatory)][bool]$Default
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Default
    }

    switch ($Value.Trim().ToLowerInvariant()) {
        "true" { return $true }
        "1" { return $true }
        "yes" { return $true }
        "false" { return $false }
        "0" { return $false }
        "no" { return $false }
        default {
            Write-Host "  ERROR: $Name must be one of: true, false, 1, 0, yes, no" -ForegroundColor Red
            exit 1
        }
    }
}

function Test-AuthorizationFailure {
    param([Parameter(Mandatory)][string]$Output)

    return $Output -match 'AuthorizationFailed|403 \(403 Forbidden\)|403 Forbidden|does not have authorization|authorization to perform action|insufficient privileges|Status=403|PermissionDenied'
}

function Test-ExistingResourceFailure {
    param([Parameter(Mandatory)][string]$Output)

    return $Output -match 'RoleAssignmentExists|already exists|needs to be imported into the State|to be managed via Terraform this resource needs to be imported'
}

function Initialize-Terraform {
    param([Parameter(Mandatory)][string]$StatePath)

    Write-Host "  Initializing terraform (state: $StatePath)..." -ForegroundColor Gray
    $initOutput = & terraform init -reconfigure "-backend-config=path=$StatePath" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ERROR: terraform init failed" -ForegroundColor Red
        Write-Host ($initOutput | Out-String).Trim() -ForegroundColor DarkGray
        exit 1
    }
}

function Invoke-TerraformCapability {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Prefix,
        [Parameter(Mandatory)][hashtable]$BaseTfVars,
        [Parameter(Mandatory)][hashtable]$Overrides,
        [Parameter(Mandatory)][string[]]$Targets,
        [Parameter(Mandatory)][string]$AuthorizationReason
    )

    $tfVars = @{}
    foreach ($key in $BaseTfVars.Keys) {
        $tfVars[$key] = $BaseTfVars[$key]
    }
    foreach ($key in $Overrides.Keys) {
        $tfVars[$key] = $Overrides[$key]
    }

    $stateName = ($BaseTfVars.cluster_resource_id -split '/')[-1]
    $tfVarsPath = Join-Path ([System.IO.Path]::GetTempPath()) "spi-infra-access-$stateName-$Prefix.tfvars.json"
    try {
        $tfVars | ConvertTo-Json -Depth 8 | Set-Content -Path $tfVarsPath -Encoding utf8

        $applyArgs = @("apply", "-auto-approve", "-var-file=$tfVarsPath")
        foreach ($target in $Targets) {
            $applyArgs += "-target=$target"
        }

        Write-Host "  $Label..." -NoNewline
        $applyOutput = & terraform @applyArgs 2>&1
        $applyText = ($applyOutput | Out-String).Trim()

        if ($LASTEXITCODE -eq 0) {
            Write-Host " enabled" -ForegroundColor Green
            Set-FeatureState -Prefix $Prefix -Enabled $true -Status "enabled" -Reason ""
            return $true
        }

        if (Test-ExistingResourceFailure -Output $applyText) {
            Write-Host " already granted" -ForegroundColor Green
            Set-FeatureState -Prefix $Prefix -Enabled $true -Status "existing" -Reason ""
            return $true
        }

        if ($BestEffort -and (Test-AuthorizationFailure -Output $applyText)) {
            Write-Host " skipped (insufficient authorization)" -ForegroundColor Yellow
            Set-FeatureState -Prefix $Prefix -Enabled $false -Status "skipped" -Reason $AuthorizationReason
            return $false
        }

        Write-Host " FAILED" -ForegroundColor Red
        Write-Host $applyText -ForegroundColor DarkGray
        exit 1
    }
    finally {
        if (Test-Path $tfVarsPath) {
            Remove-Item $tfVarsPath -Force
        }
    }
}

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "  Bootstrap Access: infra-access"                                   -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

$subscriptionId = Get-RequiredValue -Name "AZURE_SUBSCRIPTION_ID" -Description "subscription ID"
$clusterResourceId = Get-RequiredValue -Name "AKS_RESOURCE_ID" -Description "AKS resource ID"
$monitorWorkspaceId = Get-RequiredValue -Name "PROMETHEUS_WORKSPACE_ID" -Description "Azure Monitor workspace ID"
$logAnalyticsWorkspaceId = Get-RequiredValue -Name "LOG_ANALYTICS_WORKSPACE_ID" -Description "Log Analytics workspace ID"

$grafanaResourceId = Get-AzdValue -Name "GRAFANA_RESOURCE_ID"
$grafanaPrincipalId = Get-AzdValue -Name "GRAFANA_PRINCIPAL_ID"
$externalDnsPrincipalId = Get-AzdValue -Name "EXTERNAL_DNS_PRINCIPAL_ID"
$dnsZoneName = Get-AzdValue -Name "TF_VAR_dns_zone_name"
$dnsZoneRg = Get-AzdValue -Name "TF_VAR_dns_zone_resource_group"
$dnsZoneSubId = Get-AzdValue -Name "TF_VAR_dns_zone_subscription_id"

Assert-GuidValues -Label "AksAdminPrincipalIds" -Values $AksAdminPrincipalIds
Assert-GuidValues -Label "GrafanaAdminPrincipalIds" -Values $GrafanaAdminPrincipalIds

if (-not [string]::IsNullOrEmpty($grafanaPrincipalId)) {
    Assert-GuidValues -Label "GRAFANA_PRINCIPAL_ID" -Values @($grafanaPrincipalId)
}

if (-not [string]::IsNullOrEmpty($externalDnsPrincipalId)) {
    Assert-GuidValues -Label "EXTERNAL_DNS_PRINCIPAL_ID" -Values @($externalDnsPrincipalId)
}

$enableAksBootstrapAccess = $AksAdminPrincipalIds.Count -gt 0
$enableGrafanaMonitorAccess = (-not $SkipGrafanaMonitorAccess) -and
    -not [string]::IsNullOrEmpty($grafanaResourceId) -and
    -not [string]::IsNullOrEmpty($grafanaPrincipalId)
$enableGrafanaAdminAccess = $GrafanaAdminPrincipalIds.Count -gt 0 -and -not [string]::IsNullOrEmpty($grafanaResourceId)
$enableExternalDnsZoneAccess = (-not $SkipExternalDnsZoneAccess) -and
    -not [string]::IsNullOrEmpty($externalDnsPrincipalId) -and
    -not [string]::IsNullOrEmpty($dnsZoneName) -and
    -not [string]::IsNullOrEmpty($dnsZoneRg) -and
    -not [string]::IsNullOrEmpty($dnsZoneSubId)

Write-Host "  AKS admin bootstrap: $(if ($enableAksBootstrapAccess) { 'requested' } else { 'not requested' })" -ForegroundColor Gray
Write-Host "  Grafana monitor access: $(if ($enableGrafanaMonitorAccess) { 'requested' } else { 'not requested' })" -ForegroundColor Gray
Write-Host "  Grafana admin access: $(if ($enableGrafanaAdminAccess) { 'requested' } else { 'not requested' })" -ForegroundColor Gray
Write-Host "  ExternalDNS zone access: $(if ($enableExternalDnsZoneAccess) { 'requested' } else { 'not requested' })" -ForegroundColor Gray

if (-not $enableAksBootstrapAccess -and -not $enableGrafanaMonitorAccess -and -not $enableGrafanaAdminAccess -and -not $enableExternalDnsZoneAccess) {
    Write-Host "  Nothing to bootstrap." -ForegroundColor Yellow
    exit 0
}

Push-Location "$PSScriptRoot/../infra-access"
try {
    if (-not (Test-Path ".tfstate")) {
        New-Item -ItemType Directory -Path ".tfstate" | Out-Null
    }

    $clusterName = ($clusterResourceId -split '/')[-1]
    $statePath = ".tfstate/$clusterName.tfstate"
    Initialize-Terraform -StatePath $statePath

    $baseTfVars = @{
        cluster_resource_id                   = $clusterResourceId
        subscription_id                       = $subscriptionId
        enable_aks_bootstrap_access           = $false
        aks_admin_principal_ids               = @()
        grafana_resource_id                   = $grafanaResourceId
        grafana_managed_identity_principal_id = $grafanaPrincipalId
        monitor_workspace_id                  = $monitorWorkspaceId
        log_analytics_workspace_id            = $logAnalyticsWorkspaceId
        enable_grafana_monitor_access         = $false
        enable_grafana_admin_access           = $false
        grafana_admin_principal_ids           = @()
        external_dns_principal_id             = $externalDnsPrincipalId
        dns_zone_name                         = $dnsZoneName
        dns_zone_resource_group               = $dnsZoneRg
        dns_zone_subscription_id              = $dnsZoneSubId
        enable_external_dns_zone_access       = $false
    }

    if ($enableAksBootstrapAccess) {
        $aksReason = "AKS Cluster Admin role not granted. Run: az role assignment create --assignee $($AksAdminPrincipalIds[0]) --role 'Azure Kubernetes Service RBAC Cluster Admin' --scope $clusterResourceId"
        $null = Invoke-TerraformCapability -Label "AKS bootstrap access" -Prefix "AKS_BOOTSTRAP_ACCESS" -BaseTfVars $baseTfVars -Overrides @{
            enable_aks_bootstrap_access = $true
            aks_admin_principal_ids     = $AksAdminPrincipalIds
        } -Targets @("azurerm_role_assignment.aks_cluster_admin") -AuthorizationReason $aksReason
    }

    if ($enableGrafanaMonitorAccess) {
        $null = Invoke-TerraformCapability -Label "Grafana monitor access" -Prefix "GRAFANA_MONITOR_ACCESS" -BaseTfVars $baseTfVars -Overrides @{
            enable_grafana_monitor_access = $true
        } -Targets @(
            "azurerm_role_assignment.grafana_monitoring_reader",
            "azurerm_role_assignment.grafana_monitoring_data_reader",
            "azurerm_role_assignment.grafana_log_analytics_reader"
        ) -AuthorizationReason "Grafana monitor access was skipped because the current identity cannot create the required monitoring role assignments."
    }

    if ($enableGrafanaAdminAccess) {
        $null = Invoke-TerraformCapability -Label "Grafana admin access" -Prefix "GRAFANA_ADMIN_ACCESS" -BaseTfVars $baseTfVars -Overrides @{
            enable_grafana_admin_access = $true
            grafana_admin_principal_ids = $GrafanaAdminPrincipalIds
        } -Targets @("azurerm_role_assignment.grafana_admin") -AuthorizationReason "Grafana admin access was skipped because the current identity cannot create Grafana role assignments."
    }

    if ($enableExternalDnsZoneAccess) {
        $dnsZoneScope = "/subscriptions/$dnsZoneSubId/resourceGroups/$dnsZoneRg/providers/Microsoft.Network/dnszones/$dnsZoneName"
        $dnsReason = "ExternalDNS needs 'DNS Zone Contributor' on the DNS zone. Run: az role assignment create --assignee $externalDnsPrincipalId --role 'DNS Zone Contributor' --scope $dnsZoneScope"
        $null = Invoke-TerraformCapability -Label "ExternalDNS zone access" -Prefix "EXTERNAL_DNS_ZONE_ACCESS" -BaseTfVars $baseTfVars -Overrides @{
            enable_external_dns_zone_access = $true
        } -Targets @("azurerm_role_assignment.external_dns_dns_contributor") -AuthorizationReason $dnsReason
    }
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Green
Write-Host "  Bootstrap Access Complete"                                         -ForegroundColor Green
Write-Host "==================================================================" -ForegroundColor Green
Write-Host ""
