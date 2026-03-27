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

# ECK Operator (cluster-wide singleton)
resource "helm_release" "elastic_operator" {
  name             = "elastic-operator"
  repository       = "https://helm.elastic.co"
  chart            = "eck-operator"
  version          = "3.3.0"
  namespace        = var.namespace
  create_namespace = false
  timeout          = 600
  atomic           = true

  set = [
    {
      name  = "installCRDs"
      value = "true"
    },
    {
      name  = "resources.requests.cpu"
      value = "100m"
    },
    {
      name  = "resources.requests.memory"
      value = "150Mi"
    },
    {
      name  = "resources.limits.cpu"
      value = "1"
    },
    {
      name  = "resources.limits.memory"
      value = "1Gi"
    },
  ]

  postrender = {
    binary_path = "pwsh"
    args        = ["-File", "${path.module}/postrender.ps1"]
  }
}
