#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Post-provision: configure safeguards and deploy foundation layer.
.DESCRIPTION
    Runs after cluster provisioning (azd provision) to:
    1. Configure kubeconfig and verify RBAC
    2. Set up AKS deployment safeguards
    3. Wait for Gatekeeper readiness
    4. Verify namespace exclusions
    5. Deploy foundation layer (cert-manager, ECK, ExternalDNS, Gateway)

    After this hook completes, the cluster is ready for stack deployment (azd deploy).
.EXAMPLE
    azd hooks run postprovision
.EXAMPLE
    ./scripts/post-provision.ps1
#>

#Requires -Version 7.4

$ErrorActionPreference = "Stop"

#region Utility Functions

function Get-ClusterContext {
    $resourceGroup = $env:AZURE_RESOURCE_GROUP
    $clusterName = $env:AZURE_AKS_CLUSTER_NAME
    $subscriptionId = $env:AZURE_SUBSCRIPTION_ID

    if ([string]::IsNullOrEmpty($resourceGroup) -or [string]::IsNullOrEmpty($clusterName)) {
        Write-Host "  Getting values from terraform outputs..." -ForegroundColor Gray
        Push-Location $PSScriptRoot/../infra
        if ([string]::IsNullOrEmpty($resourceGroup)) { $resourceGroup = terraform output -raw AZURE_RESOURCE_GROUP 2>$null }
        if ([string]::IsNullOrEmpty($clusterName)) { $clusterName = terraform output -raw AZURE_AKS_CLUSTER_NAME 2>$null }
        if ([string]::IsNullOrEmpty($subscriptionId)) { $subscriptionId = terraform output -raw AZURE_SUBSCRIPTION_ID 2>$null }
        Pop-Location
    }

    if ([string]::IsNullOrEmpty($subscriptionId)) {
        Write-Host "  Subscription ID not provided; falling back to current az account..." -ForegroundColor Gray
        $subscriptionId = az account show --query id -o tsv 2>$null
    }

    if ([string]::IsNullOrEmpty($resourceGroup) -or [string]::IsNullOrEmpty($clusterName)) {
        Write-Host "  Could not determine resource group or cluster name" -ForegroundColor Red
        exit 1
    }

    $clusterResourceId = Get-AzdValue -Name "AKS_RESOURCE_ID"
    if ([string]::IsNullOrEmpty($clusterResourceId) -and -not [string]::IsNullOrEmpty($subscriptionId)) {
        $clusterResourceId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ContainerService/managedClusters/$clusterName"
    }

    return @{
        ResourceGroup    = $resourceGroup
        ClusterName      = $clusterName
        SubscriptionId   = $subscriptionId
        ClusterResourceId = $clusterResourceId
        SubArgs          = if (-not [string]::IsNullOrEmpty($subscriptionId)) { @("--subscription", $subscriptionId) } else { @() }
    }
}

function Get-AzdValue {
    param([Parameter(Mandatory)][string]$Name)

    $value = [Environment]::GetEnvironmentVariable($Name)
    if (-not [string]::IsNullOrEmpty($value)) {
        return $value
    }

    $value = azd env get-value $Name 2>$null
    if ($LASTEXITCODE -ne 0) {
        return ""
    }

    return "$value".Trim()
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
    if ($LASTEXITCODE -eq 0) {
        [Environment]::SetEnvironmentVariable($Name, $Value)
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

function Get-ModeValue {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Default = "auto"
    )

    $value = Get-AzdValue -Name $Name
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $Default
    }

    return $value.Trim().ToLowerInvariant()
}

function Get-BoolValue {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Default
    )

    $value = Get-AzdValue -Name $Name
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $Default
    }

    switch ($value.Trim().ToLowerInvariant()) {
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

function ConvertFrom-Base64UrlString {
    param([Parameter(Mandatory)][string]$Value)

    $padded = $Value.Replace('-', '+').Replace('_', '/')
    switch ($padded.Length % 4) {
        2 { $padded += '==' }
        3 { $padded += '=' }
        0 { }
        default { throw "Invalid base64url value length." }
    }

    return [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($padded))
}

function Get-CurrentPrincipalContext {
    $accountJson = az account show -o json 2>$null
    $account = if ($accountJson) { $accountJson | ConvertFrom-Json } else { $null }
    $principalName = if ($account) { "$($account.user.name)" } else { "" }
    $principalType = if ($account) { "$($account.user.type)" } else { "" }
    $objectId = ""

    $token = az account get-access-token --resource https://management.azure.com/ --query accessToken -o tsv 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($token)) {
        try {
            $parts = $token -split '\.'
            if ($parts.Length -ge 2) {
                $payload = ConvertFrom-Base64UrlString -Value $parts[1] | ConvertFrom-Json
                if ($payload.oid) {
                    $objectId = "$($payload.oid)"
                }
            }
        }
        catch {
            $objectId = ""
        }
    }

    return @{
        Name     = $principalName
        Type     = $principalType
        ObjectId = $objectId
    }
}

function Set-PostProvisionState {
    param(
        [Parameter(Mandatory)][bool]$Ready,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Reason,
        [Parameter(Mandatory)][bool]$FoundationDeployed,
        [Parameter(Mandatory)][AllowEmptyString()][string]$FoundationReason
    )

    Set-EnvValue -Name "SPI_POSTPROVISION_READY" -Value $Ready.ToString().ToLowerInvariant()
    Set-EnvValue -Name "SPI_POSTPROVISION_REASON" -Value $Reason
    Set-EnvValue -Name "SPI_FOUNDATION_DEPLOYED" -Value $FoundationDeployed.ToString().ToLowerInvariant()
    Set-EnvValue -Name "SPI_FOUNDATION_REASON" -Value $FoundationReason
}

function Get-DeferredFeatureNotes {
    $notes = [System.Collections.Generic.List[string]]::new()

    $topReason = Get-AzdValue -Name "SPI_POSTPROVISION_REASON"
    if (-not [string]::IsNullOrWhiteSpace($topReason)) {
        $notes.Add($topReason)
    }

    foreach ($prefix in @(
        "AKS_BOOTSTRAP_ACCESS",
        "GRAFANA_MONITOR_ACCESS",
        "GRAFANA_ADMIN_ACCESS",
        "EXTERNAL_DNS_ZONE_ACCESS"
    )) {
        $status = Get-AzdValue -Name "${prefix}_STATUS"
        $reason = Get-AzdValue -Name "${prefix}_REASON"
        if ($status -eq "skipped" -and -not [string]::IsNullOrWhiteSpace($reason)) {
            $notes.Add($reason)
        }
    }

    $dnsStatus = Get-AzdValue -Name "SPI_DNS_ZONE_STATUS"
    $dnsReason = Get-AzdValue -Name "SPI_DNS_ZONE_REASON"
    if (($dnsStatus -eq "multiple" -or $dnsStatus -eq "error") -and -not [string]::IsNullOrWhiteSpace($dnsReason)) {
        $notes.Add($dnsReason)
    }

    return $notes | Select-Object -Unique
}

