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

# OSDU core service deployments (Azure SPI variant)
#
# Key differences from cimpl:
#   - No cimpl_tenant / cimpl_project / subscriber_private_key_id
#   - Uses data_partition + workload_identity_client_id
#   - extra_set references Azure PaaS (Service Bus topics, Redis DB numbers, Storage)
#   - Preconditions reference Azure PaaS availability, not in-cluster middleware

module "partition" {
  source = "./modules/osdu-service"

  service_name                = "partition"
  repository                  = "oci://community.opengroup.org:5555/osdu/platform/system/partition/cimpl-helm"
  chart                       = "core-plus-partition-deploy"
  chart_version               = lookup(var.osdu_service_versions, "partition", var.osdu_chart_version)
  enable                      = local.deploy_partition
  enable_common               = local.deploy_common
  namespace                   = local.osdu_namespace
  osdu_domain                 = local.osdu_domain
  data_partition              = var.data_partition
  azure_tenant_id             = var.tenant_id
  workload_identity_client_id = var.osdu_identity_client_id
  kustomize_path              = path.module

  extra_set = [
    {
      name  = "data.storageAccountName"
      value = var.storage_account_name
    },
  ]

  depends_on = [module.osdu_common]
}

module "entitlements" {
  source = "./modules/osdu-service"

  service_name                = "entitlements"
  repository                  = "oci://community.opengroup.org:5555/osdu/platform/security-and-compliance/entitlements/cimpl-helm"
  chart                       = "core-plus-entitlements-deploy"
  chart_version               = lookup(var.osdu_service_versions, "entitlements", var.osdu_chart_version)
  enable                      = local.deploy_entitlements
  enable_common               = local.deploy_common
  namespace                   = local.osdu_namespace
  osdu_domain                 = local.osdu_domain
  data_partition              = var.data_partition
  azure_tenant_id             = var.tenant_id
  workload_identity_client_id = var.osdu_identity_client_id
  kustomize_path              = path.module

  preconditions = [
    { condition = !local.deploy_entitlements || local.deploy_partition, error_message = "Entitlements requires Partition." },
  ]

  depends_on = [module.osdu_common, module.partition]
}

module "legal" {
  source = "./modules/osdu-service"

  service_name                = "legal"
  repository                  = "oci://community.opengroup.org:5555/osdu/platform/security-and-compliance/legal/cimpl-helm"
  chart                       = "core-plus-legal-deploy"
  chart_version               = lookup(var.osdu_service_versions, "legal", var.osdu_chart_version)
  enable                      = local.deploy_legal
  enable_common               = local.deploy_common
  namespace                   = local.osdu_namespace
  osdu_domain                 = local.osdu_domain
  data_partition              = var.data_partition
  azure_tenant_id             = var.tenant_id
  workload_identity_client_id = var.osdu_identity_client_id
  kustomize_path              = path.module

  extra_set = [
    {
      name  = "data.servicebusTopic"
      value = "legaltags"
    },
  ]

  preconditions = [
    { condition = !local.deploy_legal || local.deploy_entitlements, error_message = "Legal requires Entitlements." },
    { condition = !local.deploy_legal || local.deploy_partition, error_message = "Legal requires Partition." },
  ]

  depends_on = [module.osdu_common, module.entitlements]
}

module "schema" {
  source = "./modules/osdu-service"

  service_name                = "schema"
  repository                  = "oci://community.opengroup.org:5555/osdu/platform/system/schema-service/cimpl-helm"
  chart                       = "core-plus-schema-deploy"
  chart_version               = lookup(var.osdu_service_versions, "schema", var.osdu_chart_version)
  enable                      = local.deploy_schema
  enable_common               = local.deploy_common
  namespace                   = local.osdu_namespace
  osdu_domain                 = local.osdu_domain
  data_partition              = var.data_partition
  azure_tenant_id             = var.tenant_id
  workload_identity_client_id = var.osdu_identity_client_id
  kustomize_path              = path.module

