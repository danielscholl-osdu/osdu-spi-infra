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

# Credential variables (all sensitive)

variable "postgresql_password" {
  description = "PostgreSQL admin password"
  type        = string
  sensitive   = true
}

variable "postgresql_username" {
  description = "PostgreSQL application database owner username"
  type        = string
  default     = "osdu"
}

variable "keycloak_db_password" {
  description = "Keycloak database password"
  type        = string
  sensitive   = true
}

variable "keycloak_admin_password" {
  description = "Keycloak admin password (auto-generated if unset)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "datafier_client_secret" {
  description = "Keycloak client secret for the datafier service account"
  type        = string
  sensitive   = true
}

variable "airflow_db_password" {
  description = "Airflow database password"
  type        = string
  sensitive   = true
}

variable "redis_password" {
  description = "Redis authentication password"
  type        = string
  sensitive   = true
}

variable "rabbitmq_username" {
  description = "RabbitMQ admin username"
  type        = string
  default     = "rabbitmq"
}

variable "rabbitmq_password" {
  description = "RabbitMQ admin password"
  type        = string
  sensitive   = true
}

variable "rabbitmq_erlang_cookie" {
  description = "RabbitMQ Erlang cookie for clustering"
  type        = string
  sensitive   = true
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
