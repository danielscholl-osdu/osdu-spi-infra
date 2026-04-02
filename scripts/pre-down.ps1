#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pre-down cleanup: delete resource group and clear terraform state.
.DESCRIPTION
    Runs before azd down to clean up resources. Deletes the resource group via ARM
    (which destroys everything) and clears terraform state so azd's terraform destroy
    sees an empty state and completes instantly.

    Why not let terraform destroy handle it?
    AKS node pool deletion can take 30+ minutes, exceeding terraform's per-resource
    timeout. ARM handles resource group deletion reliably in the background.
.EXAMPLE
    azd hooks run predown
.EXAMPLE
    ./scripts/pre-down.ps1
#>

#Requires -Version 7.4

$ErrorActionPreference = "Stop"

# Track result for state cleanup decision
$script:rgDeleteInitiated = $false

#region Functions

function Connect-Azure {
    Write-Host "  Checking Azure CLI session..." -ForegroundColor Gray
    $account = az account show -o json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $account) {
        Write-Host "  Azure CLI session expired, launching login..." -ForegroundColor Yellow
        az login | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  ERROR: Azure login failed" -ForegroundColor Red
            exit 1
        }
        $account = az account show -o json 2>$null
    }
    $parsed = $account | ConvertFrom-Json
    Write-Host "  Logged in: $($parsed.user.name) ($($parsed.id))" -ForegroundColor Gray
}

function Remove-DnsRecords {
    Write-Host ""
    Write-Host "=================================================================="
    Write-Host "  [1/3] Cleaning DNS Records"
    Write-Host "=================================================================="

    $dnsZone = $env:TF_VAR_dns_zone_name
    $dnsRg = $env:TF_VAR_dns_zone_resource_group
    $dnsSub = $env:TF_VAR_dns_zone_subscription_id

    if ([string]::IsNullOrEmpty($dnsZone) -or [string]::IsNullOrEmpty($dnsRg)) {
        Write-Host "  No DNS zone configured, skipping" -ForegroundColor Gray
        return
    }

    Write-Host "  DNS Zone: $dnsZone ($dnsRg)" -ForegroundColor Gray

    $clusterName = Get-ClusterName
    if ([string]::IsNullOrEmpty($clusterName)) {
        Write-Host "  Could not determine cluster name, skipping DNS cleanup" -ForegroundColor Yellow
        return
    }

    $subArgs = if (-not [string]::IsNullOrEmpty($dnsSub)) { @("--subscription", $dnsSub) } else { @() }
    $ownerPattern = "external-dns/owner=$([regex]::Escape($clusterName))(,|$)"

    # List TXT record sets and find those owned by this cluster
    $txtJson = az network dns record-set txt list -g $dnsRg -z $dnsZone @subArgs -o json 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  WARNING: Failed to list DNS records in zone '$dnsZone'. Check permissions and zone existence." -ForegroundColor Yellow
        return
    }
    $txtRecords = if ($txtJson) { $txtJson | ConvertFrom-Json } else { @() }

    $ownedNames = [System.Collections.ArrayList]::new()
    foreach ($rec in $txtRecords) {
        if ($rec.name -eq "@") { continue }
        foreach ($entry in $rec.txtRecords) {
            $val = ($entry.value -join "")
            if ($val -match $ownerPattern) {
                [void]$ownedNames.Add($rec.name)
                break
            }
        }
    }

    if ($ownedNames.Count -eq 0) {
        Write-Host "  No DNS records owned by $clusterName" -ForegroundColor Gray
        return
    }

    Write-Host "  Found $($ownedNames.Count) records owned by $clusterName" -ForegroundColor Gray
    foreach ($name in $ownedNames) {
        Remove-DnsRecord -Name $name -Zone $dnsZone -ResourceGroup $dnsRg -SubArgs $subArgs
    }
}

function Get-ClusterName {
    $name = $env:AZURE_AKS_CLUSTER_NAME
    if (-not [string]::IsNullOrEmpty($name)) { return $name }

    $envName = $env:AZURE_ENV_NAME
    if (-not [string]::IsNullOrEmpty($envName)) { return "spi-$envName" }

    return $null
}

