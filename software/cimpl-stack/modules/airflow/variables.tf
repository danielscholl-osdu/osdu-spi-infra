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
  description = "Kubernetes namespace"
  type        = string
}

variable "postgresql_host" {
  description = "PostgreSQL read-write service host"
  type        = string
}

variable "airflow_db_password" {
  description = "Airflow database password"
  type        = string
  sensitive   = true
}

variable "osdu_namespace" {
  description = "Kubernetes namespace for OSDU services"
  type        = string
  default     = "osdu"
}

# OSDU package versions — controls DAG source tag and pip packages.
# DAG archive is fetched from ingestion-dags at tag v<osdu_airflow_version>.

variable "osdu_airflow_version" {
  description = "Version of osdu-airflow package and ingestion DAGs source tag"
  type        = string
  default     = "0.29.2"
}

variable "osdu_ingestion_version" {
  description = "Version of osdu-ingestion package"
  type        = string
  default     = "0.29.0"
}

variable "osdu_api_version" {
  description = "Version of osdu-api package"
  type        = string
  default     = "1.1.0"
}

variable "osdu_dags_branch" {
  description = "Git ref for DAG source repos (e.g., 'master' for latest, 'v0.27.0' for pinned)"
  type        = string
  default     = "master"
}

variable "keycloak_host" {
  description = "Keycloak service host (e.g., keycloak.platform.svc.cluster.local)"
  type        = string
}

variable "datafier_client_secret" {
  description = "Keycloak client secret for the datafier service account"
  type        = string
  sensitive   = true
}

variable "nodepool_name" {
  description = "Name of the Karpenter NodePool for scheduling"
  type        = string
  default     = "platform"
}
