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

# Workload Identity for OSDU services.
# A single user-assigned managed identity is shared by all OSDU services.
# Federated credentials link each namespace's service account to this identity.

# ──────────────────────────────────────────────
# OSDU Service Managed Identity
# ──────────────────────────────────────────────

resource "azurerm_user_assigned_identity" "osdu" {
  name                = "${local.cluster_name}-osdu-identity"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  tags                = local.common_tags
}

# ──────────────────────────────────────────────
# Federated Identity Credentials (per namespace)
# ──────────────────────────────────────────────

resource "azurerm_federated_identity_credential" "osdu" {
  for_each  = local.federated_credentials
  name      = each.key
  parent_id = azurerm_user_assigned_identity.osdu.id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = module.aks.oidc_issuer_profile_issuer_url
  subject   = each.value
}

# ──────────────────────────────────────────────
# Role Assignments (Contributor-safe)
# Elevated roles (CosmosDB data-plane) are in infra-access/.
# ──────────────────────────────────────────────

# Key Vault Secrets User
resource "azurerm_role_assignment" "osdu_kv_secrets" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.osdu.principal_id
}

# Storage Blob Data Contributor on common storage
resource "azurerm_role_assignment" "osdu_common_blob" {
  scope                = azurerm_storage_account.common.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.osdu.principal_id
}

# Storage Table Data Contributor on common storage
resource "azurerm_role_assignment" "osdu_common_table" {
  scope                = azurerm_storage_account.common.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_user_assigned_identity.osdu.principal_id
}

# Storage Blob Data Contributor on each partition storage
resource "azurerm_role_assignment" "osdu_partition_blob" {
  for_each             = local.partitions
  scope                = azurerm_storage_account.partition[each.key].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.osdu.principal_id
}

# Service Bus Data Sender on each partition namespace
resource "azurerm_role_assignment" "osdu_sb_sender" {
  for_each             = local.partitions
  scope                = azurerm_servicebus_namespace.partition[each.key].id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = azurerm_user_assigned_identity.osdu.principal_id
}

# Service Bus Data Receiver on each partition namespace
resource "azurerm_role_assignment" "osdu_sb_receiver" {
  for_each             = local.partitions
  scope                = azurerm_servicebus_namespace.partition[each.key].id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = azurerm_user_assigned_identity.osdu.principal_id
}

# ACR Pull
resource "azurerm_role_assignment" "osdu_acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.osdu.principal_id
}
