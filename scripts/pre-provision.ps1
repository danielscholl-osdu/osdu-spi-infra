#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pre-provision validation and environment configuration.
.DESCRIPTION
    Validates prerequisites and configures environment defaults before azd provision.
    Auto-logs in when Azure CLI auth fails, auto-detects values where possible,
    generates secure defaults for credentials, and persists via 'azd env set'.
.EXAMPLE
    azd hooks run preprovision
.EXAMPLE
    ./scripts/pre-provision.ps1
#>

#Requires -Version 7.4

$ErrorActionPreference = "Stop"

# Track validation results
$script:issues = [System.Collections.ArrayList]::new()
$script:warnings = [System.Collections.ArrayList]::new()

#region Utility Functions

function New-RandomPassword {
    param([int]$Length = 16)
    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $bytes = New-Object 'System.Byte[]' ($Length)
        $rng.GetBytes($bytes)
        return -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
    }
    finally { $rng.Dispose() }
}

function Set-EnvValue {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value,
        [ValidateSet("Critical", "Warning")][string]$Severity = "Critical"
    )
    if ($Value -eq "") {
        azd env set $Name ' ' 2>$null | Out-Null
    }
    else {
        azd env set $Name $Value 2>$null | Out-Null
    }
    if ($LASTEXITCODE -eq 0) {
        [Environment]::SetEnvironmentVariable($Name, $Value)
    }
    if ($LASTEXITCODE -ne 0) {
        $msg = "Failed to persist $Name via 'azd env set'"
        if ($Severity -eq "Critical") { [void]$script:issues.Add($msg) }
        else { [void]$script:warnings.Add($msg) }
        return $false
    }
    return $true
}

function Get-FeatureMode {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Default = "auto"
    )

    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $Default
    }

    switch ($value.Trim().ToLowerInvariant()) {
        "auto" { return "auto" }
        "enabled" { return "enabled" }
        "disabled" { return "disabled" }
        default {
            [void]$script:issues.Add("$Name must be one of: auto, enabled, disabled")
            return $Default
        }
    }
}

#endregion

#region Core Functions

function Test-RequiredTools {
    Write-Host "`n=================================================================="
    Write-Host "  Checking Required Tools"
    Write-Host "=================================================================="

    $tools = @(
        @{ Name = "terraform"; VersionCmd = 'terraform version -json | ConvertFrom-Json | Select-Object -ExpandProperty terraform_version' },
        @{ Name = "az"; VersionCmd = '(az version | ConvertFrom-Json)."azure-cli"' },
        @{ Name = "kubelogin"; VersionCmd = 'kubelogin --version 2>&1 | Select-String -Pattern "v[\d\.]+" | ForEach-Object { $_.Matches[0].Value -replace "v","" }' },
        @{ Name = "kubectl"; VersionCmd = '(kubectl version --client -o json | ConvertFrom-Json).clientVersion.gitVersion -replace "v",""'; InstallHint = "Install kubectl: https://kubernetes.io/docs/tasks/tools/" },
        @{ Name = "helm"; VersionCmd = '(helm version --template "{{.Version}}") -replace "v",""'; InstallHint = "Install helm: https://helm.sh/docs/intro/install/" }
    )

    foreach ($tool in $tools) {
        Write-Host "  $($tool.Name)..." -NoNewline
        $cmd = Get-Command $tool.Name -ErrorAction SilentlyContinue
        if (-not $cmd) {
            Write-Host " NOT FOUND" -ForegroundColor Red
            $hint = if ($tool.InstallHint) { $tool.InstallHint } else { "Please install $($tool.Name)" }
            Write-Host "    $hint" -ForegroundColor Gray
            [void]$script:issues.Add("$($tool.Name) is not installed")
            continue
        }
        try {
            $version = Invoke-Expression $tool.VersionCmd
            Write-Host " v$version" -ForegroundColor Green
        }
        catch { Write-Host " (version check failed)" -ForegroundColor Yellow }
    }
}

