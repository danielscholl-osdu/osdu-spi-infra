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

  preconditions = [
    { condition = !local.deploy_unit || local.deploy_entitlements, error_message = "Unit requires Entitlements." },
    { condition = !local.deploy_unit || local.deploy_partition, error_message = "Unit requires Partition." },
  ]

  depends_on = [module.osdu_common, module.entitlements]
}
