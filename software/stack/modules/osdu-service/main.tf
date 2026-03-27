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

# Reusable OSDU service Helm release (Azure SPI variant)
#
# Encapsulates common Helm set values shared by all OSDU services on Azure,
# plus postrender for AKS safeguards compliance. Service-specific overrides
# are passed via extra_set. Dependency ordering is controlled by the caller
# via module-level depends_on.
#
# Key differences from cimpl variant:
#   - No cimpl_tenant / cimpl_project / subscriber_private_key_id
#   - Uses Azure workload identity (pod label + service account)
#   - References osdu-config ConfigMap for Azure PaaS endpoints

locals {
  common_set = [
    {
      name  = "global.onPremEnabled"
      value = "false"
      type  = "string"
    },
    {
      name  = "global.domain"
      value = var.osdu_domain
    },
    {
      name  = "global.dataPartitionId"
      value = var.data_partition
    },
    {
      name  = "data.serviceAccountName"
      value = "workload-identity-sa"
    },
    {
      name  = "data.bootstrapServiceAccountName"
      value = "workload-identity-sa"
    },
    {
      name  = "data.cronJobServiceAccountName"
      value = "workload-identity-sa"
    },
    {
      name  = "data.logLevel"
      value = "INFO"
    },
    {
      name  = "data.imagePullPolicy"
      value = "IfNotPresent"
    },
    {
      name  = "data.configMapRef"
      value = "osdu-config"
    },
    {
      name  = "data.podLabels.azure\\.workload\\.identity/use"
      value = "true"
      type  = "string"
    },
    {
      name  = "rosa"
      value = "false"
      type  = "string"
    },
  ]

  all_set = concat(local.common_set, var.extra_set)
}

resource "helm_release" "service" {
  count = var.enable && var.enable_common ? 1 : 0

  name             = var.service_name
  repository       = var.repository
  chart            = var.chart
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = false
  timeout          = var.timeout
  atomic           = var.atomic

  postrender = {
    binary_path = "pwsh"
    args        = ["-File", "${var.kustomize_path}/kustomize/postrender.ps1", "-ServiceName", var.service_name, "-ReleaseNamespace", var.namespace]
  }

  set = local.all_set

  lifecycle {
    precondition {
      condition     = length(var.preconditions) == 0 || alltrue([for p in var.preconditions : p.condition])
      error_message = length(var.preconditions) == 0 ? "no preconditions" : join("; ", [for p in var.preconditions : p.error_message if !p.condition])
    }
  }
}
