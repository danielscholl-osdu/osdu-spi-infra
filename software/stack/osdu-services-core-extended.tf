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

# OSDU core extended service deployments (Azure SPI variant)
#
# Additional core services beyond the foundational set in osdu-services-core.tf:
# Notification, Dataset, Register, Policy, and Secret.

module "notification" {
  source = "./modules/osdu-spi-service"

  service_name     = "notification"
  image_repository = local.osdu_images["notification"].repository
  image_tag        = local.osdu_images["notification"].tag
  enable           = local.deploy_notification
  enable_common    = local.deploy_common
  namespace        = local.osdu_namespace
  redis_tls        = true

  # Notification uses port 8080 with a service-specific info endpoint
  probes = {
    liveness = {
      path                = "/api/notification/v1/info"
      port                = 8080
      initialDelaySeconds = 250
      periodSeconds       = 10
      timeoutSeconds      = 5
      failureThreshold    = 3
    }
    readiness = {
      path                = "/api/notification/v1/info"
      port                = 8080
      initialDelaySeconds = 10
      periodSeconds       = 10
      timeoutSeconds      = 5
      failureThreshold    = 3
    }
  }

  env = [
    { name = "SPRING_APPLICATION_NAME", value = "notification" },
    { name = "SERVER_SERVLET_CONTEXTPATH", value = "/api/notification/v1/" },

    { name = "ACCEPT_HTTP", value = "true" },
    { name = "AZURE_ISTIOAUTH_ENABLED", value = "true" },
    { name = "AZURE_PAAS_WORKLOADIDENTITY_ISENABLED", value = "true" },
    { name = "COSMOSDB_DATABASE", value = "osdu-db" },
    { name = "SERVICEBUS_TOPIC_NAME", value = "recordstopic" },
    { name = "REDIS_DATABASE", value = "6" },
    { name = "service_bus_enabled", value = "true" },
    { name = "event_grid_to_service_bus_enabled", value = "false" },
    { name = "PARTITION_SERVICE_ENDPOINT", value = "http://partition/api/partition/v1" },
    { name = "ENTITLEMENTS_SERVICE_ENDPOINT", value = "http://entitlements/api/entitlements/v2" },
    { name = "ENTITLEMENTS_SERVICE_API_KEY", value = "OBSOLETE" },
    { name = "REGISTER_SERVICE_ENDPOINT", value = "http://register/api/register/v1" },
  ]

  preconditions = [
    { condition = !local.deploy_notification || local.deploy_entitlements, error_message = "Notification requires Entitlements." },
    { condition = !local.deploy_notification || local.deploy_partition, error_message = "Notification requires Partition." },
  ]

  depends_on = [module.osdu_common, module.entitlements]
}

module "dataset" {
  source = "./modules/osdu-spi-service"

  service_name     = "dataset"
  image_repository = local.osdu_images["dataset"].repository
  image_tag        = local.osdu_images["dataset"].tag
  enable           = local.deploy_dataset
  enable_common    = local.deploy_common
  namespace        = local.osdu_namespace
  redis_tls        = true

  # Dataset uses port 8081 with /health/liveness path
  probes = {
    liveness = {
      path                = "/health/liveness"
      port                = 8081
      initialDelaySeconds = 250
      periodSeconds       = 10
      timeoutSeconds      = 5
      failureThreshold    = 3
    }
    readiness = {
      path                = "/health/readiness"
      port                = 8081
      initialDelaySeconds = 10
      periodSeconds       = 10
      timeoutSeconds      = 5
      failureThreshold    = 3
    }
  }

  env = [
    { name = "SPRING_APPLICATION_NAME", value = "dataset" },
    { name = "SERVER_SERVLET_CONTEXTPATH", value = "/api/dataset/v1/" },

    { name = "ACCEPT_HTTP", value = "true" },
    { name = "AZURE_ISTIOAUTH_ENABLED", value = "true" },
    { name = "AZURE_PAAS_WORKLOADIDENTITY_ISENABLED", value = "true" },
    { name = "COSMOSDB_DATABASE", value = "osdu-db" },
    { name = "PARTITION_SERVICE_ENDPOINT", value = "http://partition/api/partition/v1" },
    { name = "ENTITLEMENTS_SERVICE_ENDPOINT", value = "http://entitlements/api/entitlements/v2" },
    { name = "ENTITLEMENTS_SERVICE_API_KEY", value = "OBSOLETE" },
    { name = "STORAGE_SERVICE_ENDPOINT", value = "http://storage/api/storage/v2" },
    { name = "SCHEMA_SERVICE_ENDPOINT", value = "http://schema/api/schema-service/v1" },
    { name = "FILE_SERVICE_ENDPOINT", value = "http://file/api/file" },
  ]

  preconditions = [
    { condition = !local.deploy_dataset || local.deploy_storage, error_message = "Dataset requires Storage." },
    { condition = !local.deploy_dataset || local.deploy_schema, error_message = "Dataset requires Schema." },
    { condition = !local.deploy_dataset || local.deploy_entitlements, error_message = "Dataset requires Entitlements." },
    { condition = !local.deploy_dataset || local.deploy_partition, error_message = "Dataset requires Partition." },
  ]

  depends_on = [module.osdu_common, module.storage]
}

module "register" {
  source = "./modules/osdu-spi-service"

  service_name     = "register"
  image_repository = local.osdu_images["register"].repository
  image_tag        = local.osdu_images["register"].tag
  enable           = local.deploy_register
  enable_common    = local.deploy_common
  namespace        = local.osdu_namespace
  redis_tls        = true