function Remove-DnsRecord {
    param(
        [string]$Name,
        [string]$Zone,
        [string]$ResourceGroup,
        [array]$SubArgs
    )

    # Delete A record if it exists
    $aExists = az network dns record-set a show -g $ResourceGroup -z $Zone -n $Name @SubArgs 2>$null
    if ($LASTEXITCODE -eq 0 -and $aExists) {
        az network dns record-set a delete -g $ResourceGroup -z $Zone -n $Name @SubArgs -y 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  WARNING: Failed to delete A record $Name.$Zone" -ForegroundColor Yellow
        }
        else {
            Write-Host "  Removed: $Name.$Zone (A)" -ForegroundColor Gray
        }
    }

    # Delete CNAME record if it exists
    $cnameExists = az network dns record-set cname show -g $ResourceGroup -z $Zone -n $Name @SubArgs 2>$null
    if ($LASTEXITCODE -eq 0 -and $cnameExists) {
        az network dns record-set cname delete -g $ResourceGroup -z $Zone -n $Name @SubArgs -y 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  WARNING: Failed to delete CNAME record $Name.$Zone" -ForegroundColor Yellow
        }
        else {
            Write-Host "  Removed: $Name.$Zone (CNAME)" -ForegroundColor Gray
        }
    }

    # Delete TXT record
    az network dns record-set txt delete -g $ResourceGroup -z $Zone -n $Name @SubArgs -y 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  WARNING: Failed to delete TXT record $Name.$Zone" -ForegroundColor Yellow
    }
    else {
        Write-Host "  Removed: $Name.$Zone (TXT)" -ForegroundColor Gray
    }
}

function Get-ResourceGroupName {
    $rg = $env:AZURE_RESOURCE_GROUP
    if (-not [string]::IsNullOrEmpty($rg)) { return $rg }

    # Fallback: query azd environment (avoids deprecated -state flag)
    $rg = azd env get-value AZURE_RESOURCE_GROUP 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrEmpty($rg)) { return $rg }

    return $null
}

function Remove-ResourceGroup {
    Write-Host ""
    Write-Host "=================================================================="
    Write-Host "  [2/3] Deleting Resource Group"
    Write-Host "=================================================================="

    $resourceGroup = Get-ResourceGroupName

    if ([string]::IsNullOrEmpty($resourceGroup)) {
        Write-Host "  No resource group found, skipping" -ForegroundColor Gray
        $script:rgDeleteInitiated = $true  # Nothing to delete, safe to clear state
        return
    }

    # Check if the resource group still exists
    $rgExists = az group exists -n $resourceGroup 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  WARNING: Failed to check resource group '$resourceGroup' (az auth/subscription issue?)" -ForegroundColor Yellow
        Write-Host "  Attempting delete anyway..." -ForegroundColor Yellow
        az group delete -n $resourceGroup --no-wait -y 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Delete initiated" -ForegroundColor Green
            $script:rgDeleteInitiated = $true
        }
        else {
            Write-Host "  WARNING: Delete command also failed. Resource group may still exist." -ForegroundColor Yellow
            Write-Host "  Run manually: az group delete -n $resourceGroup --no-wait -y" -ForegroundColor Yellow
        }
        return
    }

    if ($rgExists -ne "true") {
        Write-Host "  Resource group '$resourceGroup' not found (already deleted)" -ForegroundColor Gray
        $script:rgDeleteInitiated = $true
        return
    }

    Write-Host "  Resource Group: $resourceGroup" -ForegroundColor Gray
    Write-Host "  Deleting (ARM will handle cleanup in background)..." -ForegroundColor Gray
    az group delete -n $resourceGroup --no-wait -y 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Delete initiated" -ForegroundColor Green
        $script:rgDeleteInitiated = $true
    }
    else {
        Write-Host "  WARNING: Delete command failed, azd will retry via terraform" -ForegroundColor Yellow
    }
}

