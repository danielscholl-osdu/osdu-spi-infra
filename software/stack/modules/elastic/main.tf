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

# Elasticsearch + Kibana CRs and bootstrap resources

resource "kubectl_manifest" "elasticsearch" {
  yaml_body = <<-YAML
    apiVersion: elasticsearch.k8s.elastic.co/v1
    kind: Elasticsearch
    metadata:
      name: elasticsearch
      namespace: ${var.namespace}
    spec:
      version: 8.18.2
      http:
        service:
          spec:
            selector:
              common.k8s.elastic.co/type: elasticsearch
              elasticsearch.k8s.elastic.co/cluster-name: elasticsearch
              elasticsearch.service/http: "true"
        tls:
          selfSignedCertificate: {}
      transport:
        service:
          spec:
            selector:
              common.k8s.elastic.co/type: elasticsearch
              elasticsearch.k8s.elastic.co/cluster-name: elasticsearch
              elasticsearch.service/transport: "true"
      nodeSets:
        - name: default
          count: 3
          volumeClaimTemplates:
            - metadata:
                name: elasticsearch-data
              spec:
                accessModes:
                  - ReadWriteOnce
                resources:
                  requests:
                    storage: 128Gi
                storageClassName: es-storageclass
          config:
            node.roles: ["master", "data", "ingest"]
            node.store.allow_mmap: false
          podTemplate:
            metadata:
              labels:
                elasticsearch.service/http: "true"
                elasticsearch.service/transport: "true"
            spec:
              securityContext:
                fsGroup: 1000
                runAsNonRoot: true
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
                      elasticsearch.k8s.elastic.co/cluster-name: elasticsearch
                - maxSkew: 1
                  topologyKey: kubernetes.io/hostname
                  whenUnsatisfiable: ScheduleAnyway
                  labelSelector:
                    matchLabels:
                      elasticsearch.k8s.elastic.co/cluster-name: elasticsearch
              containers:
                - name: elasticsearch
                  env:
                    - name: ES_JAVA_OPTS
                      value: "-Xms2g -Xmx2g"
                  resources:
                    requests:
                      memory: 4Gi
                      cpu: 1
                    limits:
                      memory: 4Gi
                      cpu: 2
                  livenessProbe:
                    tcpSocket:
                      port: 9200
                    initialDelaySeconds: 90
                    periodSeconds: 30
                    timeoutSeconds: 10
                    failureThreshold: 3
  YAML
}

resource "kubectl_manifest" "kibana" {
  yaml_body = <<-YAML
    apiVersion: kibana.k8s.elastic.co/v1
    kind: Kibana
    metadata:
      name: kibana
      namespace: ${var.namespace}
    spec:
      version: 8.18.2
      count: 1
      elasticsearchRef:
        name: elasticsearch
%{if var.has_ingress_hostname~}
      config:
        server.publicBaseUrl: "https://${var.kibana_hostname}"
%{endif~}
      http:
        tls:
          selfSignedCertificate:
            disabled: true
      podTemplate:
        spec:
          securityContext:
            runAsNonRoot: true
            seccompProfile:
              type: RuntimeDefault
          tolerations:
            - effect: NoSchedule
              key: workload
              value: "platform"
          containers:
            - name: kibana
              resources:
                requests:
                  memory: 1Gi
                  cpu: 0.5
                limits:
                  memory: 2Gi
                  cpu: 1
              readinessProbe:
                httpGet:
                  path: /api/status
                  port: 5601
                  scheme: HTTP
                initialDelaySeconds: 30
                periodSeconds: 10
                timeoutSeconds: 5
                failureThreshold: 3
              livenessProbe:
                httpGet:
                  path: /api/status
                  port: 5601
                  scheme: HTTP
                initialDelaySeconds: 60
                periodSeconds: 30
                timeoutSeconds: 10
                failureThreshold: 3
  YAML

  depends_on = [kubectl_manifest.elasticsearch]
}

# Bootstrap resources

resource "kubernetes_service_account_v1" "elastic_bootstrap" {
  count = var.enable_bootstrap ? 1 : 0

  metadata {
    name      = "bootstrap-sa"
    namespace = var.namespace
  }
}

resource "time_sleep" "wait_for_eck_reconciliation" {
  count = var.enable_bootstrap ? 1 : 0

  depends_on      = [kubectl_manifest.elasticsearch]
  create_duration = "60s"
}

data "kubernetes_secret_v1" "elasticsearch_password" {
  count = var.enable_bootstrap ? 1 : 0

  metadata {
    name      = "elasticsearch-es-elastic-user"
    namespace = var.namespace
  }

  depends_on = [time_sleep.wait_for_eck_reconciliation]
}

resource "kubernetes_secret_v1" "elastic_bootstrap_secret" {
  count = var.enable_bootstrap ? 1 : 0

  metadata {
    name      = "elastic-bootstrap-secret"
    namespace = var.namespace
  }

  data = {
    ELASTIC_HOST_SYSTEM = "elasticsearch-es-http.${var.namespace}.svc"
    ELASTIC_PORT_SYSTEM = "9200"
    ELASTIC_USER_SYSTEM = "elastic"
    ELASTIC_PASS_SYSTEM = data.kubernetes_secret_v1.elasticsearch_password[0].data["elastic"]
  }
}

resource "kubernetes_secret_v1" "indexer_elastic_secret" {
  count = var.enable_bootstrap ? 1 : 0

  metadata {
    name      = "indexer-elastic-secret"
    namespace = var.namespace
  }

  data = {
    ELASTIC_USER_SYSTEM = "elastic"
    ELASTIC_PASS_SYSTEM = data.kubernetes_secret_v1.elasticsearch_password[0].data["elastic"]
  }
}

resource "kubernetes_secret_v1" "search_elastic_secret" {
  count = var.enable_bootstrap ? 1 : 0

  metadata {
    name      = "search-elastic-secret"
    namespace = var.namespace
  }

  data = {
    ELASTIC_USER_SYSTEM = "elastic"
    ELASTIC_PASS_SYSTEM = data.kubernetes_secret_v1.elasticsearch_password[0].data["elastic"]
  }
}

resource "helm_release" "elastic_bootstrap" {
  count = var.enable_bootstrap ? 1 : 0

  name             = "elastic-bootstrap"
  repository       = "oci://community.opengroup.org:5555/osdu/platform/deployment-and-operations/base-containers-cimpl/elastic-bootstrap/cimpl-helm"
  chart            = "elastic-bootstrap"
  version          = "0.0.7-latest"
  namespace        = var.namespace
  create_namespace = false
  timeout          = 600

  set = [
    {
      name  = "elasticsearch.image"
      value = "community.opengroup.org:5555/osdu/platform/deployment-and-operations/base-containers-cimpl/elastic-bootstrap/elastic-bootstrap:f72735fb"
    },
    {
      name  = "elasticsearch.host"
      value = "elasticsearch-es-http.${var.namespace}.svc"
    },
    {
      name  = "elasticsearch.port"
      value = "9200"
    },
    {
      name  = "elasticsearch.protocol"
      value = "https"
    },
    {
      name  = "elasticsearch.username"
      value = "elastic"
    },
  ]

  postrender = {
    binary_path = "pwsh"
    args        = ["-File", "${path.module}/postrender.ps1"]
  }

  depends_on = [
    kubectl_manifest.elasticsearch,
    kubernetes_service_account_v1.elastic_bootstrap,
    kubernetes_secret_v1.elastic_bootstrap_secret,
    kubernetes_secret_v1.indexer_elastic_secret,
    kubernetes_secret_v1.search_elastic_secret,
  ]
}
