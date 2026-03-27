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

# Azure Service Bus for OSDU event-driven messaging.
# Each partition gets its own namespace with the standard set of OSDU topics.

# ──────────────────────────────────────────────
# Per-Partition Service Bus Namespaces
# ──────────────────────────────────────────────

resource "azurerm_servicebus_namespace" "partition" {
  for_each            = local.partitions
  name                = substr("sb-${each.key}-${local.cluster_name}-${random_string.suffix.result}", 0, 50)
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  sku                 = var.servicebus_sku

  tags = merge(local.common_tags, {
    partition = each.key
  })
}

# ──────────────────────────────────────────────
# Topics (flattened partition x topic)
# ──────────────────────────────────────────────

resource "azurerm_servicebus_topic" "partition" {
  for_each            = local.partition_sb_topics
  name                = each.value.topic
  namespace_id        = azurerm_servicebus_namespace.partition[each.value.partition].id
  max_size_in_megabytes = each.value.max_size
}

# ──────────────────────────────────────────────
# Subscriptions (flattened partition x topic x subscription)
# ──────────────────────────────────────────────

resource "azurerm_servicebus_subscription" "partition" {
  for_each           = local.partition_sb_subscriptions
  name               = each.value.subscription
  topic_id           = azurerm_servicebus_topic.partition["${each.value.partition}/${each.value.topic}"].id
  max_delivery_count = each.value.max_delivery
  lock_duration      = each.value.lock_duration
}