function Connect-Azure {
    Write-Host "`n=================================================================="
    Write-Host "  Checking Azure CLI Login"
    Write-Host "=================================================================="

    $account = az account show 2>$null | ConvertFrom-Json
    if (-not $account) {
        Write-Host "  Status: NOT LOGGED IN — attempting login..." -ForegroundColor Yellow
        az login 2>$null | Out-Null
        $account = az account show 2>$null | ConvertFrom-Json
        if (-not $account) {
            Write-Host "  Status: LOGIN FAILED" -ForegroundColor Red
            Write-Host "    Run manually: az login" -ForegroundColor Gray
            [void]$script:issues.Add("Azure CLI is not logged in (auto-login failed)")
            return $null
        }
        Write-Host "  Status: OK (logged in automatically)" -ForegroundColor Green
    }
    else {
        Write-Host "  Status: OK" -ForegroundColor Green
    }

    Write-Host "  Subscription: $($account.name)" -ForegroundColor Gray
    Write-Host "  Tenant: $($account.tenantId)" -ForegroundColor Gray

    $currentSubId = [Environment]::GetEnvironmentVariable("AZURE_SUBSCRIPTION_ID")
    if ([string]::IsNullOrEmpty($currentSubId)) {
        Set-EnvValue -Name "AZURE_SUBSCRIPTION_ID" -Value $account.id -Severity "Warning" | Out-Null
        Write-Host "  AZURE_SUBSCRIPTION_ID: auto-set ($($account.id))" -ForegroundColor Green
    }

    return $account
}

function Set-EnvironmentDefaults {
    param($Account)

    Write-Host "`n=================================================================="
    Write-Host "  Configuring Environment Defaults"
    Write-Host "=================================================================="

    Set-AcmeEmail -Account $Account
    Set-IngressPrefix
    Set-SimpleDefaults
    Set-PaaSDefaults
    Set-DnsZone -Account $Account
    Set-CoreFeatureFlags
    Reset-DeploymentState
    Set-Credentials
}

function Set-AcmeEmail {
    param($Account)

    $acmeEmail = [Environment]::GetEnvironmentVariable("TF_VAR_acme_email")
    Write-Host "  TF_VAR_acme_email..." -NoNewline

    if (-not [string]::IsNullOrEmpty($acmeEmail)) {
        Write-Host " $acmeEmail" -ForegroundColor Green
        return
    }
    if (-not $Account) {
        Write-Host " SKIPPED (not logged in)" -ForegroundColor Yellow
        return
    }

    # Strategy 1: Try Azure AD Graph (az ad signed-in-user show)
    $detectedEmail = az ad signed-in-user show --query mail -o tsv 2>$null
    if ([string]::IsNullOrEmpty($detectedEmail) -or $detectedEmail -eq "null") {
        $upn = az ad signed-in-user show --query userPrincipalName -o tsv 2>$null
        if (-not [string]::IsNullOrEmpty($upn) -and $upn -match '^(.+)#EXT#@') {
            $detectedEmail = $Matches[1] -replace '_([^_]+)$', '@$1'
        }
        elseif (-not [string]::IsNullOrEmpty($upn) -and $upn -notmatch '#') {
            $detectedEmail = $upn
        }
    }

    # Strategy 2: Decode the azd auth token JWT for email/upn claims
    if ([string]::IsNullOrEmpty($detectedEmail) -or $detectedEmail -eq "null") {
        try {
            $token = azd auth token --output json 2>$null | ConvertFrom-Json
            $jwt = if ($token.token) { $token.token } else { "$token".Trim() }
            if (-not [string]::IsNullOrEmpty($jwt) -and $jwt.Contains('.')) {
                $payload = $jwt.Split('.')[1]
                # Fix base64url encoding: replace URL-safe chars and add padding
                $payload = $payload.Replace('-', '+').Replace('_', '/')
                switch ($payload.Length % 4) {
                    2 { $payload += '==' }
                    3 { $payload += '=' }
                }
                $claims = [System.Text.Encoding]::UTF8.GetString(
                    [System.Convert]::FromBase64String($payload)
                ) | ConvertFrom-Json
                foreach ($claim in @('email', 'upn', 'preferred_username', 'unique_name')) {
                    $val = $claims.$claim
                    if (-not [string]::IsNullOrEmpty($val) -and $val -match '@' -and $val -notmatch '#') {
                        $detectedEmail = $val
                        break
                    }
                }
            }
        }
        catch {
            # azd auth token unavailable or JWT decode failed — continue silently
        }
    }

    if (-not [string]::IsNullOrEmpty($detectedEmail) -and $detectedEmail -ne "null" -and $detectedEmail -notmatch '#') {
        Set-EnvValue -Name "TF_VAR_acme_email" -Value $detectedEmail -Severity "Warning" | Out-Null
        Write-Host " auto-detected ($detectedEmail)" -ForegroundColor Green
    }
    else {
        Write-Host " NOT SET" -ForegroundColor Yellow
        Write-Host "    Could not auto-detect a valid email from Azure AD" -ForegroundColor Gray
        Write-Host "    Set with: azd env set TF_VAR_acme_email 'you@example.com'" -ForegroundColor Gray
        [void]$script:warnings.Add("TF_VAR_acme_email could not be auto-detected (only needed for Let's Encrypt)")
    }
}

