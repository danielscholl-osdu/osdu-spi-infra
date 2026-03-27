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

variable "namespace" {
  description = "Kubernetes namespace for ExternalDNS"
  type        = string
}

variable "cluster_name" {
  description = "Name of the AKS cluster (used as txtOwnerId)"
  type        = string
}

variable "dns_zone_name" {
  description = "Azure DNS zone name"
  type        = string
}

variable "dns_zone_resource_group" {
  description = "Resource group containing the DNS zone"
  type        = string
}

variable "dns_zone_subscription_id" {
  description = "Subscription ID containing the DNS zone"
  type        = string
}

variable "tenant_id" {
  description = "Azure tenant ID"
  type        = string
}

variable "external_dns_client_id" {
  description = "Client ID of the ExternalDNS managed identity"
  type        = string
}
