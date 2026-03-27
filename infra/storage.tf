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

# Azure Storage Accounts for OSDU.
# - Common/system storage: shared across partitions (Airflow DAGs, CRS data, etc.)
# - Partition storage: per-partition data (legal configs, WKS mappings, file areas)

# ──────────────────────────────────────────────
# Common/System Storage Account
# ──────────────────────────────────────────────

resource "azurerm_storage_account" "common" {
  name                            = substr("stcom${replace(local.cluster_name, "-", "")}${random_string.suffix.result}", 0, 24)
  resource_group_name             = azurerm_resource_group.main.name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  allow_nested_items_to_be_public = false

  tags = local.common_tags
}

resource "azurerm_storage_container" "common" {
  for_each              = toset(local.common_storage_containers)
  name                  = each.key
  storage_account_id    = azurerm_storage_account.common.id
  container_access_type = "private"
}

resource "azurerm_storage_table" "partition_info" {
  name                 = "partitionInfo"
  storage_account_name = azurerm_storage_account.common.name
}

# ──────────────────────────────────────────────
# Per-Partition Storage Accounts
# ──────────────────────────────────────────────

resource "azurerm_storage_account" "partition" {
  for_each                        = local.partitions
  name                            = substr("st${replace(each.key, "-", "")}${random_string.suffix.result}", 0, 24)
  resource_group_name             = azurerm_resource_group.main.name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  allow_nested_items_to_be_public = false

  tags = merge(local.common_tags, {
    partition = each.key
  })
}

resource "azurerm_storage_container" "partition" {
  for_each = merge([
    for p in var.data_partitions : {
      for c in local.partition_storage_containers :
      "${p}/${c}" => {
        partition = p
        container = c
      }
    }
  ]...)

  name                  = each.value.container
  storage_account_id    = azurerm_storage_account.partition[each.value.partition].id
  container_access_type = "private"
}
