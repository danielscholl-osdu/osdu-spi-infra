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
# Azure PaaS replaces in-cluster middleware for: Service Bus, Storage, CosmosDB, Key Vault.
# In-cluster: Elasticsearch, Redis, CNPG PostgreSQL (Airflow), Airflow.
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

  # Cross-namespace service FQDNs (in-cluster services)
  elasticsearch_host = "elasticsearch-es-http.${local.platform_namespace}.svc.cluster.local"
  postgresql_host    = "postgresql-rw.${local.platform_namespace}.svc.cluster.local"
  redis_host         = "redis-master.${local.platform_namespace}.svc.cluster.local"
  redis_port         = "6380"

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

  # -- OSDU service image resolution ----------------------------------------
  # Azure SPI images from the OSDU community registry. Image names follow the
  # pattern: {service}-{branch}:{full_40char_git_sha}
  # Per-service overrides via var.osdu_image_overrides take full precedence.
  _osdu_image_defaults = {
    partition      = { repository = "community.opengroup.org:5555/osdu/platform/system/partition/partition-${var.osdu_image_branch}", tag = "119bf4d9e25879e5f47206dcf24b4998ee4eb355" }
    entitlements   = { repository = "community.opengroup.org:5555/osdu/platform/security-and-compliance/entitlements/entitlements-${var.osdu_image_branch}", tag = "0fb954f01c7ef59a68194c88dec4d8d166d0b48e" }
    legal          = { repository = "community.opengroup.org:5555/osdu/platform/security-and-compliance/legal/legal-${var.osdu_image_branch}", tag = "2e82d5975a49564b64574190e492af403164637d" }
    schema         = { repository = "community.opengroup.org:5555/osdu/platform/system/schema-service/schema-service-${var.osdu_image_branch}", tag = "868023373a2f7550d9f3e850d06434838eeeb2b4" }
    storage        = { repository = "community.opengroup.org:5555/osdu/platform/system/storage/storage-${var.osdu_image_branch}", tag = "13d0a957c558dd109dd1bb4fb705de583cdc295c" }
    search         = { repository = "community.opengroup.org:5555/osdu/platform/system/search-service/search-service-${var.osdu_image_branch}", tag = "1756362704ad9ee2b63c83562cebcd9abd233e26" }
    indexer        = { repository = "community.opengroup.org:5555/osdu/platform/system/indexer-service/indexer-service-${var.osdu_image_branch}", tag = "4a2bd12e73f914460c93aade608287d16e42e2ce" }
    indexer_queue  = { repository = "community.opengroup.org:5555/osdu/platform/system/indexer-queue/indexer-queue-${var.osdu_image_branch}", tag = "1ad21add706aecd9d1762998113d5976443a4d57" }
    file           = { repository = "community.opengroup.org:5555/osdu/platform/system/file/file-${var.osdu_image_branch}", tag = "2b149c5ec48451034fbc2562c7cbe622f41843d1" }
    workflow       = { repository = "community.opengroup.org:5555/osdu/platform/data-flow/ingestion/ingestion-workflow/ingestion-workflow-${var.osdu_image_branch}", tag = "13fbcfce32601edbfc1c10a1994f8af5a388436f" }
    crs_conversion = { repository = "community.opengroup.org:5555/osdu/platform/system/reference/crs-conversion-service/crs-conversion-service-${var.osdu_image_branch}", tag = "43adf2bef10e3e6d3980b4ff74f78e1aff0c2880" }
    crs_catalog    = { repository = "community.opengroup.org:5555/osdu/platform/system/reference/crs-catalog-service/crs-catalog-service-${var.osdu_image_branch}", tag = "49761e5b20118a9998b4a2a88d6e57eddd4d745e" }
    unit           = { repository = "community.opengroup.org:5555/osdu/platform/system/reference/unit-service/unit-service-${var.osdu_image_branch}", tag = "2fdf7e3c4674f87ad0d556e0f1f6da458dac2b18" }
  }

  osdu_images = {
    for svc, defaults in local._osdu_image_defaults : svc => lookup(var.osdu_image_overrides, svc, defaults)
  }
}
