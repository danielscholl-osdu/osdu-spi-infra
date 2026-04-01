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

  # Elasticsearch host for ConfigMap (credentials handled separately)
  enable_elasticsearch = var.enable_elasticsearch && var.enable_elastic_bootstrap
  elasticsearch_host   = local.elasticsearch_host
}

# Copy the ECK CA cert from platform namespace to osdu namespace.
# The osdu-spi-service chart mounts elastic-ca-cert for search/indexer TLS.
# Uses kubectl instead of Terraform data sources to avoid timing issues
# with ECK secret population during initial cluster bootstrap.
resource "null_resource" "copy_elastic_ca_cert" {
  count = var.enable_elasticsearch && var.enable_elastic_bootstrap && local.deploy_common ? 1 : 0

  triggers = {
    source_namespace = local.platform_namespace
    target_namespace = local.osdu_namespace
  }

  provisioner "local-exec" {
    command     = <<-EOT
      for i in $(seq 1 60); do
        CA=$(kubectl get secret elasticsearch-es-http-certs-public \
          -n ${local.platform_namespace} \
          -o jsonpath='{.data.ca\.crt}' 2>/dev/null)
        if [ -n "$CA" ]; then
          echo "CA cert ready after $((i * 10))s"
          kubectl create secret generic elastic-ca-cert \
            --namespace=${local.osdu_namespace} \
            --from-literal="ca.crt=$(echo "$CA" | base64 -d)" \
            --dry-run=client -o yaml | kubectl apply -f -
          exit 0
        fi
        echo "Waiting for ES CA cert... attempt $i/60"
        sleep 10
      done
      echo "ERROR: Timed out waiting for CA cert after 600s"
      exit 1
    EOT
    interpreter = ["/bin/sh", "-c"]
  }

  depends_on = [module.elastic, module.osdu_common]
}

# Store Elasticsearch credentials in Key Vault for the partition service.
# Search and indexer services retrieve ES credentials at runtime via the
# partition service API, which reads them from Key Vault.
resource "null_resource" "elastic_keyvault_secrets" {
  count = var.enable_elasticsearch && var.enable_elastic_bootstrap && local.deploy_common ? 1 : 0

  triggers = {
    keyvault_name  = var.keyvault_name
    data_partition = var.data_partition
    elastic_host   = local.elasticsearch_host
  }

  provisioner "local-exec" {
    command     = <<-EOT
      # Wait for ES password secret to be populated
      for i in $(seq 1 60); do
        PASS=$(kubectl get secret elasticsearch-es-elastic-user \
          -n ${local.platform_namespace} \
          -o jsonpath='{.data.elastic}' 2>/dev/null)
        if [ -n "$PASS" ]; then
          ELASTIC_PASS=$(echo "$PASS" | base64 -d)
          echo "ES password ready after $((i * 10))s"

          az keyvault secret set --vault-name ${var.keyvault_name} \
            --name "${var.data_partition}-elastic-endpoint" \
            --value "https://${local.elasticsearch_host}:9200" \
            --output none
          az keyvault secret set --vault-name ${var.keyvault_name} \
            --name "${var.data_partition}-elastic-username" \
            --value "elastic" \
            --output none
          az keyvault secret set --vault-name ${var.keyvault_name} \
            --name "${var.data_partition}-elastic-password" \
            --value "$ELASTIC_PASS" \
            --output none

          echo "ES credentials stored in Key Vault (${var.keyvault_name})"
          exit 0
        fi
        echo "Waiting for ES password... attempt $i/60"
        sleep 10
      done
      echo "ERROR: Timed out waiting for ES password after 600s"
      exit 1
    EOT
    interpreter = ["/bin/sh", "-c"]
  }

  depends_on = [module.elastic, module.osdu_common]
}

# Indexer and workflow services retrieve Redis connection details at runtime
# via KeyVaultFacade. Store the in-cluster Redis hostname and password.
resource "null_resource" "redis_keyvault_secrets" {
  count = var.enable_redis && local.deploy_common ? 1 : 0

  triggers = {
    keyvault_name = var.keyvault_name
    redis_host    = "redis-master.${local.platform_namespace}.svc.cluster.local"
  }

  provisioner "local-exec" {
    command     = <<-EOT
      az keyvault secret set --vault-name ${var.keyvault_name} \
        --name "redis-hostname" \
        --value "redis-master.${local.platform_namespace}.svc.cluster.local" \
        --output none

      az keyvault secret set --vault-name ${var.keyvault_name} \
        --name "redis-password" \
        --value "${var.redis_password}" \
        --output none

      echo "Redis credentials stored in Key Vault (${var.keyvault_name})"
    EOT
    interpreter = ["/bin/sh", "-c"]
  }

  depends_on = [module.redis, module.osdu_common]
}
