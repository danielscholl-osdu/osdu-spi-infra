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

# Variables for Azure PaaS resources required by OSDU Azure SPI.

variable "data_partitions" {
  description = "List of OSDU data partition names. Each partition gets its own Storage, CosmosDB, and Service Bus resources."
  type        = list(string)
  default     = ["opendes"]

  validation {
    condition     = length(var.data_partitions) > 0
    error_message = "At least one data partition must be specified."
  }
}

# CosmosDB configuration
variable "cosmosdb_max_throughput" {
  description = "CosmosDB autoscale max throughput (RU/s) per database"
  type        = number
  default     = 4000
}

variable "cosmosdb_consistency_level" {
  description = "CosmosDB consistency level"
  type        = string
  default     = "Session"
}

# Azure Service Bus configuration
variable "servicebus_sku" {
  description = "Service Bus SKU (Standard or Premium)"
  type        = string
  default     = "Standard"
}

# Azure Container Registry configuration
variable "acr_sku" {
  description = "Container Registry SKU"
  type        = string
  default     = "Basic"
}
