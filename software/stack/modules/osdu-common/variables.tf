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

# Variables for the OSDU common module (Azure SPI variant)

variable "namespace" {
  description = "OSDU Kubernetes namespace"
  type        = string
}

variable "osdu_domain" {
  description = "OSDU domain (e.g. prefix.dnszone)"
  type        = string
}

variable "data_partition" {
  description = "Data partition ID"
  type        = string
}

variable "azure_tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
}

variable "workload_identity_client_id" {
  description = "Managed identity client ID for workload identity"
  type        = string
}

variable "keyvault_uri" {
  description = "Azure Key Vault URI (e.g. https://kv-name.vault.azure.net/)"
  type        = string
}

variable "keyvault_name" {
  description = "Azure Key Vault name"
  type        = string
}

variable "cosmosdb_endpoint" {
  description = "Azure Cosmos DB account endpoint"
  type        = string
}

variable "cosmosdb_database" {
  description = "Cosmos DB database name"
  type        = string
  default     = "osdu-db"
}

variable "storage_account_name" {
  description = "Azure Storage account name"
  type        = string
}

variable "servicebus_namespace" {
  description = "Azure Service Bus namespace (FQDN)"
  type        = string
}

variable "redis_hostname" {
  description = "Azure Cache for Redis hostname"
  type        = string
}

variable "redis_port" {
  description = "Azure Cache for Redis port"
  type        = string
  default     = "6380"
}

variable "appinsights_key" {
  description = "Application Insights instrumentation key"
  type        = string
  default     = ""
}

variable "enable_elasticsearch" {
  description = "Whether Elasticsearch is deployed (controls ES secret creation)"
  type        = bool
  default     = false
}

variable "elasticsearch_host" {
  description = "Elasticsearch HTTP service host"
  type        = string
  default     = ""
}

