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

# Reusable OSDU service deployment using the local osdu-spi-service chart.
#
# Replaces the previous osdu-service module that consumed CIMPL Helm charts
# from OCI registries with kustomize postrender. This module uses a local
# chart with AKS Automatic compliance baked in (seccomp, security context,
# topology spread), eliminating the postrender step entirely.

resource "helm_release" "service" {
  count = var.enable && var.enable_common ? 1 : 0

  name             = var.service_name
  chart            = "${path.module}/../../charts/osdu-spi-service"
  namespace        = var.namespace
  create_namespace = false
  timeout          = var.timeout
  atomic           = var.atomic

  values = [yamlencode({
    image = {
      repository = var.image_repository
      tag        = var.image_tag
    }
    replicaCount       = var.replica_count
    containerPort      = var.container_port
    serviceAccountName = "workload-identity-sa"
    configMapRef       = "osdu-config"
    workloadIdentity   = true
    topologySpread     = true
    elasticTls         = var.elastic_tls
    istioProxyPin = {
      enabled = var.istio_proxy_pin
      image   = "mcr.microsoft.com/oss/v2/istio/proxyv2:v1.28.3-2"
    }
    env       = var.env
    resources = var.resources
    probes    = var.probes
  })]

  lifecycle {
    precondition {
      condition     = length(var.preconditions) == 0 || alltrue([for p in var.preconditions : p.condition])
      error_message = length(var.preconditions) == 0 ? "no preconditions" : join("; ", [for p in var.preconditions : p.error_message if !p.condition])
    }
  }
}
