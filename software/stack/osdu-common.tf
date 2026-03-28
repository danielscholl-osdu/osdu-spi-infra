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

# OSDU common namespace resources (namespace, configmap, workload identity SA, secrets)
# Azure SPI variant -- passes Azure PaaS endpoint variables

module "osdu_common" {
  source = "./modules/osdu-common"
  count  = local.deploy_common ? 1 : 0

  namespace      = local.osdu_namespace
  osdu_domain    = local.osdu_domain
  data_partition = var.data_partition

  # Azure identity
  azure_tenant_id             = var.tenant_id
  workload_identity_client_id = var.osdu_identity_client_id

  # Azure PaaS endpoints
  keyvault_uri         = var.keyvault_uri
  keyvault_name        = var.keyvault_name
  cosmosdb_endpoint    = var.cosmosdb_endpoint
  cosmosdb_database    = var.cosmosdb_database
  storage_account_name = var.storage_account_name
  servicebus_namespace = var.servicebus_namespace
  redis_hostname       = local.redis_host
  redis_port           = local.redis_port
  appinsights_key      = var.appinsights_key

  # Elasticsearch credentials from in-cluster ECK
  enable_elasticsearch   = var.enable_elasticsearch && var.enable_elastic_bootstrap
  elasticsearch_host     = local.elasticsearch_host
  elasticsearch_password = var.enable_elasticsearch && var.enable_elastic_bootstrap ? module.elastic[0].elastic_password : ""
  elasticsearch_ca_cert  = var.enable_elasticsearch && var.enable_elastic_bootstrap ? module.elastic[0].elastic_ca_cert : ""
}
