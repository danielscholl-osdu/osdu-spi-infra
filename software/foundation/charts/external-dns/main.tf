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

# ExternalDNS for automatic DNS record management via Gateway API HTTPRoutes
resource "helm_release" "external_dns" {
  name             = "external-dns"
  repository       = "oci://registry-1.docker.io/bitnamicharts"
  chart            = "external-dns"
  version          = "9.0.3"
  namespace        = var.namespace
  create_namespace = false
  timeout          = 600
  atomic           = true

  set = [
    {
      name  = "global.security.allowInsecureImages"
      value = "true"
    },
    {
      name  = "image.registry"
      value = "registry.k8s.io"
    },
    {
      name  = "image.repository"
      value = "external-dns/external-dns"
    },
    {
      name  = "image.tag"
      value = "v0.15.1"
    },
    {
      name  = "provider"
      value = "azure"
    },
    {
      name  = "sources[0]"
      value = "gateway-httproute"
    },
    {
      name  = "policy"
      value = "sync"
    },
    {
      name  = "domainFilters[0]"
      value = var.dns_zone_name
    },
    {
      name  = "txtOwnerId"
      value = var.cluster_name
    },
    {
      name  = "azure.resourceGroup"
      value = var.dns_zone_resource_group
    },
    {
      name  = "azure.subscriptionId"
      value = var.dns_zone_subscription_id
    },
    {
      name  = "azure.tenantId"
      value = var.tenant_id
    },
    {
      name  = "azure.useWorkloadIdentityExtension"
      value = "true"
    },
    {
      name  = "serviceAccount.annotations.azure\\.workload\\.identity/client-id"
      value = var.external_dns_client_id
    },
    {
      name  = "podLabels.azure\\.workload\\.identity/use"
      value = "true"
      type  = "string"
    },
    {
      name  = "resources.requests.cpu"
      value = "50m"
    },
    {
      name  = "resources.requests.memory"
      value = "64Mi"
    },
    {
      name  = "resources.limits.cpu"
      value = "200m"
    },
    {
      name  = "resources.limits.memory"
      value = "128Mi"
    },
  ]
}
