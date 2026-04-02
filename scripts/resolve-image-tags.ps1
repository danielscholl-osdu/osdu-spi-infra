#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Resolves latest OSDU container image tags from the GitLab registry and writes osdu-images.auto.tfvars.

.DESCRIPTION
  Queries the OSDU community GitLab container registry API for each service and
  writes resolved image tags to software/stack/osdu-images.auto.tfvars for Terraform consumption.

  The GitLab cleanup policy prunes old image tags, so hardcoded SHAs go stale.
  This script ensures we always deploy with a tag that exists in the registry.

  Environment variables:
    OSDU_IMAGE_BRANCH         - Branch suffix for image names (default: master)
    OSDU_SKIP_IMAGE_RESOLVE   - Set to "true" to skip resolution entirely

.EXAMPLE
  # Resolve latest master branch images (default)
  ./scripts/resolve-image-tags.ps1

  # Use a release branch
  $env:OSDU_IMAGE_BRANCH = "release-0-27"
  ./scripts/resolve-image-tags.ps1
#>

param(
    [string]$OutputDir = "$PSScriptRoot/../software/stack"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Skip gate ---

if ($env:OSDU_SKIP_IMAGE_RESOLVE -eq "true") {
    Write-Host "  Skipping OSDU image tag resolution (OSDU_SKIP_IMAGE_RESOLVE=true)" -ForegroundColor Yellow
    return
}

# --- Image registry ---
# Maps service_name -> { project_id, image_name (without branch suffix) }
# Project IDs from community.opengroup.org GitLab

$ImageRegistry = [ordered]@{
    partition      = @{ project_id = 221;  image = "partition" }
    entitlements   = @{ project_id = 400;  image = "entitlements" }
    legal          = @{ project_id = 74;   image = "legal" }
    schema         = @{ project_id = 26;   image = "schema-service" }
    storage        = @{ project_id = 44;   image = "storage" }
    search         = @{ project_id = 19;   image = "search-service" }
    indexer        = @{ project_id = 25;   image = "indexer-service" }
    indexer_queue  = @{ project_id = 73;   image = "indexer-queue" }
    file           = @{ project_id = 90;   image = "file" }
    workflow       = @{ project_id = 146;  image = "ingestion-workflow" }
    crs_conversion = @{ project_id = 22;   image = "crs-conversion-service" }
    crs_catalog    = @{ project_id = 21;   image = "crs-catalog-service" }
    unit           = @{ project_id = 5;    image = "unit-service" }

    # Core extended services
    notification    = @{ project_id = 143;  image = "notification" }
    dataset         = @{ project_id = 118;  image = "dataset" }
    register        = @{ project_id = 157;  image = "register" }
    policy          = @{ project_id = 420;  image = "policy" }
    secret          = @{ project_id = 723;  image = "secret"; branch = "main" }

    # DDMS services
    wellbore        = @{ project_id = 98;   image = "wellbore-domain-services" }
    wellbore_worker = @{ project_id = 1384; image = "wellbore-domain-services-worker"; branch = "main" }
    eds_dms         = @{ project_id = 1247; image = "eds-dms" }
    oetp_server     = @{ project_id = 828;  image = "open-etp-server"; branch = "main" }
}

$Branch = if ($env:OSDU_IMAGE_BRANCH) { $env:OSDU_IMAGE_BRANCH } else { "master" }
$GitLabHost = "https://community.opengroup.org"

# --- Resolve tags ---

Write-Host ""
Write-Host "  Resolving OSDU container image tags (branch: $Branch)..." -ForegroundColor Cyan
Write-Host ""

$ResolvedImages = [ordered]@{}
$Errors = @()

foreach ($svc in $ImageRegistry.Keys) {
    $entry = $ImageRegistry[$svc]
    $svcBranch = if ($entry.ContainsKey("branch")) { $entry.branch } else { $Branch }
    $imageName = "$($entry.image)-$svcBranch"

    try {
        # List registry repositories for this project
        $reposUrl = "$GitLabHost/api/v4/projects/$($entry.project_id)/registry/repositories"
        $repos = Invoke-RestMethod -Uri $reposUrl -TimeoutSec 10

        # Find the repository matching our image name
        $repo = $repos | Where-Object { $_.name -eq $imageName } | Select-Object -First 1

        if (-not $repo) {
            Write-Host "    WARN: $svc - image '$imageName' not found in registry" -ForegroundColor Yellow
            $Errors += $svc
            continue
        }

        # Get the latest tag (first one returned)
        $tagsUrl = "$GitLabHost/api/v4/projects/$($entry.project_id)/registry/repositories/$($repo.id)/tags?per_page=1"
        $tags = Invoke-RestMethod -Uri $tagsUrl -TimeoutSec 10

        if ($tags.Count -eq 0) {
            Write-Host "    WARN: $svc - no tags found for '$imageName'" -ForegroundColor Yellow
            $Errors += $svc
            continue
        }

        $tag = $tags[0].name
        $repository = $repo.location -replace ":$tag$", ""

        $ResolvedImages[$svc] = @{
            repository = $repository
            tag        = $tag
        }

        $shortTag = $tag.Substring(0, [Math]::Min(12, $tag.Length))
        Write-Host "    $($svc.PadRight(20)) -> $shortTag" -ForegroundColor Green
    }
    catch {
        Write-Host "    WARN: $svc - failed to query registry: $_" -ForegroundColor Yellow
        $Errors += $svc
    }
}

if ($ResolvedImages.Count -eq 0) {
    Write-Host ""
    Write-Host "  ERROR: No image tags could be resolved. Check network connectivity to community.opengroup.org." -ForegroundColor Red
    exit 1
}

# --- Write output ---

$OutputFile = Join-Path (Resolve-Path $OutputDir) "osdu-images.auto.tfvars"

$lines = @()
$lines += "# Auto-generated by resolve-image-tags.ps1 -- do not edit manually"
$lines += "# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC' -AsUTC)"
$lines += "# Branch: $Branch"
$lines += ""
$lines += "osdu_image_overrides = {"

foreach ($svc in $ResolvedImages.Keys) {
    $img = $ResolvedImages[$svc]
    $lines += "  $($svc.PadRight(20)) = { repository = `"$($img.repository)`", tag = `"$($img.tag)`" }"
}

$lines += "}"

$content = $lines -join "`n"
Set-Content -Path $OutputFile -Value $content -NoNewline

Write-Host ""
Write-Host "  Wrote $($ResolvedImages.Count) image tags to:" -ForegroundColor Cyan
Write-Host "    $OutputFile"

if ($Errors.Count -gt 0) {
    Write-Host ""
    Write-Host "  WARNING: $($Errors.Count) service(s) could not be resolved: $($Errors -join ', ')" -ForegroundColor Yellow
    Write-Host "  These services will use the hardcoded defaults in locals.tf" -ForegroundColor Yellow
}

Write-Host ""
