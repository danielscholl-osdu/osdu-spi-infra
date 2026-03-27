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

# Lightweight PostgreSQL for Airflow metadata database
# Uses Bitnami PostgreSQL Helm chart (single-instance, not CNPG)
#
# This is NOT the OSDU data store -- OSDU services use Azure CosmosDB.
# This PostgreSQL instance is solely for Airflow's metadata database.

resource "helm_release" "postgresql" {
  name             = "postgresql"
  repository       = "oci://registry-1.docker.io/bitnamicharts"
  chart            = "postgresql"
  version          = "16.4.1"
  namespace        = var.namespace
  create_namespace = false
  wait             = true
  timeout          = 600

  values = [<<-YAML
    auth:
      database: airflow
      username: airflow
      existingSecret: ""

    primary:
      persistence:
        size: ${var.storage_size}
      resources:
        requests:
          cpu: 250m
          memory: 512Mi
        limits:
          cpu: "1"
          memory: 1Gi
      tolerations:
        - key: workload
          operator: Equal
          value: "platform"
          effect: NoSchedule
      nodeSelector:
        agentpool: platform
      podSecurityContext:
        fsGroup: 1001
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containerSecurityContext:
        runAsUser: 1001
        allowPrivilegeEscalation: false

    metrics:
      enabled: false
  YAML
  ]

  set_sensitive = [
    {
      name  = "auth.password"
      value = var.db_password
    },
  ]
}
