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
      "istio.io/rev" = var.istio_revision
    }
  }
}

# ─── PeerAuthentication (STRICT mTLS) ──────────────────────────────────────────

resource "kubectl_manifest" "osdu_peer_authentication" {
  yaml_body = <<-YAML
    apiVersion: security.istio.io/v1
    kind: PeerAuthentication
    metadata:
      name: osdu-mtls
      namespace: ${var.namespace}
    spec:
      mtls:
        mode: PERMISSIVE
  YAML

  depends_on = [kubernetes_namespace_v1.osdu]
}

# ─── Istio JWT Authentication ──────────────────────────────────────────────────
# Validates Azure AD tokens (v1 + v2 issuers) at the sidecar level.

resource "kubectl_manifest" "request_authentication" {
  yaml_body = <<-YAML
    apiVersion: security.istio.io/v1
    kind: RequestAuthentication
    metadata:
      name: req-authn-for-all
      namespace: ${var.namespace}
    spec:
      jwtRules:
        - issuer: "https://sts.windows.net/${var.azure_tenant_id}/"
          jwksUri: "https://login.microsoftonline.com/common/discovery/v2.0/keys"
          audiences:
            - "${var.workload_identity_client_id}"
          outputPayloadToHeader: "x-payload"
          forwardOriginalToken: true
          fromHeaders:
            - name: Authorization
              prefix: "Bearer "
        - issuer: "https://login.microsoftonline.com/${var.azure_tenant_id}/v2.0"
          jwksUri: "https://login.microsoftonline.com/common/discovery/v2.0/keys"
          audiences:
            - "${var.workload_identity_client_id}"
          outputPayloadToHeader: "x-payload"
          forwardOriginalToken: true
          fromHeaders:
            - name: Authorization
              prefix: "Bearer "
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
    DOMAIN               = var.osdu_domain
    DATA_PARTITION       = var.data_partition
    AZURE_TENANT_ID      = var.azure_tenant_id
    AAD_CLIENT_ID        = var.workload_identity_client_id
    KEYVAULT_URI         = var.keyvault_uri
    KEYVAULT_URL         = var.keyvault_uri
    KEYVAULT_NAME        = var.keyvault_name
    COSMOSDB_ENDPOINT    = var.cosmosdb_endpoint
    COSMOSDB_DATABASE    = var.cosmosdb_database
    STORAGE_ACCOUNT_NAME = var.storage_account_name
    SERVICEBUS_NAMESPACE = var.servicebus_namespace
    REDIS_HOSTNAME       = var.redis_hostname
    REDIS_PORT           = var.redis_port
    SERVER_PORT          = "8080"
    APPINSIGHTS_KEY      = var.appinsights_key
    ELASTICSEARCH_HOST   = var.elasticsearch_host
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

# Elasticsearch secrets removed -- ES credentials no longer flow through Terraform.
# The CA cert is copied cross-namespace by null_resource.copy_elastic_ca_cert
# in the stack root (osdu-common.tf).