  preconditions = [
    { condition = !local.deploy_schema || local.deploy_entitlements, error_message = "Schema requires Entitlements." },
    { condition = !local.deploy_schema || local.deploy_partition, error_message = "Schema requires Partition." },
  ]

  depends_on = [module.osdu_common, module.entitlements]
}

module "storage" {
  source = "./modules/osdu-service"

  service_name                = "storage"
  repository                  = "oci://community.opengroup.org:5555/osdu/platform/system/storage/cimpl-helm"
  chart                       = "core-plus-storage-deploy"
  chart_version               = lookup(var.osdu_service_versions, "storage", var.osdu_chart_version)
  enable                      = local.deploy_storage
  enable_common               = local.deploy_common
  namespace                   = local.osdu_namespace
  osdu_domain                 = local.osdu_domain
  data_partition              = var.data_partition
  azure_tenant_id             = var.tenant_id
  workload_identity_client_id = var.osdu_identity_client_id
  kustomize_path              = path.module

  extra_set = [
    {
      name  = "data.servicebusTopic"
      value = "recordstopic"
    },
    {
      name  = "data.redisDatabase"
      value = "4"
    },
  ]

  preconditions = [
    { condition = !local.deploy_storage || local.deploy_legal, error_message = "Storage requires Legal." },
    { condition = !local.deploy_storage || local.deploy_entitlements, error_message = "Storage requires Entitlements." },
    { condition = !local.deploy_storage || local.deploy_partition, error_message = "Storage requires Partition." },
  ]

  depends_on = [module.osdu_common, module.legal]
}

module "search" {
  source = "./modules/osdu-service"

  service_name                = "search"
  repository                  = "oci://community.opengroup.org:5555/osdu/platform/system/search-service/cimpl-helm"
  chart                       = "core-plus-search-deploy"
  chart_version               = lookup(var.osdu_service_versions, "search", var.osdu_chart_version)
  enable                      = local.deploy_search
  enable_common               = local.deploy_common
  namespace                   = local.osdu_namespace
  osdu_domain                 = local.osdu_domain
  data_partition              = var.data_partition
  azure_tenant_id             = var.tenant_id
  workload_identity_client_id = var.osdu_identity_client_id
  kustomize_path              = path.module

  extra_set = [
    {
      name  = "data.redisDatabase"
      value = "5"
    },
  ]

  preconditions = [
    { condition = !local.deploy_search || local.deploy_entitlements, error_message = "Search requires Entitlements." },
    { condition = !local.deploy_search || local.deploy_partition, error_message = "Search requires Partition." },
    { condition = !local.deploy_search || var.enable_elasticsearch, error_message = "Search requires Elasticsearch." },
    { condition = !local.deploy_search || var.enable_elastic_bootstrap, error_message = "Search requires Elastic Bootstrap." },
  ]

  depends_on = [module.osdu_common, module.storage]
}

module "indexer" {
  source = "./modules/osdu-service"

  service_name                = "indexer"
  repository                  = "oci://community.opengroup.org:5555/osdu/platform/system/indexer-service/cimpl-helm"
  chart                       = "core-plus-indexer-deploy"
  chart_version               = lookup(var.osdu_service_versions, "indexer", var.osdu_chart_version)
  enable                      = local.deploy_indexer
  enable_common               = local.deploy_common
  namespace                   = local.osdu_namespace
  osdu_domain                 = local.osdu_domain
  data_partition              = var.data_partition
  azure_tenant_id             = var.tenant_id
  workload_identity_client_id = var.osdu_identity_client_id
  kustomize_path              = path.module

  extra_set = [
    {
      name  = "data.servicebusTopic"
      value = "indexing-progress"
    },
    {
      name  = "data.redisDatabase"
      value = "4"
    },
  ]

  preconditions = [
    { condition = !local.deploy_indexer || local.deploy_entitlements, error_message = "Indexer requires Entitlements." },
    { condition = !local.deploy_indexer || local.deploy_partition, error_message = "Indexer requires Partition." },
    { condition = !local.deploy_indexer || var.enable_elasticsearch, error_message = "Indexer requires Elasticsearch." },
    { condition = !local.deploy_indexer || var.enable_elastic_bootstrap, error_message = "Indexer requires Elastic Bootstrap." },
  ]

