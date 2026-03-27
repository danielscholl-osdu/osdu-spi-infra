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

# Layer 1: Infrastructure
#
# This layer provisions:
# - AKS Automatic cluster with Istio service mesh
# - Azure PaaS resources (CosmosDB, Service Bus, Storage, Redis, Key Vault, ACR)
# - Workload Identity for OSDU services
# - Monitoring (Log Analytics, App Insights, Prometheus, Grafana)
#
# Usage:
#   azd provision  # Provisions this layer
#
# After provisioning, get kubeconfig:
#   az aks get-credentials -g <resource-group> -n <cluster-name>
#   kubelogin convert-kubeconfig -l azurecli

# Get current tenant and subscription details for outputs and secret population.
data "azurerm_client_config" "current" {}

# Random suffix for globally unique resource names (storage accounts, etc.)
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace for Container Insights
resource "azurerm_log_analytics_workspace" "aks" {
  name                = "${local.cluster_name}-logs"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.common_tags
}

# Application Insights for OSDU service telemetry
resource "azurerm_application_insights" "main" {
  name                = "${local.cluster_name}-insights"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  workspace_id        = azurerm_log_analytics_workspace.aks.id
  application_type    = "web"
  tags                = local.common_tags
}