function Show-BootstrapAccessInstructions {
    param($Ctx, [hashtable]$Principal)

    Write-Host ""
    Write-Host "  Skipped: Foundation and stack deployment." -ForegroundColor Yellow
    Write-Host "  The current user does not have 'Azure Kubernetes Service RBAC Cluster Admin'" -ForegroundColor Yellow
    Write-Host "  on the cluster, which is required to deploy Kubernetes resources." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  To grant access and continue:" -ForegroundColor Gray

    $principalArg = if (-not [string]::IsNullOrWhiteSpace($Principal.ObjectId)) { $Principal.ObjectId } else { "<your-aad-object-id>" }
    Write-Host "    az role assignment create --assignee $principalArg ``" -ForegroundColor Cyan
    Write-Host "      --role 'Azure Kubernetes Service RBAC Cluster Admin' ``" -ForegroundColor Cyan
    Write-Host "      --scope $($Ctx.ClusterResourceId)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Then re-run:" -ForegroundColor Gray
    Write-Host "    azd up" -ForegroundColor Cyan
}

function Invoke-BootstrapAccess {
    param(
        [string[]]$AksAdminPrincipalIds = @(),
        [string[]]$GrafanaAdminPrincipalIds = @(),
        [switch]$SkipGrafanaMonitorAccess,
        [switch]$SkipExternalDnsZoneAccess,
        [switch]$SkipCnpgProbeExemption,
        [switch]$BestEffort
    )

    $scriptPath = Join-Path $PSScriptRoot "bootstrap-access.ps1"
    $pwshArgs = @("-NoProfile", "-File", $scriptPath)

    if ($BestEffort) { $pwshArgs += "-BestEffort" }
    if ($SkipGrafanaMonitorAccess) { $pwshArgs += "-SkipGrafanaMonitorAccess" }
    if ($SkipExternalDnsZoneAccess) { $pwshArgs += "-SkipExternalDnsZoneAccess" }
    if ($SkipCnpgProbeExemption) { $pwshArgs += "-SkipCnpgProbeExemption" }
    if ($AksAdminPrincipalIds.Count -gt 0) {
        $pwshArgs += "-AksAdminPrincipalIds"
        $pwshArgs += $AksAdminPrincipalIds
    }
    if ($GrafanaAdminPrincipalIds.Count -gt 0) {
        $pwshArgs += "-GrafanaAdminPrincipalIds"
        $pwshArgs += $GrafanaAdminPrincipalIds
    }

    & pwsh @pwshArgs
    $exitCode = $LASTEXITCODE

    # Refresh in-process env vars from azd disk state.
    # bootstrap-access.ps1 runs as a child process — its azd env set calls
    # update the disk file but not the parent's in-process environment.
    foreach ($prefix in @("AKS_BOOTSTRAP_ACCESS", "GRAFANA_MONITOR_ACCESS", "GRAFANA_ADMIN_ACCESS", "EXTERNAL_DNS_ZONE_ACCESS")) {
        foreach ($suffix in @("ENABLED", "STATUS", "REASON")) {
            $varName = "${prefix}_${suffix}"
            $diskValue = azd env get-value $varName 2>$null
            if ($LASTEXITCODE -eq 0 -and $null -ne $diskValue) {
                [Environment]::SetEnvironmentVariable($varName, "$diskValue".Trim())
            }
        }
    }

    return ($exitCode -eq 0)
}

function Test-KubePermissions {
    $maxWait = 300
    if ($env:RBAC_WAIT_TIMEOUT) {
        if ([int]::TryParse($env:RBAC_WAIT_TIMEOUT, [ref]$maxWait)) {
            Write-Host "  Using custom RBAC wait timeout: $maxWait`s" -ForegroundColor Gray
        }
        else {
            $maxWait = 300
        }
    }
    $interval = 15
    $elapsed = 0

    while ($elapsed -lt $maxWait) {
        $canCreate = kubectl auth can-i create namespaces 2>&1
        if ($canCreate -eq "yes") {
            Write-Host "  RBAC permissions: OK" -ForegroundColor Green
            return $true
        }

        $output = "$canCreate"
        if ($output -match "\bAADSTS\b|\bauthentication failed\b|\bunauthorized\b|\blogin\s+failed\b|token expired|invalid token|token not found|credential expired|invalid credential|credentials? not found") {
            Write-Host "  ERROR: Authentication failed (not an RBAC propagation issue)" -ForegroundColor Red
            Write-Host "  Detail: $($output.Substring(0, [Math]::Min(200, $output.Length)))" -ForegroundColor Gray
            Write-Host "  Please re-authenticate:" -ForegroundColor Yellow
            Write-Host "    az logout" -ForegroundColor Gray
            Write-Host "    az login" -ForegroundColor Gray
            exit 1
        }

        if ($output -match "^no") {
            if ($elapsed -eq 0) {
                Write-Host "  Permission denied — will retry for up to $maxWait`s in case of propagation delay..." -ForegroundColor Yellow
                Write-Host "    kubectl: $($output.Substring(0, [Math]::Min(150, $output.Length)))" -ForegroundColor Gray
            }
            else {
                Write-Host "  Waiting for RBAC propagation... ($elapsed`s)" -ForegroundColor Gray
            }
        }
        else {
            Write-Host "  Waiting for RBAC propagation... ($elapsed`s) — kubectl: $($output.Substring(0, [Math]::Min(150, $output.Length)))" -ForegroundColor Gray
        }
        Start-Sleep -Seconds $interval
        $elapsed += $interval
    }

    $finalCheck = kubectl auth can-i create namespaces 2>&1
    if ($finalCheck -eq "yes") {
        Write-Host "  RBAC permissions: OK (detected on final check)" -ForegroundColor Green
        return $true
    }

    Write-Host "  RBAC check timed out after $maxWait`s — last response: $finalCheck" -ForegroundColor Yellow
    return $false
}

