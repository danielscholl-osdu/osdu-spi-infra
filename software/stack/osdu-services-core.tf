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
# Uses the local osdu-spi-service Helm chart with AKS Automatic compliance
# baked in (seccomp, security context, topology spread). No kustomize postrender.
# Images default to OSDU community registry, master branch.
#
# Env vars aligned with osdu-developer reference deployment.

module "partition" {
  source = "./modules/osdu-spi-service"

  service_name     = "partition"
  image_repository = local.osdu_images["partition"].repository
  image_tag        = local.osdu_images["partition"].tag
  enable           = local.deploy_partition
  enable_common    = local.deploy_common
  namespace        = local.osdu_namespace
  redis_tls        = true

  env = [
    { name = "SPRING_APPLICATION_NAME", value = "partition" },
    { name = "SERVER_SERVLET_CONTEXTPATH", value = "/api/partition/v1/" },

    { name = "ACCEPT_HTTP", value = "true" },
    { name = "AZURE_ISTIOAUTH_ENABLED", value = "true" },
    { name = "AZURE_PAAS_WORKLOADIDENTITY_ISENABLED", value = "true" },
    { name = "REDIS_DATABASE", value = "1" },
    { name = "PARTITION_SPRING_LOGGING_LEVEL", value = "DEBUG" },
  ]

  depends_on = [module.osdu_common]
}

module "entitlements" {
  source = "./modules/osdu-spi-service"

  service_name     = "entitlements"
  image_repository = local.osdu_images["entitlements"].repository
  image_tag        = local.osdu_images["entitlements"].tag
  enable           = local.deploy_entitlements
  enable_common    = local.deploy_common
  namespace        = local.osdu_namespace
  redis_tls        = true

  env = [
    { name = "SPRING_APPLICATION_NAME", value = "entitlements" },
    { name = "SERVER_SERVLET_CONTEXTPATH", value = "/api/entitlements/v2/" },

    { name = "ACCEPT_HTTP", value = "true" },
    { name = "AZURE_ISTIOAUTH_ENABLED", value = "true" },
    { name = "AZURE_PAAS_WORKLOADIDENTITY_ISENABLED", value = "true" },
    { name = "SPRING_CONFIG_NAME", value = "common,application" },
    { name = "SERVICE_DOMAIN_NAME", value = "dataservices.energy" },
    { name = "ROOT_DATA_GROUP_QUOTA", value = "5000" },
    { name = "REDIS_TTL_SECONDS", value = "1" },
    { name = "REDIS_DATABASE", value = "2" },
    { name = "PARTITION_SERVICE_ENDPOINT", value = "http://partition/api/partition/v1" },
  ]

  preconditions = [
    { condition = !local.deploy_entitlements || local.deploy_partition, error_message = "Entitlements requires Partition." },
  ]

  depends_on = [module.osdu_common, module.partition]
}

module "legal" {
  source = "./modules/osdu-spi-service"

  service_name     = "legal"
  image_repository = local.osdu_images["legal"].repository
  image_tag        = local.osdu_images["legal"].tag
  enable           = local.deploy_legal
  enable_common    = local.deploy_common
  namespace        = local.osdu_namespace
  redis_tls        = true

  env = [
    { name = "SPRING_APPLICATION_NAME", value = "legal" },
    { name = "SERVER_SERVLET_CONTEXTPATH", value = "/api/legal/v1/" },

    { name = "ACCEPT_HTTP", value = "true" },
    { name = "AZURE_ISTIOAUTH_ENABLED", value = "true" },
    { name = "AZURE_PAAS_WORKLOADIDENTITY_ISENABLED", value = "true" },
    { name = "SPRING_CONFIG_NAME", value = "common,application" },
    { name = "COSMOSDB_DATABASE", value = "osdu-db" },
    { name = "AZURE_STORAGE_ENABLE_HTTPS", value = "true" },
    { name = "AZURE_STORAGE_CONTAINER_NAME", value = "legal-service-azure-configuration" },
    { name = "LEGAL_SERVICE_REGION", value = "us" },
    { name = "SERVICEBUS_TOPIC_NAME", value = "legaltags" },
    { name = "REDIS_DATABASE", value = "2" },
    { name = "PARTITION_SERVICE_ENDPOINT", value = "http://partition/api/partition/v1" },
    { name = "ENTITLEMENTS_SERVICE_ENDPOINT", value = "http://entitlements/api/entitlements/v2" },
    { name = "ENTITLEMENTS_SERVICE_API_KEY", value = "OBSOLETE" },
  ]

