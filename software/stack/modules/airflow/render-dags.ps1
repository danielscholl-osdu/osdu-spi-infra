#Requires -Version 5.1
<#
.SYNOPSIS
    Render OSDU DAG templates ({| |} markers) with Azure SPI provider values.

.DESCRIPTION
    The upstream OSDU repos use {| VAR |} (Jinja custom delimiters) so that
    Airflow's own {{ }} template expressions pass through unmodified.  This
    script replaces {| |} markers with Azure-appropriate values and injects
    required Python imports (k8s_models).

    Azure SPI variant: uses CLOUD_PROVIDER=azure with workload identity
    authentication on spawned KubernetesPodOperator pods. No Keycloak or
    MinIO references.

.PARAMETER DagsDir
    Path to directory containing DAG .py files.

.PARAMETER OsduNamespace
    OSDU namespace (defaults to "osdu").

.EXAMPLE
    .\render-dags.ps1 -DagsDir "C:\dags" -OsduNamespace "osdu"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$DagsDir,

    [Parameter(Position = 1)]
    [string]$OsduNamespace = 'osdu'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# sub: replace  {| VAR_NAME |}  or  {| VAR_NAME|default(...) |}  with a value
# ---------------------------------------------------------------------------
function Invoke-TemplateSub {
    param(
        [string]$VarName,
        [string]$Value,
        [string]$FilePath
    )
    $content = Get-Content -Path $FilePath -Raw
    $pattern = "\{\|.*?\b$VarName\b.*?\|\}"
    $safeValue = $Value -replace '\$', '$$$$'
    $content = [regex]::Replace($content, $pattern, $safeValue)
    Set-Content -Path $FilePath -Value $content -NoNewline
}

# ---------------------------------------------------------------------------
# Inject import lines before the first airflow import line.
# ---------------------------------------------------------------------------
function Invoke-InjectImports {
    param(
        [string[]]$ImportLines,
        [string]$AirflowPattern,
        [string]$FilePath
    )
    $lines = Get-Content -Path $FilePath
    $injected = $false
    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $lines) {
        if (-not $injected -and $line -match $AirflowPattern) {
            foreach ($imp in $ImportLines) {
                $result.Add($imp)
            }
            $injected = $true
        }
        $result.Add($line)
    }
    Set-Content -Path $FilePath -Value $result
}

# ---------------------------------------------------------------------------
# Shared KubernetesPodOperator kwargs for Azure SPI
# Workload identity SA enables Azure AD token acquisition on spawned pods.
# ---------------------------------------------------------------------------
# K8S_POD_OPERATOR_KWARGS: used by DAGs that accept startup_timeout_seconds as a separate param
$k8sPodKwargsStandard = '{"service_account_name":"workload-identity-sa","labels":{"azure.workload.identity/use":"true"},"container_resources":k8s_models.V1ResourceRequirements(limits={"memory":"1Gi","cpu":"1000m"},requests={"memory":"1Gi","cpu":"200m"}),"startup_timeout_seconds":300}'
# K8S_POD_KWARGS: used by DAGs that pass kwargs directly to KubernetesPodOperator (no startup_timeout_seconds to avoid duplicates)
$k8sPodKwargsLarge = '{"service_account_name":"workload-identity-sa","labels":{"azure.workload.identity/use":"true"},"container_resources":k8s_models.V1ResourceRequirements(limits={"memory":"8Gi","cpu":"1000m"},requests={"memory":"1Gi","cpu":"200m"})}'

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
$pyFiles = Get-ChildItem -Path $DagsDir -Filter '*.py' -File -ErrorAction SilentlyContinue
if (-not $pyFiles) {
    return
}