function Connect-Cluster {
    param(
        $Ctx,
        [hashtable]$Principal,
        [string]$AksBootstrapMode
    )

    Write-Host "`n[1/5] Configuring kubeconfig..." -ForegroundColor Cyan
    $attemptedBootstrap = $false
    $maxAttempts = 2

    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $credentialsOutput = az aks get-credentials -g $Ctx.ResourceGroup -n $Ctx.ClusterName @($Ctx.SubArgs) --overwrite-existing 2>&1
        if ($LASTEXITCODE -eq 0) {
            break
        }

        $credText = "$credentialsOutput"
        if ($credText -notmatch "AuthorizationFailed|Forbidden|does not have authorization|insufficient privileges|PermissionDenied") {
            Write-Host "  Failed to get kubeconfig" -ForegroundColor Red
            Write-Host "  $credText" -ForegroundColor Gray
            exit 1
        }

        if ($AksBootstrapMode -eq "disabled") {
            Set-FeatureState -Prefix "AKS_BOOTSTRAP_ACCESS" -Enabled $false -Status "disabled" -Reason "AKS bootstrap is disabled by AKS_BOOTSTRAP_MODE=disabled."
            return $false
        }

        if ($attemptedBootstrap) {
            if ($AksBootstrapMode -eq "enabled") {
                Write-Host "  ERROR: Automatic AKS bootstrap did not grant usable Kubernetes access." -ForegroundColor Red
                exit 1
            }
            return $false
        }

        if ([string]::IsNullOrWhiteSpace($Principal.ObjectId)) {
            $reason = "AKS bootstrap access was skipped because the current principal object ID could not be resolved automatically."
            Set-FeatureState -Prefix "AKS_BOOTSTRAP_ACCESS" -Enabled $false -Status "skipped" -Reason $reason
            if ($AksBootstrapMode -eq "enabled") {
                Write-Host "  ERROR: $reason" -ForegroundColor Red
                exit 1
            }
            return $false
        }

        Write-Host "  Kubeconfig access: not available yet; attempting automatic AKS bootstrap..." -ForegroundColor Yellow
        $bootstrapOk = Invoke-BootstrapAccess -AksAdminPrincipalIds @($Principal.ObjectId) -SkipGrafanaMonitorAccess -SkipExternalDnsZoneAccess -SkipCnpgProbeExemption -BestEffort:($AksBootstrapMode -eq "auto")
        if (-not $bootstrapOk) {
            if ($AksBootstrapMode -eq "enabled") {
                Write-Host "  ERROR: AKS bootstrap failed" -ForegroundColor Red
                exit 1
            }
            return $false
        }

        $attemptedBootstrap = $true
        $aksStatus = Get-AzdValue -Name "AKS_BOOTSTRAP_ACCESS_STATUS"
        if ($aksStatus -notin @("enabled", "existing")) {
            if ($AksBootstrapMode -eq "enabled") {
                Write-Host "  ERROR: AKS bootstrap did not complete successfully." -ForegroundColor Red
                exit 1
            }
            return $false
        }

        Write-Host "  Retrying kubeconfig after AKS bootstrap..." -ForegroundColor Gray
    }

    $convertOutput = kubelogin convert-kubeconfig -l azurecli 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Failed to convert kubeconfig for Azure CLI auth" -ForegroundColor Red
        Write-Host "  $convertOutput" -ForegroundColor Gray
        exit 1
    }
    Write-Host "  Kubeconfig configured" -ForegroundColor Green

    # Quick single check — if RBAC is already there, skip the polling loop entirely.
    Write-Host "`n[1.5/5] Verifying RBAC permissions..." -ForegroundColor Cyan
    $quickCheck = kubectl auth can-i create namespaces 2>&1
    if ($quickCheck -eq "yes") {
        Write-Host "  RBAC permissions: OK" -ForegroundColor Green
        $existingAksStatus = Get-AzdValue -Name "AKS_BOOTSTRAP_ACCESS_STATUS"
        if ([string]::IsNullOrWhiteSpace($existingAksStatus) -or $existingAksStatus -eq "pending") {
            Set-FeatureState -Prefix "AKS_BOOTSTRAP_ACCESS" -Enabled $true -Status "existing" -Reason ""
        }
        return $true
    }

    # Kubeconfig succeeded (Cluster User role) but Kubernetes RBAC denied.
    # Attempt bootstrap to grant Cluster Admin before entering the polling loop.
    if (-not $attemptedBootstrap -and $AksBootstrapMode -ne "disabled" -and -not [string]::IsNullOrWhiteSpace($Principal.ObjectId)) {
        Write-Host "  Permission denied — attempting bootstrap to grant Cluster Admin..." -ForegroundColor Yellow
        Write-Host "    kubectl: $("$quickCheck".Substring(0, [Math]::Min(150, "$quickCheck".Length)))" -ForegroundColor Gray
        $bootstrapOk = Invoke-BootstrapAccess -AksAdminPrincipalIds @($Principal.ObjectId) -SkipGrafanaMonitorAccess -SkipExternalDnsZoneAccess -SkipCnpgProbeExemption -BestEffort:($AksBootstrapMode -eq "auto")
        if ($bootstrapOk) {
            $aksStatus = Get-AzdValue -Name "AKS_BOOTSTRAP_ACCESS_STATUS"
            if ($aksStatus -in @("enabled", "existing")) {
                # Now wait for the new role assignment to propagate.
                if (Test-KubePermissions) {
                    return $true
                }
            }
        }
        $attemptedBootstrap = $true
    }

    # No bootstrap attempted or bootstrap didn't help — poll in case of external propagation.
    if (-not $attemptedBootstrap) {
        if (Test-KubePermissions) {
            $existingAksStatus = Get-AzdValue -Name "AKS_BOOTSTRAP_ACCESS_STATUS"
            if ([string]::IsNullOrWhiteSpace($existingAksStatus) -or $existingAksStatus -eq "pending") {
                Set-FeatureState -Prefix "AKS_BOOTSTRAP_ACCESS" -Enabled $true -Status "existing" -Reason ""
            }
            return $true
        }
    }

    $reason = "AKS bootstrap access did not propagate in time for Kubernetes deployment."
    if ($attemptedBootstrap) {
        Set-FeatureState -Prefix "AKS_BOOTSTRAP_ACCESS" -Enabled $false -Status "skipped" -Reason $reason
    }

    if ($AksBootstrapMode -eq "enabled") {
        Write-Host "  ERROR: $reason" -ForegroundColor Red
        exit 1
    }

    return $false
}
function Set-Safeguards {
    param($Ctx)

    Write-Host "`n[2/5] Checking cluster configuration..." -ForegroundColor Cyan

    $clusterSkuOutput = az aks show -g $Ctx.ResourceGroup -n $Ctx.ClusterName @($Ctx.SubArgs) --query "sku.name" -o tsv 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ERROR: Failed to determine AKS cluster SKU via 'az aks show'." -ForegroundColor Red
        Write-Host "  Ensure you are logged in, have access to the subscription, and the cluster exists." -ForegroundColor Red
        exit 1
    }

    $clusterSku = if ($clusterSkuOutput) { $clusterSkuOutput.Trim() } else { "" }
    if ([string]::IsNullOrEmpty($clusterSku)) {
        Write-Host "  ERROR: AKS cluster SKU was not returned by 'az aks show'." -ForegroundColor Red
        exit 1
    }

    $script:isAutomatic = ($clusterSku -eq "Automatic")

    if ($script:isAutomatic) {
        Write-Host "  Cluster type: AKS Automatic" -ForegroundColor Cyan
        Write-Host "  Safeguards: Enforced (cannot be modified)" -ForegroundColor Yellow
        Write-Host "  Workloads must be compliant with Deployment Safeguards" -ForegroundColor Yellow
        return
    }

    Write-Host "  Cluster type: Standard AKS" -ForegroundColor Cyan
    Write-Host "  Configuring AKS safeguards..." -ForegroundColor Cyan

    $excludedNsList = @(
        "kube-system", "gatekeeper-system", "foundation",
        "elasticsearch", "aks-istio-ingress"
    )

    $maxRetries = 3
    $retryCount = 0
    $configured = $false

    while (-not $configured -and $retryCount -lt $maxRetries) {
        $retryCount++
        Write-Host "  Attempt $retryCount of $maxRetries..." -ForegroundColor Gray

        Write-Host "  Trying az aks safeguards update..." -ForegroundColor Gray
        $null = az aks safeguards update -g $Ctx.ResourceGroup -n $Ctx.ClusterName @($Ctx.SubArgs) `
            --level Warn --excluded-ns @excludedNsList --only-show-errors 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Host "  Fallback: trying az aks update --safeguards-level..." -ForegroundColor Gray
            $excludedNsComma = $excludedNsList -join ","
            $null = az aks update -g $Ctx.ResourceGroup -n $Ctx.ClusterName @($Ctx.SubArgs) `
                --safeguards-level Warning --safeguards-excluded-ns $excludedNsComma --only-show-errors 2>&1
        }

        if ($LASTEXITCODE -eq 0) {
            $configured = $true
            Write-Host "  Safeguards: Warning mode" -ForegroundColor Green
            Write-Host "  Excluded: $($excludedNsList -join ', ')" -ForegroundColor Gray
        }
        elseif ($retryCount -lt $maxRetries) {
            Write-Host "  Safeguards configuration failed, retrying in 30 seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds 30
        }
    }

    if (-not $configured) {
        Write-Host "  ERROR: Safeguards configuration failed after $maxRetries attempts" -ForegroundColor Red
        exit 1
    }
}

