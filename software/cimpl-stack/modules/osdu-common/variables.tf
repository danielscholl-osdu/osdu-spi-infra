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
  description = "OSDU Kubernetes namespace"
  type        = string
}

variable "istio_revision" {
  description = "Istio revision label for sidecar injection (AKS Managed Istio)"
  type        = string
  default     = "asm-1-28"
}

variable "platform_namespace" {
  description = "Platform Kubernetes namespace (for cross-namespace service references)"
  type        = string
  default     = "platform"
}

variable "osdu_domain" {
  description = "OSDU domain (e.g. prefix.dnszone)"
  type        = string
}

variable "cimpl_project" {
  description = "CIMPL project/group identifier"
  type        = string
}

variable "cimpl_tenant" {
  description = "CIMPL data partition ID"
  type        = string
}

variable "cimpl_subscriber_private_key_id" {
  description = "Subscriber private key identifier for OSDU services"
  type        = string
  sensitive   = true
}

variable "postgresql_host" {
  description = "PostgreSQL read-write service host"
  type        = string
}

variable "postgresql_username" {
  description = "PostgreSQL application database owner username"
  type        = string
}

variable "postgresql_password" {
  description = "PostgreSQL admin password"
  type        = string
  sensitive   = true
}

variable "keycloak_host" {
  description = "Keycloak service host"
  type        = string
}

variable "redis_password" {
  description = "Redis authentication password"
  type        = string
  sensitive   = true
}

variable "datafier_client_secret" {
  description = "Keycloak client secret for the datafier service account"
  type        = string
  sensitive   = true
}

variable "enable_partition" {
  description = "Enable OSDU Partition service secrets"
  type        = bool
  default     = true
}

variable "enable_entitlements" {
  description = "Enable OSDU Entitlements service secrets"
  type        = bool
  default     = true
}

variable "enable_legal" {
  description = "Enable OSDU Legal service secrets"
  type        = bool
  default     = true
}

variable "enable_schema" {
  description = "Enable OSDU Schema service secrets"
  type        = bool
  default     = true
}

variable "enable_storage" {
  description = "Enable OSDU Storage service secrets"
  type        = bool
  default     = true
}

variable "enable_file" {
  description = "Enable OSDU File service secrets"
  type        = bool
  default     = true
}

variable "enable_dataset" {
  description = "Enable OSDU Dataset service secrets"
  type        = bool
  default     = true
}

variable "enable_register" {
  description = "Enable OSDU Register service secrets"
  type        = bool
  default     = true
}

variable "enable_workflow" {
  description = "Enable OSDU Workflow service secrets"
  type        = bool
  default     = false
}

variable "enable_notification" {
  description = "Enable OSDU Notification service secrets"
  type        = bool
  default     = true
}

variable "enable_policy" {
  description = "Enable OSDU Policy service secrets"
  type        = bool
  default     = true
}

variable "enable_wellbore" {
  description = "Enable OSDU Wellbore service secrets"
  type        = bool
  default     = true
}

variable "enable_eds_dms" {
  description = "Enable OSDU EDS-DMS service secrets"
  type        = bool
  default     = true
}

variable "enable_oetp_server" {
  description = "Enable OSDU OETP Server service secrets"
  type        = bool
  default     = true
}

variable "minio_root_user" {
  description = "MinIO root username"
  type        = string
}

variable "minio_root_password" {
  description = "MinIO root password"
  type        = string
  sensitive   = true
}

variable "rabbitmq_username" {
  description = "RabbitMQ username"
  type        = string
}

variable "rabbitmq_password" {
  description = "RabbitMQ password"
  type        = string
  sensitive   = true
}

variable "elastic_password" {
  description = "Elasticsearch elastic user password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "elastic_host" {
  description = "Elasticsearch HTTP service host"
  type        = string
  default     = ""
}

variable "elastic_ca_cert" {
  description = "ECK self-signed CA certificate (PEM, base64-encoded)"
  type        = string
  default     = ""
}

variable "enable_elastic_ca_cert" {
  description = "Whether the elastic CA cert is available (avoids unknown-at-plan-time count)"
  type        = bool
  default     = false
}

variable "enable_search" {
  description = "Enable search service ES secret"
  type        = bool
  default     = false
}

variable "enable_indexer" {
  description = "Enable indexer service ES secret"
  type        = bool
  default     = false
}
