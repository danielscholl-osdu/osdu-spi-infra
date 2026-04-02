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

# CNPG PostgreSQL Cluster, credential secrets, and database bootstrap

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

resource "kubernetes_secret_v1" "postgresql_user" {
  metadata {
    name      = "postgresql-user-credentials"
    namespace = var.namespace
  }

  data = {
    username = var.postgresql_username
    password = var.postgresql_password
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
          database: osdu
          owner: ${var.postgresql_username}
          secret:
            name: postgresql-user-credentials
          dataChecksums: true
      storage:
        size: 8Gi
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
                      - ${var.nodepool_name}
        tolerations:
          - effect: NoSchedule
            key: workload
            value: "${var.nodepool_name}"
  YAML

  depends_on = [
    kubernetes_secret_v1.postgresql_superuser,
    kubernetes_secret_v1.postgresql_user
  ]
}

# Database credential secrets

resource "kubernetes_secret_v1" "keycloak_db" {
  metadata {
    name      = "keycloak-db-credentials"
    namespace = var.namespace
  }

  data = {
    username = "keycloak"
    password = var.keycloak_db_password
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

# Database bootstrap job

locals {
  bootstrap_sql = join("\n", [
    for db in ["partition", "entitlements", "legal", "schema", "storage",
      "file", "dataset", "register", "workflow", "seismic",
    "reservoir", "well_delivery"] :
    templatefile("${path.module}/sql/${db}.sql.tftpl", {
      data_partition_id = var.cimpl_tenant
    })
  ])
}

resource "kubectl_manifest" "cnpg_database_bootstrap" {
  yaml_body = <<-YAML
    apiVersion: batch/v1
    kind: Job
    metadata:
      name: cnpg-database-bootstrap
      namespace: ${var.namespace}
    spec:
      backoffLimit: 20
      ttlSecondsAfterFinished: 600
      template:
        metadata:
          annotations:
            sidecar.istio.io/inject: "false"
        spec:
          automountServiceAccountToken: false
          restartPolicy: OnFailure
          securityContext:
            runAsNonRoot: true
            runAsUser: 999
            runAsGroup: 999
            seccompProfile:
              type: RuntimeDefault
          containers:
            - name: cnpg-database-bootstrap
              image: "ghcr.io/cloudnative-pg/postgresql:16.4"
              imagePullPolicy: IfNotPresent
              env:
                - name: PGHOST
                  value: "postgresql-rw.${var.namespace}.svc.cluster.local"
                - name: PGDATABASE
                  value: "postgres"
                - name: PGUSER
                  valueFrom:
                    secretKeyRef:
                      name: postgresql-superuser-credentials
                      key: username
                - name: PGPASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: postgresql-superuser-credentials
                      key: password
                - name: KEYCLOAK_PASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: keycloak-db-credentials
                      key: password
                - name: AIRFLOW_PASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: airflow-db-credentials
                      key: password
              command:
                - /bin/sh
                - -ec
              args:
                - |
                  echo "=== CNPG Database Bootstrap (ROSA-aligned) ==="

                  echo "Waiting for PostgreSQL to accept connections..."
                  for i in $(seq 1 60); do
                    if pg_isready -h "$PGHOST" -U "$PGUSER" 2>/dev/null; then
                      echo "PostgreSQL is ready."
                      break
                    fi
                    echo "  attempt $i/60 - not ready, waiting 10s..."
                    sleep 10
                  done

                  create_role_and_db() {
                    local role="$1" password="$2" dbname="$3"
                    if psql -tAc "SELECT 1 FROM pg_roles WHERE rolname = '$role'" | grep -q 1; then
                      echo "Role $role exists, updating password..."
                      psql -c "ALTER ROLE $role WITH LOGIN PASSWORD '$password'"
                    else
                      echo "Creating role $role..."
                      psql -c "CREATE ROLE $role WITH LOGIN PASSWORD '$password'"
                    fi
                    if psql -tAc "SELECT 1 FROM pg_database WHERE datname = '$dbname'" | grep -q 1; then
                      echo "Database $dbname already exists."
                    else
                      echo "Creating database $dbname..."
                      psql -c "CREATE DATABASE $dbname OWNER $role"
                    fi
                  }

                  create_role_and_db keycloak "$KEYCLOAK_PASSWORD" keycloak
                  create_role_and_db airflow "$AIRFLOW_PASSWORD" airflow

                  echo "Creating OSDU service databases..."
                  for db in partition entitlements legal schema storage file dataset register workflow seismic reservoir well_delivery; do
                    if psql -tAc "SELECT 1 FROM pg_database WHERE datname = '$db'" | grep -q 1; then
                      echo "  Database $db already exists."
                    else
                      echo "  Creating database $db..."
                      psql -c "CREATE DATABASE $db OWNER osdu"
                    fi
                  done

                  cat > /tmp/bootstrap.sql <<'BOOTSTRAP_SQL'
                  ${indent(18, local.bootstrap_sql)}
                  BOOTSTRAP_SQL

                  echo "Executing ROSA-aligned DDL across all databases..."
                  psql -f /tmp/bootstrap.sql

                  echo "=== Database bootstrap complete (14 databases) ==="
              resources:
                requests:
                  cpu: 50m
                  memory: 128Mi
                limits:
                  cpu: 250m
                  memory: 256Mi
  YAML

  depends_on = [
    kubectl_manifest.postgresql_cluster,
    kubernetes_secret_v1.postgresql_superuser,
    kubernetes_secret_v1.keycloak_db,
    kubernetes_secret_v1.airflow_db
  ]
}
moved {
  from = kubernetes_secret.postgresql_user
  to   = kubernetes_secret_v1.postgresql_user
}

moved {
  from = kubernetes_secret.airflow_db
  to   = kubernetes_secret_v1.airflow_db
}
