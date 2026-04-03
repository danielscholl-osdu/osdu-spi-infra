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

# Keycloak/OpenID and KMS identity secrets

resource "kubernetes_secret_v1" "datafier" {
  count = var.enable_entitlements ? 1 : 0

  metadata {
    name      = "datafier-secret"
    namespace = var.namespace
  }

  data = {
    OPENID_PROVIDER_CLIENT_ID     = "datafier"
    OPENID_PROVIDER_CLIENT_SECRET = var.datafier_client_secret
    OPENID_PROVIDER_URL           = "http://${var.keycloak_host}/realms/osdu"
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

resource "kubernetes_secret_v1" "storage_keycloak" {
  count = var.enable_storage ? 1 : 0

  metadata {
    name      = "storage-keycloak-secret"
    namespace = var.namespace
  }

  data = {
    OPENID_PROVIDER_CLIENT_ID     = "datafier"
    OPENID_PROVIDER_CLIENT_SECRET = var.datafier_client_secret
    OPENID_PROVIDER_URL           = "http://${var.keycloak_host}/realms/osdu"
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

resource "kubernetes_secret_v1" "file_keycloak" {
  count = var.enable_file ? 1 : 0

  metadata {
    name      = "file-keycloak-secret"
    namespace = var.namespace
  }

  data = {
    OPENID_PROVIDER_CLIENT_ID     = "datafier"
    OPENID_PROVIDER_CLIENT_SECRET = var.datafier_client_secret
    OPENID_PROVIDER_URL           = "http://${var.keycloak_host}/realms/osdu"
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

resource "kubernetes_secret_v1" "notification_keycloak" {
  count = var.enable_notification ? 1 : 0

  metadata {
    name      = "notification-keycloak-secret"
    namespace = var.namespace
  }

  data = {
    OPENID_PROVIDER_CLIENT_ID     = "datafier"
    OPENID_PROVIDER_CLIENT_SECRET = var.datafier_client_secret
    OPENID_PROVIDER_URL           = "http://${var.keycloak_host}/realms/osdu"
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

resource "kubernetes_secret_v1" "register_keycloak" {
  count = var.enable_register ? 1 : 0

  metadata {
    name      = "register-keycloak-secret"
    namespace = var.namespace
  }

  data = {
    OPENID_PROVIDER_CLIENT_ID     = "datafier"
    OPENID_PROVIDER_CLIENT_SECRET = var.datafier_client_secret
    OPENID_PROVIDER_URL           = "http://${var.keycloak_host}/realms/osdu"
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

resource "kubernetes_secret_v1" "register_kms" {
  count = var.enable_register ? 1 : 0

  metadata {
    name      = "register-kms-secret"
    namespace = var.namespace
  }

  data = {
    ENCRYPTION_KEY = var.cimpl_subscriber_private_key_id
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

resource "kubernetes_secret_v1" "workflow_keycloak" {
  count = var.enable_workflow ? 1 : 0

  metadata {
    name      = "workflow-keycloak-secret"
    namespace = var.namespace
  }

  data = {
    OPENID_PROVIDER_CLIENT_ID     = "datafier"
    OPENID_PROVIDER_CLIENT_SECRET = var.datafier_client_secret
    OPENID_PROVIDER_URL           = "http://${var.keycloak_host}/realms/osdu"
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

resource "kubernetes_secret_v1" "indexer_keycloak" {
  count = var.enable_indexer ? 1 : 0

  metadata {
    name      = "indexer-keycloak-secret"
    namespace = var.namespace
  }

  data = {
    OPENID_PROVIDER_CLIENT_ID     = "datafier"
    OPENID_PROVIDER_CLIENT_SECRET = var.datafier_client_secret
    OPENID_PROVIDER_URL           = "http://${var.keycloak_host}/realms/osdu"
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

resource "kubernetes_secret_v1" "wellbore_keycloak" {
  count = var.enable_wellbore ? 1 : 0

  metadata {
    name      = "wellbore-keycloak-secret"
    namespace = var.namespace
  }

  data = {
    OPENID_PROVIDER_CLIENT_ID     = "datafier"
    OPENID_PROVIDER_CLIENT_SECRET = var.datafier_client_secret
    OPENID_PROVIDER_URL           = "http://${var.keycloak_host}/realms/osdu"
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

resource "kubernetes_secret_v1" "eds_keycloak" {
  count = var.enable_eds_dms ? 1 : 0

  metadata {
    name      = "eds-keycloak-secret"
    namespace = var.namespace
  }

  data = {
    OPENID_PROVIDER_CLIENT_ID     = "datafier"
    OPENID_PROVIDER_CLIENT_SECRET = var.datafier_client_secret
    OPENID_PROVIDER_URL           = "http://${var.keycloak_host}/realms/osdu"
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}

resource "kubernetes_secret_v1" "oetp_server_secret" {
  count = var.enable_oetp_server ? 1 : 0

  metadata {
    name      = "oetp-server-secret"
    namespace = var.namespace
  }

  data = {
    CIMPL_CLIENT_ID                 = "datafier"
    CIMPL_CLIENT_SECRET             = var.datafier_client_secret
    CIMPL_TOKEN_URI                 = "http://${var.keycloak_host}/realms/osdu/protocol/openid-connect/token"
    CIMPL_SUBSCRIBER_PRIVATE_KEY_ID = var.cimpl_subscriber_private_key_id
  }

  depends_on = [kubernetes_namespace_v1.osdu]
}
moved {
  from = kubernetes_secret.storage_keycloak
  to   = kubernetes_secret_v1.storage_keycloak
}

moved {
  from = kubernetes_secret.notification_keycloak
  to   = kubernetes_secret_v1.notification_keycloak
}

moved {
  from = kubernetes_secret.register_kms
  to   = kubernetes_secret_v1.register_kms
}
