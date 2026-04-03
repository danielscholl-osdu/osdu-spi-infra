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

# Variables for the gateway module (Azure SPI variant -- no Keycloak)

variable "namespace" {
  description = "Kubernetes namespace (platform namespace for certs and middleware services)"
  type        = string
}

variable "osdu_namespace" {
  description = "Kubernetes namespace for OSDU services"
  type        = string
  default     = "osdu"
}

variable "stack_label" {
  description = "Stack label for resource naming"
  type        = string
}

variable "kibana_hostname" {
  description = "External hostname for Kibana"
  type        = string
}

variable "osdu_hostname" {
  description = "External hostname for OSDU API"
  type        = string
  default     = ""
}

variable "airflow_hostname" {
  description = "External hostname for Airflow UI"
  type        = string
  default     = ""
}

variable "active_cluster_issuer" {
  description = "ClusterIssuer name for TLS certificates"
  type        = string
}

variable "enable_cert_manager" {
  description = "Enable cert-manager TLS certificates"
  type        = bool
  default     = true
}

variable "enable_osdu_api" {
  description = "Enable OSDU API external routing"
  type        = bool
  default     = false
}

variable "enable_airflow" {
  description = "Enable Airflow external routing"
  type        = bool
  default     = false
}

variable "osdu_api_routes" {
  description = "List of OSDU API routes to create"
  type = list(object({
    path_prefix  = string
    service_name = string
  }))
  default = []
}

variable "additional_listeners" {
  description = "Additional Gateway listeners from other stacks (e.g., CIMPL) to include in the shared Gateway spec"
  type        = list(any)
  default     = []
}
