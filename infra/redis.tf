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

# Azure Cache for Redis for OSDU service caching.
# Replaces in-cluster Redis used by cimpl-azure-provisioning.

resource "azurerm_redis_cache" "main" {
  name                = "redis-${local.cluster_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  capacity            = var.redis_capacity
  family              = var.redis_sku_name == "Premium" ? "P" : "C"
  sku_name            = var.redis_sku_name
  non_ssl_port_enabled = true
  minimum_tls_version = "1.2"

  redis_configuration {}

  tags = local.common_tags
}