function Clear-TerraformState {
    Write-Host ""
    Write-Host "=================================================================="
    Write-Host "  [3/3] Clearing Terraform State"
    Write-Host "=================================================================="

    if (-not $script:rgDeleteInitiated) {
        Write-Host "  SKIPPING state cleanup — resource group deletion was not confirmed" -ForegroundColor Yellow
        Write-Host "  Terraform state preserved so 'azd down' can retry destruction" -ForegroundColor Yellow
        return
    }

    $cleared = $false
    $stateFiles = @("terraform.tfstate", "terraform.tfstate.backup")

    # Clear foundation layer state
    $foundationDir = "$PSScriptRoot/../software/foundation"
    foreach ($file in $stateFiles) {
        $path = Join-Path $foundationDir $file
        if (Test-Path $path) {
            Remove-Item -Path $path -Force
            Write-Host "  Removed: foundation/$file" -ForegroundColor Gray
            $cleared = $true
        }
    }

    # Clear stack layer state (config-driven stack)
    $stateDir = "$PSScriptRoot/../software/spi-stack/.tfstate"
    if (Test-Path $stateDir) {
        $stateItems = Get-ChildItem -Path $stateDir -Filter "*.tfstate*" -ErrorAction SilentlyContinue
        foreach ($item in $stateItems) {
            Remove-Item -Path $item.FullName -Force
            Write-Host "  Removed: stack/.tfstate/$($item.Name)" -ForegroundColor Gray
            $cleared = $true
        }
    }

    # Clear cimpl-stack layer state
    $cimplStateDir = "$PSScriptRoot/../software/cimpl-stack/.tfstate"
    if (Test-Path $cimplStateDir) {
        $stateItems = Get-ChildItem -Path $cimplStateDir -Filter "*.tfstate*" -ErrorAction SilentlyContinue
        foreach ($item in $stateItems) {
            Remove-Item -Path $item.FullName -Force
            Write-Host "  Removed: cimpl-stack/.tfstate/$($item.Name)" -ForegroundColor Gray
            $cleared = $true
        }
    }

    # Clear infra-access layer state (local state per cluster)
    $accessStateDir = "$PSScriptRoot/../infra-access/.tfstate"
    if (Test-Path $accessStateDir) {
        $stateItems = Get-ChildItem -Path $accessStateDir -Filter "*.tfstate*" -ErrorAction SilentlyContinue
        foreach ($item in $stateItems) {
            Remove-Item -Path $item.FullName -Force
            Write-Host "  Removed: infra-access/.tfstate/$($item.Name)" -ForegroundColor Gray
            $cleared = $true
        }
    }

    # Clear infra layer state (managed by azd at .azure/<env>/infra/)
    $envName = $env:AZURE_ENV_NAME
    if (-not [string]::IsNullOrEmpty($envName)) {
        $infraDir = "$PSScriptRoot/../.azure/$envName/infra"
        foreach ($file in $stateFiles) {
            $path = Join-Path $infraDir $file
            if (Test-Path $path) {
                Remove-Item -Path $path -Force
                Write-Host "  Removed: .azure/$envName/infra/$file" -ForegroundColor Gray
                $cleared = $true
            }
        }
    }

    if (-not $cleared) {
        Write-Host "  No state files found (already clean)" -ForegroundColor Gray
    }
}

function Show-Summary {
    Write-Host ""
    if ($script:rgDeleteInitiated) {
        Write-Host "==================================================================" -ForegroundColor Green
        Write-Host "  Pre-Down Complete"                                                -ForegroundColor Green
        Write-Host "==================================================================" -ForegroundColor Green
        Write-Host "  Resource group deleting in background via ARM" -ForegroundColor Gray
        Write-Host "  Terraform state cleared for clean next deployment" -ForegroundColor Gray
    }
    else {
        Write-Host "==================================================================" -ForegroundColor Yellow
        Write-Host "  Pre-Down Incomplete"                                              -ForegroundColor Yellow
        Write-Host "==================================================================" -ForegroundColor Yellow
        Write-Host "  Resource group deletion could not be confirmed" -ForegroundColor Yellow
        Write-Host "  Terraform state preserved — azd will attempt terraform destroy" -ForegroundColor Yellow
        Write-Host "  If that also fails, delete manually:" -ForegroundColor Yellow
        Write-Host "    az group delete -n $($env:AZURE_RESOURCE_GROUP) --no-wait -y" -ForegroundColor Yellow
    }
    Write-Host ""
}

#endregion

#region Main

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "  Pre-Down: Resource Cleanup"                                       -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

Connect-Azure
Remove-DnsRecords
Remove-ResourceGroup
Clear-TerraformState
Show-Summary

exit 0

#endregion
