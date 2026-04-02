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

# OSDU core service deployments
# Ref: https://community.opengroup.org/osdu/platform

module "partition" {
  source = "./modules/osdu-service"

  service_name              = "partition"
  repository                = "oci://community.opengroup.org:5555/osdu/platform/system/partition/cimpl-helm"
  chart                     = "core-plus-partition-deploy"
  chart_version             = lookup(var.osdu_service_versions, "partition", var.osdu_chart_version)
  enable                    = local.deploy_partition
  enable_common             = local.deploy_common
  namespace                 = local.osdu_namespace
  osdu_domain               = local.osdu_domain
  cimpl_tenant              = var.cimpl_tenant
  cimpl_project             = var.cimpl_project
  subscriber_private_key_id = var.cimpl_subscriber_private_key_id
  kustomize_path            = path.module
  nodepool_name             = local.osdu_nodepool_label
  platform_namespace        = local.platform_namespace

  extra_set = [
    {
      name  = "data.minioExternalEndpoint"
      value = "http://minio.${local.platform_namespace}.svc.cluster.local:9000"
    },
    {
      name  = "data.minioUIEndpoint"
      value = "http://minio.${local.platform_namespace}.svc.cluster.local:9001"
    },
  ]

  depends_on = [module.osdu_common, module.postgresql]
}

module "entitlements" {
  source = "./modules/osdu-service"

  service_name              = "entitlements"
  repository                = "oci://community.opengroup.org:5555/osdu/platform/security-and-compliance/entitlements/cimpl-helm"
  chart                     = "core-plus-entitlements-deploy"
  chart_version             = lookup(var.osdu_service_versions, "entitlements", var.osdu_chart_version)
  enable                    = local.deploy_entitlements
  enable_common             = local.deploy_common
  namespace                 = local.osdu_namespace
  osdu_domain               = local.osdu_domain
  cimpl_tenant              = var.cimpl_tenant
  cimpl_project             = var.cimpl_project
  subscriber_private_key_id = var.cimpl_subscriber_private_key_id
  kustomize_path            = path.module
  nodepool_name             = local.osdu_nodepool_label
  platform_namespace        = local.platform_namespace

  preconditions = [
    { condition = !local.deploy_entitlements || var.enable_keycloak, error_message = "Entitlements requires Keycloak." },
    { condition = !local.deploy_entitlements || local.deploy_partition, error_message = "Entitlements requires Partition." },
    { condition = !local.deploy_entitlements || var.enable_postgresql, error_message = "Entitlements requires PostgreSQL." },
  ]

  depends_on = [module.osdu_common, module.keycloak, module.partition]
}

module "legal" {
  source = "./modules/osdu-service"

  service_name              = "legal"
  repository                = "oci://community.opengroup.org:5555/osdu/platform/security-and-compliance/legal/cimpl-helm"
  chart                     = "core-plus-legal-deploy"
  chart_version             = lookup(var.osdu_service_versions, "legal", var.osdu_chart_version)
  enable                    = local.deploy_legal
  enable_common             = local.deploy_common
  namespace                 = local.osdu_namespace
  osdu_domain               = local.osdu_domain
  cimpl_tenant              = var.cimpl_tenant
  cimpl_project             = var.cimpl_project
  subscriber_private_key_id = var.cimpl_subscriber_private_key_id
  kustomize_path            = path.module
  nodepool_name             = local.osdu_nodepool_label
  platform_namespace        = local.platform_namespace

  # Chart default image tag :64459360 does not exist for legal-status-update-master.
  # Override to the release image used by ROSA (qa/main/terraform/master-chart/variables.tf:724).
  extra_set = [
    {
      name  = "data.legalStatusUpdateImage"
      value = "community.opengroup.org:5555/osdu/platform/security-and-compliance/legal/legal-status-update-release:77a98643"
    },
  ]

  preconditions = [
    { condition = !local.deploy_legal || local.deploy_entitlements, error_message = "Legal requires Entitlements." },
    { condition = !local.deploy_legal || local.deploy_partition, error_message = "Legal requires Partition." },
    { condition = !local.deploy_legal || var.enable_postgresql, error_message = "Legal requires PostgreSQL." },
  ]

  depends_on = [module.osdu_common, module.entitlements]
}

# ─── Legal COO configuration ─────────────────────────────────────────────────
# The legal service reads a Legal_COO.json file from MinIO to determine which
# countries require client consent (e.g., Malaysia). On ROSA, the QA pipeline
# seeds this file; on AKS we provision it as part of the stack deploy.
# Two steps: (1) upload the file to MinIO, (2) register the bucket name as a
# partition property so the legal service can find it.

