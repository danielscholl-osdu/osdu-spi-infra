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

# AKS Automatic Cluster using Azure Verified Module
module "aks" {
  source  = "Azure/avm-res-containerservice-managedcluster/azurerm"
  version = "0.4.3"

  name      = local.cluster_name
  location  = var.location
  parent_id = azurerm_resource_group.main.id

  # Kubernetes Version (1.33 - default, KubernetesOfficial support)
  kubernetes_version = "1.33"

  # AKS Automatic SKU
  sku = {
    name = "Automatic"
    tier = "Standard"
  }

  # Node Auto-Provisioning (AKS Automatic feature)
  node_provisioning_profile = {
    mode = "Auto"
  }

  # Auto-upgrade
  auto_upgrade_profile = {
    upgrade_channel         = "stable"
    node_os_upgrade_channel = "NodeImage"
  }

  # Network Configuration (Required for modern AKS)
  network_profile = {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_dataplane   = "cilium"
    outbound_type       = "managedNATGateway"
    service_cidr        = "10.0.0.0/16"
    dns_service_ip      = "10.0.0.10"
  }

  # AAD Integration & RBAC
  aad_profile = {
    managed           = true
    enable_azure_rbac = true
  }

  # Disable local accounts (require Azure AD)
  disable_local_accounts = true

  # OIDC Issuer for Workload Identity
  oidc_issuer_profile = {
    enabled = true
  }

  # Azure Policy
  addon_profile_azure_policy = {
    enabled = true
  }

  # Key Vault Secrets Provider
  addon_profile_key_vault_secrets_provider = {
    enabled = true
    config = {
      enable_secret_rotation = true
    }
  }

  # Storage CSI Drivers
  storage_profile = {
    disk_driver_enabled         = true
    file_driver_enabled         = true
    blob_driver_enabled         = true
    snapshot_controller_enabled = true
  }

  # Istio Service Mesh (AKS Managed)
  service_mesh_profile = {
    mode = "Istio"
    istio = {
      revisions = ["asm-1-28"]
      components = {
        ingress_gateways = [
          {
            enabled = true
            mode    = "External"
          }
        ]
      }
    }
  }

  # Monitoring: Managed Prometheus (metrics)
  azure_monitor_profile = {
    metrics = {
      enabled = true
    }
  }

  # Monitoring: Container Insights (logs)
  addon_profile_oms_agent = {
    enabled = true
    config = {
      log_analytics_workspace_resource_id = azurerm_log_analytics_workspace.aks.id
      use_aad_auth                        = true
    }
  }

  # Monitoring: Wire up Prometheus data collection rules
  onboard_monitoring      = true
  prometheus_workspace_id = azurerm_monitor_workspace.prometheus.id

  # Managed Identities
  managed_identities = {
    system_assigned = true
  }

  # Default Node Pool (System)
  default_agent_pool = {
    name                         = "system"
    vm_size                      = var.system_pool_vm_size
    count_of                     = 2
    os_sku                       = "AzureLinux"
    availability_zones           = var.system_pool_availability_zones
    only_critical_addons_enabled = true
  }

  tags = local.common_tags
}

# Elevated access bootstrap (AKS RBAC role assignments and policy exemptions)
# is managed in infra-access/ so Contributor-scoped provisioning can succeed.
