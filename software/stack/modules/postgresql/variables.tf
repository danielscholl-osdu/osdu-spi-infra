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

# Variables for the lightweight PostgreSQL module (Airflow metadata only)

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "db_password" {
  description = "PostgreSQL password for the airflow user"
  type        = string
  sensitive   = true
}

variable "storage_size" {
  description = "PVC storage size for PostgreSQL data"
  type        = string
  default     = "8Gi"
}