function Set-IngressPrefix {
    $ingressPrefix = [Environment]::GetEnvironmentVariable("SPI_INGRESS_PREFIX")
    Write-Host "  SPI_INGRESS_PREFIX..." -NoNewline

    if (-not [string]::IsNullOrEmpty($ingressPrefix)) {
        Write-Host " $ingressPrefix" -ForegroundColor Green
        return
    }

    $chars = 'abcdefghijklmnopqrstuvwxyz0123456789'
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $bytes = New-Object 'System.Byte[]' 8
        $rng.GetBytes($bytes)
        $ingressPrefix = -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
    } finally { $rng.Dispose() }

    Set-EnvValue -Name "SPI_INGRESS_PREFIX" -Value $ingressPrefix -Severity "Warning" | Out-Null
    Write-Host " generated ($ingressPrefix)" -ForegroundColor Green
}

function Set-SimpleDefaults {
    $defaults = @(
        @{ Name = "TF_VAR_enable_public_ingress"; Default = "true"; Label = "true = public LB" },
        @{ Name = "TF_VAR_use_letsencrypt_production"; Default = "false"; Label = "false = staging" },
        @{ Name = "AKS_BOOTSTRAP_MODE"; Default = "auto"; Label = "auto = bootstrap current principal when possible" },
        @{ Name = "GRAFANA_MODE"; Default = "auto"; Label = "auto = create workspace and bootstrap access when possible" },
        @{ Name = "EXTERNAL_DNS_MODE"; Default = "auto"; Label = "auto = use a single discovered DNS zone when possible" }
    )

    foreach ($d in $defaults) {
        $current = [Environment]::GetEnvironmentVariable($d.Name)
        Write-Host "  $($d.Name)..." -NoNewline
        if ([string]::IsNullOrEmpty($current)) {
            Set-EnvValue -Name $d.Name -Value $d.Default -Severity "Warning" | Out-Null
            Write-Host " using default ($($d.Label))" -ForegroundColor Green

        }
        else {
            Write-Host " $current" -ForegroundColor Green
        }
    }
}

function Set-PaaSDefaults {
    Write-Host ""
    Write-Host "  Configuring PaaS default variables..." -ForegroundColor Gray

    $paasDefaults = @(
        @{ Name = "TF_VAR_data_partition"; Default = "opendes"; Label = "opendes" },
        @{ Name = "TF_VAR_enable_airflow"; Default = "true"; Label = "true = deploy Airflow" }
    )

    foreach ($d in $paasDefaults) {
        $current = [Environment]::GetEnvironmentVariable($d.Name)
        Write-Host "  $($d.Name)..." -NoNewline
        if ([string]::IsNullOrEmpty($current)) {
            Set-EnvValue -Name $d.Name -Value $d.Default -Severity "Warning" | Out-Null
            Write-Host " using default ($($d.Label))" -ForegroundColor Green
        }
        else {
            Write-Host " $current" -ForegroundColor Green
        }
    }
}

function Set-DnsDiscoveryState {
    param(
        [Parameter(Mandatory)][string]$Status,
        [string]$Reason = ""
    )

    Set-EnvValue -Name "SPI_DNS_ZONE_STATUS" -Value $Status -Severity "Warning" | Out-Null
    Set-EnvValue -Name "SPI_DNS_ZONE_REASON" -Value $Reason -Severity "Warning" | Out-Null
}

