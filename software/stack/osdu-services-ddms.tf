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

# OSDU DDMS (Domain Data Management) service deployments (Azure SPI variant)
#
# Domain-specific services: Wellbore, Wellbore Worker, EDS DMS, Open ETP Server.
# These require core services and are gated by the DDMS group switch.

module "wellbore" {
  source = "./modules/osdu-spi-service"

  service_name     = "wellbore"
  image_repository = local.osdu_images["wellbore"].repository
  image_tag        = local.osdu_images["wellbore"].tag
  enable           = local.deploy_wellbore
  enable_common    = local.deploy_common
  namespace        = local.osdu_namespace
  redis_tls        = true

  # Wellbore is a Python FastAPI service — uses CLOUD_PROVIDER and SERVICE_HOST_* env vars
  container_port = 8080

  env = [
    { name = "CLOUD_PROVIDER", value = "az" },
    { name = "SERVICE_HOST_SEARCH", value = "http://search/api/search/v2" },
    { name = "SERVICE_HOST_SCHEMA", value = "http://schema/api/schema-service/v1" },
    { name = "SERVICE_HOST_STORAGE", value = "http://storage/api/storage/v2" },
    { name = "SERVICE_HOST_PARTITION", value = "http://partition/api/partition/v1" },
    { name = "SERVICE_HOST_ENTITLEMENTS", value = "http://entitlements/api/entitlements/v2" },
    { name = "SERVICE_HOST_LEGAL", value = "http://legal/api/legal/v1" },
    { name = "SERVICE_HOST_FILE", value = "http://file/api/file" },
  ]

  # Python FastAPI probes on port 8080
  probes = {
    liveness = {
      path                = "/api/os-wellbore-ddms/about"
      port                = 8080
      initialDelaySeconds = 30
      periodSeconds       = 10
      timeoutSeconds      = 5
      failureThreshold    = 6
    }
    readiness = {
      path                = "/api/os-wellbore-ddms/about"
      port                = 8080
      initialDelaySeconds = 10
      periodSeconds       = 10
      timeoutSeconds      = 5
      failureThreshold    = 3
    }
  }

  preconditions = [
    { condition = !local.deploy_wellbore || local.deploy_storage, error_message = "Wellbore requires Storage." },
    { condition = !local.deploy_wellbore || local.deploy_entitlements, error_message = "Wellbore requires Entitlements." },
    { condition = !local.deploy_wellbore || local.deploy_partition, error_message = "Wellbore requires Partition." },
  ]

  depends_on = [module.osdu_common, module.storage]
}

module "wellbore_worker" {
  source = "./modules/osdu-spi-service"

  service_name     = "wellbore-worker"
  image_repository = local.osdu_images["wellbore_worker"].repository
  image_tag        = local.osdu_images["wellbore_worker"].tag
  enable           = local.deploy_wellbore_worker
  enable_common    = local.deploy_common
  namespace        = local.osdu_namespace
  redis_tls        = true

  # Wellbore worker is also Python FastAPI
  container_port = 8080

  env = [
    { name = "CLOUD_PROVIDER", value = "az" },
    { name = "SERVICE_HOST_SEARCH", value = "http://search/api/search/v2" },
    { name = "SERVICE_HOST_SCHEMA", value = "http://schema/api/schema-service/v1" },
    { name = "SERVICE_HOST_STORAGE", value = "http://storage/api/storage/v2" },
    { name = "SERVICE_HOST_PARTITION", value = "http://partition/api/partition/v1" },
    { name = "SERVICE_HOST_ENTITLEMENTS", value = "http://entitlements/api/entitlements/v2" },
    { name = "SERVICE_HOST_WELLBORE", value = "http://wellbore/api/os-wellbore-ddms" },
  ]

  probes = {
    liveness = {
      path                = "/api/os-wellbore-ddms/worker/about"
      port                = 8080
      initialDelaySeconds = 30
      periodSeconds       = 10
      timeoutSeconds      = 5
      failureThreshold    = 6
    }
    readiness = {
      path                = "/api/os-wellbore-ddms/worker/about"
      port                = 8080
      initialDelaySeconds = 10
      periodSeconds       = 10
      timeoutSeconds      = 5
      failureThreshold    = 3
    }
  }

  preconditions = [
    { condition = !local.deploy_wellbore_worker || local.deploy_wellbore, error_message = "Wellbore Worker requires Wellbore." },
  ]

  depends_on = [module.osdu_common, module.wellbore]
}

