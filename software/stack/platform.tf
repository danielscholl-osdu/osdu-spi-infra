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

# Platform namespace for middleware
resource "kubernetes_namespace_v1" "platform" {
  metadata {
    name = local.platform_namespace
    labels = {
      "istio-injection" = "enabled"
    }
  }
}

# Istio STRICT mTLS for platform namespace
resource "kubectl_manifest" "platform_peer_authentication" {
  yaml_body = <<-YAML
    apiVersion: security.istio.io/v1
    kind: PeerAuthentication
    metadata:
      name: platform-strict-mtls
      namespace: ${local.platform_namespace}
    spec:
      mtls:
        mode: STRICT
  YAML

  depends_on = [kubernetes_namespace_v1.platform]
}

# Shared Karpenter NodePool for all stacks (idempotent via server_side_apply)
resource "kubectl_manifest" "karpenter_nodepool" {
  count = var.enable_nodepool ? 1 : 0

  server_side_apply = true

  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: platform
    spec:
      template:
        metadata:
          labels:
            agentpool: platform
        spec:
          taints:
            - key: workload
              value: "platform"
              effect: NoSchedule
          requirements:
            - key: karpenter.azure.com/sku-family
              operator: In
              values: ["D"]
            - key: karpenter.azure.com/sku-cpu
              operator: In
              values: ["4", "8"]
            - key: karpenter.azure.com/sku-storage-premium-capable
              operator: In
              values: ["true"]
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["on-demand"]
            - key: kubernetes.io/arch
              operator: In
              values: ["amd64"]
            - key: kubernetes.io/os
              operator: In
              values: ["linux"]
          nodeClassRef:
            group: karpenter.azure.com
            kind: AKSNodeClass
            name: platform
      disruption:
        consolidationPolicy: WhenEmpty
        consolidateAfter: 5m
      limits:
        cpu: "64"
        memory: 256Gi
  YAML

  wait = true
}

resource "kubectl_manifest" "karpenter_aksnodeclass" {
  count = var.enable_nodepool ? 1 : 0

  server_side_apply = true

  yaml_body = <<-YAML
    apiVersion: karpenter.azure.com/v1alpha2
    kind: AKSNodeClass
    metadata:
      name: platform
    spec:
      imageFamily: AzureLinux
      osDiskSizeGB: 128
  YAML

  wait = true
}