function Wait-ForGatekeeper {
    param($Ctx)

    Write-Host "`n[3/5] Waiting for Gatekeeper controller..." -ForegroundColor Cyan

    if ($env:SKIP_SAFEGUARDS_WAIT -eq "true") {
        Write-Host "  SKIP_SAFEGUARDS_WAIT=true — Bypassing all safeguards checks" -ForegroundColor Yellow
        return
    }

    # Check if Azure Policy add-on is enabled
    Write-Host "  Checking Azure Policy add-on status..." -ForegroundColor Gray
    $policyEnabled = az aks show -g $Ctx.ResourceGroup -n $Ctx.ClusterName @($Ctx.SubArgs) --query "addonProfiles.azurepolicy.enabled" -o tsv 2>$null

    if ($policyEnabled -ne "true") {
        Write-Host "  Azure Policy add-on not enabled — skipping Gatekeeper check" -ForegroundColor Yellow
        return
    }
    Write-Host "  Azure Policy add-on: Enabled" -ForegroundColor Green

    $maxWait = if ($env:SAFEGUARDS_WAIT_TIMEOUT) { [int]$env:SAFEGUARDS_WAIT_TIMEOUT } else { 1200 }
    $interval = 15

    # Wait for gatekeeper-system namespace
    Write-Host "  Checking for Gatekeeper namespace..." -ForegroundColor Gray
    $elapsed = 0
    $nsFound = $false
    while (-not $nsFound -and $elapsed -lt $maxWait) {
        $ns = kubectl get namespace gatekeeper-system --no-headers 2>$null
        if (-not [string]::IsNullOrEmpty($ns)) {
            $nsFound = $true
            Write-Host "  Gatekeeper namespace: Found" -ForegroundColor Green
        }
        else {
            Write-Host "  Waiting for gatekeeper-system namespace... ($elapsed`s)" -ForegroundColor Gray
            Start-Sleep -Seconds $interval
            $elapsed += $interval
        }
    }

    if (-not $nsFound) {
        Write-Host "  ERROR: Gatekeeper namespace not found after ${maxWait}s" -ForegroundColor Red
        Write-Host "  Bypass: SKIP_SAFEGUARDS_WAIT=true azd hooks run postprovision" -ForegroundColor Yellow
        exit 1
    }

    # Wait for Gatekeeper controller deployment
    Write-Host "  Checking Gatekeeper controller status..." -ForegroundColor Gray
    $elapsed = 0
    $ready = $false
    while (-not $ready -and $elapsed -lt $maxWait) {
        # Try gatekeeper-controller (AKS Automatic), then gatekeeper-controller-manager (standard)
        $null = kubectl -n gatekeeper-system rollout status deploy/gatekeeper-controller --timeout=10s 2>&1
        if ($LASTEXITCODE -eq 0) {
            $ready = $true
            Write-Host "  Gatekeeper controller: Ready" -ForegroundColor Green
        }
        else {
            $null = kubectl -n gatekeeper-system rollout status deploy/gatekeeper-controller-manager --timeout=10s 2>&1
            if ($LASTEXITCODE -eq 0) {
                $ready = $true
                Write-Host "  Gatekeeper controller-manager: Ready" -ForegroundColor Green
            }
            else {
                Write-Host "  Waiting for Gatekeeper controller... ($elapsed`s)" -ForegroundColor Gray
                Start-Sleep -Seconds $interval
                $elapsed += $interval
            }
        }
    }

    if (-not $ready) {
        Write-Host "  ERROR: Gatekeeper controller not ready after ${maxWait}s" -ForegroundColor Red
        exit 1
    }
}