  preconditions = [
    { condition = !local.deploy_legal || local.deploy_entitlements, error_message = "Legal requires Entitlements." },
    { condition = !local.deploy_legal || local.deploy_partition, error_message = "Legal requires Partition." },
  ]

  depends_on = [module.osdu_common, module.entitlements]
}

module "schema" {
  source = "./modules/osdu-spi-service"

  service_name     = "schema"
  image_repository = local.osdu_images["schema"].repository
  image_tag        = local.osdu_images["schema"].tag
  enable           = local.deploy_schema
  enable_common    = local.deploy_common
  namespace        = local.osdu_namespace
  redis_tls        = true

  env = [
    { name = "SPRING_APPLICATION_NAME", value = "schema" },
    { name = "SERVER_SERVLET_CONTEXTPATH", value = "/api/schema-service/v1/" },
    { name = "SERVER_PORT", value = "8080" },

    { name = "ACCEPT_HTTP", value = "true" },
    { name = "AZURE_ISTIOAUTH_ENABLED", value = "true" },
    { name = "AZURE_PAAS_WORKLOADIDENTITY_ISENABLED", value = "true" },
    { name = "COSMOSDB_DATABASE", value = "osdu-db" },
    { name = "AZURE_SYSTEM_STORAGECONTAINERNAME", value = "system" },
    { name = "SERVICEBUS_TOPIC_NAME", value = "schemachangedtopic" },
    { name = "EVENT_GRID_ENABLED", value = "false" },
    { name = "EVENT_GRID_TOPIC", value = "schemachangedtopic" },
    { name = "SERVICE_BUS_ENABLED", value = "true" },
    { name = "PARTITION_SERVICE_ENDPOINT", value = "http://partition/api/partition/v1" },
    { name = "ENTITLEMENTS_SERVICE_ENDPOINT", value = "http://entitlements/api/entitlements/v2" },
    { name = "ENTITLEMENTS_SERVICE_API_KEY", value = "OBSOLETE" },
  ]

  preconditions = [
    { condition = !local.deploy_schema || local.deploy_entitlements, error_message = "Schema requires Entitlements." },
    { condition = !local.deploy_schema || local.deploy_partition, error_message = "Schema requires Partition." },
  ]

  depends_on = [module.osdu_common, module.entitlements]
}

module "storage" {
  source = "./modules/osdu-spi-service"

  service_name     = "storage"
  image_repository = local.osdu_images["storage"].repository
  image_tag        = local.osdu_images["storage"].tag
  enable           = local.deploy_storage
  enable_common    = local.deploy_common
  namespace        = local.osdu_namespace
  redis_tls        = true
  istio_proxy_pin  = true

  env = [
    { name = "SPRING_APPLICATION_NAME", value = "storage" },
    { name = "SERVER_SERVLET_CONTEXTPATH", value = "/api/storage/v2/" },

    { name = "ACCEPT_HTTP", value = "true" },
    { name = "AZURE_ISTIOAUTH_ENABLED", value = "true" },
    { name = "AZURE_PAAS_WORKLOADIDENTITY_ISENABLED", value = "true" },
    { name = "COSMOSDB_DATABASE", value = "osdu-db" },
    { name = "AZURE_SERVICEBUS_ENABLED", value = "true" },
    { name = "AZURE_EVENTGRID_ENABLED", value = "false" },
    { name = "SERVICEBUS_TOPIC_NAME", value = "recordstopic" },
    { name = "SERVICEBUS_V2_TOPIC_NAME", value = "recordstopic-v2" },
    { name = "REDIS_DATABASE", value = "4" },
    { name = "PARTITION_SERVICE_ENDPOINT", value = "http://partition/api/partition/v1" },
    { name = "ENTITLEMENTS_SERVICE_ENDPOINT", value = "http://entitlements/api/entitlements/v2" },
    { name = "ENTITLEMENTS_SERVICE_API_KEY", value = "OBSOLETE" },
    { name = "LEGAL_SERVICE_ENDPOINT", value = "http://legal/api/legal/v1" },
    { name = "LEGAL_SERVICE_REGION", value = "southcentralus" },
    { name = "LEGAL_SERVICEBUS_TOPIC_NAME", value = "legaltagschangedtopiceg" },
    { name = "LEGAL_SERVICEBUS_TOPIC_SUBSCRIPTION", value = "eg_sb_legaltagchangedsubscription" },
    { name = "CRS_CONVERSION_SERVICE_ENDPOINT", value = "http://crs-conversion/api/crs/converter/v2" },
    { name = "POLICY_SERVICE_ENDPOINT", value = "http://policy/api/policy/v1" },
    { name = "OPA_ENABLED", value = "false" },
  ]

