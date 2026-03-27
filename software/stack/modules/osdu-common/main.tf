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

# OSDU namespace, ConfigMap, workload identity SA, and Elasticsearch credentials
# Azure SPI variant -- uses Azure PaaS (CosmosDB, Service Bus, Storage, Redis)

# ─── Namespace ──────────────────────────────────────────────────────────────────

resource "kubernetes_namespace_v1" "osdu" {
  metadata {
    name = var.namespace
    labels = {
      "istio-injection" = "enabled"
    }
  }
}

# ─── PeerAuthentication (STRICT mTLS) ──────────────────────────────────────────

resource "kubectl_manifest" "osdu_peer_authentication" {
  yaml_body = <<-YAML
    apiVersion: security.istio.io/v1
    kind: PeerAuthentication
    metadata:
      name: osdu-strict-mtls
      namespace: ${var.namespace}
    spec:
      mtls:
        mode: STRICT
  YAML

  depends_on = [kubernetes_namespace_v1.osdu]
}

# ─── ConfigMap with Azure PaaS endpoints ────────────────────────────────────────

resource "kubernetes_config_map_v1" "osdu_config" {
  metadata {
    name      = "osdu-config"
    namespace = var.namespace
  }

  data = {
    domain               = var.osdu_domain
    data_partition       = var.data_partition
    azure_tenant_id      = var.azure_tenant_id
    keyvault_uri         = var.keyvault_uri
    keyvault_name        = var.keyvault_name
    cosmosdb_endpoint    = var.cosmosdb_endpoint
    cosmosdb_database    = var.cosmosdb_database
    storage_account_name = var.storage_account_name
    servicebus_namespace = var.servicebus_namespace
    redis_hostname       = var.redis_hostname
    redis_port           = var.redis_port
    appinsights_key      = var.appinsights_key
    elasticsearch_host   = var.elasticsearch_host
  }

  lifecycle {
    precondition {
      condition     = var.osdu_domain != ""
      error_message = "osdu-config: domain must be non-empty."
    }
    precondition {
      condition     = var.data_partition != ""
      error_message = "osdu-config: data_partition must be non-empty."
    }
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

# ─── Workload Identity ServiceAccount ───────────────────────────────────────────

resource "kubernetes_service_account_v1" "workload_identity" {
  metadata {
    name      = "workload-identity-sa"
    namespace = var.namespace
    annotations = {
      "azure.workload.identity/client-id" = var.workload_identity_client_id
      "azure.workload.identity/tenant-id" = var.azure_tenant_id
    }
    labels = {
      "azure.workload.identity/use" = "true"
    }
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

# ─── Elasticsearch credential secret ───────────────────────────────────────────

resource "kubernetes_secret_v1" "elastic_credentials" {
  count = var.elasticsearch_password != "" ? 1 : 0

  metadata {
    name      = "elastic-credentials"
    namespace = var.namespace
  }

  data = {
    ELASTIC_USER_SYSTEM = "elastic"
    ELASTIC_PASS_SYSTEM = var.elasticsearch_password
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

resource "kubernetes_secret_v1" "elastic_ca_cert" {
  count = var.elasticsearch_ca_cert != "" ? 1 : 0

  metadata {
    name      = "elastic-ca-cert"
    namespace = var.namespace
  }

  data = {
    "ca.crt" = var.elasticsearch_ca_cert
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}