resource "null_resource" "legal_coo_seed" {
  count = local.deploy_legal && var.enable_minio ? 1 : 0

  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    interpreter = ["pwsh", "-Command"]
    command     = "& '${path.module}/scripts/legal-coo-seed.ps1' -PlatformNamespace '${local.platform_namespace}' -OsduNamespace '${local.osdu_namespace}' -CimplTenant '${var.cimpl_tenant}'"
  }

  depends_on = [module.minio, module.partition, module.osdu_common]
}

module "schema" {
  source = "./modules/osdu-service"

  service_name              = "schema"
  repository                = "oci://community.opengroup.org:5555/osdu/platform/system/schema-service/cimpl-helm"
  chart                     = "core-plus-schema-deploy"
  chart_version             = lookup(var.osdu_service_versions, "schema", var.osdu_chart_version)
  enable                    = local.deploy_schema
  enable_common             = local.deploy_common
  namespace                 = local.osdu_namespace
  osdu_domain               = local.osdu_domain
  cimpl_tenant              = var.cimpl_tenant
  cimpl_project             = var.cimpl_project
  subscriber_private_key_id = var.cimpl_subscriber_private_key_id
  kustomize_path            = path.module
  nodepool_name             = local.osdu_nodepool_label
  platform_namespace        = local.platform_namespace

  preconditions = [
    { condition = !local.deploy_schema || local.deploy_entitlements, error_message = "Schema requires Entitlements." },
    { condition = !local.deploy_schema || local.deploy_partition, error_message = "Schema requires Partition." },
    { condition = !local.deploy_schema || var.enable_postgresql, error_message = "Schema requires PostgreSQL." },
  ]

  depends_on = [module.osdu_common, module.entitlements]
}

module "storage" {
  source = "./modules/osdu-service"

  service_name              = "storage"
  repository                = "oci://community.opengroup.org:5555/osdu/platform/system/storage/cimpl-helm"
  chart                     = "core-plus-storage-deploy"
  chart_version             = lookup(var.osdu_service_versions, "storage", var.osdu_chart_version)
  enable                    = local.deploy_storage
  enable_common             = local.deploy_common
  namespace                 = local.osdu_namespace
  osdu_domain               = local.osdu_domain
  cimpl_tenant              = var.cimpl_tenant
  cimpl_project             = var.cimpl_project
  subscriber_private_key_id = var.cimpl_subscriber_private_key_id
  kustomize_path            = path.module
  nodepool_name             = local.osdu_nodepool_label
  platform_namespace        = local.platform_namespace

  preconditions = [
    { condition = !local.deploy_storage || local.deploy_legal, error_message = "Storage requires Legal." },
    { condition = !local.deploy_storage || local.deploy_entitlements, error_message = "Storage requires Entitlements." },
    { condition = !local.deploy_storage || local.deploy_partition, error_message = "Storage requires Partition." },
    { condition = !local.deploy_storage || var.enable_postgresql, error_message = "Storage requires PostgreSQL." },
  ]

  depends_on = [module.osdu_common, module.legal]
}

module "search" {
  source = "./modules/osdu-service"

  service_name              = "search"
  repository                = "oci://community.opengroup.org:5555/osdu/platform/system/search-service/cimpl-helm"
  chart                     = "core-plus-search-deploy"
  chart_version             = lookup(var.osdu_service_versions, "search", var.osdu_chart_version)
  enable                    = local.deploy_search
  enable_common             = local.deploy_common
  namespace                 = local.osdu_namespace
  osdu_domain               = local.osdu_domain
  cimpl_tenant              = var.cimpl_tenant
  cimpl_project             = var.cimpl_project
  subscriber_private_key_id = var.cimpl_subscriber_private_key_id
  kustomize_path            = path.module
  nodepool_name             = local.osdu_nodepool_label
  platform_namespace        = local.platform_namespace

  extra_set = []

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

  service_name              = "indexer"
  repository                = "oci://community.opengroup.org:5555/osdu/platform/system/indexer-service/cimpl-helm"
  chart                     = "core-plus-indexer-deploy"
  chart_version             = lookup(var.osdu_service_versions, "indexer", var.osdu_chart_version)
  enable                    = local.deploy_indexer
  enable_common             = local.deploy_common
  namespace                 = local.osdu_namespace
  osdu_domain               = local.osdu_domain
  cimpl_tenant              = var.cimpl_tenant
  cimpl_project             = var.cimpl_project
  subscriber_private_key_id = var.cimpl_subscriber_private_key_id
  kustomize_path            = path.module
  nodepool_name             = local.osdu_nodepool_label
  platform_namespace        = local.platform_namespace

  extra_set = []

