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

# Reusable OSDU service Helm release
#
# Encapsulates the 14 common Helm set values shared by all OSDU services,
# plus postrender for AKS safeguards compliance. Service-specific overrides
# are passed via extra_set. Dependency ordering is controlled by the caller
# via module-level depends_on.

locals {
  common_set = [
    {
      name  = "global.onPremEnabled"
      value = "true"
      type  = "string"
    },
    {
      name  = "global.domain"
      value = var.osdu_domain
    },
    {
      name  = "global.dataPartitionId"
      value = var.cimpl_tenant
    },
    {
      name  = "data.serviceAccountName"
      value = var.service_name
    },
    {
      name  = "data.bootstrapServiceAccountName"
      value = "bootstrap-sa"
    },
    {
      name  = "data.cronJobServiceAccountName"
      value = "bootstrap-sa"
    },
    {
      name  = "data.logLevel"
      value = "INFO"
    },
    {
      name  = "data.bucketPrefix"
      value = "refi"
    },
    {
      name  = "data.groupId"
      value = "group"
    },
    {
      name  = "data.imagePullPolicy"
      value = "IfNotPresent"
    },
    {
      name  = "data.sharedTenantName"
      value = var.cimpl_tenant
    },
    {
      name  = "data.googleCloudProject"
      value = var.cimpl_project
    },
    {
      name  = "data.bucketName"
      value = "refi-opa-policies"
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
  timeout          = 1200

  postrender = {
    binary_path = "pwsh"
    args        = ["-File", "${var.kustomize_path}/kustomize/postrender.ps1", "-ServiceName", var.service_name, "-ReleaseNamespace", var.namespace]
  }

  set = local.all_set

  set_sensitive = [
    {
      name  = "data.subscriberPrivateKeyId"
      value = var.subscriber_private_key_id
    }
  ]

  lifecycle {
    precondition {
      condition     = length(var.preconditions) == 0 || alltrue([for p in var.preconditions : p.condition])
      error_message = length(var.preconditions) == 0 ? "no preconditions" : join("; ", [for p in var.preconditions : p.error_message if !p.condition])
    }
  }
}
