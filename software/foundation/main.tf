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

# Foundation Layer - Cluster-wide shared components (singletons)
#
# Deploys shared components that all stacks depend on:
# - cert-manager for TLS certificate management
# - ECK operator for Elasticsearch
# - ExternalDNS for DNS record management
# - Gateway API CRDs and base Gateway resource
# - Shared StorageClasses
#
# Prerequisites:
# - AKS cluster must be provisioned (Layer 1: infra/)
# - kubeconfig must be configured

locals {
  common_labels = {
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = "osdu-spi-foundation"
  }
}

# Shared namespace for foundation components
resource "kubernetes_namespace_v1" "platform" {
  metadata {
    name = "foundation"
  }
}


# ---------------------------------------------------------------------------
# Charts -- each chart is a self-contained sub-module
# ---------------------------------------------------------------------------

module "cert_manager" {
  source = "./charts/cert-manager"
  count  = var.enable_cert_manager ? 1 : 0

  namespace                  = kubernetes_namespace_v1.platform.metadata[0].name
  acme_email                 = var.acme_email
  use_letsencrypt_production = var.use_letsencrypt_production
}

module "elastic" {
  source = "./charts/elastic"
  count  = var.enable_elasticsearch ? 1 : 0

  namespace = kubernetes_namespace_v1.platform.metadata[0].name
}

module "cnpg" {
  source = "./charts/cnpg"
  count  = var.enable_postgresql ? 1 : 0

  namespace = kubernetes_namespace_v1.platform.metadata[0].name
}

module "external_dns" {
  source = "./charts/external-dns"
  count  = var.enable_external_dns ? 1 : 0

  namespace                = kubernetes_namespace_v1.platform.metadata[0].name
  cluster_name             = var.cluster_name
  dns_zone_name            = var.dns_zone_name
  dns_zone_resource_group  = var.dns_zone_resource_group
  dns_zone_subscription_id = var.dns_zone_subscription_id
  tenant_id                = var.tenant_id
  external_dns_client_id   = var.external_dns_client_id
}


# ---------------------------------------------------------------------------
# Gateway API -- CRDs and base Gateway resource
# ---------------------------------------------------------------------------

locals {
  gateway_api_crd_file = "${path.module}/crds/gateway-api-v1.2.1.yaml"
  gateway_api_crds = [
    for doc in split("---", file(local.gateway_api_crd_file)) :
    doc if trimspace(doc) != "" && can(yamldecode(doc))
  ]
}

resource "kubectl_manifest" "gateway_api_crds" {
  for_each = var.enable_gateway ? { for doc in local.gateway_api_crds : yamldecode(doc).metadata.name => doc } : {}

  yaml_body         = each.value
  wait              = true
  server_side_apply = true
}

# Ensure the AKS-managed Istio ingress gateway service uses the desired LoadBalancer type
resource "kubectl_manifest" "istio_gateway_annotation" {
  count = var.enable_gateway ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: v1
    kind: Service
    metadata:
      name: aks-istio-ingressgateway-external
      namespace: aks-istio-ingress
      annotations:
        service.beta.kubernetes.io/azure-load-balancer-internal: "${var.enable_public_ingress ? "false" : "true"}"
  YAML

  server_side_apply = true
  force_conflicts   = true
}

# Base Gateway with HTTP listener only -- stacks add HTTPS listeners via server-side apply.
resource "kubectl_manifest" "gateway" {
  count = var.enable_gateway ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: Gateway
    metadata:
      name: istio
      namespace: aks-istio-ingress
    spec:
      gatewayClassName: istio
      addresses:
        - value: aks-istio-ingressgateway-external
          type: Hostname
      listeners:
        - name: http
          protocol: HTTP
          port: 80
          allowedRoutes:
            namespaces:
              from: All
  YAML

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubectl_manifest.gateway_api_crds]
}


# ---------------------------------------------------------------------------
# Storage Classes -- shared across all stacks
# ---------------------------------------------------------------------------

resource "kubectl_manifest" "pg_storage_class" {
  count     = var.enable_postgresql ? 1 : 0
  yaml_body = <<-YAML
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: pg-storageclass
      labels:
        app: postgresql
    parameters:
      skuName: Premium_LRS
      kind: Managed
      cachingMode: ReadOnly
      tags: costcenter=dev,app=postgresql
    provisioner: disk.csi.azure.com
    reclaimPolicy: Retain
    volumeBindingMode: WaitForFirstConsumer
    allowVolumeExpansion: true
  YAML
}

resource "kubectl_manifest" "elastic_storage_class" {
  count     = var.enable_elasticsearch ? 1 : 0
  yaml_body = <<-YAML
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: es-storageclass
      labels:
        app: elasticsearch
    parameters:
      skuName: Premium_LRS
      kind: Managed
      cachingMode: ReadOnly
      tags: costcenter=dev,app=elasticsearch
    provisioner: disk.csi.azure.com
    reclaimPolicy: Retain
    volumeBindingMode: WaitForFirstConsumer
    allowVolumeExpansion: true
  YAML
}

# State migration: renamed deprecated types to _v1 equivalents
moved {
  from = kubernetes_namespace.platform
  to   = kubernetes_namespace_v1.platform
}