  preconditions = [
    { condition = !local.deploy_indexer || local.deploy_entitlements, error_message = "Indexer requires Entitlements." },
    { condition = !local.deploy_indexer || local.deploy_partition, error_message = "Indexer requires Partition." },
    { condition = !local.deploy_indexer || var.enable_elasticsearch, error_message = "Indexer requires Elasticsearch." },
    { condition = !local.deploy_indexer || var.enable_elastic_bootstrap, error_message = "Indexer requires Elastic Bootstrap." },
  ]

  depends_on = [module.osdu_common, module.storage]
}

module "file" {
  source = "./modules/osdu-service"

  service_name              = "file"
  repository                = "oci://community.opengroup.org:5555/osdu/platform/system/file/cimpl-helm"
  chart                     = "core-plus-file-deploy"
  chart_version             = lookup(var.osdu_service_versions, "file", var.osdu_chart_version)
  enable                    = local.deploy_file
  enable_common             = local.deploy_common
  namespace                 = local.osdu_namespace
  osdu_domain               = local.osdu_domain
  cimpl_tenant              = var.cimpl_tenant
  cimpl_project             = var.cimpl_project
  subscriber_private_key_id = var.cimpl_subscriber_private_key_id
  kustomize_path            = path.module
  nodepool_name             = local.osdu_nodepool_label
  platform_namespace        = local.platform_namespace

  preconditions = [
    { condition = !local.deploy_file || local.deploy_legal, error_message = "File requires Legal." },
    { condition = !local.deploy_file || local.deploy_entitlements, error_message = "File requires Entitlements." },
    { condition = !local.deploy_file || local.deploy_partition, error_message = "File requires Partition." },
    { condition = !local.deploy_file || var.enable_postgresql, error_message = "File requires PostgreSQL." },
  ]

  depends_on = [module.osdu_common, module.legal]
}

module "notification" {
  source = "./modules/osdu-service"

  service_name              = "notification"
  repository                = "oci://community.opengroup.org:5555/osdu/platform/system/notification/cimpl-helm"
  chart                     = "core-plus-notification-deploy"
  chart_version             = lookup(var.osdu_service_versions, "notification", var.osdu_chart_version)
  enable                    = local.deploy_notification
  enable_common             = local.deploy_common
  namespace                 = local.osdu_namespace
  osdu_domain               = local.osdu_domain
  cimpl_tenant              = var.cimpl_tenant
  cimpl_project             = var.cimpl_project
  subscriber_private_key_id = var.cimpl_subscriber_private_key_id
  kustomize_path            = path.module
  nodepool_name             = local.osdu_nodepool_label
  platform_namespace        = local.platform_namespace

  extra_set = [
    {
      name  = "data.rabbitmqHost"
      value = local.rabbitmq_host
    }
  ]

  preconditions = [
    { condition = !local.deploy_notification || local.deploy_entitlements, error_message = "Notification requires Entitlements." },
    { condition = !local.deploy_notification || local.deploy_partition, error_message = "Notification requires Partition." },
    { condition = !local.deploy_notification || var.enable_rabbitmq, error_message = "Notification requires RabbitMQ." },
  ]

  depends_on = [module.osdu_common, module.entitlements]
}

module "dataset" {
  source = "./modules/osdu-service"

  service_name              = "dataset"
  repository                = "oci://community.opengroup.org:5555/osdu/platform/system/dataset/cimpl-helm"
  chart                     = "core-plus-dataset-deploy"
  chart_version             = lookup(var.osdu_service_versions, "dataset", var.osdu_chart_version)
  enable                    = local.deploy_dataset
  enable_common             = local.deploy_common
  namespace                 = local.osdu_namespace
  osdu_domain               = local.osdu_domain
  cimpl_tenant              = var.cimpl_tenant
  cimpl_project             = var.cimpl_project
  subscriber_private_key_id = var.cimpl_subscriber_private_key_id
  kustomize_path            = path.module
  nodepool_name             = local.osdu_nodepool_label
  platform_namespace        = local.platform_namespace

  preconditions = [
    { condition = !local.deploy_dataset || local.deploy_entitlements, error_message = "Dataset requires Entitlements." },
    { condition = !local.deploy_dataset || local.deploy_partition, error_message = "Dataset requires Partition." },
    { condition = !local.deploy_dataset || local.deploy_storage, error_message = "Dataset requires Storage." },
    { condition = !local.deploy_dataset || var.enable_postgresql, error_message = "Dataset requires PostgreSQL." },
  ]

  depends_on = [module.osdu_common, module.storage]
}

module "register" {
  source = "./modules/osdu-service"

