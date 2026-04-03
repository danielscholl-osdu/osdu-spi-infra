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
# Azure SPI variant -- only PostgreSQL passwords needed (PaaS handles the rest)

variable "redis_password" {
  description = "In-cluster Redis authentication password"
  type        = string
  sensitive   = true
}

variable "postgresql_password" {
  description = "PostgreSQL superuser password (CNPG cluster for Airflow)"
  type        = string
  sensitive   = true
}

variable "airflow_db_password" {
  description = "Airflow database user password"
  type        = string
  sensitive   = true
}
