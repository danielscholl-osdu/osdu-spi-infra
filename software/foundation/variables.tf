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

# Variables for foundation layer

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

# cert-manager configuration
variable "acme_email" {
  description = "Email for Let's Encrypt certificate notifications"
  type        = string
}

variable "use_letsencrypt_production" {
  description = "Use Let's Encrypt production issuer (default: false = staging)"
  type        = bool
  default     = false
}

# Feature flags
variable "enable_cert_manager" {
  description = "Enable cert-manager deployment"
  type        = bool
  default     = true
}

variable "enable_elasticsearch" {
  description = "Enable ECK operator deployment"
  type        = bool
  default     = true
}

variable "enable_gateway" {
  description = "Enable Gateway API resources"
  type        = bool
  default     = true
}

variable "enable_public_ingress" {
  description = "Expose Istio ingress gateway via public LoadBalancer (false = internal-only)"
  type        = bool
  default     = true
}

variable "enable_external_dns" {
  description = "Enable ExternalDNS for automatic DNS record management"
  type        = bool
  default     = false
}

# Ingress configuration
variable "ingress_prefix" {
  description = "Unique prefix for ingress hostnames"
  type        = string
  default     = ""
}

# DNS configuration
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
  description = "Subscription ID containing the DNS zone"
  type        = string
  default     = ""
}

variable "external_dns_client_id" {
  description = "Client ID of the ExternalDNS managed identity"
  type        = string
  default     = ""
}

variable "tenant_id" {
  description = "Azure tenant ID"
  type        = string
  default     = ""
}