  service_name              = "register"
  repository                = "oci://community.opengroup.org:5555/osdu/platform/system/register/cimpl-helm"
  chart                     = "core-plus-register-deploy"
  chart_version             = lookup(var.osdu_service_versions, "register", var.osdu_chart_version)
  enable                    = local.deploy_register
  enable_common             = local.deploy_common
  namespace                 = local.osdu_namespace
  osdu_domain               = local.osdu_domain
  cimpl_tenant              = var.cimpl_tenant
  cimpl_project             = var.cimpl_project
  subscriber_private_key_id = var.cimpl_subscriber_private_key_id
  kustomize_path            = path.module
  nodepool_name             = local.osdu_nodepool_label
  platform_namespace        = local.platform_namespace

  preconditions = [
    { condition = !local.deploy_register || local.deploy_entitlements, error_message = "Register requires Entitlements." },
    { condition = !local.deploy_register || local.deploy_partition, error_message = "Register requires Partition." },
    { condition = !local.deploy_register || var.enable_postgresql, error_message = "Register requires PostgreSQL." },
  ]

  depends_on = [module.osdu_common, module.entitlements]
}

module "policy" {
  source = "./modules/osdu-service"

  service_name              = "policy"
  repository                = "oci://community.opengroup.org:5555/osdu/platform/security-and-compliance/policy/cimpl-helm"
  chart                     = "core-plus-policy-deploy"
  chart_version             = lookup(var.osdu_service_versions, "policy", var.osdu_chart_version)
  enable                    = local.deploy_policy
  enable_common             = local.deploy_common
  namespace                 = local.osdu_namespace
  osdu_domain               = local.osdu_domain
  cimpl_tenant              = var.cimpl_tenant
  cimpl_project             = var.cimpl_project
  subscriber_private_key_id = var.cimpl_subscriber_private_key_id
  kustomize_path            = path.module
  nodepool_name             = local.osdu_nodepool_label
  platform_namespace        = local.platform_namespace

  preconditions = [
    { condition = !local.deploy_policy || local.deploy_entitlements, error_message = "Policy requires Entitlements." },
    { condition = !local.deploy_policy || local.deploy_partition, error_message = "Policy requires Partition." },
  ]

  depends_on = [module.osdu_common, module.entitlements]
}

module "secret" {
  source = "./modules/osdu-service"

  service_name              = "secret"
  repository                = "oci://community.opengroup.org:5555/osdu/platform/security-and-compliance/secret/cimpl-helm"
  chart                     = "core-plus-secret-deploy"
  chart_version             = lookup(var.osdu_service_versions, "secret", var.osdu_chart_version)
  enable                    = local.deploy_secret
  enable_common             = local.deploy_common
  namespace                 = local.osdu_namespace
  osdu_domain               = local.osdu_domain
  cimpl_tenant              = var.cimpl_tenant
  cimpl_project             = var.cimpl_project
  subscriber_private_key_id = var.cimpl_subscriber_private_key_id
  kustomize_path            = path.module
  nodepool_name             = local.osdu_nodepool_label
  platform_namespace        = local.platform_namespace

  # Note: data.secretAdminNamespace defaults to "secret-admin" in the chart.
  # The chart creates a namespace named "{release-namespace}-{secretAdminNamespace}",
  # so the default produces "osdu-secret-admin". Do NOT set this to the release
  # namespace value (e.g. "osdu") or it creates a redundant "osdu-osdu" namespace.

  preconditions = [
    { condition = !local.deploy_secret || local.deploy_entitlements, error_message = "Secret requires Entitlements." },
    { condition = !local.deploy_secret || local.deploy_partition, error_message = "Secret requires Partition." },
  ]

  depends_on = [module.osdu_common, module.entitlements]
}

module "workflow" {
  source = "./modules/osdu-service"

  service_name              = "workflow"
  repository                = "oci://community.opengroup.org:5555/osdu/platform/data-flow/ingestion/ingestion-workflow/cimpl-helm"
  chart                     = "core-plus-workflow-deploy"
  chart_version             = lookup(var.osdu_service_versions, "workflow", var.osdu_chart_version)
  enable                    = local.deploy_workflow
  enable_common             = local.deploy_common
  namespace                 = local.osdu_namespace
  osdu_domain               = local.osdu_domain
  cimpl_tenant              = var.cimpl_tenant
  cimpl_project             = var.cimpl_project
  subscriber_private_key_id = var.cimpl_subscriber_private_key_id
  kustomize_path            = path.module
  nodepool_name             = local.osdu_nodepool_label
  platform_namespace        = local.platform_namespace

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
    { condition = !local.deploy_workflow || var.enable_postgresql, error_message = "Workflow requires PostgreSQL." },
    { condition = !local.deploy_workflow || var.enable_airflow, error_message = "Workflow requires Airflow." },
  ]

  depends_on = [module.osdu_common, module.storage]
}
