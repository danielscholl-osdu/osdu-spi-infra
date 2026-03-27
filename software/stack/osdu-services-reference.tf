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
  source = "./modules/osdu-service"

  service_name                = "crs-conversion"
  repository                  = "oci://community.opengroup.org:5555/osdu/platform/system/reference/crs-conversion-service/cimpl-helm"
  chart                       = "core-plus-crs-conversion-deploy"
  chart_version               = lookup(var.osdu_service_versions, "crs_conversion", var.osdu_chart_version)
  enable                      = local.deploy_crs_conversion
  enable_common               = local.deploy_common
  namespace                   = local.osdu_namespace
  osdu_domain                 = local.osdu_domain
  data_partition              = var.data_partition
  azure_tenant_id             = var.tenant_id
  workload_identity_client_id = var.osdu_identity_client_id
  kustomize_path              = path.module

  preconditions = [
    { condition = !local.deploy_crs_conversion || local.deploy_entitlements, error_message = "CRS Conversion requires Entitlements." },
    { condition = !local.deploy_crs_conversion || local.deploy_partition, error_message = "CRS Conversion requires Partition." },
  ]

  depends_on = [module.osdu_common, module.entitlements]
}

module "crs_catalog" {
  source = "./modules/osdu-service"

  service_name                = "crs-catalog"
  repository                  = "oci://community.opengroup.org:5555/osdu/platform/system/reference/crs-catalog-service/cimpl-helm"
  chart                       = "core-plus-crs-catalog-deploy"
  chart_version               = lookup(var.osdu_service_versions, "crs_catalog", var.osdu_chart_version)
  enable                      = local.deploy_crs_catalog
  enable_common               = local.deploy_common
  namespace                   = local.osdu_namespace
  osdu_domain                 = local.osdu_domain
  data_partition              = var.data_partition
  azure_tenant_id             = var.tenant_id
  workload_identity_client_id = var.osdu_identity_client_id
  kustomize_path              = path.module

  preconditions = [
    { condition = !local.deploy_crs_catalog || local.deploy_entitlements, error_message = "CRS Catalog requires Entitlements." },
    { condition = !local.deploy_crs_catalog || local.deploy_partition, error_message = "CRS Catalog requires Partition." },
  ]

  depends_on = [module.osdu_common, module.entitlements]
}

module "unit" {
  source = "./modules/osdu-service"

  service_name                = "unit"
  repository                  = "oci://community.opengroup.org:5555/osdu/platform/system/reference/unit-service/cimpl-helm"
  chart                       = "core-plus-unit-deploy"
  chart_version               = lookup(var.osdu_service_versions, "unit", var.osdu_chart_version)
  enable                      = local.deploy_unit
  enable_common               = local.deploy_common
  namespace                   = local.osdu_namespace
  osdu_domain                 = local.osdu_domain
  data_partition              = var.data_partition
  azure_tenant_id             = var.tenant_id
  workload_identity_client_id = var.osdu_identity_client_id
  kustomize_path              = path.module

  preconditions = [
    { condition = !local.deploy_unit || local.deploy_entitlements, error_message = "Unit requires Entitlements." },
    { condition = !local.deploy_unit || local.deploy_partition, error_message = "Unit requires Partition." },
  ]

  depends_on = [module.osdu_common, module.entitlements]
}