  preconditions = [
    { condition = !local.deploy_storage || local.deploy_legal, error_message = "Storage requires Legal." },
    { condition = !local.deploy_storage || local.deploy_entitlements, error_message = "Storage requires Entitlements." },
    { condition = !local.deploy_storage || local.deploy_partition, error_message = "Storage requires Partition." },
  ]

  depends_on = [module.osdu_common, module.legal]
}

module "search" {
  source = "./modules/osdu-spi-service"

  service_name     = "search"
  image_repository = local.osdu_images["search"].repository
  image_tag        = local.osdu_images["search"].tag
  enable           = local.deploy_search
  enable_common    = local.deploy_common
  namespace        = local.osdu_namespace
  elastic_tls      = true
  redis_tls        = true

  env = [
    { name = "SPRING_APPLICATION_NAME", value = "search" },
    { name = "SERVER_SERVLET_CONTEXTPATH", value = "/api/search/v2/" },

    { name = "ACCEPT_HTTP", value = "true" },
    { name = "AZURE_ISTIOAUTH_ENABLED", value = "true" },
    { name = "AZURE_PAAS_WORKLOADIDENTITY_ISENABLED", value = "true" },
    { name = "COSMOSDB_DATABASE", value = "osdu-db" },
    { name = "REDIS_DATABASE", value = "5" },
    { name = "ENVIRONMENT", value = "evt" },
    { name = "ELASTIC_CACHE_EXPIRATION", value = "1" },
    { name = "MAX_CACHE_VALUE_SIZE", value = "60" },
    { name = "POLICY_SERVICE_ENABLED", value = "false" },
    { name = "PARTITION_SERVICE_ENDPOINT", value = "http://partition/api/partition/v1" },
    { name = "ENTITLEMENTS_SERVICE_ENDPOINT", value = "http://entitlements/api/entitlements/v2" },
    { name = "ENTITLEMENTS_SERVICE_API_KEY", value = "OBSOLETE" },
    { name = "POLICY_SERVICE_ENDPOINT", value = "http://policy/api/policy/v1" },
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
  source = "./modules/osdu-spi-service"

  service_name     = "indexer"
  image_repository = local.osdu_images["indexer"].repository
  image_tag        = local.osdu_images["indexer"].tag
  enable           = local.deploy_indexer
  enable_common    = local.deploy_common
  namespace        = local.osdu_namespace
  elastic_tls      = true
  redis_tls        = true
  istio_proxy_pin  = true

  env = [
    { name = "SPRING_APPLICATION_NAME", value = "indexer" },
    { name = "SERVER_SERVLET_CONTEXTPATH", value = "/api/indexer/v2/" },

    { name = "ACCEPT_HTTP", value = "true" },
    { name = "AZURE_ISTIOAUTH_ENABLED", value = "true" },
    { name = "AZURE_PAAS_WORKLOADIDENTITY_ISENABLED", value = "true" },
    { name = "SECURITY_HTTPS_CERTIFICATE_TRUST", value = "true" },
    { name = "COSMOSDB_DATABASE", value = "osdu-db" },
    { name = "SERVICEBUS_TOPIC_NAME", value = "indexing-progress" },
    { name = "REINDEX_TOPIC_NAME", value = "recordstopic" },
    { name = "REDIS_DATABASE", value = "4" },
    { name = "REDIS_TTL_SECONDS", value = "3600" },
    { name = "PARTITION_SERVICE_ENDPOINT", value = "http://partition/api/partition/v1" },
    { name = "ENTITLEMENTS_SERVICE_ENDPOINT", value = "http://entitlements/api/entitlements/v2" },
    { name = "ENTITLEMENTS_SERVICE_API_KEY", value = "OBSOLETE" },
    { name = "SCHEMA_SERVICE_URL", value = "http://schema/api/schema-service/v1" },
    { name = "STORAGE_SERVICE_URL", value = "http://storage/api/storage/v2" },
    { name = "STORAGE_SCHEMA_HOST", value = "http://storage/api/storage/v2/schemas" },
    { name = "STORAGE_QUERY_RECORD_FOR_CONVERSION_HOST", value = "http://storage/api/storage/v2/query/records:batch" },
    { name = "STORAGE_QUERY_RECORD_HOST", value = "http://storage/api/storage/v2/query/records" },
    { name = "SEARCH_SERVICE_URL", value = "http://search/api/search/v2" },
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
  source = "./modules/osdu-spi-service"

  service_name     = "indexer-queue"
  image_repository = local.osdu_images["indexer_queue"].repository
  image_tag        = local.osdu_images["indexer_queue"].tag
  enable           = local.deploy_indexer_queue
  enable_common    = local.deploy_common
  namespace        = local.osdu_namespace

  env = [
    { name = "SPRING_APPLICATION_NAME", value = "indexer-queue" },

    { name = "AZURE_ISTIOAUTH_ENABLED", value = "true" },
    { name = "AZURE_PAAS_WORKLOADIDENTITY_ISENABLED", value = "true" },
    { name = "AZURE_SERVICEBUS_TOPIC_NAME", value = "recordstopic" },
    { name = "AZURE_REINDEX_TOPIC_NAME", value = "reindextopic" },
    { name = "AZURE_SERVICEBUS_TOPIC_SUBSCRIPTION", value = "recordstopicsubscription" },
    { name = "AZURE_REINDEX_TOPIC_SUBSCRIPTION", value = "reindextopicsubscription" },
    { name = "AZURE_SCHEMACHANGED_TOPIC_NAME", value = "schemachangedtopic" },
    { name = "AZURE_SCHEMACHANGED_TOPIC_SUBSCRIPTION", value = "schemachangedtopiceg" },
    { name = "MAX_CONCURRENT_CALLS", value = "32" },
    { name = "MAX_DELIVERY_COUNT", value = "5" },
    { name = "EXECUTOR_N_THREADS", value = "32" },
    { name = "MAX_LOCK_RENEW_DURATION_SECONDS", value = "600" },
    { name = "PARTITION_API", value = "http://partition/api/partition/v1" },
    { name = "INDEXER_WORKER_URL", value = "http://indexer/api/indexer/v2/_dps/task-handlers/index-worker" },
    { name = "schema_worker_url", value = "http://indexer/api/indexer/v2/_dps/task-handlers/schema-worker" },
    { name = "AZURE_APP_RESOURCE_ID", value = var.osdu_identity_client_id },
  ]

  preconditions = [
    { condition = !local.deploy_indexer_queue || local.deploy_indexer, error_message = "Indexer Queue requires Indexer." },
    { condition = !local.deploy_indexer_queue || local.deploy_storage, error_message = "Indexer Queue requires Storage." },
  ]

  depends_on = [module.osdu_common, module.indexer]
}

module "file" {
  source = "./modules/osdu-spi-service"

  service_name     = "file"
  image_repository = local.osdu_images["file"].repository
  image_tag        = local.osdu_images["file"].tag
  enable           = local.deploy_file
  enable_common    = local.deploy_common
  namespace        = local.osdu_namespace
  redis_tls        = true
  istio_proxy_pin  = true

  env = [
    { name = "SPRING_APPLICATION_NAME", value = "file" },
    { name = "SERVER_SERVLET_CONTEXTPATH", value = "/api/file/" },

    { name = "ACCEPT_HTTP", value = "true" },
    { name = "AZURE_ISTIOAUTH_ENABLED", value = "true" },
    { name = "AZURE_PAAS_WORKLOADIDENTITY_ISENABLED", value = "true" },
    { name = "SPRING_CONFIG_NAME", value = "common,application" },
    { name = "COSMOSDB_DATABASE", value = "osdu-db" },
    { name = "OSDU_ENTITLEMENTS_APP_KEY", value = "OBSOLETE" },
    { name = "AZURE_PUBSUB_PUBLISH", value = "true" },
    { name = "SERVICE_BUS_ENABLED_STATUS", value = "true" },
    { name = "SERVICE_BUS_TOPIC_STATUS", value = "statuschangedtopic" },
    { name = "BATCH_SIZE", value = "100" },
    { name = "SEARCH_QUERY_LIMIT", value = "1000" },
    { name = "PARTITION_SERVICE_ENDPOINT", value = "http://partition/api/partition/v1" },
    { name = "OSDU_ENTITLEMENTS_URL", value = "http://entitlements/api/entitlements/v2" },
    { name = "authorizeAPI", value = "http://entitlements/api/entitlements/v2" },
    { name = "OSDU_STORAGE_URL", value = "http://storage/api/storage/v2" },
    { name = "SEARCH_HOST", value = "http://search/api/search/v2" },
    { name = "AZURE_AD_APP_RESOURCE_ID", value = var.osdu_identity_client_id },
    { name = "AAD_CLIENT_ID", value = var.osdu_identity_client_id },
  ]

  preconditions = [
    { condition = !local.deploy_file || local.deploy_legal, error_message = "File requires Legal." },
    { condition = !local.deploy_file || local.deploy_entitlements, error_message = "File requires Entitlements." },
    { condition = !local.deploy_file || local.deploy_partition, error_message = "File requires Partition." },
  ]

  depends_on = [module.osdu_common, module.legal]
}

module "workflow" {
  source = "./modules/osdu-spi-service"

  service_name     = "workflow"
  image_repository = local.osdu_images["workflow"].repository
  image_tag        = local.osdu_images["workflow"].tag
  enable           = local.deploy_workflow
  enable_common    = local.deploy_common
  namespace        = local.osdu_namespace
  redis_tls        = true

  env = [
    { name = "SPRING_APPLICATION_NAME", value = "workflow" },
    { name = "SERVER_SERVLET_CONTEXTPATH", value = "/api/workflow/" },

    { name = "ACCEPT_HTTP", value = "true" },
    { name = "AZURE_ISTIOAUTH_ENABLED", value = "true" },
    { name = "AZURE_PAAS_WORKLOADIDENTITY_ISENABLED", value = "true" },
    { name = "SPRING_CONFIG_NAME", value = "common,application" },
    { name = "COSMOSDB_DATABASE", value = "osdu-db" },
    { name = "COSMOSDB_SYSTEM_DATABASE", value = "osdu-system-db" },
    { name = "AZURE_STORAGE_ENABLE_HTTPS", value = "true" },
    { name = "AUTHORIZEAPI", value = "http://entitlements/api/entitlements/v2" },
    { name = "AUTHORIZEAPIKEY", value = "OBSOLETE" },
    { name = "PARTITION_SERVICE_ENDPOINT", value = "http://partition/api/partition/v1" },
    { name = "OSDU_ENTITLEMENTS_URL", value = "http://entitlements/api/entitlements/v2" },
    { name = "OSDU_ENTITLEMENTS_APPKEY", value = "OBSOLETE" },
    { name = "OSDU_AIRFLOW_URL", value = "http://airflow-web.${local.platform_namespace}.svc.cluster.local:8080/airflow" },
    { name = "OSDU_AIRFLOW_VERSION2_ENABLED", value = "true" },
    { name = "DP_AIRFLOW_FOR_SYSTEM_DAG", value = "false" },
    { name = "IGNORE_DAGCONTENT", value = "true" },
    { name = "IGNORE_CUSTOMOPERATORCONTENT", value = "true" },
  ]

  preconditions = [
    { condition = !local.deploy_workflow || local.deploy_entitlements, error_message = "Workflow requires Entitlements." },
    { condition = !local.deploy_workflow || local.deploy_partition, error_message = "Workflow requires Partition." },
    { condition = !local.deploy_workflow || local.deploy_storage, error_message = "Workflow requires Storage." },
    { condition = !local.deploy_workflow || var.enable_airflow, error_message = "Workflow requires Airflow." },
  ]

  depends_on = [module.osdu_common, module.storage]
}
