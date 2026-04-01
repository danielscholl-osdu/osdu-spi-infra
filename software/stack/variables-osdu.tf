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

# OSDU configuration variables (Azure SPI variant)

variable "osdu_image_branch" {
  description = "Branch suffix appended to OSDU image repository names (e.g. 'master', 'release-0-27')"
  type        = string
  default     = "master"
}

variable "osdu_image_overrides" {
  description = "Per-service image overrides (service key -> {repository, tag})"
  type = map(object({
    repository = string
    tag        = string
  }))
  default = {}
}

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
