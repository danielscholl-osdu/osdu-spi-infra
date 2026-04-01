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

# OSDU reference systems service deployments (Azure SPI variant)
#
# Reference services require data files at startup (JSON catalogs, SIS data).
# Init containers download these from the OSDU community GitLab into emptyDir
# volumes, which are then mounted read-only into the main container.

# -- Shared init container security context (AKS Deployment Safeguards compliant)
locals {
  init_security_context = {
    allowPrivilegeEscalation = false
    runAsNonRoot             = true
    runAsUser                = 1000
    capabilities             = { drop = ["ALL"] }
  }

  init_resources = {
    requests = { cpu = "50m", memory = "64Mi" }
    limits   = { cpu = "200m", memory = "128Mi" }
  }
}

module "crs_conversion" {
  source = "./modules/osdu-spi-service"

  service_name     = "crs-conversion"
  image_repository = local.osdu_images["crs_conversion"].repository
  image_tag        = local.osdu_images["crs_conversion"].tag
  enable           = local.deploy_crs_conversion
  enable_common    = local.deploy_common
  namespace        = local.osdu_namespace

  env = [
    { name = "SPRING_APPLICATION_NAME", value = "crs-conversion-service" },
    { name = "SERVER_SERVLET_CONTEXTPATH", value = "/api/crs/converter/" },

    { name = "ACCEPT_HTTP", value = "true" },
    { name = "AZURE_ISTIOAUTH_ENABLED", value = "true" },
    { name = "AZURE_PAAS_WORKLOADIDENTITY_ISENABLED", value = "true" },
    { name = "SERVICE_DOMAIN_NAME", value = "dataservices.energy" },
    { name = "SIS_DATA", value = "/apachesis_setup/SIS_DATA" },
    { name = "PARTITION_SERVICE_ENDPOINT", value = "http://partition/api/partition/v1" },
    { name = "ENTITLEMENT_URL", value = "http://entitlements/api/entitlements/v2" },
    { name = "STORAGE_URL", value = "http://storage/api/storage/v2" },
  ]

  volumes = [{ name = "sis-data", emptyDir = {} }]

  init_containers = [
    {
      name    = "download-sis-data"
      image   = "curlimages/curl:8.12.1"
      command = ["sh", "-c", "cd /data && curl -sSL https://community.opengroup.org/osdu/platform/system/reference/crs-conversion-service/-/archive/master/crs-conversion-service-master.tar.gz | tar xzf - --strip-components=1 crs-conversion-service-master/apachesis_setup"]
      volumeMounts    = [{ name = "sis-data", mountPath = "/data" }]
      resources       = local.init_resources
      securityContext = local.init_security_context
    }
  ]

  volume_mounts = [{ name = "sis-data", mountPath = "/apachesis_setup", readOnly = true }]

  preconditions = [
    { condition = !local.deploy_crs_conversion || local.deploy_entitlements, error_message = "CRS Conversion requires Entitlements." },
    { condition = !local.deploy_crs_conversion || local.deploy_partition, error_message = "CRS Conversion requires Partition." },
  ]

  depends_on = [module.osdu_common, module.entitlements]
}

module "crs_catalog" {
  source = "./modules/osdu-spi-service"

  service_name     = "crs-catalog"
  image_repository = local.osdu_images["crs_catalog"].repository
  image_tag        = local.osdu_images["crs_catalog"].tag
  enable           = local.deploy_crs_catalog
  enable_common    = local.deploy_common
  namespace        = local.osdu_namespace

  env = [
    { name = "SPRING_APPLICATION_NAME", value = "crs-catalog" },
    { name = "SERVER_SERVLET_CONTEXTPATH", value = "/api/crs/catalog/" },

    { name = "ACCEPT_HTTP", value = "true" },
    { name = "AZURE_ISTIOAUTH_ENABLED", value = "true" },
    { name = "AZURE_PAAS_WORKLOADIDENTITY_ISENABLED", value = "true" },
    { name = "PARTITION_SERVICE_ENDPOINT", value = "http://partition/api/partition/v1" },
    { name = "ENTITLEMENT_URL", value = "http://entitlements/api/entitlements/v2" },
  ]

  volumes = [{ name = "crs-data", emptyDir = {} }]

  init_containers = [
    {
      name    = "download-catalog"
      image   = "curlimages/curl:8.12.1"
      command = ["sh", "-c", "curl -sSL -o /data/crs_catalog_v2.json https://community.opengroup.org/osdu/platform/system/reference/crs-catalog-service/-/raw/master/data/crs_catalog_v2.json"]
      volumeMounts    = [{ name = "crs-data", mountPath = "/data" }]
      resources       = local.init_resources
      securityContext = local.init_security_context
    }
  ]

  volume_mounts = [{ name = "crs-data", mountPath = "/mnt/crs_catalogs", readOnly = true }]

  preconditions = [
    { condition = !local.deploy_crs_catalog || local.deploy_entitlements, error_message = "CRS Catalog requires Entitlements." },
    { condition = !local.deploy_crs_catalog || local.deploy_partition, error_message = "CRS Catalog requires Partition." },
  ]

  depends_on = [module.osdu_common, module.entitlements]
}

module "unit" {
  source = "./modules/osdu-spi-service"

  service_name     = "unit"
  image_repository = local.osdu_images["unit"].repository
  image_tag        = local.osdu_images["unit"].tag
  enable           = local.deploy_unit
  enable_common    = local.deploy_common
  namespace        = local.osdu_namespace

  env = [
    { name = "SPRING_APPLICATION_NAME", value = "unit" },
    { name = "SERVER_SERVLET_CONTEXTPATH", value = "/api/unit/" },

    { name = "ACCEPT_HTTP", value = "true" },
    { name = "AZURE_ISTIOAUTH_ENABLED", value = "true" },
    { name = "AZURE_PAAS_WORKLOADIDENTITY_ISENABLED", value = "true" },
    { name = "PARTITION_SERVICE_ENDPOINT", value = "http://partition/api/partition/v1" },
    { name = "ENTITLEMENT_URL", value = "http://entitlements/api/entitlements/v2" },
  ]

  volumes = [{ name = "unit-data", emptyDir = {} }]

  init_containers = [
    {
      name    = "download-catalog"
      image   = "curlimages/curl:8.12.1"
      command = ["sh", "-c", "curl -sSL -o /data/unit_catalog_v2.json https://community.opengroup.org/osdu/platform/system/reference/unit-service/-/raw/master/data/unit_catalog_v2.json"]
      volumeMounts    = [{ name = "unit-data", mountPath = "/data" }]
      resources       = local.init_resources
      securityContext = local.init_security_context
    }
  ]

  volume_mounts = [{ name = "unit-data", mountPath = "/mnt/unit_catalogs", readOnly = true }]

  preconditions = [
    { condition = !local.deploy_unit || local.deploy_entitlements, error_message = "Unit requires Entitlements." },
    { condition = !local.deploy_unit || local.deploy_partition, error_message = "Unit requires Partition." },
  ]

  depends_on = [module.osdu_common, module.entitlements]
}