function Test-Exclusions {
    param($Ctx)

    Write-Host "`n[4/5] Final verification..." -ForegroundColor Cyan

    if ($env:SKIP_SAFEGUARDS_WAIT -eq "true") {
        Write-Host "  Bypassed" -ForegroundColor Yellow
        return
    }

    if ($script:isAutomatic) {
        Test-ProbeExemption
    }
    else {
        Test-NamespaceExclusions
    }
}

function Test-ProbeExemption {
    Write-Host "  AKS Automatic — verifying probe exemption propagation..." -ForegroundColor Cyan
    Write-Host "  Namespaces will be created by Terraform during deploy" -ForegroundColor Gray

    $maxWaitDefault = 1200
    $maxWait = $maxWaitDefault
    if ($env:SAFEGUARDS_WAIT_TIMEOUT) {
        if (-not [int]::TryParse($env:SAFEGUARDS_WAIT_TIMEOUT, [ref]$maxWait)) {
            Write-Host "  WARNING: SAFEGUARDS_WAIT_TIMEOUT '$($env:SAFEGUARDS_WAIT_TIMEOUT)' is not a valid integer; using default ${maxWaitDefault}s." -ForegroundColor Yellow
            $maxWait = $maxWaitDefault
        }
    }
    $interval = 30
    $elapsed = 0

    # Job that is fully safeguards-compliant EXCEPT for probes.
    # If the probe exemption has propagated, this dry-run succeeds.
    $testJobYaml = @"
apiVersion: batch/v1
kind: Job
metadata:
  name: probe-exemption-test
  namespace: default
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app: probe-exemption-test
      containers:
      - name: test
        image: mcr.microsoft.com/cbl-mariner/base/core:2.0
        command: ["true"]
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
          limits:
            cpu: 100m
            memory: 64Mi
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
      restartPolicy: Never
"@

    while ($elapsed -lt $maxWait) {
        $result = $testJobYaml | kubectl create --dry-run=server -f - 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Probe exemption: Propagated" -ForegroundColor Green
            return
        }
        $output = "$result"
        if ($output -match "livenessProbe|readinessProbe|Probe|probe") {
            Write-Host "  Waiting for probe exemption propagation... ($elapsed`s / $maxWait`s)" -ForegroundColor Gray
            Start-Sleep -Seconds $interval
            $elapsed += $interval
        }
        else {
            Write-Host "  ERROR: kubectl dry-run failed (not probe-related):" -ForegroundColor Red
            Write-Host "  $output" -ForegroundColor DarkGray
            exit 1
        }
    }

    Write-Host "  WARNING: Probe exemption not detected after $maxWait`s" -ForegroundColor Yellow
    Write-Host "  Workloads requiring probe exemption may be blocked by deployment safeguards." -ForegroundColor Yellow
    Write-Host "  Bypass: SKIP_SAFEGUARDS_WAIT=true azd hooks run postprovision" -ForegroundColor Gray
    exit 1
}

function Test-NamespaceExclusions {
    $targetNamespaces = @("foundation", "elasticsearch")

    foreach ($ns in $targetNamespaces) {
        $nsExists = kubectl get namespace $ns --no-headers 2>$null
        if ([string]::IsNullOrEmpty($nsExists)) {
            Write-Host "  Creating namespace: $ns" -ForegroundColor Gray
            $nsResult = kubectl create namespace $ns 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "  ERROR: Failed to create namespace $ns" -ForegroundColor Red
                Write-Host "        $nsResult" -ForegroundColor Gray
                exit 1
            }
        }
    }

    Write-Host "  Verifying namespace exclusions via dry-run..." -ForegroundColor Gray

    # Deployment that triggers multiple policies (no probes, no securityContext, latest tag)
    $testDeploymentYaml = @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: safeguards-test
spec:
  replicas: 2
  selector:
    matchLabels:
      app: safeguards-test
  template:
    metadata:
      labels:
        app: safeguards-test
    spec:
      containers:
      - name: test
        image: nginx:latest
"@

    $allOk = $true
    $failedNs = @()

    foreach ($ns in $targetNamespaces) {
        $result = $testDeploymentYaml | kubectl apply --dry-run=server -n $ns -f - 2>&1
        $exitCode = $LASTEXITCODE
        $isPolicyError = ($result -match "denied|violation|constraint")

        # Retry once for transient (non-policy) errors
        if ($exitCode -ne 0 -and -not $isPolicyError) {
            Write-Host "  RETRY: $ns — transient error, retrying..." -ForegroundColor Yellow
            Start-Sleep -Seconds 2
            $result = $testDeploymentYaml | kubectl apply --dry-run=server -n $ns -f - 2>&1
            $exitCode = $LASTEXITCODE
            $isPolicyError = ($result -match "denied|violation|constraint")
        }

        if ($exitCode -ne 0) {
            $allOk = $false
            $failedNs += $ns
            $label = if ($isPolicyError) { "policy violation" } else { "dry-run error" }
            Write-Host "  FAIL: $ns — $label" -ForegroundColor Red
            Write-Host "        $(($result -split "`n")[0])" -ForegroundColor Gray
        }
        else {
            Write-Host "  OK: $ns — exclusions working" -ForegroundColor Green
        }
    }

    if (-not $allOk) {
        Write-Host "`n  ERROR: Namespace exclusions not effective for: $($failedNs -join ', ')" -ForegroundColor Red
        Write-Host "  Possible causes:" -ForegroundColor Yellow
        Write-Host "    - Another Azure Policy assignment at subscription/management group level" -ForegroundColor Yellow
        Write-Host "    - Azure Policy addon has not reconciled yet (try again in 2-3 min)" -ForegroundColor Yellow
        Write-Host "  Debug:" -ForegroundColor Yellow
        Write-Host "    kubectl get constraints -o json | jq '.items[].spec.match.excludedNamespaces'" -ForegroundColor Yellow
        Write-Host "  Bypass:" -ForegroundColor Yellow
        Write-Host "    SKIP_SAFEGUARDS_WAIT=true azd hooks run postprovision" -ForegroundColor Yellow
        exit 1
    }

    Write-Host "  All namespace exclusions verified" -ForegroundColor Green
}

