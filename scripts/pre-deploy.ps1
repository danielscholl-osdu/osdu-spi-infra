#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pre-deploy: deploy stack (config-driven via STACK_NAME).
.DESCRIPTION
    Runs before service deployment (azd deploy) to deploy the stack
    (OSDU services on Azure PaaS).

    Stack naming is config-driven:
    - No STACK_NAME -> namespaces: platform, osdu (state: default.tfstate)
    - STACK_NAME=blue -> namespaces: platform-blue, osdu-blue (state: blue.tfstate)

    Foundation is deployed during post-provision (azd provision).

    Prerequisites:
    - Cluster provisioned (azd provision)
    - Safeguards configured and foundation deployed (post-provision)
    - Environment variables set: TF_VAR_acme_email, SPI_INGRESS_PREFIX
.EXAMPLE
    azd deploy
.EXAMPLE
    azd env set STACK_NAME blue && azd deploy
.EXAMPLE
    azd hooks run predeploy
.EXAMPLE
    ./scripts/pre-deploy.ps1
#>

#Requires -Version 7.4

$ErrorActionPreference = "Stop"

#region Functions

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

function Get-ClusterContext {
    $resourceGroup = Get-AzdValue -Name "AZURE_RESOURCE_GROUP"
    $clusterName = Get-AzdValue -Name "AZURE_AKS_CLUSTER_NAME"
    $subscriptionId = Get-AzdValue -Name "AZURE_SUBSCRIPTION_ID"

    if ([string]::IsNullOrEmpty($subscriptionId)) {
        Write-Host "  Subscription ID not provided; falling back to current az account..." -ForegroundColor Gray
        $subscriptionId = az account show --query id -o tsv 2>$null
    }

    if ([string]::IsNullOrEmpty($resourceGroup) -or [string]::IsNullOrEmpty($clusterName)) {
        Write-Host "  ERROR: Could not determine resource group or cluster name" -ForegroundColor Red
        exit 1
    }

    Write-Host "  Resource Group: $resourceGroup" -ForegroundColor Gray
    Write-Host "  Cluster: $clusterName" -ForegroundColor Gray
    if (-not [string]::IsNullOrEmpty($subscriptionId)) {
        Write-Host "  Subscription: $subscriptionId" -ForegroundColor Gray
    }

    return @{
        ResourceGroup  = $resourceGroup
        ClusterName    = $clusterName
        SubscriptionId = $subscriptionId
        SubArgs        = if (-not [string]::IsNullOrEmpty($subscriptionId)) { @("--subscription", $subscriptionId) } else { @() }
    }
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

function Show-CoreOnlySummary {
    param([hashtable]$Ctx)

    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor Yellow
    Write-Host "  Deploy Skipped — post-provision did not complete"                  -ForegroundColor Yellow
    Write-Host "==================================================================" -ForegroundColor Yellow
    Write-Host "  Cluster: $($Ctx.ClusterName)" -ForegroundColor Gray
    Write-Host "  Resource Group: $($Ctx.ResourceGroup)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  The foundation layer was not deployed during provisioning." -ForegroundColor Yellow
    Write-Host "  This usually means the current user needs 'Azure Kubernetes Service RBAC Cluster Admin'" -ForegroundColor Yellow
    Write-Host "  on the cluster. See post-provision output above for the az command to grant it." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  After granting access, re-run:" -ForegroundColor Gray
    Write-Host "    azd up" -ForegroundColor Cyan
    Write-Host ""
}

function Connect-Cluster {
    param([hashtable]$Ctx)

    Write-Host ""
    Write-Host "=================================================================="
    Write-Host "  [1/3] Verifying Cluster Access"
    Write-Host "=================================================================="

    $nodes = kubectl get nodes --no-headers 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Kubeconfig not configured, configuring now..." -ForegroundColor Yellow
        az aks get-credentials -g $Ctx.ResourceGroup -n $Ctx.ClusterName @($Ctx.SubArgs) --overwrite-existing
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  ERROR: Failed to configure kubeconfig for stack deployment" -ForegroundColor Red
            exit 1
        }
        kubelogin convert-kubeconfig -l azurecli
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  ERROR: Failed to convert kubeconfig for Azure CLI auth" -ForegroundColor Red
            exit 1
        }
        $nodes = kubectl get nodes --no-headers 2>$null
    }
    $nodeCount = ($nodes -split "`n" | Where-Object { $_ }).Count
    Write-Host "  Cluster access verified ($nodeCount nodes)" -ForegroundColor Green
}

function Get-StackName {
    $stackName = Get-AzdValue -Name "STACK_NAME"
    return $stackName
}

