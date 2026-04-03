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

# OSDU namespace, ConfigMap, credentials, and service account

resource "kubernetes_namespace_v1" "osdu" {
  metadata {
    name = var.namespace
    labels = {
      "istio.io/rev" = var.istio_revision
    }
  }
}

resource "kubernetes_config_map_v1" "osdu_config" {
  metadata {
    name      = "osdu-config"
    namespace = var.namespace
  }

  data = {
    domain        = var.osdu_domain
    cimpl_project = var.cimpl_project
    cimpl_tenant  = var.cimpl_tenant
  }

  lifecycle {
    precondition {
      condition     = var.osdu_domain != ""
      error_message = "osdu-config: domain must be non-empty when enable_common is true."
    }
    precondition {
      condition     = var.cimpl_tenant != ""
      error_message = "osdu-config: cimpl_tenant must be non-empty when enable_common is true."
    }
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

resource "kubernetes_secret_v1" "osdu_credentials" {
  metadata {
    name      = "osdu-credentials"
    namespace = var.namespace
  }

  data = {
    cimpl_subscriber_private_key_id = var.cimpl_subscriber_private_key_id
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

resource "kubernetes_service_account_v1" "bootstrap" {
  metadata {
    name      = "bootstrap-sa"
    namespace = var.namespace
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}
