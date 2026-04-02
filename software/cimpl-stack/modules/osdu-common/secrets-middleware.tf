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

# Redis, MinIO, RabbitMQ, and Elasticsearch secrets

# ─── Redis secrets ───────────────────────────────────────────────────────────

resource "kubernetes_secret_v1" "entitlements_redis" {
  count = var.enable_entitlements ? 1 : 0

  metadata {
    name      = "entitlements-redis-secret"
    namespace = var.namespace
  }

  data = {
    REDIS_PASSWORD = var.redis_password
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

resource "kubernetes_secret_v1" "storage_redis" {
  count = var.enable_storage ? 1 : 0

  metadata {
    name      = "storage-redis-secret"
    namespace = var.namespace
  }

  data = {
    REDIS_PASSWORD = var.redis_password
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

resource "kubernetes_secret_v1" "notification_redis" {
  count = var.enable_notification ? 1 : 0

  metadata {
    name      = "notification-redis-secret"
    namespace = var.namespace
  }

  data = {
    REDIS_PASSWORD = var.redis_password
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

resource "kubernetes_secret_v1" "search_redis" {
  count = var.enable_search ? 1 : 0

  metadata {
    name      = "search-redis-secret"
    namespace = var.namespace
  }

  data = {
    REDIS_PASSWORD = var.redis_password
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

resource "kubernetes_secret_v1" "indexer_redis" {
  count = var.enable_indexer ? 1 : 0

  metadata {
    name      = "indexer-redis-secret"
    namespace = var.namespace
  }

  data = {
    REDIS_PASSWORD = var.redis_password
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

resource "kubernetes_secret_v1" "dataset_redis" {
  count = var.enable_dataset ? 1 : 0

  metadata {
    name      = "dataset-redis-secret"
    namespace = var.namespace
  }

  data = {
    REDIS_PASSWORD = var.redis_password
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

# ─── MinIO secrets ───────────────────────────────────────────────────────────

resource "kubernetes_secret_v1" "legal_minio" {
  count = var.enable_legal ? 1 : 0

  metadata {
    name      = "legal-minio-secret"
    namespace = var.namespace
  }

  data = {
    MINIO_ACCESS_KEY = var.minio_root_user
    MINIO_SECRET_KEY = var.minio_root_password
    AWS_REGION       = "us-east-1"
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

resource "kubernetes_secret_v1" "schema_minio" {
  count = var.enable_schema ? 1 : 0

  metadata {
    name      = "schema-minio-secret"
    namespace = var.namespace
  }

  data = {
    MINIO_ACCESS_KEY = var.minio_root_user
    MINIO_SECRET_KEY = var.minio_root_password
    AWS_REGION       = "us-east-1"
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

resource "kubernetes_secret_v1" "policy_minio" {
  count = var.enable_policy ? 1 : 0

  metadata {
    name      = "policy-minio-secret"
    namespace = var.namespace
  }

  data = {
    MINIO_ACCESS_KEY = var.minio_root_user
    MINIO_SECRET_KEY = var.minio_root_password
    AWS_REGION       = "us-east-1"
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

resource "kubernetes_secret_v1" "minio_bootstrap" {
  count = var.enable_policy ? 1 : 0

  metadata {
    name      = "minio-bootstrap-secret"
    namespace = var.namespace
  }

  data = {
    MINIO_ACCESS_KEY = var.minio_root_user
    MINIO_SECRET_KEY = var.minio_root_password
    MINIO_HOST       = "http://minio.${var.platform_namespace}.svc.cluster.local"
    MINIO_PORT       = "9000"
    AWS_REGION       = "us-east-1"
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

resource "kubernetes_secret_v1" "storage_minio" {
  count = var.enable_storage ? 1 : 0

  metadata {
    name      = "storage-minio-secret"
    namespace = var.namespace
  }

  data = {
    MINIO_ACCESS_KEY = var.minio_root_user
    MINIO_SECRET_KEY = var.minio_root_password
    AWS_REGION       = "us-east-1"
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

resource "kubernetes_secret_v1" "file_minio" {
  count = var.enable_file ? 1 : 0

  metadata {
    name      = "file-minio-secret"
    namespace = var.namespace
  }

  data = {
    MINIO_ACCESS_KEY = var.minio_root_user
    MINIO_SECRET_KEY = var.minio_root_password
    AWS_REGION       = "us-east-1"
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

resource "kubernetes_secret_v1" "wellbore_minio" {
  count = var.enable_wellbore ? 1 : 0

  metadata {
    name      = "wellbore-minio-secret"
    namespace = var.namespace
  }

  data = {
    MINIO_ACCESS_KEY = var.minio_root_user
    MINIO_SECRET_KEY = var.minio_root_password
    MINIO_ENDPOINT   = "http://minio.${var.platform_namespace}.svc.cluster.local:9000"
    AWS_REGION       = "us-east-1"
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

# ─── Airflow secret (workflow service → Airflow REST API) ────────────────────

resource "kubernetes_secret_v1" "workflow_airflow" {
  count = var.enable_workflow ? 1 : 0

  metadata {
    name      = "workflow-airflow-secret"
    namespace = var.namespace
  }

  data = {
    AIRFLOW_USERNAME = "admin"
    AIRFLOW_PASSWORD = "admin"
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

# ─── RabbitMQ secret (shared by legal, schema, register, notification, workflow) ─

resource "kubernetes_secret_v1" "rabbitmq" {
  count = (var.enable_legal || var.enable_schema || var.enable_register || var.enable_notification || var.enable_workflow) ? 1 : 0

  metadata {
    name      = "rabbitmq-secret"
    namespace = var.namespace
  }

  data = {
    RABBITMQ_ADMIN_USERNAME = var.rabbitmq_username
    RABBITMQ_ADMIN_PASSWORD = var.rabbitmq_password
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

# ─── Elasticsearch secrets ───────────────────────────────────────────────────

resource "kubernetes_secret_v1" "indexer_elastic" {
  count = var.enable_indexer ? 1 : 0

  metadata {
    name      = "indexer-elastic-secret"
    namespace = var.namespace
  }

  data = {
    ELASTIC_HOST_SYSTEM = var.elastic_host
    ELASTIC_PORT_SYSTEM = "9200"
    ELASTIC_USER_SYSTEM = "elastic"
    ELASTIC_PASS_SYSTEM = var.elastic_password
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

resource "kubernetes_secret_v1" "search_elastic" {
  count = var.enable_search ? 1 : 0

  metadata {
    name      = "search-elastic-secret"
    namespace = var.namespace
  }

  data = {
    ELASTIC_HOST_SYSTEM = var.elastic_host
    ELASTIC_PORT_SYSTEM = "9200"
    ELASTIC_USER_SYSTEM = "elastic"
    ELASTIC_PASS_SYSTEM = var.elastic_password
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

resource "kubernetes_secret_v1" "elastic_ca_cert" {
  count = (var.enable_search || var.enable_indexer) && var.enable_elastic_ca_cert ? 1 : 0

  metadata {
    name      = "elastic-ca-cert"
    namespace = var.namespace
  }

  data = {
    "ca.crt" = var.elastic_ca_cert
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}
moved {
  from = kubernetes_secret.storage_redis
  to   = kubernetes_secret_v1.storage_redis
}

moved {
  from = kubernetes_secret.search_redis
  to   = kubernetes_secret_v1.search_redis
}

moved {
  from = kubernetes_secret.dataset_redis
  to   = kubernetes_secret_v1.dataset_redis
}

moved {
  from = kubernetes_secret.schema_minio
  to   = kubernetes_secret_v1.schema_minio
}

moved {
  from = kubernetes_secret.minio_bootstrap
  to   = kubernetes_secret_v1.minio_bootstrap
}

moved {
  from = kubernetes_secret.file_minio
  to   = kubernetes_secret_v1.file_minio
}

moved {
  from = kubernetes_secret.indexer_elastic
  to   = kubernetes_secret_v1.indexer_elastic
}