function Get-PlatformVars {
    param([hashtable]$Ctx)

    $acmeEmail = Get-AzdValue -Name "TF_VAR_acme_email"
    if ([string]::IsNullOrEmpty($acmeEmail)) {
        Write-Host "  ERROR: Missing TF_VAR_acme_email" -ForegroundColor Red
        Write-Host "    Set with: azd env set TF_VAR_acme_email 'you@example.com'" -ForegroundColor Gray
        exit 1
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

    Write-Host "  LetsEncrypt issuer: $(if ($useLetsencryptProd -eq 'true') { 'production' } else { 'staging' })" -ForegroundColor Gray
    Write-Host "  ExternalDNS: $(if ($enableExternalDns -eq 'true') { 'enabled' } else { 'disabled' })" -ForegroundColor Gray

    # Collect Azure PaaS outputs
    $keyVaultUri = Get-AzdValue -Name "KEY_VAULT_URI"
    $keyVaultName = Get-AzdValue -Name "KEY_VAULT_NAME"
    $cosmosdbEndpoint = Get-AzdValue -Name "GRAPH_DB_ENDPOINT"
    $storageAccountName = Get-AzdValue -Name "PARTITION_STORAGE_NAMES"
    $commonStorageName = Get-AzdValue -Name "COMMON_STORAGE_NAME"
    $servicebusNamespace = Get-AzdValue -Name "PARTITION_SERVICEBUS_NAMESPACES"
    $redisPassword = Get-AzdValue -Name "TF_VAR_redis_password"
    $postgresqlPassword = Get-AzdValue -Name "TF_VAR_postgresql_password"
    $airflowDbPassword = Get-AzdValue -Name "TF_VAR_airflow_db_password"
    $appInsightsKey = Get-AzdValue -Name "APP_INSIGHTS_KEY"
    $osduIdentityClientId = Get-AzdValue -Name "OSDU_IDENTITY_CLIENT_ID"
    $dataPartition = Get-AzdValue -Name "TF_VAR_data_partition"
    if ([string]::IsNullOrEmpty($dataPartition)) { $dataPartition = "opendes" }

    return @{
        AcmeEmail            = $acmeEmail
        IngressPrefix        = $ingressPrefix
        UseLetsencryptProd   = $useLetsencryptProd
        EnablePublicIngress  = $enablePublicIngress
        DnsZoneName          = $dnsZoneName
        DnsZoneRg            = $dnsZoneRg
        DnsZoneSubId         = $dnsZoneSubId
        ExternalDnsClientId  = $externalDnsClientId
        TenantId             = $tenantId
        EnableExternalDns    = $enableExternalDns
        KeyVaultUri          = $keyVaultUri
        KeyVaultName         = $keyVaultName
        CosmosdbEndpoint     = $cosmosdbEndpoint
        StorageAccountName   = $storageAccountName
        CommonStorageName    = $commonStorageName
        ServicebusNamespace  = $servicebusNamespace
        RedisPassword        = $redisPassword
        PostgresqlPassword   = $postgresqlPassword
        AirflowDbPassword    = $airflowDbPassword
        AppInsightsKey       = $appInsightsKey
        OsduIdentityClientId = $osduIdentityClientId
        DataPartition        = $dataPartition
    }
}

function Deploy-Stack {
    param([hashtable]$Ctx, [hashtable]$Vars, [string]$StackName)

    $displayName = if ([string]::IsNullOrEmpty($StackName)) { "default" } else { $StackName }
    $stateFile = if ([string]::IsNullOrEmpty($StackName)) { "default" } else { $StackName }

    Write-Host ""
    Write-Host "=================================================================="
    Write-Host "  [2/3] Deploying Stack ($displayName)"
    Write-Host "=================================================================="

    # Ensure Helm repo caches are populated (Terraform Helm provider requires local index files)
    Write-Host "  Updating Helm repository caches..." -ForegroundColor Gray
    $repos = @(
        @{ Name = "apache-airflow"; Url = "https://airflow.apache.org" }
    )
    foreach ($repo in $repos) {
        helm repo add $repo.Name $repo.Url 2>&1 | Out-Null
    }
    helm repo update 2>&1 | Out-Null
    Write-Host "  Helm repos ready" -ForegroundColor Green

    Push-Location $PSScriptRoot/../software/stack
    if (-not (Test-Path ".tfstate")) { New-Item -ItemType Directory -Path ".tfstate" | Out-Null }

    Write-Host "  Initializing terraform (state: $stateFile.tfstate)..." -ForegroundColor Gray
    terraform init -reconfigure -backend-config="path=.tfstate/$stateFile.tfstate"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ERROR: Terraform init failed" -ForegroundColor Red
        Pop-Location
        exit 1
    }

    $tfArgs = @(
        "-auto-approve", "-parallelism=4",
        "-var=stack_id=$StackName",
        "-var=cluster_name=$($Ctx.ClusterName)",
        "-var=resource_group_name=$($Ctx.ResourceGroup)",
        "-var=acme_email=$($Vars.AcmeEmail)",
        "-var=ingress_prefix=$($Vars.IngressPrefix)",
        "-var=use_letsencrypt_production=$($Vars.UseLetsencryptProd)",
        "-var=enable_external_dns=$($Vars.EnableExternalDns)",
        "-var=dns_zone_name=$($Vars.DnsZoneName)",
        "-var=dns_zone_resource_group=$($Vars.DnsZoneRg)",
        "-var=dns_zone_subscription_id=$($Vars.DnsZoneSubId)",
        "-var=external_dns_client_id=$($Vars.ExternalDnsClientId)",
        "-var=tenant_id=$($Vars.TenantId)",
        "-var=keyvault_uri=$($Vars.KeyVaultUri)",
        "-var=keyvault_name=$($Vars.KeyVaultName)",
        "-var=cosmosdb_endpoint=$($Vars.CosmosdbEndpoint)",
        "-var=storage_account_name=$($Vars.StorageAccountName)",
        "-var=common_storage_name=$($Vars.CommonStorageName)",
        "-var=servicebus_namespace=$($Vars.ServicebusNamespace)",
        "-var=redis_password=$($Vars.RedisPassword)",
        "-var=postgresql_password=$($Vars.PostgresqlPassword)",
        "-var=airflow_db_password=$($Vars.AirflowDbPassword)",
        "-var=appinsights_key=$($Vars.AppInsightsKey)",
        "-var=osdu_identity_client_id=$($Vars.OsduIdentityClientId)",
        "-var=data_partition=$($Vars.DataPartition)"
    )

    $platformNs = if ([string]::IsNullOrEmpty($StackName)) { "platform" } else { "platform-$StackName" }
    $osduNs = if ([string]::IsNullOrEmpty($StackName)) { "osdu" } else { "osdu-$StackName" }

    $maxAttempts = 3
    $attempt = 0
    $success = $false

    while (-not $success -and $attempt -lt $maxAttempts) {
        $attempt++
        if ($attempt -gt 1) {
            # Clean up Helm releases left in 'failed' or 'pending-install' state
            # by the previous attempt. These are not tracked in Terraform state,
            # so a retry would fail with "cannot re-use a name that is still in use".
            foreach ($ns in @($platformNs, $osduNs)) {
                $failed = helm list -n $ns --failed --pending --short 2>$null
                foreach ($rel in ($failed -split "`n" | Where-Object { $_ })) {
                    Write-Host "  Cleaning up orphaned helm release: $rel (namespace: $ns)" -ForegroundColor Yellow
                    helm uninstall $rel -n $ns 2>$null
                }
            }

            Write-Host "  Retrying terraform apply (attempt $attempt/$maxAttempts) after transient error..." -ForegroundColor Yellow
            Start-Sleep -Seconds 10
        } else {
            Write-Host "  Running terraform apply..." -ForegroundColor Gray
        }

        terraform apply @tfArgs

        if ($LASTEXITCODE -eq 0) {
            $success = $true
        } elseif ($attempt -lt $maxAttempts) {
            Write-Host "  Terraform apply failed (attempt $attempt/$maxAttempts), will retry..." -ForegroundColor Yellow
        }
    }

    if (-not $success) {
        Write-Host "  ERROR: Stack ($displayName) deployment failed after $maxAttempts attempts" -ForegroundColor Red
        Pop-Location
        exit 1
    }

    Write-Host "  Stack ($displayName) deployed" -ForegroundColor Green
    Pop-Location
}

