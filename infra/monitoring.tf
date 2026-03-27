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

# Azure monitoring resources for the cluster.
# Grafana access bootstrap is managed separately in infra-access/.

resource "azurerm_monitor_workspace" "prometheus" {
  name                = "${local.cluster_name}-prometheus"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  tags                = local.common_tags
}

resource "azurerm_dashboard_grafana" "main" {
  count                 = var.enable_grafana_workspace ? 1 : 0
  name                  = local.grafana_name
  resource_group_name   = azurerm_resource_group.main.name
  location              = var.location
  grafana_major_version = "11"
  sku                   = "Standard"

  identity {
    type = "SystemAssigned"
  }

  azure_monitor_workspace_integrations {
    resource_id = azurerm_monitor_workspace.prometheus.id
  }

  tags = local.common_tags
}
