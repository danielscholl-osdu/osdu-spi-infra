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

# Cross-namespace service aliases and mTLS policy

# Cross-namespace aliases — ExternalName services in the OSDU namespace that
# point to middleware in the platform namespace.  AKS Gatekeeper's
# UniqueServiceSelector policy only allows one ExternalName service per
# namespace (empty selectors collide), so we use a single kubectl_manifest
# containing all aliases as separate documents.

resource "kubernetes_service_v1" "rabbitmq_alias" {
  metadata {
    name      = "rabbitmq"
    namespace = var.namespace
  }

  spec {
    type          = "ExternalName"
    external_name = "rabbitmq.${var.platform_namespace}.svc.cluster.local"
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}
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