function Test-Deployment {
    param([hashtable]$Vars, [string]$StackName)

    $platformNs = if ([string]::IsNullOrEmpty($StackName)) { "platform" } else { "platform-$StackName" }

    Write-Host ""
    Write-Host "=================================================================="
    Write-Host "  [3/3] Verifying Deployment"
    Write-Host "=================================================================="

    Write-Host "  Waiting 30 seconds for components to stabilize..." -ForegroundColor Gray
    Start-Sleep -Seconds 30

    $nodes = kubectl get nodes --no-headers 2>$null
    $nodeCount = ($nodes -split "`n" | Where-Object { $_ }).Count
    Write-Host "  Nodes: $nodeCount ready" -ForegroundColor Green

    $es = kubectl get elasticsearch -n $platformNs -o jsonpath='{.items[0].status.health}' 2>$null
    if ($es) { Write-Host "  Elasticsearch: $es" -ForegroundColor $(if ($es -eq "green") { "Green" } else { "Yellow" }) }
    else { Write-Host "  Elasticsearch: Pending" -ForegroundColor Yellow }

    $kibana = kubectl get kibana -n $platformNs -o jsonpath='{.items[0].status.health}' 2>$null
    if ($kibana) { Write-Host "  Kibana: $kibana" -ForegroundColor $(if ($kibana -eq "green") { "Green" } else { "Yellow" }) }
    else { Write-Host "  Kibana: Pending" -ForegroundColor Yellow }

    return kubectl get svc -n aks-istio-ingress aks-istio-ingressgateway-external -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
}

