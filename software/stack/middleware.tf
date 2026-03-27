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

# -- Middleware modules (Azure SPI variant) ------------------------------------
#
# In-cluster: Elasticsearch, Airflow, lightweight PostgreSQL (Airflow metadata).
# Azure PaaS (not deployed here): Redis, Service Bus, Storage, CosmosDB, Key Vault.

module "elastic" {
  source = "./modules/elastic"
  count  = var.enable_elasticsearch ? 1 : 0

  namespace            = kubernetes_namespace_v1.platform.metadata[0].name
  enable_bootstrap     = var.enable_elastic_bootstrap
  kibana_hostname      = local.kibana_hostname
  has_ingress_hostname = local.has_ingress_hostname
}

module "postgresql" {
  source = "./modules/postgresql"
  count  = local.deploy_postgresql_airflow ? 1 : 0

  namespace   = kubernetes_namespace_v1.platform.metadata[0].name
  db_password = var.airflow_db_password
}

module "airflow" {
  source = "./modules/airflow"
  count  = var.enable_airflow ? 1 : 0

  namespace       = kubernetes_namespace_v1.platform.metadata[0].name
  osdu_namespace  = local.osdu_namespace
  postgresql_host = local.postgresql_host

  airflow_db_password         = var.airflow_db_password
  workload_identity_client_id = var.osdu_identity_client_id
  azure_tenant_id             = var.tenant_id
  dag_storage_account_name    = var.storage_account_name

  osdu_airflow_version   = var.osdu_airflow_version
  osdu_ingestion_version = var.osdu_ingestion_version
  osdu_api_version       = var.osdu_api_version
  osdu_dags_branch       = var.osdu_dags_branch

  depends_on = [module.postgresql]
}

module "gateway" {
  source = "./modules/gateway"
  count  = var.enable_gateway && local.has_ingress_hostname ? 1 : 0

  namespace      = kubernetes_namespace_v1.platform.metadata[0].name
  osdu_namespace = local.osdu_namespace
  stack_label    = local.stack_label

  # Hostnames
  kibana_hostname  = local.kibana_hostname
  osdu_hostname    = local.osdu_domain
  airflow_hostname = local.airflow_hostname

  # Feature flags
  enable_osdu_api     = var.enable_osdu_api_ingress
  enable_airflow      = var.enable_airflow_ingress && var.enable_airflow
  enable_cert_manager = var.enable_cert_manager

  active_cluster_issuer = local.active_cluster_issuer

  # OSDU API path-based routes -- only for enabled services
  osdu_api_routes = var.enable_osdu_api_ingress ? concat(
    local.deploy_partition ? [{ path_prefix = "/api/partition/", service_name = "partition" }] : [],
    local.deploy_entitlements ? [{ path_prefix = "/api/entitlements/", service_name = "entitlements" }] : [],
    local.deploy_legal ? [{ path_prefix = "/api/legal/", service_name = "legal" }] : [],
    local.deploy_schema ? [{ path_prefix = "/api/schema-service/", service_name = "schema" }] : [],
    local.deploy_storage ? [{ path_prefix = "/api/storage/", service_name = "storage" }] : [],
    local.deploy_search ? [{ path_prefix = "/api/search/", service_name = "search" }] : [],
    local.deploy_indexer ? [{ path_prefix = "/api/indexer/", service_name = "indexer" }] : [],
    local.deploy_file ? [{ path_prefix = "/api/file/", service_name = "file" }] : [],
    local.deploy_workflow ? [{ path_prefix = "/api/workflow/", service_name = "workflow" }] : [],
    local.deploy_unit ? [{ path_prefix = "/api/unit/", service_name = "unit" }] : [],
    local.deploy_crs_conversion ? [{ path_prefix = "/api/crs/converter/", service_name = "crs-conversion" }] : [],
    local.deploy_crs_catalog ? [{ path_prefix = "/api/crs/catalog/", service_name = "crs-catalog" }] : [],
  ) : []

  depends_on = [module.elastic, module.airflow, module.osdu_common]
}