function Get-PlatformVars {
    param($Ctx)

    $acmeEmail = Get-AzdValue -Name "TF_VAR_acme_email"
    if ([string]::IsNullOrEmpty($acmeEmail)) {
        Write-Host "  WARNING: TF_VAR_acme_email not set, foundation will skip cert-manager issuers" -ForegroundColor Yellow
        $acmeEmail = ""
    }

    $ingressPrefix = Get-AzdValue -Name "SPI_INGRESS_PREFIX"
    $useLetsencryptProd = Get-AzdValue -Name "TF_VAR_use_letsencrypt_production"
    if ([string]::IsNullOrEmpty($useLetsencryptProd)) { $useLetsencryptProd = "false" }

    $enablePublicIngress = Get-AzdValue -Name "TF_VAR_enable_public_ingress"
    if ([string]::IsNullOrEmpty($enablePublicIngress)) { $enablePublicIngress = "true" }

    $dnsZoneName = Get-AzdValue -Name "TF_VAR_dns_zone_name"
    $dnsZoneRg = Get-AzdValue -Name "TF_VAR_dns_zone_resource_group"
    $dnsZoneSubId = Get-AzdValue -Name "TF_VAR_dns_zone_subscription_id"
    $externalDnsClientId = Get-AzdValue -Name "EXTERNAL_DNS_CLIENT_ID"
    $tenantId = Get-AzdValue -Name "AZURE_TENANT_ID"
    $externalDnsZoneAccessEnabled = Get-AzdValue -Name "EXTERNAL_DNS_ZONE_ACCESS_ENABLED"
    if ([string]::IsNullOrEmpty($externalDnsZoneAccessEnabled)) { $externalDnsZoneAccessEnabled = "false" }

    $externalDnsMode = Get-ModeValue -Name "EXTERNAL_DNS_MODE"
    $dnsStatus = Get-AzdValue -Name "SPI_DNS_ZONE_STATUS"
    $dnsReason = Get-AzdValue -Name "SPI_DNS_ZONE_REASON"

    $hasDnsZoneConfig = (-not [string]::IsNullOrEmpty($dnsZoneName)) -and
                        (-not [string]::IsNullOrEmpty($dnsZoneRg)) -and
                        (-not [string]::IsNullOrEmpty($dnsZoneSubId))
    $hasIdentityConfig = (-not [string]::IsNullOrEmpty($externalDnsClientId)) -and
                         (-not [string]::IsNullOrEmpty($tenantId))
    $hasDnsZoneAccess = $externalDnsZoneAccessEnabled -eq "true"
    $enableExternalDns = if ($externalDnsMode -ne "disabled" -and $hasDnsZoneConfig -and $hasIdentityConfig -and $hasDnsZoneAccess) { "true" } else { "false" }

    if ($externalDnsMode -eq "disabled") {
        Write-Host "  ExternalDNS: disabled by EXTERNAL_DNS_MODE" -ForegroundColor Gray
    }
    elseif ($hasDnsZoneConfig -and -not $hasIdentityConfig) {
        Write-Host "  ExternalDNS identity: not provisioned" -ForegroundColor Yellow
    }
    elseif ($hasDnsZoneConfig -and $hasIdentityConfig -and -not $hasDnsZoneAccess) {
        Write-Host "  ExternalDNS access: not bootstrapped" -ForegroundColor Yellow
        $reason = Get-AzdValue -Name "EXTERNAL_DNS_ZONE_ACCESS_REASON"
        if (-not [string]::IsNullOrWhiteSpace($reason)) {
            Write-Host "    $reason" -ForegroundColor Gray
        }
    }
    elseif (($dnsStatus -eq "multiple" -or $dnsStatus -eq "error") -and -not [string]::IsNullOrWhiteSpace($dnsReason)) {
        Write-Host "  ExternalDNS: not selected automatically" -ForegroundColor Yellow
        Write-Host "    $dnsReason" -ForegroundColor Gray
    }

    Write-Host "  ExternalDNS: $(if ($enableExternalDns -eq 'true') { 'enabled' } else { 'disabled' })" -ForegroundColor Gray

    # Capture PaaS outputs from Terraform
    $keyVaultUri = Get-AzdValue -Name "KEY_VAULT_URI"
    $keyVaultName = Get-AzdValue -Name "KEY_VAULT_NAME"
    $commonStorageName = Get-AzdValue -Name "COMMON_STORAGE_NAME"
    $redisHostname = Get-AzdValue -Name "REDIS_HOSTNAME"
    $appInsightsKey = Get-AzdValue -Name "APP_INSIGHTS_KEY"
    $osduIdentityClientId = Get-AzdValue -Name "OSDU_IDENTITY_CLIENT_ID"
    $graphDbEndpoint = Get-AzdValue -Name "GRAPH_DB_ENDPOINT"
    $partitionStorageNames = Get-AzdValue -Name "PARTITION_STORAGE_NAMES"
    $partitionCosmosEndpoints = Get-AzdValue -Name "PARTITION_COSMOS_ENDPOINTS"
    $partitionServicebusNamespaces = Get-AzdValue -Name "PARTITION_SERVICEBUS_NAMESPACES"

    return @{
        AcmeEmail                    = $acmeEmail
        IngressPrefix                = $ingressPrefix
        UseLetsencryptProd           = $useLetsencryptProd
        EnablePublicIngress          = $enablePublicIngress
        DnsZoneName                  = $dnsZoneName
        DnsZoneRg                    = $dnsZoneRg
        DnsZoneSubId                 = $dnsZoneSubId
        ExternalDnsClientId          = $externalDnsClientId
        TenantId                     = $tenantId
        EnableExternalDns            = $enableExternalDns
        KeyVaultUri                  = $keyVaultUri
        KeyVaultName                 = $keyVaultName
        CommonStorageName            = $commonStorageName
        RedisHostname                = $redisHostname
        AppInsightsKey               = $appInsightsKey
        OsduIdentityClientId         = $osduIdentityClientId
        GraphDbEndpoint              = $graphDbEndpoint
        PartitionStorageNames        = $partitionStorageNames
        PartitionCosmosEndpoints     = $partitionCosmosEndpoints
        PartitionServicebusNamespaces = $partitionServicebusNamespaces
    }
}

