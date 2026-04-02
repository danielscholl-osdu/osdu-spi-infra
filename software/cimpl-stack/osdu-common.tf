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

# OSDU common namespace resources (secrets, configmaps, service accounts)

module "osdu_common" {
  source = "./modules/osdu-common"
  count  = local.deploy_common ? 1 : 0

  namespace                       = local.osdu_namespace
  platform_namespace              = local.platform_namespace
  istio_revision                  = var.istio_revision
  osdu_domain                     = local.osdu_domain
  cimpl_project                   = var.cimpl_project
  cimpl_tenant                    = var.cimpl_tenant
  cimpl_subscriber_private_key_id = var.cimpl_subscriber_private_key_id
  postgresql_host                 = local.postgresql_host
  postgresql_username             = var.postgresql_username
  postgresql_password             = var.postgresql_password
  keycloak_host                   = local.keycloak_host
  redis_password                  = var.redis_password
  datafier_client_secret          = var.datafier_client_secret
  minio_root_user                 = var.minio_root_user
  minio_root_password             = var.minio_root_password
  rabbitmq_username               = var.rabbitmq_username
  rabbitmq_password               = var.rabbitmq_password
  elastic_password                = var.enable_elasticsearch && var.enable_elastic_bootstrap ? module.elastic[0].elastic_password : ""
  elastic_host                    = "elasticsearch-es-http.${local.platform_namespace}.svc.cluster.local"
  elastic_ca_cert                 = var.enable_elasticsearch && var.enable_elastic_bootstrap ? module.elastic[0].elastic_ca_cert : ""
  enable_elastic_ca_cert          = var.enable_elasticsearch && var.enable_elastic_bootstrap
  enable_search                   = local.deploy_search
  enable_indexer                  = local.deploy_indexer
  enable_partition                = local.deploy_partition
  enable_entitlements             = local.deploy_entitlements
  enable_legal                    = local.deploy_legal
  enable_schema                   = local.deploy_schema
  enable_storage                  = local.deploy_storage
  enable_file                     = local.deploy_file
  enable_dataset                  = local.deploy_dataset
  enable_register                 = local.deploy_register
  enable_notification             = local.deploy_notification
  enable_policy                   = local.deploy_policy
  enable_workflow                 = local.deploy_workflow
  enable_wellbore                 = local.deploy_wellbore
  enable_eds_dms                  = local.deploy_eds_dms
  enable_oetp_server              = local.deploy_oetp_server
}
