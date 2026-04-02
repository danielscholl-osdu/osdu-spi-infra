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

# Infrastructure variables for the CIMPL stack

variable "stack_id" {
  description = "Stack name suffix. Defaults to 'cimpl' producing namespaces platform-cimpl and osdu-cimpl."
  type        = string
  default     = "cimpl"
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group containing the cluster"
  type        = string
}

# Istio
variable "istio_revision" {
  description = "Istio revision label for sidecar injection (AKS Managed Istio)"
  type        = string
  default     = "asm-1-28"
}

# cert-manager
variable "acme_email" {
  description = "Email for Let's Encrypt certificate notifications"
  type        = string
}

variable "use_letsencrypt_production" {
  description = "Use Let's Encrypt production issuer (default: false = staging)"
  type        = bool
  default     = false
}

# Ingress / DNS
variable "ingress_prefix" {
  description = "Unique prefix for ingress hostnames (e.g., myenv-cimpl)"
  type        = string
  default     = ""
}

variable "dns_zone_name" {
  description = "Azure DNS zone name"
  type        = string
  default     = ""
}

variable "dns_zone_resource_group" {
  description = "Resource group containing the DNS zone"
  type        = string
  default     = ""
}

variable "dns_zone_subscription_id" {
  description = "Subscription ID for the DNS zone"
  type        = string
  default     = ""
}

variable "external_dns_client_id" {
  description = "Client ID for ExternalDNS managed identity"
  type        = string
  default     = ""
}

variable "tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
  default     = ""
}

# Gateway side-by-side
variable "spi_gateway_listeners" {
  description = "Additional Gateway listeners from the SPI stack to include in the shared Gateway spec"
  type        = list(any)
  default     = []
}

# Tags
variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default = {
    layer = "cimpl-stack"
  }
}
