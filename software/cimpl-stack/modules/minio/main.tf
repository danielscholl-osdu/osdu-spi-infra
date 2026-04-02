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

# MinIO for S3-compatible object storage

resource "helm_release" "minio" {
  name             = "minio"
  repository       = "https://charts.min.io/"
  chart            = "minio"
  version          = "5.4.0"
  namespace        = var.namespace
  create_namespace = false

  timeout = 600
  wait    = false

  postrender = {
    binary_path = "pwsh"
    args        = ["-File", "${path.module}/postrender.ps1"]
  }

  values = [<<-YAML
    mode: standalone
    commonLabels:
      app.kubernetes.io/component: minio-server
    image:
      repository: quay.io/minio/minio
      tag: "RELEASE.2024-12-18T13-15-44Z"
      pullPolicy: IfNotPresent
    replicas: 1
    persistence:
      enabled: true
      storageClass: "managed-csi"
      size: 10Gi
    resources:
      requests:
        cpu: 250m
        memory: 256Mi
      limits:
        cpu: 1
        memory: 1Gi
    rootUser: "${var.minio_root_user}"
    rootPassword: "${var.minio_root_password}"
    consoleService:
      type: ClusterIP
      port: 9001
    service:
      type: ClusterIP
      port: 9000
    securityContext:
      enabled: true
      runAsUser: 1000
      runAsGroup: 1000
      fsGroup: 1000
      fsGroupChangePolicy: OnRootMismatch
    containerSecurityContext:
      enabled: true
      runAsUser: 1000
      runAsGroup: 1000
      runAsNonRoot: true
      allowPrivilegeEscalation: false
      capabilities:
        drop:
          - ALL
      seccompProfile:
        type: RuntimeDefault
    users: []
    buckets:
      - name: refi-opa-policies
        policy: none
        purge: false
      - name: refi-osdu-records
        policy: none
        purge: false
      - name: refi-osdu-system-schema
        policy: none
        purge: false
      - name: refi-osdu-schema
        policy: none
        purge: false
      - name: refi-osdu-legal-config
        policy: none
        purge: false
    makeBucketJob:
      securityContext:
        enabled: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
      containerSecurityContext:
        enabled: true
        runAsUser: 1000
        runAsGroup: 1000
        runAsNonRoot: true
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL
        seccompProfile:
          type: RuntimeDefault
      resources:
        requests:
          cpu: 50m
          memory: 64Mi
        limits:
          cpu: 100m
          memory: 128Mi
    policies: []
    svcaccts: []
    customCommands: []
  YAML
  ]

  lifecycle {
    ignore_changes = all
  }
}
