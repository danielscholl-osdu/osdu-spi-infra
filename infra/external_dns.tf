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

# ExternalDNS workload identity resources.
# DNS zone role assignment bootstrap is managed separately in infra-access/.

locals {
  # Preserve backward compatibility: when enable_external_dns_identity is not explicitly set,
  # fall back to the original implicit trigger (all dns_zone_* variables configured).
  enable_external_dns_identity = coalesce(
    var.enable_external_dns_identity,
    var.dns_zone_name != "" && var.dns_zone_subscription_id != "" && var.dns_zone_resource_group != ""
  )
}

resource "azurerm_user_assigned_identity" "external_dns" {
  count               = local.enable_external_dns_identity ? 1 : 0
  name                = "${local.cluster_name}-external-dns"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  tags                = local.common_tags
}

resource "azurerm_federated_identity_credential" "external_dns" {
  count                     = local.enable_external_dns_identity ? 1 : 0
  name                      = "external-dns"
  user_assigned_identity_id = azurerm_user_assigned_identity.external_dns[0].id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = module.aks.oidc_issuer_profile_issuer_url
  subject                   = "system:serviceaccount:foundation:external-dns"
}
