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

# Populate Key Vault with secrets consumed by OSDU services.
# Global secrets are shared; partition secrets are per data partition.

# ──────────────────────────────────────────────
# Global Secrets
# ──────────────────────────────────────────────

locals {
  global_secrets = {
    "tenant-id"            = data.azurerm_client_config.current.tenant_id
    "subscription-id"      = data.azurerm_client_config.current.subscription_id
    "osdu-identity-id"     = azurerm_user_assigned_identity.osdu.client_id
    "keyvault-uri"         = azurerm_key_vault.main.vault_uri
    "system-storage"       = azurerm_storage_account.common.name
    "tbl-storage"          = azurerm_storage_account.common.name
    "tbl-storage-key"      = azurerm_storage_account.common.primary_access_key
    "tbl-storage-endpoint" = azurerm_storage_account.common.primary_table_endpoint
    "app-dev-sp-password"  = "DISABLED"
    "app-dev-sp-username"  = azurerm_user_assigned_identity.osdu.client_id
    "app-dev-sp-tenant-id" = data.azurerm_client_config.current.tenant_id
    "app-dev-sp-id"        = azurerm_user_assigned_identity.osdu.client_id
    "container-registry"   = azurerm_container_registry.main.name
    "insights-key"         = azurerm_application_insights.main.instrumentation_key
    "insights-connection"  = azurerm_application_insights.main.connection_string
    "graph-db-endpoint"    = azurerm_cosmosdb_account.graph.endpoint
    "graph-db-primary-key" = azurerm_cosmosdb_account.graph.primary_key
    "graph-db-connection"  = azurerm_cosmosdb_account.graph.primary_sql_connection_string
  }
}

# Grant the deployer (current identity) Key Vault Secrets Officer so we can write secrets.
resource "azurerm_role_assignment" "deployer_kv_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_key_vault_secret" "global" {
  for_each     = local.global_secrets
  name         = each.key
  value        = each.value
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.deployer_kv_officer]
}

# ──────────────────────────────────────────────
# Per-Partition Secrets
# ──────────────────────────────────────────────

locals {
  partition_secrets = merge([
    for p in var.data_partitions : {
      "${p}-storage"               = azurerm_storage_account.partition[p].name
      "${p}-storage-blob-endpoint" = azurerm_storage_account.partition[p].primary_blob_endpoint
      "${p}-cosmos-endpoint"       = azurerm_cosmosdb_account.partition[p].endpoint
      "${p}-cosmos-primary-key"    = azurerm_cosmosdb_account.partition[p].primary_key
      "${p}-cosmos-connection"     = azurerm_cosmosdb_account.partition[p].primary_sql_connection_string
      "${p}-sb-connection"         = azurerm_servicebus_namespace.partition[p].default_primary_connection_string
      "${p}-sb-namespace"          = azurerm_servicebus_namespace.partition[p].name
    }
  ]...)
}

resource "azurerm_key_vault_secret" "partition" {
  for_each     = local.partition_secrets
  name         = each.key
  value        = each.value
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.deployer_kv_officer]
}
