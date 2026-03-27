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

# Feature flags -- Platform namespace (infrastructure + middleware)
# Azure SPI variant: no Redis, RabbitMQ, MinIO, Keycloak, or full PostgreSQL flags

variable "enable_nodepool" {
  description = "Deploy shared Karpenter NodePool for stateful workloads"
  type        = bool
  default     = true
}

variable "enable_public_ingress" {
  description = "Enable public ingress"
  type        = bool
  default     = true
}

variable "enable_external_dns" {
  description = "Enable ExternalDNS"
  type        = bool
  default     = false
}

variable "enable_cert_manager" {
  description = "Enable cert-manager TLS certificates"
  type        = bool
  default     = true
}

variable "enable_gateway" {
  description = "Enable Gateway API resources for this stack"
  type        = bool
  default     = true
}

variable "enable_elasticsearch" {
  description = "Enable Elasticsearch + Kibana deployment"
  type        = bool
  default     = true
}

variable "enable_elastic_bootstrap" {
  description = "Enable Elastic Bootstrap job deployment"
  type        = bool
  default     = true
}

variable "enable_airflow" {
  description = "Enable Airflow deployment (includes lightweight in-cluster PostgreSQL)"
  type        = bool
  default     = true
}

# -- Ingress flags ------------------------------------------------------------

variable "enable_osdu_api_ingress" {
  description = "Expose OSDU APIs externally via Gateway API HTTPRoute"
  type        = bool
  default     = true
}

variable "enable_airflow_ingress" {
  description = "Expose Airflow UI externally via Gateway API HTTPRoute"
  type        = bool
  default     = true
}

variable "enable_kibana_ingress" {
  description = "Expose Kibana UI externally via Gateway API HTTPRoute"
  type        = bool
  default     = true
}
