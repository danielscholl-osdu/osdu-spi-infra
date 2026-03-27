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

# CNPG PostgreSQL Cluster for Airflow metadata database.
# This is NOT the OSDU data store -- OSDU services use Azure CosmosDB.

resource "kubernetes_secret_v1" "postgresql_superuser" {
  metadata {
    name      = "postgresql-superuser-credentials"
    namespace = var.namespace
  }

  data = {
    username = "postgres"
    password = var.postgresql_password
  }
}

resource "kubernetes_secret_v1" "airflow_db" {
  metadata {
    name      = "airflow-db-credentials"
    namespace = var.namespace
  }

  data = {
    username = "airflow"
    password = var.airflow_db_password
  }
}

resource "kubectl_manifest" "postgresql_cluster" {
  yaml_body = <<-YAML
    apiVersion: postgresql.cnpg.io/v1
    kind: Cluster
    metadata:
      name: postgresql
      namespace: ${var.namespace}
    spec:
      instances: 3
      enableSuperuserAccess: true
      minSyncReplicas: 1
      maxSyncReplicas: 1
      replicationSlots:
        highAvailability:
          enabled: true
      superuserSecret:
        name: postgresql-superuser-credentials
      bootstrap:
        initdb:
          database: airflow
          owner: airflow
          secret:
            name: airflow-db-credentials
          dataChecksums: true
      storage:
        size: ${var.storage_size}
        storageClass: pg-storageclass
      walStorage:
        size: 4Gi
        storageClass: pg-storageclass
      resources:
        requests:
          cpu: 500m
          memory: 1Gi
        limits:
          cpu: "2"
          memory: 2Gi
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              cnpg.io/cluster: postgresql
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              cnpg.io/cluster: postgresql
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: agentpool
                    operator: In
                    values:
                      - platform
        tolerations:
          - effect: NoSchedule
            key: workload
            value: "platform"
  YAML

  depends_on = [
    kubernetes_secret_v1.postgresql_superuser,
    kubernetes_secret_v1.airflow_db
  ]
}
