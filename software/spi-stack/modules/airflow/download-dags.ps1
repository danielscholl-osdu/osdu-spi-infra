#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Download OSDU DAGs from GitLab repos and create a Kubernetes ConfigMap.
.DESCRIPTION
    Downloads DAG files from OSDU ingestion repositories, processes them
    (removes non-DAG helpers, IBM/cloud-specific files), renders templates
    via render-dags.ps1, and creates the ingestion-dags ConfigMap.

    This is the PowerShell equivalent of the inline bash provisioner in
    the null_resource.ingestion_dags Terraform resource.
.PARAMETER DagsBase
    Base URL for the DAG repositories
    (e.g., "https://community.opengroup.org/osdu/platform/data-flow/ingestion").
.PARAMETER DagsRef
    Git ref/branch to download (e.g., "master" or "v0.27.0").
.PARAMETER DagsSources
    JSON string mapping repo paths to subdirectories containing DAG .py files.
.PARAMETER OsduNamespace
    OSDU namespace used for template rendering (e.g., "osdu").
.PARAMETER Namespace
    Kubernetes namespace for the ConfigMap (e.g., "platform").
.PARAMETER ScriptDir
    Path to the module directory (for locating render-dags.ps1).
#>

#Requires -Version 7.4

param(
    [Parameter(Mandatory)]
    [string]$DagsBase,

    [Parameter(Mandatory)]
    [string]$DagsRef,

    [Parameter(Mandatory)]
    [string]$DagsSources,

    [Parameter(Mandatory)]
    [string]$OsduNamespace,

    [Parameter(Mandatory)]
    [string]$Namespace,

    [Parameter(Mandatory)]
    [string]$ScriptDir
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Create temporary working directory
# ---------------------------------------------------------------------------
$Work = Join-Path ([System.IO.Path]::GetTempPath()) "dags-$([System.IO.Path]::GetRandomFileName())"
$Dags = Join-Path $Work "collected"
New-Item -ItemType Directory -Path $Dags -Force | Out-Null

try {
    # Parse the JSON mapping of repo -> subdirectory
    $sources = $DagsSources | ConvertFrom-Json -AsHashtable

    # -----------------------------------------------------------------------
    # download_dags - download and extract DAG .py files from a single repo
    # -----------------------------------------------------------------------
    function Download-Dags {
        param(
            [string]$Repo,
            [string]$Subdir
        )

        # Extract the leaf name from the repo path (e.g., "csv-parser/csv-parser" -> "csv-parser")
        $name = ($Repo -split '/')[-1]
        $url = "$DagsBase/$Repo/-/archive/$DagsRef/$name-$DagsRef.tar.gz"
        $archivePath = Join-Path $Work "$name.tar.gz"

        Write-Host "  Fetching $Repo @ $DagsRef ..."

        try {
            Invoke-WebRequest -Uri $url -OutFile $archivePath -UseBasicParsing -ErrorAction Stop
        }
        catch {
            Write-Host "    WARNING: download failed (ref '$DagsRef' may not exist for this repo)"
            return
        }

        # Extract the archive using tar (available on Windows 10+)
        tar -xzf $archivePath -C $Work
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    WARNING: tar extraction failed"
            return
        }

        # Find the subdirectory within the extracted archive
        # The archive extracts to a folder named like "<name>-<ref>"
        $extractedDirs = Get-ChildItem -Path $Work -Directory -Filter "$name-*" -ErrorAction SilentlyContinue
        $srcDir = $null
        foreach ($dir in $extractedDirs) {
            $candidate = Get-ChildItem -Path $dir.FullName -Recurse -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -replace '\\', '/' -like "*/$Subdir" } |
                Select-Object -First 1
            if ($candidate) {
                $srcDir = $candidate.FullName
                break
            }
        }

        if (-not $srcDir) {
            Write-Host "    WARNING: subdir $Subdir not found"
            return
        }

        # Copy .py files from the source directory to the collected directory
        $pyFiles = Get-ChildItem -Path $srcDir -Filter "*.py" -File -ErrorAction SilentlyContinue
        $count = 0
        foreach ($f in $pyFiles) {
            Copy-Item -Path $f.FullName -Destination $Dags -Force
            $count++
        }

        if ($count -gt 0) {
            Write-Host "    OK: $count files"
        }
        else {
            Write-Host "    WARNING: no .py files in $Subdir"
        }
    }

    # -----------------------------------------------------------------------
    # Download DAGs from all configured repos
    # -----------------------------------------------------------------------
    Write-Host "Downloading OSDU DAGs (ref: $DagsRef)..."

    foreach ($entry in $sources.GetEnumerator()) {
        Download-Dags -Repo $entry.Key -Subdir $entry.Value
    }

    # -----------------------------------------------------------------------
    # Remove non-DAG helper files and IBM-specific variants
    # -----------------------------------------------------------------------
    $removeFiles = @("__init__.py", "output_dag_folder.py", "render_dag_file.py")
    foreach ($name in $removeFiles) {
        $path = Join-Path $Dags $name
        if (Test-Path $path) {
            Remove-Item -Path $path -Force
        }
    }

    # Remove IBM-specific variants (*_ibm.py)
    Get-ChildItem -Path $Dags -Filter "*_ibm.py" -File -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-Item -Path $_.FullName -Force }

    # -----------------------------------------------------------------------
    # Remove cloud-specific DAGs that import provider modules or need
    # provider config files.  We use the template variants instead.
    # -----------------------------------------------------------------------
    $cloudSpecificFiles = @("witsml_parser_dag.py", "segy_to_vds_conversion_dag.py")
    foreach ($name in $cloudSpecificFiles) {
        $path = Join-Path $Dags $name
        if (Test-Path $path) {
            Remove-Item -Path $path -Force
        }
    }

    # -----------------------------------------------------------------------
    # Render {| |} template DAGs with baremetal values
    # -----------------------------------------------------------------------
    $renderScript = Join-Path $ScriptDir "render-dags.ps1"
    if (Test-Path $renderScript) {
        & pwsh -File $renderScript -DagsDir $Dags -OsduNamespace $OsduNamespace
        if ($LASTEXITCODE -ne 0) {
            Write-Error "render-dags.ps1 failed with exit code $LASTEXITCODE"
        }
    }
    else {
        Write-Warning "render-dags.ps1 not found at $renderScript, skipping template rendering"
    }

    # -----------------------------------------------------------------------
    # Build ConfigMap from collected DAGs
    # -----------------------------------------------------------------------
    $dagFiles = Get-ChildItem -Path $Dags -Filter "*.py" -File -ErrorAction SilentlyContinue

    if ($dagFiles -and $dagFiles.Count -gt 0) {
        # Build the --from-file arguments
        $fromFileArgs = @()
        foreach ($f in $dagFiles) {
            $fromFileArgs += "--from-file=$($f.FullName)"
        }

        # Delete existing ConfigMap (ignore if not found)
        kubectl delete configmap ingestion-dags -n $Namespace --ignore-not-found
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Failed to delete existing ingestion-dags ConfigMap (may not exist)"
        }

        # Create the new ConfigMap
        kubectl create configmap ingestion-dags -n $Namespace @fromFileArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to create ingestion-dags ConfigMap"
        }

        Write-Host "Created ingestion-dags ConfigMap with $($dagFiles.Count) DAGs"

        # Restart Airflow pods so init containers pick up the updated ConfigMap
        Write-Host "Restarting Airflow pods to load new DAGs..."
        kubectl rollout restart deployment -n $Namespace -l component=webserver 2>$null
        kubectl rollout restart deployment -n $Namespace -l component=scheduler 2>$null
        kubectl rollout restart deployment -n $Namespace -l component=triggerer 2>$null
    }
    else {
        Write-Warning "No DAG files collected"
    }
}
finally {
    # Clean up temporary directory
    if (Test-Path $Work) {
        Remove-Item -Path $Work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
