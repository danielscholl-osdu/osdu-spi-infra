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

# In-cluster Redis (Bitnami replication: 1 master + 2 replicas)
# TLS enabled via cert-manager (required by OSDU services that hardcode SSL)
# Single write endpoint: redis-master.<namespace>.svc.cluster.local:6380

resource "kubectl_manifest" "redis_selfsigned_issuer" {
  yaml_body = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: Issuer
    metadata:
      name: redis-selfsigned
      namespace: ${var.namespace}
    spec:
      selfSigned: {}
  YAML
}

resource "kubectl_manifest" "redis_tls_cert" {
  yaml_body = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: Certificate
    metadata:
      name: redis-tls
      namespace: ${var.namespace}
    spec:
      secretName: redis-tls-secret
      dnsNames:
        - redis-master.${var.namespace}.svc.cluster.local
        - redis-replicas.${var.namespace}.svc.cluster.local
      issuerRef:
        name: redis-selfsigned
        kind: Issuer
  YAML

  depends_on = [kubectl_manifest.redis_selfsigned_issuer]
}

resource "kubernetes_secret_v1" "redis_password" {
  metadata {
    name      = "redis-credentials"
    namespace = var.namespace
  }

  data = {
    "redis-password" = var.redis_password
  }
}

resource "helm_release" "redis" {
  name             = "redis"
  repository       = "oci://registry-1.docker.io/bitnamicharts"
  chart            = "redis"
  version          = "24.1.3"
  namespace        = var.namespace
  create_namespace = false
  timeout          = 600

  values = [<<-YAML
    architecture: replication

    global:
      security:
        allowInsecureImages: true
    image:
      registry: docker.io
      repository: bitnamilegacy/redis
      tag: 8.2.1-debian-12-r0

    auth:
      enabled: true
      existingSecret: redis-credentials
      existingSecretPasswordKey: redis-password

    tls:
      enabled: true
      authClients: false
      existingSecret: "redis-tls-secret"
      certFilename: "tls.crt"
      certKeyFilename: "tls.key"
      certCAFilename: "ca.crt"

    master:
      containerPorts:
        redis: 6380
      replicaCount: 1
      persistence:
        enabled: true
        storageClass: redis-storageclass
        size: 8Gi
        accessModes:
          - ReadWriteOnce
      resources:
        requests:
          cpu: 250m
          memory: 256Mi
        limits:
          cpu: "1"
          memory: 1Gi
      podSecurityContext:
        fsGroup: 1001
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containerSecurityContext:
        runAsUser: 1001
        runAsGroup: 1001
        runAsNonRoot: true
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL
        seccompProfile:
          type: RuntimeDefault
      tolerations:
        - effect: NoSchedule
          key: workload
          value: "platform"
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: agentpool
                    operator: In
                    values:
                      - platform
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app.kubernetes.io/component: master

    replica:
      containerPorts:
        redis: 6380
      replicaCount: 2
      persistence:
        enabled: true
        storageClass: redis-storageclass
        size: 8Gi
        accessModes:
          - ReadWriteOnce
      resources:
        requests:
          cpu: 250m
          memory: 256Mi
        limits:
          cpu: "1"
          memory: 1Gi
      podSecurityContext:
        fsGroup: 1001
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containerSecurityContext:
        runAsUser: 1001
        runAsGroup: 1001
        runAsNonRoot: true
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL
        seccompProfile:
          type: RuntimeDefault
      tolerations:
        - effect: NoSchedule
          key: workload
          value: "platform"
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: agentpool
                    operator: In
                    values:
                      - platform
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app.kubernetes.io/component: replica
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app.kubernetes.io/component: replica

    sentinel:
      enabled: false

    metrics:
      enabled: false
  YAML
  ]

  depends_on = [kubernetes_secret_v1.redis_password, kubectl_manifest.redis_tls_cert]
}