function Ensure-OptionalCapabilities {
    param(
        $Ctx,
        [hashtable]$Principal
    )

    $result = @{
        FoundationReady = $true
        Reason          = ""
    }

    $grafanaMode = Get-ModeValue -Name "GRAFANA_MODE"
    $externalDnsMode = Get-ModeValue -Name "EXTERNAL_DNS_MODE"

    $grafanaResourceId = Get-AzdValue -Name "GRAFANA_RESOURCE_ID"
    $grafanaPrincipalId = Get-AzdValue -Name "GRAFANA_PRINCIPAL_ID"
    $externalDnsPrincipalId = Get-AzdValue -Name "EXTERNAL_DNS_PRINCIPAL_ID"
    $dnsZoneName = Get-AzdValue -Name "TF_VAR_dns_zone_name"
    $dnsStatus = Get-AzdValue -Name "SPI_DNS_ZONE_STATUS"
    $dnsReason = Get-AzdValue -Name "SPI_DNS_ZONE_REASON"

    if ($grafanaMode -eq "disabled") {
        Set-FeatureState -Prefix "GRAFANA_MONITOR_ACCESS" -Enabled $false -Status "disabled" -Reason "Grafana access is disabled by GRAFANA_MODE=disabled."
        Set-FeatureState -Prefix "GRAFANA_ADMIN_ACCESS" -Enabled $false -Status "disabled" -Reason "Grafana access is disabled by GRAFANA_MODE=disabled."
    }
    elseif ([string]::IsNullOrEmpty($grafanaResourceId) -or [string]::IsNullOrEmpty($grafanaPrincipalId)) {
        $reason = "Grafana workspace was not created in core infrastructure."
        Set-FeatureState -Prefix "GRAFANA_MONITOR_ACCESS" -Enabled $false -Status "skipped" -Reason $reason
        Set-FeatureState -Prefix "GRAFANA_ADMIN_ACCESS" -Enabled $false -Status "skipped" -Reason $reason
        if ($grafanaMode -eq "enabled") {
            Write-Host "  ERROR: $reason" -ForegroundColor Red
            exit 1
        }
    }
    else {
        $grafanaAdminIds = @()
        if ([string]::IsNullOrWhiteSpace($Principal.ObjectId)) {
            $adminReason = "Grafana admin access was skipped because the current principal object ID could not be resolved automatically."
            Set-FeatureState -Prefix "GRAFANA_ADMIN_ACCESS" -Enabled $false -Status "skipped" -Reason $adminReason
            if ($grafanaMode -eq "enabled") {
                Write-Host "  ERROR: $adminReason" -ForegroundColor Red
                exit 1
            }
        }
        else {
            $grafanaAdminIds = @($Principal.ObjectId)
        }

        $grafanaOk = Invoke-BootstrapAccess -GrafanaAdminPrincipalIds $grafanaAdminIds -SkipExternalDnsZoneAccess -SkipCnpgProbeExemption -BestEffort:($grafanaMode -eq "auto")
        if (-not $grafanaOk) {
            Write-Host "  ERROR: Failed while applying Grafana access bootstrap." -ForegroundColor Red
            exit 1
        }
    }

    if ($externalDnsMode -eq "disabled") {
        Set-FeatureState -Prefix "EXTERNAL_DNS_ZONE_ACCESS" -Enabled $false -Status "disabled" -Reason "ExternalDNS is disabled by EXTERNAL_DNS_MODE=disabled."
    }
    elseif ([string]::IsNullOrEmpty($dnsZoneName)) {
        $reason = if (-not [string]::IsNullOrWhiteSpace($dnsReason)) { $dnsReason } else { "No DNS zone is selected for ExternalDNS." }
        Set-FeatureState -Prefix "EXTERNAL_DNS_ZONE_ACCESS" -Enabled $false -Status "skipped" -Reason $reason
        if ($externalDnsMode -eq "enabled") {
            Write-Host "  ERROR: $reason" -ForegroundColor Red
            exit 1
        }
    }
    elseif ([string]::IsNullOrEmpty($externalDnsPrincipalId)) {
        $reason = "ExternalDNS identity was not created in core infrastructure."
        Set-FeatureState -Prefix "EXTERNAL_DNS_ZONE_ACCESS" -Enabled $false -Status "skipped" -Reason $reason
        if ($externalDnsMode -eq "enabled") {
            Write-Host "  ERROR: $reason" -ForegroundColor Red
            exit 1
        }
    }
    else {
        $dnsOk = Invoke-BootstrapAccess -SkipGrafanaMonitorAccess -SkipCnpgProbeExemption -BestEffort:($externalDnsMode -eq "auto")
        if (-not $dnsOk) {
            Write-Host "  ERROR: Failed while applying ExternalDNS access bootstrap." -ForegroundColor Red
            exit 1
        }
    }

    return $result
}

function Show-PostProvisionSummary {
    param(
        $Ctx,
        [Parameter(Mandatory)][bool]$Ready
    )

    $notes = Get-DeferredFeatureNotes

    Write-Host ""
    if ($Ready) {
        Write-Host "==================================================================" -ForegroundColor Green
        Write-Host "  Post-Provision Complete"                                           -ForegroundColor Green
        Write-Host "==================================================================" -ForegroundColor Green
        Write-Host "  Cluster: $($Ctx.ClusterName)" -ForegroundColor Gray
        Write-Host "  Resource Group: $($Ctx.ResourceGroup)" -ForegroundColor Gray
        Write-Host "  Safeguards: ready" -ForegroundColor Gray
        Write-Host "  Foundation: deployed" -ForegroundColor Gray
        if ($notes.Count -gt 0) {
            Write-Host ""
            Write-Host "  Optional features not configured:" -ForegroundColor Yellow
            foreach ($note in $notes) {
                Write-Host "    - $note" -ForegroundColor Gray
            }
        }
        Write-Host ""
        Write-Host "  Next step: azd deploy" -ForegroundColor Gray
    }
    else {
        Write-Host "==================================================================" -ForegroundColor Yellow
        Write-Host "  Post-Provision Incomplete"                                         -ForegroundColor Yellow
        Write-Host "==================================================================" -ForegroundColor Yellow
        Write-Host "  Cluster: $($Ctx.ClusterName)" -ForegroundColor Gray
        Write-Host "  Resource Group: $($Ctx.ResourceGroup)" -ForegroundColor Gray
        Write-Host "  Safeguards: ready" -ForegroundColor Gray
        Write-Host "  Foundation: not deployed" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  After granting access, re-run:" -ForegroundColor Gray
        Write-Host "    azd up" -ForegroundColor Cyan
    }
    Write-Host ""
}
function Clear-FailedHelmReleases {
    Write-Host "  Checking for stuck Helm releases in foundation namespace..." -ForegroundColor Gray

    # Catch releases in failed, uninstalling, or pending-* states
    $allReleases = helm list -n foundation --all --output json 2>$null | ConvertFrom-Json
    if ($null -eq $allReleases -or $allReleases.Count -eq 0) {
        Write-Host "  No releases found" -ForegroundColor Gray
        return
    }

    $stuckReleases = $allReleases | Where-Object { $_.status -notin @("deployed", "superseded") }
    if ($stuckReleases.Count -eq 0) {
        Write-Host "  No stuck releases found" -ForegroundColor Gray
        return
    }

    foreach ($rel in $stuckReleases) {
        $name = $rel.name
        $status = $rel.status
        Write-Host "  Removing $status release: $name" -ForegroundColor Yellow

        # Try normal uninstall first
        helm uninstall $name -n foundation --no-hooks 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Removed: $name" -ForegroundColor Green
            continue
        }

        # If stuck in uninstalling state, delete the Helm secret directly
        Write-Host "  Normal uninstall failed — clearing Helm secret for: $name" -ForegroundColor Yellow
        kubectl delete secret -n foundation -l "name=$name,owner=helm" 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Cleared: $name" -ForegroundColor Green
        }
        else {
            Write-Host "  WARNING: Could not remove $name (may need manual cleanup)" -ForegroundColor Yellow
        }
    }
}

