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

# Apache Airflow workflow orchestration (Azure SPI variant)
#
# Key differences from cimpl variant:
#   - DAG storage via Azure Blob CSI driver (PersistentVolume) instead of ConfigMap/git
#   - Workload identity annotations on the Airflow ServiceAccount
#   - No Keycloak -- authentication uses Azure AD tokens
#   - PostgreSQL connection uses in-cluster Bitnami PostgreSQL (not CNPG)

locals {
  # OSDU pip packages -- sourced from OSDU GitLab PyPI registries
  pip_packages = join(" ", [
    "--extra-index-url=https://community.opengroup.org/api/v4/projects/148/packages/pypi/simple",
    "--extra-index-url=https://community.opengroup.org/api/v4/projects/668/packages/pypi/simple",
    "--extra-index-url=https://community.opengroup.org/api/v4/projects/823/packages/pypi/simple",
    "osdu-api==${var.osdu_api_version}",
    "osdu-airflow==${var.osdu_airflow_version}",
    "osdu-ingestion==${var.osdu_ingestion_version}",
    "styleframe",
  ])

  # Golden source repos for DAGs
  dags_base = "https://community.opengroup.org/osdu/platform/data-flow/ingestion"
  dags_ref  = var.osdu_dags_branch

  dags_sources = {
    "ingestion-dags"         = "src/osdu_dags"
    "csv-parser/csv-parser"  = "airflowdags"
    "segy-to-zgy-conversion" = "airflow/workflow-svc-v2"
    "segy-to-vds-conversion" = "src/dags"
    "witsml-parser"          = "energistics/src/dags/energistics"
  }
}

resource "random_bytes" "airflow_fernet_key" {
  length = 32
}

resource "random_password" "airflow_webserver_secret" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "airflow_secrets" {
  metadata {
    name      = "airflow-secrets"
    namespace = var.namespace
  }

  data = {
    "fernet-key"           = random_bytes.airflow_fernet_key.base64
    "webserver-secret-key" = random_password.airflow_webserver_secret.result
  }

  type = "Opaque"
}

# Local DAGs (generic, no osdu_airflow dependency)
resource "kubernetes_config_map_v1" "airflow_dags" {
  metadata {
    name      = "airflow-dags"
    namespace = var.namespace
  }

  data = {
    for f in fileset("${path.module}/dags", "*.py") :
    f => file("${path.module}/dags/${f}")
  }
}

# Download DAGs from golden source repos and create ConfigMap
resource "null_resource" "ingestion_dags" {
  triggers = {
    dags_branch  = var.osdu_dags_branch
    dags_sources = jsonencode(local.dags_sources)
  }

  provisioner "local-exec" {
    interpreter = ["pwsh", "-Command"]
    command     = "& '${path.module}/download-dags.ps1' -DagsBase '${local.dags_base}' -DagsRef '${local.dags_ref}' -DagsSources '${replace(jsonencode(local.dags_sources), "'", "''")}' -OsduNamespace '${var.osdu_namespace}' -Namespace '${var.namespace}' -ScriptDir '${path.module}'"
  }

  depends_on = [kubernetes_config_map_v1.airflow_dags]
}

# ─── Azure Blob CSI PersistentVolume for DAGs ──────────────────────────────────
# When a storage account and container are provided, mount DAGs from Azure Blob
# via the CSI driver. Otherwise falls back to ConfigMap-based DAGs.