  depends_on = [module.osdu_common, module.storage]
}

module "indexer_queue" {
  source = "./modules/osdu-service"

  service_name                = "indexer-queue"
  repository                  = "oci://community.opengroup.org:5555/osdu/platform/system/indexer-queue/cimpl-helm"
  chart                       = "core-plus-indexer-queue-deploy"
  chart_version               = lookup(var.osdu_service_versions, "indexer_queue", var.osdu_chart_version)
  enable                      = local.deploy_indexer_queue
  enable_common               = local.deploy_common
  namespace                   = local.osdu_namespace
  osdu_domain                 = local.osdu_domain
  data_partition              = var.data_partition
  azure_tenant_id             = var.tenant_id
  workload_identity_client_id = var.osdu_identity_client_id
  kustomize_path              = path.module

  extra_set = [
    {
      name  = "data.servicebusTopic"
      value = "recordstopicdownstream"
    },
  ]

  preconditions = [
    { condition = !local.deploy_indexer_queue || local.deploy_indexer, error_message = "Indexer Queue requires Indexer." },
    { condition = !local.deploy_indexer_queue || local.deploy_storage, error_message = "Indexer Queue requires Storage." },
  ]

  depends_on = [module.osdu_common, module.indexer]
}

module "file" {
  source = "./modules/osdu-service"

  service_name                = "file"
  repository                  = "oci://community.opengroup.org:5555/osdu/platform/system/file/cimpl-helm"
  chart                       = "core-plus-file-deploy"
  chart_version               = lookup(var.osdu_service_versions, "file", var.osdu_chart_version)
  enable                      = local.deploy_file
  enable_common               = local.deploy_common
  namespace                   = local.osdu_namespace
  osdu_domain                 = local.osdu_domain
  data_partition              = var.data_partition
  azure_tenant_id             = var.tenant_id
  workload_identity_client_id = var.osdu_identity_client_id
  kustomize_path              = path.module

  preconditions = [
    { condition = !local.deploy_file || local.deploy_legal, error_message = "File requires Legal." },
    { condition = !local.deploy_file || local.deploy_entitlements, error_message = "File requires Entitlements." },
    { condition = !local.deploy_file || local.deploy_partition, error_message = "File requires Partition." },
  ]

  depends_on = [module.osdu_common, module.legal]
}

module "workflow" {
  source = "./modules/osdu-service"

  service_name                = "workflow"
  repository                  = "oci://community.opengroup.org:5555/osdu/platform/data-flow/ingestion/ingestion-workflow/cimpl-helm"
  chart                       = "core-plus-workflow-deploy"
  chart_version               = lookup(var.osdu_service_versions, "workflow", var.osdu_chart_version)
  enable                      = local.deploy_workflow
  enable_common               = local.deploy_common
  namespace                   = local.osdu_namespace
  osdu_domain                 = local.osdu_domain
  data_partition              = var.data_partition
  azure_tenant_id             = var.tenant_id
  workload_identity_client_id = var.osdu_identity_client_id
  kustomize_path              = path.module

  extra_set = [
    {
      name  = "data.osduAirflowUrl"
      value = "http://airflow-webserver.${local.platform_namespace}.svc.cluster.local:8080"
    },
  ]

  preconditions = [
    { condition = !local.deploy_workflow || local.deploy_entitlements, error_message = "Workflow requires Entitlements." },
    { condition = !local.deploy_workflow || local.deploy_partition, error_message = "Workflow requires Partition." },
    { condition = !local.deploy_workflow || local.deploy_storage, error_message = "Workflow requires Storage." },
    { condition = !local.deploy_workflow || var.enable_airflow, error_message = "Workflow requires Airflow." },
  ]

  depends_on = [module.osdu_common, module.storage]
}
