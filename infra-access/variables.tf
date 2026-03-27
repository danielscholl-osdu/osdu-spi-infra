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

# Privilege bootstrap variables.
# These resources require Owner or User Access Administrator role.

variable "cluster_resource_id" {
  description = "Resource ID of the AKS cluster"
  type        = string
}

variable "subscription_id" {
  description = "Azure subscription ID containing the shared monitoring resources"
  type        = string
}

# AKS access
variable "enable_aks_bootstrap_access" {
  description = "Grant Azure Kubernetes Service RBAC Cluster Admin on the cluster"
  type        = bool
  default     = false
}

variable "aks_admin_principal_ids" {
  description = "Object IDs of users or groups that should receive AKS Cluster Admin"
  type        = list(string)
  default     = []
}

# Grafana access
variable "grafana_resource_id" {
  description = "Resource ID of the Grafana workspace"
  type        = string
  default     = ""
}

variable "grafana_managed_identity_principal_id" {
  description = "Principal ID of the Grafana system-assigned managed identity"
  type        = string
  default     = ""
}

variable "monitor_workspace_id" {
  description = "Resource ID of the Azure Monitor workspace"
  type        = string
  default     = ""
}

variable "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  type        = string
  default     = ""
}

variable "enable_grafana_monitor_access" {
  description = "Grant Grafana managed identity access to Azure Monitor and Log Analytics"
  type        = bool
  default     = false
}

variable "enable_grafana_admin_access" {
  description = "Grant Grafana Admin on the workspace to explicit principals"
  type        = bool
  default     = false
}

variable "grafana_admin_principal_ids" {
  description = "Object IDs of users or groups that should receive Grafana Admin"
  type        = list(string)
  default     = []
}

# ExternalDNS access
variable "external_dns_principal_id" {
  description = "Principal ID of the ExternalDNS managed identity"
  type        = string
  default     = ""
}

variable "dns_zone_name" {
  description = "Azure DNS zone name for ExternalDNS"
  type        = string
  default     = ""
}

variable "dns_zone_resource_group" {
  description = "Azure DNS zone resource group"
  type        = string
  default     = ""
}

variable "dns_zone_subscription_id" {
  description = "Azure DNS zone subscription ID"
  type        = string
  default     = ""
}

variable "enable_external_dns_zone_access" {
  description = "Grant DNS Zone Contributor to the ExternalDNS managed identity"
  type        = bool
  default     = false
}

# CosmosDB data-plane access (requires elevated permissions)
variable "enable_cosmosdb_data_access" {
  description = "Grant CosmosDB data-plane access to the OSDU managed identity"
  type        = bool
  default     = false
}

variable "osdu_identity_principal_id" {
  description = "Principal ID of the OSDU service managed identity"
  type        = string
  default     = ""
}

variable "cosmosdb_account_ids" {
  description = "Map of partition name to CosmosDB account resource ID"
  type        = map(string)
  default     = {}
}

variable "cosmosdb_graph_account_id" {
  description = "CosmosDB Gremlin account resource ID"
  type        = string
  default     = ""
}