function Deploy-Foundation {
    param($Ctx, $Vars)

    Write-Host "`n[5/5] Deploying Foundation Layer..." -ForegroundColor Cyan

    # Clean up any failed Helm releases from previous runs
    Clear-FailedHelmReleases

    # Ensure Helm repo caches are populated (Terraform Helm provider requires local index files)
    Write-Host "  Updating Helm repository caches..." -ForegroundColor Gray
    $repos = @(
        @{ Name = "jetstack";        Url = "https://charts.jetstack.io" },
        @{ Name = "elastic";         Url = "https://helm.elastic.co" }
    )
    foreach ($repo in $repos) {
        helm repo add $repo.Name $repo.Url 2>&1 | Out-Null
    }
    helm repo update 2>&1 | Out-Null
    Write-Host "  Helm repos ready" -ForegroundColor Green

    Push-Location $PSScriptRoot/../software/foundation

    # Initialize terraform if needed
    if (-not (Test-Path ".terraform")) {
        Write-Host "  Initializing terraform..." -ForegroundColor Gray
        terraform init -upgrade
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  ERROR: Terraform init failed" -ForegroundColor Red
            Pop-Location
            exit 1
        }
    }

    $tfArgs = @(
        "-var=cluster_name=$($Ctx.ClusterName)",
        "-var=resource_group_name=$($Ctx.ResourceGroup)",
        "-var=acme_email=$($Vars.AcmeEmail)",
        "-var=ingress_prefix=$($Vars.IngressPrefix)",
        "-var=enable_public_ingress=$($Vars.EnablePublicIngress)",
        "-var=use_letsencrypt_production=$($Vars.UseLetsencryptProd)",
        "-var=enable_external_dns=$($Vars.EnableExternalDns)",
        "-var=dns_zone_name=$($Vars.DnsZoneName)",
        "-var=dns_zone_resource_group=$($Vars.DnsZoneRg)",
        "-var=dns_zone_subscription_id=$($Vars.DnsZoneSubId)",
        "-var=external_dns_client_id=$($Vars.ExternalDnsClientId)",
        "-var=tenant_id=$($Vars.TenantId)"
    )

    $maxAttempts = 2
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        Write-Host "  Running terraform apply (attempt $attempt/$maxAttempts)..." -ForegroundColor Gray
        terraform apply -auto-approve @tfArgs

        if ($LASTEXITCODE -eq 0) {
            break
        }

        if ($attempt -lt $maxAttempts) {
            Write-Host "  Foundation apply failed (transient errors are common on first deploy)." -ForegroundColor Yellow
            Write-Host "  Cleaning up failed Helm releases before retry..." -ForegroundColor Yellow
            Clear-FailedHelmReleases
            Write-Host "  Retrying in 30 seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds 30
        }
        else {
            Write-Host "  ERROR: Foundation deployment failed after $maxAttempts attempts" -ForegroundColor Red
            Pop-Location
            exit 1
        }
    }

    Write-Host "  Foundation layer deployed" -ForegroundColor Green
    Pop-Location
}

#endregion

# --- Main Flow ---

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "  Post-Provision: Safeguards + Foundation"                           -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

$ctx = Get-ClusterContext
$principal = Get-CurrentPrincipalContext
Write-Host "  Resource Group: $($ctx.ResourceGroup)" -ForegroundColor Gray
Write-Host "  Cluster Name: $($ctx.ClusterName)" -ForegroundColor Gray
if (-not [string]::IsNullOrEmpty($ctx.SubscriptionId)) {
    Write-Host "  Subscription: $($ctx.SubscriptionId)" -ForegroundColor Gray
}
if (-not [string]::IsNullOrWhiteSpace($principal.Name)) {
    Write-Host "  Current Principal: $($principal.Name)" -ForegroundColor Gray
}

$aksBootstrapMode = Get-ModeValue -Name "AKS_BOOTSTRAP_MODE"
$clusterAccessReady = Connect-Cluster -Ctx $ctx -Principal $principal -AksBootstrapMode $aksBootstrapMode
if (-not $clusterAccessReady) {
    $reason = "Foundation deployment was deferred because Kubernetes bootstrap access was not available."
    Set-PostProvisionState -Ready $false -Reason $reason -FoundationDeployed $false -FoundationReason $reason
    Show-BootstrapAccessInstructions -Ctx $ctx -Principal $principal
    Show-PostProvisionSummary -Ctx $ctx -Ready $false
    exit 0
}

Set-Safeguards -Ctx $ctx
$optionalResult = Ensure-OptionalCapabilities -Ctx $ctx -Principal $principal
if (-not $optionalResult.FoundationReady) {
    Set-PostProvisionState -Ready $false -Reason $optionalResult.Reason -FoundationDeployed $false -FoundationReason $optionalResult.Reason
    Show-BootstrapAccessInstructions -Ctx $ctx -Principal $principal
    Show-PostProvisionSummary -Ctx $ctx -Ready $false
    exit 0
}

Wait-ForGatekeeper -Ctx $ctx
Test-Exclusions -Ctx $ctx

$enableFoundation = if ($env:FOUNDATION -eq "false") { $false } else { $true }
if ($enableFoundation) {
    $vars = Get-PlatformVars -Ctx $ctx
    Deploy-Foundation -Ctx $ctx -Vars $vars
    Set-PostProvisionState -Ready $true -Reason "" -FoundationDeployed $true -FoundationReason ""
    Show-PostProvisionSummary -Ctx $ctx -Ready $true
}
else {
    $reason = "Foundation deployment was skipped because FOUNDATION=false."
    Set-PostProvisionState -Ready $false -Reason $reason -FoundationDeployed $false -FoundationReason $reason
    Write-Host "`n[5/5] Foundation deployment skipped (FOUNDATION=false)" -ForegroundColor Yellow
    Show-PostProvisionSummary -Ctx $ctx -Ready $false
}

exit 0
