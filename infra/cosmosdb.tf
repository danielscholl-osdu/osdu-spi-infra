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

# Azure CosmosDB for OSDU data persistence.
# - Gremlin API account: Entitlements graph (shared, single instance)
# - SQL API accounts: per-partition operational databases (osdu-db, osdu-system-db)

# ──────────────────────────────────────────────
# Gremlin API Account (Entitlements Graph)
# ──────────────────────────────────────────────

resource "azurerm_cosmosdb_account" "graph" {
  name                = substr("cosmos-graph-${local.cluster_name}-${random_string.suffix.result}", 0, 44)
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  capabilities {
    name = "EnableGremlin"
  }

  consistency_policy {
    consistency_level = var.cosmosdb_consistency_level
  }

  geo_location {
    location          = var.location
    failover_priority = 0
  }

  backup {
    type = "Continuous"
    tier = "Continuous30Days"
  }

  tags = local.common_tags
}

resource "azurerm_cosmosdb_gremlin_database" "entitlements" {
  name                = "osdu-graph"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.graph.name

  autoscale_settings {
    max_throughput = 2000
  }
}

resource "azurerm_cosmosdb_gremlin_graph" "entitlements" {
  name                = "Entitlements"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.graph.name
  database_name       = azurerm_cosmosdb_gremlin_database.entitlements.name
  partition_key_path  = "/dataPartitionId"

  index_policy {
    automatic      = true
    indexing_mode  = "consistent"
    included_paths = ["/*"]
  }
}

# ──────────────────────────────────────────────
# SQL API Accounts (Per-Partition)
# ──────────────────────────────────────────────

resource "azurerm_cosmosdb_account" "partition" {
  for_each            = local.partitions
  name                = substr("cosmos-${each.key}-${random_string.suffix.result}", 0, 44)
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  consistency_policy {
    consistency_level = var.cosmosdb_consistency_level
  }

  geo_location {
    location          = var.location
    failover_priority = 0
  }

  backup {
    type = "Continuous"
    tier = "Continuous30Days"
  }

  tags = merge(local.common_tags, {
    partition = each.key
  })
}

# ──────────────────────────────────────────────
# Partition Database (osdu-db) + Containers
# ──────────────────────────────────────────────

resource "azurerm_cosmosdb_sql_database" "partition_db" {
  for_each            = local.partitions
  name                = "osdu-db"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.partition[each.key].name

  autoscale_settings {
    max_throughput = var.cosmosdb_max_throughput
  }
}

resource "azurerm_cosmosdb_sql_container" "partition_container" {
  for_each              = local.partition_db_containers
  name                  = each.value.container
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.partition[each.value.partition].name
  database_name         = azurerm_cosmosdb_sql_database.partition_db[each.value.partition].name
  partition_key_paths   = [each.value.partition_key]
  partition_key_version = 2
}

# ──────────────────────────────────────────────
# System Database (osdu-system-db) - Primary Partition Only
# ──────────────────────────────────────────────

resource "azurerm_cosmosdb_sql_database" "system_db" {
  name                = "osdu-system-db"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.partition[local.primary_partition].name

  autoscale_settings {
    max_throughput = var.cosmosdb_max_throughput
  }
}

resource "azurerm_cosmosdb_sql_container" "system_container" {
  for_each              = local.system_db_containers
  name                  = each.value.container
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.partition[each.value.partition].name
  database_name         = azurerm_cosmosdb_sql_database.system_db.name
  partition_key_paths   = [each.value.partition_key]
  partition_key_version = 2
}
