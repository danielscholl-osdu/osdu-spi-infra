# Copyright 2026, Microsoft
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Infrastructure layer outputs.
# Consumed by azd, the bootstrap-access layer, and the software layers.

# ──────────────────────────────────────────────
# Cluster Outputs
# ──────────────────────────────────────────────

output "AZURE_RESOURCE_GROUP" {
  description = "Resource group name"
  value       = azurerm_resource_group.main.name
}

output "AZURE_AKS_CLUSTER_NAME" {
  description = "AKS cluster name"
  value       = module.aks.name
}

output "AKS_RESOURCE_ID" {
  description = "AKS resource ID for access bootstrap"
  value       = module.aks.resource_id
}

output "OIDC_ISSUER_URL" {
  description = "OIDC issuer URL for workload identity"
  value       = module.aks.oidc_issuer_profile_issuer_url
}

output "CLUSTER_FQDN" {
  description = "AKS cluster FQDN"
  value       = module.aks.fqdn
}

output "get_credentials_command" {
  description = "Command to get kubeconfig"
  value       = "az aks get-credentials -g ${azurerm_resource_group.main.name} -n ${module.aks.name} && kubelogin convert-kubeconfig -l azurecli"
}

output "cluster_resource_group" {
  description = "Resource group for platform layer"
  value       = azurerm_resource_group.main.name
}

output "cluster_name" {
  description = "Cluster name for platform layer"
  value       = module.aks.name
}

output "AZURE_SUBSCRIPTION_ID" {
  description = "Azure subscription ID"
  value       = data.azurerm_client_config.current.subscription_id
}

output "AZURE_TENANT_ID" {
  description = "Azure tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

# ──────────────────────────────────────────────
# Monitoring Outputs
# ──────────────────────────────────────────────

output "PROMETHEUS_WORKSPACE_ID" {
  description = "Azure Monitor workspace resource ID"
  value       = azurerm_monitor_workspace.prometheus.id
}

output "LOG_ANALYTICS_WORKSPACE_ID" {
  description = "Log Analytics workspace resource ID"
  value       = azurerm_log_analytics_workspace.aks.id
}

output "GRAFANA_ENDPOINT" {
  description = "Azure Managed Grafana dashboard URL"
  value       = var.enable_grafana_workspace ? azurerm_dashboard_grafana.main[0].endpoint : ""
}

output "GRAFANA_RESOURCE_ID" {
  description = "Azure Managed Grafana resource ID for access bootstrap"
  value       = var.enable_grafana_workspace ? azurerm_dashboard_grafana.main[0].id : ""
}

output "GRAFANA_PRINCIPAL_ID" {
  description = "System-assigned identity principal ID of the Grafana workspace"
  value       = var.enable_grafana_workspace ? azurerm_dashboard_grafana.main[0].identity[0].principal_id : ""
}

# ──────────────────────────────────────────────
# ExternalDNS Outputs
# ──────────────────────────────────────────────

output "EXTERNAL_DNS_CLIENT_ID" {
  description = "Client ID of the ExternalDNS managed identity"
  value       = local.enable_external_dns_identity ? azurerm_user_assigned_identity.external_dns[0].client_id : ""
}

output "EXTERNAL_DNS_PRINCIPAL_ID" {
  description = "Principal ID of the ExternalDNS managed identity"
  value       = local.enable_external_dns_identity ? azurerm_user_assigned_identity.external_dns[0].principal_id : ""
}

# ──────────────────────────────────────────────
# Azure PaaS Outputs
# ──────────────────────────────────────────────

# Key Vault
output "KEY_VAULT_NAME" {
  description = "Azure Key Vault name"
  value       = azurerm_key_vault.main.name
}

output "KEY_VAULT_URI" {
  description = "Azure Key Vault URI"
  value       = azurerm_key_vault.main.vault_uri
}

# Storage
output "COMMON_STORAGE_NAME" {
  description = "Common/system storage account name"
  value       = azurerm_storage_account.common.name
}

# Container Registry
output "ACR_NAME" {
  description = "Azure Container Registry name"
  value       = azurerm_container_registry.main.name
}

output "ACR_LOGIN_SERVER" {
  description = "Azure Container Registry login server"
  value       = azurerm_container_registry.main.login_server
}

# Application Insights
output "APP_INSIGHTS_KEY" {
  description = "Application Insights instrumentation key"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "APP_INSIGHTS_CONNECTION" {
  description = "Application Insights connection string"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

# OSDU Identity
output "OSDU_IDENTITY_CLIENT_ID" {
  description = "OSDU service workload identity client ID"
  value       = azurerm_user_assigned_identity.osdu.client_id
}

output "OSDU_IDENTITY_PRINCIPAL_ID" {
  description = "OSDU service workload identity principal ID"
  value       = azurerm_user_assigned_identity.osdu.principal_id
}

# Graph DB
output "GRAPH_DB_ENDPOINT" {
  description = "CosmosDB Gremlin API endpoint (Entitlements)"
  value       = azurerm_cosmosdb_account.graph.endpoint
}

# Per-partition outputs (maps for software layer consumption)
output "PARTITION_STORAGE_NAMES" {
  description = "Map of partition name to storage account name"
  value       = { for p in var.data_partitions : p => azurerm_storage_account.partition[p].name }
}

output "PARTITION_COSMOS_ENDPOINTS" {
  description = "Map of partition name to CosmosDB endpoint"
  value       = { for p in var.data_partitions : p => azurerm_cosmosdb_account.partition[p].endpoint }
}

output "PARTITION_SERVICEBUS_NAMESPACES" {
  description = "Map of partition name to Service Bus namespace name"
  value       = { for p in var.data_partitions : p => azurerm_servicebus_namespace.partition[p].name }
}

output "DATA_PARTITIONS" {
  description = "List of data partition names"
  value       = var.data_partitions
}