  # Register uses port 8081 with /health/liveness path
  probes = {
    liveness = {
      path                = "/health/liveness"
      port                = 8081
      initialDelaySeconds = 250
      periodSeconds       = 10
      timeoutSeconds      = 5
      failureThreshold    = 3
    }
    readiness = {
      path                = "/health/readiness"
      port                = 8081
      initialDelaySeconds = 10
      periodSeconds       = 10
      timeoutSeconds      = 5
      failureThreshold    = 3
    }
  }

  env = [
    { name = "SPRING_APPLICATION_NAME", value = "register" },
    { name = "SERVER_SERVLET_CONTEXTPATH", value = "/api/register/v1/" },

    { name = "ACCEPT_HTTP", value = "true" },
    { name = "AZURE_ISTIOAUTH_ENABLED", value = "true" },
    { name = "AZURE_PAAS_WORKLOADIDENTITY_ISENABLED", value = "true" },
    { name = "COSMOSDB_DATABASE", value = "osdu-db" },
    { name = "SERVICEBUS_TOPIC_NAME", value = "recordstopic" },
    { name = "azure_serviceBus_enabled", value = "true" },
    { name = "azure_eventGrid_enabled", value = "false" },
    { name = "PARTITION_SERVICE_ENDPOINT", value = "http://partition/api/partition/v1" },
    { name = "ENTITLEMENTS_SERVICE_ENDPOINT", value = "http://entitlements/api/entitlements/v2" },
    { name = "ENTITLEMENTS_SERVICE_API_KEY", value = "OBSOLETE" },
  ]

  preconditions = [
    { condition = !local.deploy_register || local.deploy_entitlements, error_message = "Register requires Entitlements." },
    { condition = !local.deploy_register || local.deploy_partition, error_message = "Register requires Partition." },
  ]

  depends_on = [module.osdu_common, module.entitlements]
}

module "policy" {
  source = "./modules/osdu-spi-service"

  service_name     = "policy"
  image_repository = local.osdu_images["policy"].repository
  image_tag        = local.osdu_images["policy"].tag
  enable           = local.deploy_policy
  enable_common    = local.deploy_common
  namespace        = local.osdu_namespace

  # Policy uses port 8080 with a service-specific health endpoint
  probes = {
    liveness = {
      path                = "/api/policy/v1/health"
      port                = 8080
      initialDelaySeconds = 250
      periodSeconds       = 10
      timeoutSeconds      = 5
      failureThreshold    = 3
    }
    readiness = {
      path                = "/api/policy/v1/health"
      port                = 8080
      initialDelaySeconds = 10
      periodSeconds       = 10
      timeoutSeconds      = 5
      failureThreshold    = 3
    }
  }

  env = [
    { name = "SPRING_APPLICATION_NAME", value = "policy" },
    { name = "SERVER_SERVLET_CONTEXTPATH", value = "/api/policy/v1/" },

    { name = "ACCEPT_HTTP", value = "true" },
    { name = "AZURE_ISTIOAUTH_ENABLED", value = "true" },
    { name = "AZURE_PAAS_WORKLOADIDENTITY_ISENABLED", value = "true" },
    { name = "OPA_ENABLED", value = "false" },
    { name = "PARTITION_SERVICE_ENDPOINT", value = "http://partition/api/partition/v1" },
    { name = "ENTITLEMENTS_SERVICE_ENDPOINT", value = "http://entitlements/api/entitlements/v2" },
    { name = "ENTITLEMENTS_SERVICE_API_KEY", value = "OBSOLETE" },
  ]

  preconditions = [
    { condition = !local.deploy_policy || local.deploy_entitlements, error_message = "Policy requires Entitlements." },
    { condition = !local.deploy_policy || local.deploy_partition, error_message = "Policy requires Partition." },
  ]

  depends_on = [module.osdu_common, module.entitlements]
}

module "secret" {
  source = "./modules/osdu-spi-service"

  service_name     = "secret"
  image_repository = local.osdu_images["secret"].repository
  image_tag        = local.osdu_images["secret"].tag
  enable           = local.deploy_secret
  enable_common    = local.deploy_common
  namespace        = local.osdu_namespace

  # Secret uses port 8081 with /health/liveness path
  probes = {
    liveness = {
      path                = "/health/liveness"
      port                = 8081
      initialDelaySeconds = 250
      periodSeconds       = 10
      timeoutSeconds      = 5
      failureThreshold    = 3
    }
    readiness = {
      path                = "/health/readiness"
      port                = 8081
      initialDelaySeconds = 10
      periodSeconds       = 10
      timeoutSeconds      = 5
      failureThreshold    = 3
    }
  }

  env = [
    { name = "SPRING_APPLICATION_NAME", value = "secret" },
    { name = "SERVER_SERVLET_CONTEXTPATH", value = "/api/secret/v1/" },

    { name = "ACCEPT_HTTP", value = "true" },
    { name = "AZURE_ISTIOAUTH_ENABLED", value = "true" },
    { name = "AZURE_PAAS_WORKLOADIDENTITY_ISENABLED", value = "true" },
    { name = "PARTITION_SERVICE_ENDPOINT", value = "http://partition/api/partition/v1" },
    { name = "ENTITLEMENTS_SERVICE_ENDPOINT", value = "http://entitlements/api/entitlements/v2" },
    { name = "ENTITLEMENTS_SERVICE_API_KEY", value = "OBSOLETE" },
  ]

  preconditions = [
    { condition = !local.deploy_secret || local.deploy_entitlements, error_message = "Secret requires Entitlements." },
    { condition = !local.deploy_secret || local.deploy_partition, error_message = "Secret requires Partition." },
  ]

  depends_on = [module.osdu_common, module.entitlements]
}
