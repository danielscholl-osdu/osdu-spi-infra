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

# Variables for infrastructure layer (Layer 1)
# This layer provisions the AKS cluster and Azure PaaS resources.

variable "environment_name" {
  description = "The name of the azd environment (used for resource uniqueness)"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus2"
}

variable "contact_email" {
  description = "Contact email for resource tagging (owner identification)"
  type        = string
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

# DNS zone configuration for ExternalDNS and ingress hostnames.
variable "dns_zone_name" {
  description = "Azure DNS zone name for ExternalDNS"
  type        = string
  default     = ""
}

variable "dns_zone_resource_group" {
  description = "Resource group containing the DNS zone"
  type        = string
  default     = ""
}

variable "dns_zone_subscription_id" {
  description = "Subscription ID containing the DNS zone (cross-subscription support)"
  type        = string
  default     = ""
}

variable "enable_grafana_workspace" {
  description = "Create the Azure Managed Grafana workspace. Access bootstrap happens separately in infra-access/."
  type        = bool
  default     = true
}

variable "enable_external_dns_identity" {
  description = "Create the ExternalDNS workload identity. Defaults to true when all dns_zone_* variables are set."
  type        = bool
  default     = null
}

# System node pool configuration
variable "system_pool_vm_size" {
  description = "VM size for the AKS system node pool"
  type        = string
  default     = "Standard_D4lds_v5"
}

variable "system_pool_availability_zones" {
  description = "Availability zones for the AKS system node pool (reduce to avoid capacity issues)"
  type        = list(string)
  default     = ["1", "2", "3"]

  validation {
    condition     = length(var.system_pool_availability_zones) > 0
    error_message = "system_pool_availability_zones must specify at least one availability zone."
  }
}
