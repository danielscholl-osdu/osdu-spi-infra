#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Post-down cleanup: remove Terraform working directories and stale artifacts.
.DESCRIPTION
    Runs after azd down to clean up .terraform/ directories, local .tfstate/
    directories, and any remaining state backup files across all Terraform layers.
    Committed lock files are preserved in the repository.
.EXAMPLE
    azd hooks run postdown
.EXAMPLE
    ./scripts/post-down.ps1
#>

#Requires -Version 7.4

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "  Post-Down: Cleaning Terraform Artifacts"                          -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

$repoRoot = (Resolve-Path "$PSScriptRoot/..").Path
$cleaned = $false

# Terraform layers to clean
$layers = @(
    @{ Path = "infra";               Label = "infra";               RemoveLockfile = $false },
    @{ Path = "infra-access";        Label = "infra-access";        RemoveLockfile = $false },
    @{ Path = "software/foundation"; Label = "foundation";          RemoveLockfile = $false },
    @{ Path = "software/spi-stack";   Label = "spi-stack";           RemoveLockfile = $false },
    @{ Path = "software/cimpl-stack"; Label = "cimpl-stack";         RemoveLockfile = $false }
)

# Add azd-managed infra state directory if env is known
$envName = $env:AZURE_ENV_NAME
if (-not [string]::IsNullOrEmpty($envName)) {
    $layers += @{ Path = ".azure/$envName/infra"; Label = ".azure/$envName/infra"; RemoveLockfile = $true }
}

foreach ($layer in $layers) {
    $dir = Join-Path $repoRoot $layer.Path
    if (-not (Test-Path $dir)) { continue }

    # Remove .terraform/ directory
    $tfDir = Join-Path $dir ".terraform"
    if (Test-Path $tfDir) {
        Remove-Item -Path $tfDir -Recurse -Force
        Write-Host "  Removed: $($layer.Label)/.terraform/" -ForegroundColor Gray
        $cleaned = $true
    }

    # Remove lockfiles only from ephemeral azd state directories.
    if ($layer.RemoveLockfile) {
        $lockFile = Join-Path $dir ".terraform.lock.hcl"
        if (Test-Path $lockFile) {
            Remove-Item -Path $lockFile -Force
            Write-Host "  Removed: $($layer.Label)/.terraform.lock.hcl" -ForegroundColor Gray
            $cleaned = $true
        }
    }

    # Remove local .tfstate/ directories created by repo-managed Terraform roots.
    $localStateDir = Join-Path $dir ".tfstate"
    if (Test-Path $localStateDir) {
        Remove-Item -Path $localStateDir -Recurse -Force
        Write-Host "  Removed: $($layer.Label)/.tfstate/" -ForegroundColor Gray
        $cleaned = $true
    }

    # Remove stale .tfstate backup files (e.g., terraform.tfstate.1234567890.backup)
    $backups = Get-ChildItem -Path $dir -Filter "*.tfstate.*.backup" -ErrorAction SilentlyContinue
    foreach ($backup in $backups) {
        Remove-Item -Path $backup.FullName -Force
        Write-Host "  Removed: $($layer.Label)/$($backup.Name)" -ForegroundColor Gray
        $cleaned = $true
    }

    # Remove stale .tfstate files at root of layer (not in .tfstate/ subdirs)
    $stateFiles = Get-ChildItem -Path $dir -Filter "terraform.tfstate*" -ErrorAction SilentlyContinue
    foreach ($sf in $stateFiles) {
        Remove-Item -Path $sf.FullName -Force
        Write-Host "  Removed: $($layer.Label)/$($sf.Name)" -ForegroundColor Gray
        $cleaned = $true
    }
}

# Clean generated osdu-versions.auto.tfvars (created by prerestore hook)
$osduVersionsFile = Join-Path $repoRoot "software/spi-stack/osdu-versions.auto.tfvars"
if (Test-Path $osduVersionsFile) {
    Remove-Item -Path $osduVersionsFile -Force
    Write-Host "  Removed: stack/osdu-versions.auto.tfvars" -ForegroundColor Gray
    $cleaned = $true
}

if (-not $cleaned) {
    Write-Host "  Already clean — no artifacts found" -ForegroundColor Gray
}

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Green
Write-Host "  Post-Down Complete"                                               -ForegroundColor Green
Write-Host "==================================================================" -ForegroundColor Green
Write-Host ""

exit 0