function Show-Summary {
    param([hashtable]$Ctx, [hashtable]$Vars, [string]$ExternalIp, [string]$StackName)

    $displayName = if ([string]::IsNullOrEmpty($StackName)) { "default" } else { $StackName }
    $platformNs = if ([string]::IsNullOrEmpty($StackName)) { "platform" } else { "platform-$StackName" }
    $osduNs = if ([string]::IsNullOrEmpty($StackName)) { "osdu" } else { "osdu-$StackName" }

    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor Green
    Write-Host "  Pre-Deploy Complete: Stack ($displayName) Deployed"               -ForegroundColor Green
    Write-Host "==================================================================" -ForegroundColor Green
    Write-Host "  Cluster: $($Ctx.ClusterName)"
    Write-Host "  Resource Group: $($Ctx.ResourceGroup)"
    Write-Host "  Stack: $displayName"
    Write-Host "  Namespaces: $platformNs, $osduNs"

    $notes = Get-DeferredFeatureNotes
    if ($notes.Count -gt 0) {
        Write-Host ""
        Write-Host "  Optional features not configured:" -ForegroundColor Yellow
        foreach ($note in $notes) {
            Write-Host "    - $note" -ForegroundColor Gray
        }
    }

    if ($ExternalIp) {
        Write-Host "  External IP: $ExternalIp"
        Write-Host ""

        $hasIngress = (-not [string]::IsNullOrEmpty($Vars.IngressPrefix)) -and (-not [string]::IsNullOrEmpty($Vars.DnsZoneName))
        $kibanaHost   = if ($hasIngress) { "$($Vars.IngressPrefix)-kibana.$($Vars.DnsZoneName)" } else { "" }
        $osduApiHost  = if ($hasIngress) { "$($Vars.IngressPrefix).$($Vars.DnsZoneName)" } else { "" }
        $airflowHost  = if ($hasIngress) { "$($Vars.IngressPrefix)-airflow.$($Vars.DnsZoneName)" } else { "" }

        Write-Host "  Next steps:" -ForegroundColor Yellow
        if ($Vars.EnableExternalDns -eq "true" -and $hasIngress) {
            Write-Host "    1. DNS A records will be auto-created by ExternalDNS" -ForegroundColor Gray
        }
        elseif ($hasIngress) {
            Write-Host "    1. Create DNS A records for *.developer domain -> $ExternalIp" -ForegroundColor Gray
        }
        else {
            Write-Host "    1. Configure DNS zone for external access" -ForegroundColor Gray
        }

        $step = 2
        if (-not [string]::IsNullOrEmpty($osduApiHost)) {
            Write-Host "    $step. OSDU API:  https://$osduApiHost/api/" -ForegroundColor Gray
            $step++
        }
        if (-not [string]::IsNullOrEmpty($kibanaHost)) {
            Write-Host "    $step. Kibana:    https://$kibanaHost" -ForegroundColor Gray
            $step++
        }
        if (-not [string]::IsNullOrEmpty($airflowHost) -and $env:TF_VAR_enable_airflow -ne "false") {
            Write-Host "    $step. Airflow:   https://$airflowHost" -ForegroundColor Gray
            $step++
        }
        Write-Host "    $step. Get Elasticsearch password:" -ForegroundColor Gray
        Write-Host "       kubectl get secret elasticsearch-es-elastic-user -n $platformNs -o jsonpath='{.data.elastic}' | base64 -d" -ForegroundColor DarkGray
    }
    Write-Host ""
}

#endregion

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "  Pre-Deploy: Stack Deployment"                                     -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

$ctx = Get-ClusterContext
$postProvisionReady = Get-AzdValue -Name "SPI_POSTPROVISION_READY"
if ($postProvisionReady -ne "true") {
    Show-CoreOnlySummary -Ctx $ctx
    exit 0
}

Connect-Cluster -Ctx $ctx
$stackName = Get-StackName
$vars = Get-PlatformVars -Ctx $ctx
Deploy-Stack -Ctx $ctx -Vars $vars -StackName $stackName
$ip = Test-Deployment -Vars $vars -StackName $stackName
Show-Summary -Ctx $ctx -Vars $vars -ExternalIp $ip -StackName $stackName

exit 0