function Set-DnsZone {
    param($Account)

    $dnsZone = [Environment]::GetEnvironmentVariable("TF_VAR_dns_zone_name")
    Write-Host "  TF_VAR_dns_zone_name..." -NoNewline

    if (-not [string]::IsNullOrEmpty($dnsZone)) {
        Write-Host " $dnsZone" -ForegroundColor Green
        Set-EnvValue -Name "DNS_ZONE_NAME" -Value $dnsZone -Severity "Warning" | Out-Null
        Set-DnsDiscoveryState -Status "selected"

        foreach ($pair in @(
            @{ TfVar = "TF_VAR_dns_zone_resource_group"; Mirror = "DNS_ZONE_RESOURCE_GROUP" },
            @{ TfVar = "TF_VAR_dns_zone_subscription_id"; Mirror = "DNS_ZONE_SUBSCRIPTION_ID" }
        )) {
            $val = [Environment]::GetEnvironmentVariable($pair.TfVar)
            Write-Host "  $($pair.TfVar)..." -NoNewline
            if ([string]::IsNullOrEmpty($val)) {
                Write-Host " NOT SET" -ForegroundColor Yellow
                Write-Host "    Required when dns_zone_name is set: azd env set $($pair.TfVar) '<value>'" -ForegroundColor Gray
                [void]$script:issues.Add("$($pair.TfVar) is required when TF_VAR_dns_zone_name is set")
            }
            else {
                Write-Host " $val" -ForegroundColor Green
                Set-EnvValue -Name $pair.Mirror -Value $val -Severity "Warning" | Out-Null
            }
        }
        return
    }

    if (-not $Account) {
        Write-Host " SKIPPED (not logged in)" -ForegroundColor Yellow
        Set-DnsDiscoveryState -Status "error" -Reason "Azure login was unavailable, so DNS zone discovery was skipped."
        return
    }

    $subId = [Environment]::GetEnvironmentVariable("AZURE_SUBSCRIPTION_ID")
    if ([string]::IsNullOrEmpty($subId)) { $subId = $Account.id }
    $zonesJson = az network dns zone list --subscription $subId --query "[].{name:name, id:id, resourceGroup:resourceGroup}" -o json 2>$null
    $zoneListExitCode = $LASTEXITCODE

    if ($zoneListExitCode -ne 0) {
        Write-Host " failed to list DNS zones" -ForegroundColor Yellow
        Write-Host "    The 'az network dns zone list' command failed (exit code: $zoneListExitCode)" -ForegroundColor Yellow
        Write-Host "    DNS zone settings remain unset until you configure them manually." -ForegroundColor Gray
        Set-DnsDiscoveryState -Status "error" -Reason "Azure CLI could not list DNS zones for automatic selection."
        [void]$script:warnings.Add("Failed to list DNS zones — ExternalDNS remains automatic only when a zone is configured explicitly")
        return
    }

    $zones = if ($zonesJson) { $zonesJson | ConvertFrom-Json } else { @() }

    if ($zones.Count -eq 1) {
        $z = $zones[0]
        foreach ($pair in @(
            @{ Name = "TF_VAR_dns_zone_name"; Value = $z.name },
            @{ Name = "DNS_ZONE_NAME"; Value = $z.name },
            @{ Name = "TF_VAR_dns_zone_resource_group"; Value = $z.resourceGroup },
            @{ Name = "DNS_ZONE_RESOURCE_GROUP"; Value = $z.resourceGroup },
            @{ Name = "TF_VAR_dns_zone_subscription_id"; Value = $subId },
            @{ Name = "DNS_ZONE_SUBSCRIPTION_ID"; Value = $subId }
        )) { Set-EnvValue -Name $pair.Name -Value $pair.Value -Severity "Warning" | Out-Null }

        Write-Host " auto-discovered ($($z.name))" -ForegroundColor Green
        Write-Host "    Resource Group: $($z.resourceGroup)" -ForegroundColor Gray

        Set-DnsDiscoveryState -Status "selected"
    }
    elseif ($zones.Count -gt 1) {
        Write-Host " multiple DNS zones found" -ForegroundColor Yellow
        foreach ($z in $zones) {
            Write-Host "    - $($z.name) (rg: $($z.resourceGroup))" -ForegroundColor Gray
        }
        Write-Host "    To select one: azd env set TF_VAR_dns_zone_name '<zone-name>'" -ForegroundColor Gray
        Set-DnsDiscoveryState -Status "multiple" -Reason "Multiple DNS zones were found. Set TF_VAR_dns_zone_name to select one."
    }
    else {
        Write-Host " no DNS zones found (ExternalDNS remains disabled)" -ForegroundColor Gray
        Set-DnsDiscoveryState -Status "none" -Reason "No DNS zones were found for automatic ExternalDNS configuration."
    }
}

