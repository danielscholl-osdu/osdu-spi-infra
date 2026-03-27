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

# Config-driven stack -- middleware + OSDU services (Azure SPI variant)
#
# Azure PaaS replaces in-cluster middleware for: PostgreSQL, Redis, Service Bus,
# Storage, CosmosDB, Key Vault. In-cluster: Elasticsearch, Airflow, lightweight PG.
#
# A single source directory serves all stack instances via STACK_NAME:
# - (unset)  -> namespaces: platform, osdu
# - "blue"   -> namespaces: platform-blue, osdu-blue
# All stacks share one Karpenter NodePool named "platform".

locals {
  platform_namespace = var.stack_id != "" ? "platform-${var.stack_id}" : "platform"
  osdu_namespace     = var.stack_id != "" ? "osdu-${var.stack_id}" : "osdu"
  nodepool_name      = "platform"
  stack_label        = var.stack_id != "" ? var.stack_id : "default"

  common_labels = {
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = "osdu-stack-${local.stack_label}"
  }

  # Cross-namespace service FQDNs (only in-cluster services)
  elasticsearch_host = "elasticsearch-es-http.${local.platform_namespace}.svc.cluster.local"
  postgresql_host    = "postgresql.${local.platform_namespace}.svc.cluster.local"

  # Ingress hostname derivation
  kibana_hostname      = var.ingress_prefix != "" && var.dns_zone_name != "" ? "${var.ingress_prefix}-kibana.${var.dns_zone_name}" : ""
  airflow_hostname     = var.ingress_prefix != "" && var.dns_zone_name != "" ? "${var.ingress_prefix}-airflow.${var.dns_zone_name}" : ""
  has_ingress_hostname = local.kibana_hostname != ""
  osdu_domain          = var.ingress_prefix != "" && var.dns_zone_name != "" ? "${var.ingress_prefix}.${var.dns_zone_name}" : ""

  active_cluster_issuer = var.use_letsencrypt_production ? "letsencrypt-prod" : "letsencrypt-staging"

  # -- OSDU service deploy flags -------------------------------------------
  # Group cascade: reference requires core
  _osdu_core      = var.enable_osdu_core_services
  _osdu_reference = local._osdu_core && var.enable_osdu_reference_services

  # Core services (group + individual)
  deploy_common        = local._osdu_core && var.enable_common && local.osdu_domain != ""
  deploy_partition     = local._osdu_core && var.enable_partition
  deploy_entitlements  = local._osdu_core && var.enable_entitlements
  deploy_legal         = local._osdu_core && var.enable_legal
  deploy_schema        = local._osdu_core && var.enable_schema
  deploy_storage       = local._osdu_core && var.enable_storage
  deploy_search        = local._osdu_core && var.enable_search
  deploy_indexer       = local._osdu_core && var.enable_indexer
  deploy_indexer_queue = local._osdu_core && var.enable_indexer_queue
  deploy_file          = local._osdu_core && var.enable_file
  deploy_workflow      = local._osdu_core && var.enable_workflow

  # Reference services (group + individual)
  deploy_unit           = local._osdu_reference && var.enable_unit
  deploy_crs_conversion = local._osdu_reference && var.enable_crs_conversion
  deploy_crs_catalog    = local._osdu_reference && var.enable_crs_catalog

  # Middleware deploy flags
  deploy_postgresql_airflow = var.enable_airflow
}