resource "kubernetes_persistent_volume_v1" "dags_blob" {
  count = var.dag_storage_account_name != "" ? 1 : 0

  metadata {
    name = "airflow-dags-blob-pv"
  }

  spec {
    capacity = {
      storage = "10Gi"
    }
    access_modes                     = ["ReadOnlyMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "azureblob-fuse-premium"

    persistent_volume_source {
      csi {
        driver        = "blob.csi.azure.com"
        read_only     = true
        volume_handle = "airflow-dags-${var.namespace}"
        volume_attributes = {
          containerName  = var.dag_container_name
          storageAccount = var.dag_storage_account_name
        }
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim_v1" "dags_blob" {
  count = var.dag_storage_account_name != "" ? 1 : 0

  metadata {
    name      = "airflow-dags-blob-pvc"
    namespace = var.namespace
  }

  spec {
    access_modes       = ["ReadOnlyMany"]
    storage_class_name = "azureblob-fuse-premium"
    volume_name        = kubernetes_persistent_volume_v1.dags_blob[0].metadata[0].name

    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
}

# ─── DAG volume configuration ─────────────────────────────────────────────────

locals {
  # When Blob CSI is enabled, use PVC; otherwise use ConfigMap init containers
  use_blob_dags = var.dag_storage_account_name != ""

  # Volume definitions for ConfigMap-based DAGs (fallback)
  configmap_extra_volumes = [
    {
      name = "dags-local"
      configMap = {
        name = "airflow-dags"
      }
    },
    {
      name = "dags-ingestion"
      configMap = {
        name     = "ingestion-dags"
        optional = true
      }
    },
    {
      name     = "dags"
      emptyDir = {}
    },
  ]

  configmap_init_container = {
    name    = "copy-dags"
    image   = "apache/airflow:2.11.2"
    command = ["sh", "-c", "cp /dags-local/*.py /opt/airflow/dags/ 2>/dev/null; cp /dags-ingestion/*.py /opt/airflow/dags/ 2>/dev/null; true"]
    volumeMounts = [
      { name = "dags-local", mountPath = "/dags-local", readOnly = true },
      { name = "dags-ingestion", mountPath = "/dags-ingestion", readOnly = true },
      { name = "dags", mountPath = "/opt/airflow/dags" },
    ]
    resources = {
      requests = { cpu = "25m", memory = "64Mi" }
      limits   = { cpu = "100m", memory = "128Mi" }
    }
    securityContext = {
      runAsUser                = 50000
      allowPrivilegeEscalation = false
    }
  }
}

resource "helm_release" "airflow" {
  name             = "airflow"
  repository       = "https://airflow.apache.org"
  chart            = "airflow"
  version          = "1.19.0"
  namespace        = var.namespace
  create_namespace = false
  wait             = true
  wait_for_jobs    = true
  timeout          = 900

  values = [<<-YAML
    airflowVersion: "2.11.2"
    defaultAirflowRepository: apache/airflow
    defaultAirflowTag: "2.11.2"

    executor: KubernetesExecutor

    config:
      webserver:
        enable_proxy_fix: "True"
      core:
        dags_are_paused_at_creation: "False"

    env:
      - name: _PIP_ADDITIONAL_REQUIREMENTS
        value: "${local.pip_packages}"
      - name: AIRFLOW_VAR_ENV_VARS_ENABLED
        value: "true"
      - name: AIRFLOW_VAR_CORE__SERVICE__PARTITION__URL
        value: "http://partition.${var.osdu_namespace}.svc.cluster.local/api/partition/v1"
      - name: AIRFLOW_VAR_CORE__SERVICE__LEGAL__HOST
        value: "http://legal.${var.osdu_namespace}.svc.cluster.local/api/legal/v1"
      - name: AIRFLOW_VAR_CORE__SERVICE__ENTITLEMENTS__URL
        value: "http://entitlements.${var.osdu_namespace}.svc.cluster.local/api/entitlements/v2"
      - name: AIRFLOW_VAR_CORE__SERVICE__SCHEMA__URL
        value: "http://schema.${var.osdu_namespace}.svc.cluster.local/api/schema-service/v1"
      - name: AIRFLOW_VAR_CORE__SERVICE__SEARCH__URL
        value: "http://search.${var.osdu_namespace}.svc.cluster.local/api/search/v2"
      - name: AIRFLOW_VAR_CORE__SERVICE__SEARCH_WITH_CURSOR__URL
        value: "http://search.${var.osdu_namespace}.svc.cluster.local/api/search/v2/query_with_cursor"
      - name: AIRFLOW_VAR_CORE__SERVICE__STORAGE__URL
        value: "http://storage.${var.osdu_namespace}.svc.cluster.local/api/storage/v2"
      - name: AIRFLOW_VAR_CORE__SERVICE__FILE__HOST
        value: "http://file.${var.osdu_namespace}.svc.cluster.local/api/file"
      - name: AIRFLOW_VAR_CORE__SERVICE__DATASET__URL
        value: "http://dataset.${var.osdu_namespace}.svc.cluster.local/api/dataset/v1"
      - name: AIRFLOW_VAR_CORE__SERVICE__DATASET__HOST
        value: "http://dataset.${var.osdu_namespace}.svc.cluster.local/api/dataset/v1"
      - name: AIRFLOW_VAR_CORE__SERVICE__WORKFLOW__HOST
        value: "http://workflow.${var.osdu_namespace}.svc.cluster.local/api/workflow/v1"
      - name: AIRFLOW_VAR_CORE__SERVICE__WORKFLOW__URL
        value: "http://workflow.${var.osdu_namespace}.svc.cluster.local/api/workflow/v1"
      - name: AIRFLOW_VAR_CORE__CONFIG__SHOW_SKIPPED_IDS
        value: "True"
      - name: AIRFLOW_VAR_ENTITLEMENTS_MODULE_NAME
        value: "entitlements_client"
      - name: AIRFLOW_VAR_SCHEDULER_INTERVAL
        value: "*/5 * * * *"
      - name: CLOUD_PROVIDER
        value: "azure"
      - name: PYTHONPATH
        value: "/opt/airflow/dags:/opt/airflow"

    fernetKeySecretName: airflow-secrets
    webserverSecretKeySecretName: airflow-secrets

    # Workload identity annotations on the Airflow ServiceAccount
    serviceAccount:
      create: true
      name: airflow-sa
      annotations:
        azure.workload.identity/client-id: "${var.workload_identity_client_id}"
        azure.workload.identity/tenant-id: "${var.azure_tenant_id}"

    data:
      metadataConnection:
        user: airflow
        pass: "${var.airflow_db_password}"
        protocol: postgresql
        host: ${var.postgresql_host}
        port: 5432
        db: airflow

    createUserJob:
      useHelmHooks: false
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
    migrateDatabaseJob:
      useHelmHooks: false
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

    logGroomerSidecar:
      resources:
        requests:
          cpu: 25m
          memory: 128Mi
        limits:
          cpu: 100m
          memory: 256Mi

    waitForMigrations:
      resources:
        requests:
          cpu: 25m
          memory: 128Mi
        limits:
          cpu: 100m
          memory: 256Mi

    postgresql:
      enabled: false
    redis:
      enabled: false

    securityContexts:
      pod:
        runAsUser: 50000
        runAsGroup: 0
        fsGroup: 0
      containers:
        runAsUser: 50000
        allowPrivilegeEscalation: false

    webserver:
      replicas: 1
      resources:
        requests:
          cpu: 200m
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
      extraVolumes:
        - name: dags-local
          configMap:
            name: airflow-dags
        - name: dags-ingestion
          configMap:
            name: ingestion-dags
            optional: true
        - name: dags
          emptyDir: {}
      extraVolumeMounts:
        - name: dags
          mountPath: /opt/airflow/dags
      extraInitContainers:
        - name: copy-dags
          image: apache/airflow:2.11.2
          command: ['sh', '-c', 'cp /dags-local/*.py /opt/airflow/dags/ 2>/dev/null; cp /dags-ingestion/*.py /opt/airflow/dags/ 2>/dev/null; true']
          volumeMounts:
            - name: dags-local
              mountPath: /dags-local
              readOnly: true
            - name: dags-ingestion
              mountPath: /dags-ingestion
              readOnly: true
            - name: dags
              mountPath: /opt/airflow/dags
          resources:
            requests:
              cpu: 25m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi
          securityContext:
            runAsUser: 50000
            allowPrivilegeEscalation: false

    scheduler:
      replicas: 1
      resources:
        requests:
          cpu: 250m
          memory: 512Mi
        limits:
          cpu: "1"
          memory: 1Gi
      logGroomerSidecar:
        resources:
          requests:
            cpu: 25m
            memory: 128Mi
          limits:
            cpu: 100m
            memory: 256Mi
      tolerations:
        - key: workload
          operator: Equal
          value: "platform"
          effect: NoSchedule
      nodeSelector:
        agentpool: platform
      extraVolumes:
        - name: dags-local
          configMap:
            name: airflow-dags
        - name: dags-ingestion
          configMap:
            name: ingestion-dags
            optional: true
        - name: dags
          emptyDir: {}
      extraVolumeMounts:
        - name: dags
          mountPath: /opt/airflow/dags
      extraInitContainers:
        - name: copy-dags
          image: apache/airflow:2.11.2
          command: ['sh', '-c', 'cp /dags-local/*.py /opt/airflow/dags/ 2>/dev/null; cp /dags-ingestion/*.py /opt/airflow/dags/ 2>/dev/null; true']
          volumeMounts:
            - name: dags-local
              mountPath: /dags-local
              readOnly: true
            - name: dags-ingestion
              mountPath: /dags-ingestion
              readOnly: true
            - name: dags
              mountPath: /opt/airflow/dags
          resources:
            requests:
              cpu: 25m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi
          securityContext:
            runAsUser: 50000
            allowPrivilegeEscalation: false

    triggerer:
      replicas: 1
      resources:
        requests:
          cpu: 200m
          memory: 512Mi
        limits:
          cpu: "1"
          memory: 1Gi
      logGroomerSidecar:
        resources:
          requests:
            cpu: 25m
            memory: 128Mi
          limits:
            cpu: 100m
            memory: 256Mi
      tolerations:
        - key: workload
          operator: Equal
          value: "platform"
          effect: NoSchedule
      nodeSelector:
        agentpool: platform
      extraVolumes:
        - name: dags-local
          configMap:
            name: airflow-dags
        - name: dags-ingestion
          configMap:
            name: ingestion-dags
            optional: true
        - name: dags
          emptyDir: {}
      extraVolumeMounts:
        - name: dags
          mountPath: /opt/airflow/dags
      extraInitContainers:
        - name: copy-dags
          image: apache/airflow:2.11.2
          command: ['sh', '-c', 'cp /dags-local/*.py /opt/airflow/dags/ 2>/dev/null; cp /dags-ingestion/*.py /opt/airflow/dags/ 2>/dev/null; true']
          volumeMounts:
            - name: dags-local
              mountPath: /dags-local
              readOnly: true
            - name: dags-ingestion
              mountPath: /dags-ingestion
              readOnly: true
            - name: dags
              mountPath: /opt/airflow/dags
          resources:
            requests:
              cpu: 25m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi
          securityContext:
            runAsUser: 50000
            allowPrivilegeEscalation: false

    workers:
      replicas: 0
      extraVolumes:
        - name: dags-local
          configMap:
            name: airflow-dags
        - name: dags-ingestion
          configMap:
            name: ingestion-dags
            optional: true
        - name: dags
          emptyDir: {}
      extraVolumeMounts:
        - name: dags
          mountPath: /opt/airflow/dags
      extraInitContainers:
        - name: copy-dags
          image: apache/airflow:2.11.2
          command: ['sh', '-c', 'cp /dags-local/*.py /opt/airflow/dags/ 2>/dev/null; cp /dags-ingestion/*.py /opt/airflow/dags/ 2>/dev/null; true']
          volumeMounts:
            - name: dags-local
              mountPath: /dags-local
              readOnly: true
            - name: dags-ingestion
              mountPath: /dags-ingestion
              readOnly: true
            - name: dags
              mountPath: /opt/airflow/dags
          resources:
            requests:
              cpu: 25m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi
          securityContext:
            runAsUser: 50000
            allowPrivilegeEscalation: false

    statsd:
      enabled: false
  YAML
  ]

  depends_on = [
    kubernetes_secret_v1.airflow_secrets,
    kubernetes_config_map_v1.airflow_dags,
    null_resource.ingestion_dags,
  ]
}