function Set-CoreFeatureFlags {
    $grafanaMode = Get-FeatureMode -Name "GRAFANA_MODE"
    $externalDnsMode = Get-FeatureMode -Name "EXTERNAL_DNS_MODE"
    $dnsZoneName = [Environment]::GetEnvironmentVariable("TF_VAR_dns_zone_name")

    $currentGrafanaFlag = [Environment]::GetEnvironmentVariable("ENABLE_GRAFANA_WORKSPACE")
    $grafanaFlag = if ($grafanaMode -eq "disabled") {
        "false"
    }
    elseif (-not [string]::IsNullOrEmpty($currentGrafanaFlag)) {
        $currentGrafanaFlag
    }
    else {
        "true"
    }
    Set-EnvValue -Name "ENABLE_GRAFANA_WORKSPACE" -Value $grafanaFlag -Severity "Warning" | Out-Null
    Write-Host "  ENABLE_GRAFANA_WORKSPACE... $grafanaFlag" -ForegroundColor Green

    $currentExternalDnsFlag = [Environment]::GetEnvironmentVariable("ENABLE_EXTERNAL_DNS_IDENTITY")
    $externalDnsFlag = if ($externalDnsMode -eq "disabled") {
        "false"
    }
    elseif (-not [string]::IsNullOrEmpty($currentExternalDnsFlag)) {
        $currentExternalDnsFlag
    }
    elseif (-not [string]::IsNullOrEmpty($dnsZoneName)) {
        "true"
    }
    else {
        "false"
    }
    Set-EnvValue -Name "ENABLE_EXTERNAL_DNS_IDENTITY" -Value $externalDnsFlag -Severity "Warning" | Out-Null
    Write-Host "  ENABLE_EXTERNAL_DNS_IDENTITY... $externalDnsFlag" -ForegroundColor Green

    if ($externalDnsMode -eq "enabled" -and [string]::IsNullOrEmpty($dnsZoneName)) {
        [void]$script:issues.Add("EXTERNAL_DNS_MODE=enabled requires a selected DNS zone (set TF_VAR_dns_zone_name and related values)")
    }
}

function Reset-DeploymentState {
    $defaults = @{
        SPI_POSTPROVISION_READY              = "false"
        SPI_POSTPROVISION_REASON             = "Post-provision has not completed yet."
        SPI_FOUNDATION_DEPLOYED              = "false"
        SPI_FOUNDATION_REASON                = "Foundation deployment has not completed yet."
        AKS_BOOTSTRAP_ACCESS_ENABLED           = "false"
        AKS_BOOTSTRAP_ACCESS_STATUS            = "pending"
        AKS_BOOTSTRAP_ACCESS_REASON            = ""
        GRAFANA_MONITOR_ACCESS_ENABLED         = "false"
        GRAFANA_MONITOR_ACCESS_STATUS          = "pending"
        GRAFANA_MONITOR_ACCESS_REASON          = ""
        GRAFANA_ADMIN_ACCESS_ENABLED           = "false"
        GRAFANA_ADMIN_ACCESS_STATUS            = "pending"
        GRAFANA_ADMIN_ACCESS_REASON            = ""
        EXTERNAL_DNS_ZONE_ACCESS_ENABLED       = "false"
        EXTERNAL_DNS_ZONE_ACCESS_STATUS        = "pending"
        EXTERNAL_DNS_ZONE_ACCESS_REASON        = ""
    }

    foreach ($entry in $defaults.GetEnumerator()) {
        Set-EnvValue -Name $entry.Key -Value $entry.Value -Severity "Warning" | Out-Null
    }
}

