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

# Config-driven CIMPL stack — middleware + OSDU services (fully in-cluster)
#
# Runs alongside the Azure SPI stack in the same AKS Automatic cluster.
# Isolated via dedicated namespaces and Karpenter NodePools:
#   - platform-cimpl  (middleware: Elasticsearch, Redis, PostgreSQL, RabbitMQ, MinIO, Keycloak, Airflow)
#   - osdu-cimpl      (OSDU microservices)
#
# Foundation layer (cert-manager, ECK, CNPG, ExternalDNS, Gateway API) is shared.

locals {
  platform_namespace = var.stack_id != "" ? "platform-${var.stack_id}" : "platform"
  osdu_namespace     = var.stack_id != "" ? "osdu-${var.stack_id}" : "osdu"
  nodepool_name      = var.stack_id != "" ? "platform-${var.stack_id}" : "platform"
  osdu_nodepool_name = var.stack_id != "" ? "osdu-${var.stack_id}" : "osdu"
  stack_label        = var.stack_id != "" ? var.stack_id : "default"

  # Node scheduling for OSDU services — when nodepool isolation is enabled,
  # pods get a nodeSelector and toleration targeting the dedicated OSDU pool.
  osdu_node_scheduling = var.enable_nodepool ? {
    nodeSelector = { "agentpool" = local.osdu_nodepool_name }
    tolerations = [{
      key      = "workload"
      operator = "Equal"
      value    = local.osdu_nodepool_name
      effect   = "NoSchedule"
    }]
    } : {
    nodeSelector = {}
    tolerations  = []
  }

  common_labels = {
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = "cimpl-stack-${local.stack_label}"
  }

  # Cross-namespace service FQDNs
  postgresql_host = "postgresql-rw.${local.platform_namespace}.svc.cluster.local"
  redis_host      = "redis-master.${local.platform_namespace}.svc.cluster.local"
  rabbitmq_host   = "rabbitmq.${local.platform_namespace}.svc.cluster.local"
  keycloak_host   = "keycloak.${local.platform_namespace}.svc.cluster.local"

  # Ingress hostname derivation
  kibana_hostname      = var.ingress_prefix != "" && var.dns_zone_name != "" ? "${var.ingress_prefix}-kibana.${var.dns_zone_name}" : ""
  keycloak_hostname    = var.ingress_prefix != "" && var.dns_zone_name != "" ? "${var.ingress_prefix}-keycloak.${var.dns_zone_name}" : ""
  airflow_hostname     = var.ingress_prefix != "" && var.dns_zone_name != "" ? "${var.ingress_prefix}-airflow.${var.dns_zone_name}" : ""
  has_ingress_hostname = local.kibana_hostname != ""
  osdu_domain          = var.ingress_prefix != "" && var.dns_zone_name != "" ? "${var.ingress_prefix}.${var.dns_zone_name}" : ""

  active_cluster_issuer = var.use_letsencrypt_production ? "letsencrypt-prod" : "letsencrypt-staging"

  # ── OSDU service deploy flags ─────────────────────────────────────────
  # Group cascade: reference and domain require core
  _osdu_core      = var.enable_osdu_core_services
  _osdu_reference = local._osdu_core && var.enable_osdu_reference_services
  _osdu_domain    = local._osdu_core && var.enable_osdu_domain_services

  # Core services (group + individual)
  deploy_common       = local._osdu_core && var.enable_common && local.osdu_domain != ""
  deploy_partition    = local._osdu_core && var.enable_partition
  deploy_entitlements = local._osdu_core && var.enable_entitlements
  deploy_legal        = local._osdu_core && var.enable_legal
  deploy_schema       = local._osdu_core && var.enable_schema
  deploy_storage      = local._osdu_core && var.enable_storage
  deploy_search       = local._osdu_core && var.enable_search
  deploy_indexer      = local._osdu_core && var.enable_indexer
  deploy_file         = local._osdu_core && var.enable_file
  deploy_notification = local._osdu_core && var.enable_notification
  deploy_dataset      = local._osdu_core && var.enable_dataset
  deploy_register     = local._osdu_core && var.enable_register
  deploy_policy       = local._osdu_core && var.enable_policy
  deploy_secret       = local._osdu_core && var.enable_secret
  deploy_workflow     = local._osdu_core && var.enable_workflow

  # Reference services (group + individual)
  deploy_unit           = local._osdu_reference && var.enable_unit
  deploy_crs_conversion = local._osdu_reference && var.enable_crs_conversion
  deploy_crs_catalog    = local._osdu_reference && var.enable_crs_catalog

  # Domain services (group + individual)
  deploy_wellbore        = local._osdu_domain && var.enable_wellbore
  deploy_wellbore_worker = local._osdu_domain && var.enable_wellbore_worker
  deploy_eds_dms         = local._osdu_domain && var.enable_eds_dms
  deploy_oetp_server     = local._osdu_domain && var.enable_oetp_server

  # Bootstrap data (requires keycloak + core services actually deployed)
  deploy_bootstrap_data = (local._osdu_core
    && var.enable_bootstrap_data
    && var.enable_keycloak
    && local.deploy_legal
    && local.deploy_storage
    && local.deploy_entitlements
  )

  # Reference data version — follows osdu_dags_branch unless explicitly overridden
  bootstrap_data_branch = var.bootstrap_data_branch != "" ? var.bootstrap_data_branch : var.osdu_dags_branch
}
