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

# Privilege bootstrap layer.
# These operations require Owner or User Access Administrator role.

locals {
  aks_admin_principal_ids     = var.enable_aks_bootstrap_access ? toset(var.aks_admin_principal_ids) : toset([])
  grafana_admin_principal_ids = var.enable_grafana_admin_access ? toset(var.grafana_admin_principal_ids) : toset([])

  enable_grafana_monitor_access = (
    var.enable_grafana_monitor_access &&
    var.grafana_resource_id != "" &&
    var.grafana_managed_identity_principal_id != "" &&
    var.monitor_workspace_id != "" &&
    var.log_analytics_workspace_id != "" &&
    var.subscription_id != ""
  )

  enable_external_dns_zone_access = (
    var.enable_external_dns_zone_access &&
    var.external_dns_principal_id != "" &&
    var.dns_zone_name != "" &&
    var.dns_zone_resource_group != "" &&
    var.dns_zone_subscription_id != ""
  )

  enable_cosmosdb_data_access = (
    var.enable_cosmosdb_data_access &&
    var.osdu_identity_principal_id != ""
  )
}

# ──────────────────────────────────────────────
# AKS Cluster Admin
# ──────────────────────────────────────────────

resource "azurerm_role_assignment" "aks_cluster_admin" {
  for_each             = local.aks_admin_principal_ids
  scope                = var.cluster_resource_id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = each.value
}

# ──────────────────────────────────────────────
# Grafana Access
# ──────────────────────────────────────────────

resource "azurerm_role_assignment" "grafana_monitoring_reader" {
  count                = local.enable_grafana_monitor_access ? 1 : 0
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Monitoring Reader"
  principal_id         = var.grafana_managed_identity_principal_id
}

resource "azurerm_role_assignment" "grafana_monitoring_data_reader" {
  count                = local.enable_grafana_monitor_access ? 1 : 0
  scope                = var.monitor_workspace_id
  role_definition_name = "Monitoring Data Reader"
  principal_id         = var.grafana_managed_identity_principal_id
}

resource "azurerm_role_assignment" "grafana_log_analytics_reader" {
  count                = local.enable_grafana_monitor_access ? 1 : 0
  scope                = var.log_analytics_workspace_id
  role_definition_name = "Log Analytics Reader"
  principal_id         = var.grafana_managed_identity_principal_id
}

resource "azurerm_role_assignment" "grafana_admin" {
  for_each             = local.grafana_admin_principal_ids
  scope                = var.grafana_resource_id
  role_definition_name = "Grafana Admin"
  principal_id         = each.value
}

# ──────────────────────────────────────────────
# ExternalDNS Zone Access
# ──────────────────────────────────────────────

resource "azurerm_role_assignment" "external_dns_dns_contributor" {
  count                = local.enable_external_dns_zone_access ? 1 : 0
  scope                = "/subscriptions/${var.dns_zone_subscription_id}/resourceGroups/${var.dns_zone_resource_group}/providers/Microsoft.Network/dnszones/${var.dns_zone_name}"
  role_definition_name = "DNS Zone Contributor"
  principal_id         = var.external_dns_principal_id
}

# ──────────────────────────────────────────────
# CosmosDB Data-Plane Access
# Uses the built-in CosmosDB Data Contributor role.
# ──────────────────────────────────────────────

resource "azurerm_cosmosdb_sql_role_assignment" "osdu_partition_data" {
  for_each            = local.enable_cosmosdb_data_access ? var.cosmosdb_account_ids : {}
  resource_group_name = split("/", each.value)[4]
  account_name        = split("/", each.value)[8]
  role_definition_id  = "${each.value}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = var.osdu_identity_principal_id
  scope               = each.value
}

resource "azurerm_cosmosdb_sql_role_assignment" "osdu_graph_data" {
  count               = local.enable_cosmosdb_data_access && var.cosmosdb_graph_account_id != "" ? 1 : 0
  resource_group_name = split("/", var.cosmosdb_graph_account_id)[4]
  account_name        = split("/", var.cosmosdb_graph_account_id)[8]
  role_definition_id  = "${var.cosmosdb_graph_account_id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = var.osdu_identity_principal_id
  scope               = var.cosmosdb_graph_account_id
}