function Set-Credentials {
    $secrets = @(
        @{ Name = "TF_VAR_airflow_db_password" }
    )

    foreach ($s in $secrets) {
        $current = [Environment]::GetEnvironmentVariable($s.Name)
        Write-Host "  $($s.Name)..." -NoNewline
        if ([string]::IsNullOrEmpty($current)) {
            $len = if ($s.ContainsKey('Length')) { $s.Length } else { 16 }
            $generated = New-RandomPassword -Length $len
            if (Set-EnvValue -Name $s.Name -Value $generated -Severity "Critical") {
                Write-Host " generated" -ForegroundColor Green
            }
            else {
                Write-Host " FAILED" -ForegroundColor Red
            }
        }
        else {
            Write-Host " set" -ForegroundColor Green
        }
    }
}

function Register-Providers {
    Write-Host "`n=================================================================="
    Write-Host "  Checking Azure Resource Providers"
    Write-Host "=================================================================="

    $providers = @(
        "Microsoft.ContainerService",
        "Microsoft.OperationsManagement",
        "Microsoft.DocumentDB",
        "Microsoft.ServiceBus",
        "Microsoft.Cache",
        "Microsoft.Storage",
        "Microsoft.KeyVault"
    )

    foreach ($provider in $providers) {
        Write-Host "  $provider..." -NoNewline
        $stateRaw = az provider show -n $provider --query "registrationState" -o tsv 2>$null
        $exitCode = $LASTEXITCODE
        $state = if ($stateRaw) { "$stateRaw".Trim() } else { "Unknown" }

        if ($exitCode -ne 0) {
            Write-Host " check failed" -ForegroundColor Yellow
            [void]$script:warnings.Add("Could not check resource provider $provider (az CLI error)")
        }
        elseif ($state -eq "Registered") {
            Write-Host " Registered" -ForegroundColor Green
        }
        else {
            Write-Host " $state — registering..." -ForegroundColor Yellow
            az provider register -n $provider 2>$null
            if ($LASTEXITCODE -ne 0) {
                Write-Host "    Registration failed" -ForegroundColor Red
                [void]$script:issues.Add("Failed to register resource provider $provider")
            }
            else {
                Write-Host "    Registration initiated (Terraform will wait during apply)" -ForegroundColor Gray
                [void]$script:warnings.Add("Resource provider $provider registration initiated (not yet complete)")
            }
        }
    }
}

function Show-Summary {
    Write-Host ""

    if ($script:warnings.Count -gt 0) {
        Write-Host "==================================================================" -ForegroundColor Yellow
        Write-Host "  Warnings ($($script:warnings.Count))"                              -ForegroundColor Yellow
        Write-Host "==================================================================" -ForegroundColor Yellow
        for ($i = 0; $i -lt $script:warnings.Count; $i++) {
            Write-Host "  $($i + 1). $($script:warnings[$i])" -ForegroundColor Yellow
        }
        Write-Host ""
    }

    if ($script:issues.Count -gt 0) {
        Write-Host "==================================================================" -ForegroundColor Red
        Write-Host "  Pre-Provision Validation FAILED ($($script:issues.Count) issues)"  -ForegroundColor Red
        Write-Host "==================================================================" -ForegroundColor Red
        for ($i = 0; $i -lt $script:issues.Count; $i++) {
            Write-Host "  $($i + 1). $($script:issues[$i])" -ForegroundColor Yellow
        }
        Write-Host ""
        exit 1
    }

    $label = if ($script:warnings.Count -gt 0) { "PASSED (with $($script:warnings.Count) warnings)" } else { "PASSED" }
    Write-Host "==================================================================" -ForegroundColor Green
    Write-Host "  Pre-Provision Validation $label"                                   -ForegroundColor Green
    Write-Host "==================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Modes:" -ForegroundColor Gray
    Write-Host "    AKS_BOOTSTRAP_MODE=$(Get-FeatureMode -Name 'AKS_BOOTSTRAP_MODE')" -ForegroundColor Gray
    Write-Host "    GRAFANA_MODE=$(Get-FeatureMode -Name 'GRAFANA_MODE')" -ForegroundColor Gray
    Write-Host "    EXTERNAL_DNS_MODE=$(Get-FeatureMode -Name 'EXTERNAL_DNS_MODE')" -ForegroundColor Gray
    Write-Host ""
    Write-Host ""
    exit 0
}

#endregion

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "  Pre-Provision Validation"                                         -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

Test-RequiredTools
$account = Connect-Azure
Set-EnvironmentDefaults -Account $account
Register-Providers
Show-Summary