foreach ($f in $pyFiles) {
    $filePath = $f.FullName

    # Skip files that have no {| markers
    $content = Get-Content -Path $filePath -Raw
    if ($content -notmatch '\{\|') {
        continue
    }

    $base = $f.Name
    Write-Host "  Rendering template: $base"

    switch ($base) {

        'witsml_parser_dag_bootstrap.py' {
            Invoke-TemplateSub -VarName 'DAG_NAME' `
                -Value 'Energistics_xml_ingest' `
                -FilePath $filePath
            Invoke-TemplateSub -VarName 'DOCKER_IMAGE' `
                -Value '{{ var.value.image__witsml_parser }}' `
                -FilePath $filePath
            Invoke-TemplateSub -VarName 'K8S_NAMESPACE' `
                -Value $OsduNamespace `
                -FilePath $filePath

            Invoke-TemplateSub -VarName 'K8S_POD_KWARGS' `
                -Value $k8sPodKwargsLarge `
                -FilePath $filePath

            $envVars = '{"CLOUD_PROVIDER":"azure",' +
                '"OSDU_ANTHOS_STORAGE_URL":"{{ var.value.core__service__storage__url }}",' +
                '"OSDU_ANTHOS_DATASET_URL":"{{ var.value.core__service__dataset__url }}",' +
                '"OSDU_ANTHOS_DATA_PARTITION":"{{ dag_run.conf[''execution_context''][''Payload''][''data-partition-id''] }}"}'
            Invoke-TemplateSub -VarName 'ENV_VARS' `
                -Value $envVars `
                -FilePath $filePath

            Invoke-InjectImports `
                -ImportLines @('from kubernetes.client import models as k8s_models') `
                -AirflowPattern '^import airflow' `
                -FilePath $filePath

            # Rename bootstrap file to final name
            $newPath = Join-Path $DagsDir 'witsml_parser_dag.py'
            Move-Item -Path $filePath -Destination $newPath -Force
        }

        'csv_ingestion_all_steps.py' {
            Invoke-TemplateSub -VarName 'DAG_NAME' `
                -Value 'csv_ingestion' `
                -FilePath $filePath
            Invoke-TemplateSub -VarName 'DOCKER_IMAGE' `
                -Value '{{ var.value.image__csv_parser }}' `
                -FilePath $filePath
            Invoke-TemplateSub -VarName 'NAMESPACE' `
                -Value $OsduNamespace `
                -FilePath $filePath

            Invoke-TemplateSub -VarName 'K8S_POD_OPERATOR_KWARGS' `
                -Value $k8sPodKwargsStandard `
                -FilePath $filePath

            $envVars = '{"CLOUD_PROVIDER":"azure",' +
                '"STORAGE_URL":"{{ var.value.core__service__storage__url }}",' +
                '"SCHEMA_URL":"{{ var.value.core__service__schema__url }}",' +
                '"SEARCH_URL":"{{ var.value.core__service__search__url }}",' +
                '"PARTITION_URL":"{{ var.value.core__service__partition__url }}",' +
                '"UNIT_URL":"{{ var.value.core__service__unit__url }}",' +
                '"FILE_URL":"{{ var.value.core__service__file__host }}",' +
                '"DATASET_URL":"{{ var.value.core__service__dataset__url }}",' +
                '"WORKFLOW_URL":"{{ var.value.core__service__workflow__url }}",' +
                '"data_service_to_use":"file"}'
            Invoke-TemplateSub -VarName 'ENV_VARS' `
                -Value $envVars `
                -FilePath $filePath

            Invoke-InjectImports `
                -ImportLines @('from kubernetes.client import models as k8s_models') `
                -AirflowPattern '^import airflow' `
                -FilePath $filePath
        }

        'segy_to_zgy_ingestion_dag.py' {
            Invoke-TemplateSub -VarName 'DAG_NAME' `
                -Value 'Segy_to_zgy_conversion' `
                -FilePath $filePath
            Invoke-TemplateSub -VarName 'DOCKER_IMAGE' `
                -Value '{{ var.value.image__segy_to_zgy_converter }}' `
                -FilePath $filePath
            Invoke-TemplateSub -VarName 'NAMESPACE' `
                -Value $OsduNamespace `
                -FilePath $filePath
            Invoke-TemplateSub -VarName 'STORAGE_SVC_URL' `
                -Value '{{ var.value.core__service__storage__url }}' `
                -FilePath $filePath
            Invoke-TemplateSub -VarName 'SD_SVC_URL' `
                -Value '{{ var.value.core__service__seismic__url }}' `
                -FilePath $filePath

            Invoke-TemplateSub -VarName 'K8S_POD_OPERATOR_KWARGS' `
                -Value $k8sPodKwargsStandard `
                -FilePath $filePath

            # No MinIO -- Azure Storage is used via the OSDU storage service
            Invoke-TemplateSub -VarName 'EXTRA_ENV_VARS' `
                -Value '{}' `
                -FilePath $filePath

            Invoke-InjectImports `
                -ImportLines @('from kubernetes.client import models as k8s_models') `
                -AirflowPattern '^from airflow' `
                -FilePath $filePath
        }

        'segy_to_vds_ssdms_conversion_dag.py' {
            Invoke-TemplateSub -VarName 'DAG_NAME' `
                -Value 'Segy_to_vds_conversion_sdms' `
                -FilePath $filePath
            Invoke-TemplateSub -VarName 'DOCKER_IMAGE' `
                -Value '{{ var.value.image__segy_to_vds_converter }}' `
                -FilePath $filePath
            Invoke-TemplateSub -VarName 'K8S_NAMESPACE' `
                -Value $OsduNamespace `
                -FilePath $filePath
            Invoke-TemplateSub -VarName 'SEISMIC_STORE_URL' `
                -Value '{{ var.value.core__service__seismic__url }}' `
                -FilePath $filePath

            Invoke-TemplateSub -VarName 'K8S_POD_KWARGS' `
                -Value $k8sPodKwargsLarge `
                -FilePath $filePath

            # No MinIO -- Azure Storage is used via the OSDU storage service
            Invoke-TemplateSub -VarName 'EXTRA_ENV_VARS' `
                -Value '{}' `
                -FilePath $filePath

            Invoke-InjectImports `
                -ImportLines @('from kubernetes.client import models as k8s_models') `
                -AirflowPattern '^from airflow' `
                -FilePath $filePath
        }

        default {
            Write-Host "    Unknown template, removing: $base"
            Remove-Item -Path $filePath -Force
        }
    }
}