module "eds_dms" {
  source = "./modules/osdu-spi-service"

  service_name     = "eds-dms"
  image_repository = local.osdu_images["eds_dms"].repository
  image_tag        = local.osdu_images["eds_dms"].tag
  enable           = local.deploy_eds_dms
  enable_common    = local.deploy_common
  namespace        = local.osdu_namespace
  redis_tls        = true

  env = [
    { name = "SPRING_APPLICATION_NAME", value = "eds-dms" },
    { name = "SERVER_SERVLET_CONTEXTPATH", value = "/api/eds/v1/" },

    { name = "ACCEPT_HTTP", value = "true" },
    { name = "AZURE_ISTIOAUTH_ENABLED", value = "true" },
    { name = "AZURE_PAAS_WORKLOADIDENTITY_ISENABLED", value = "true" },
    { name = "COSMOSDB_DATABASE", value = "osdu-db" },
    { name = "PARTITION_SERVICE_ENDPOINT", value = "http://partition/api/partition/v1" },
    { name = "ENTITLEMENTS_SERVICE_ENDPOINT", value = "http://entitlements/api/entitlements/v2" },
    { name = "ENTITLEMENTS_SERVICE_API_KEY", value = "OBSOLETE" },
    { name = "STORAGE_SERVICE_ENDPOINT", value = "http://storage/api/storage/v2" },
    { name = "SCHEMA_SERVICE_ENDPOINT", value = "http://schema/api/schema-service/v1" },
    { name = "DATASET_SERVICE_ENDPOINT", value = "http://dataset/api/dataset/v1" },
    { name = "KEY_VAULT_URL", value = var.keyvault_uri },
    { name = "AUTHORIZE_API", value = "http://entitlements/api/entitlements/v2" },
    { name = "AUTHORIZE_API_KEY", value = "OBSOLETE" },
    { name = "PARTITION_API", value = "http://partition/api/partition/v1" },
    { name = "STORAGE_API", value = "http://storage/api/storage/v2" },
    { name = "SCHEMA_API", value = "http://schema/api/schema-service/v1" },
    { name = "DATASET_API", value = "http://dataset/api/dataset/v1" },
    { name = "SEARCH_API", value = "http://search/api/search/v2" },
  ]

  preconditions = [
    { condition = !local.deploy_eds_dms || local.deploy_storage, error_message = "EDS DMS requires Storage." },
    { condition = !local.deploy_eds_dms || local.deploy_entitlements, error_message = "EDS DMS requires Entitlements." },
    { condition = !local.deploy_eds_dms || local.deploy_partition, error_message = "EDS DMS requires Partition." },
  ]

  depends_on = [module.osdu_common, module.storage]
}

module "oetp_server" {
  source = "./modules/osdu-spi-service"

  service_name     = "oetp-server"
  image_repository = local.osdu_images["oetp_server"].repository
  image_tag        = local.osdu_images["oetp_server"].tag
  enable           = local.deploy_oetp_server
  enable_common    = local.deploy_common
  namespace        = local.osdu_namespace
  redis_tls        = true

  env = [
    { name = "SPRING_APPLICATION_NAME", value = "oetp-server" },
    { name = "SERVER_SERVLET_CONTEXTPATH", value = "/api/oetp/v1/" },

    { name = "ACCEPT_HTTP", value = "true" },
    { name = "AZURE_ISTIOAUTH_ENABLED", value = "true" },
    { name = "AZURE_PAAS_WORKLOADIDENTITY_ISENABLED", value = "true" },
    { name = "COSMOSDB_DATABASE", value = "osdu-db" },
    { name = "PARTITION_SERVICE_ENDPOINT", value = "http://partition/api/partition/v1" },
    { name = "ENTITLEMENTS_SERVICE_ENDPOINT", value = "http://entitlements/api/entitlements/v2" },
    { name = "ENTITLEMENTS_SERVICE_API_KEY", value = "OBSOLETE" },
    { name = "STORAGE_SERVICE_ENDPOINT", value = "http://storage/api/storage/v2" },
  ]

  preconditions = [
    { condition = !local.deploy_oetp_server || local.deploy_storage, error_message = "Open ETP Server requires Storage." },
    { condition = !local.deploy_oetp_server || local.deploy_entitlements, error_message = "Open ETP Server requires Entitlements." },
    { condition = !local.deploy_oetp_server || local.deploy_partition, error_message = "Open ETP Server requires Partition." },
  ]

  depends_on = [module.osdu_common, module.storage]
}
