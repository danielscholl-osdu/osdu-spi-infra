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

# Feature flags -- OSDU Core Services

variable "enable_osdu_core_services" {
  description = "Master switch for all OSDU core services (partition through workflow)"
  type        = bool
  default     = true
}

variable "enable_common" {
  description = "Enable OSDU common namespace resources"
  type        = bool
  default     = true
}

variable "enable_partition" {
  description = "Enable OSDU Partition service deployment"
  type        = bool
  default     = true
}

variable "enable_entitlements" {
  description = "Enable OSDU Entitlements service deployment"
  type        = bool
  default     = true
}

variable "enable_legal" {
  description = "Enable OSDU Legal service deployment"
  type        = bool
  default     = true
}

variable "enable_schema" {
  description = "Enable OSDU Schema service deployment"
  type        = bool
  default     = true
}

variable "enable_storage" {
  description = "Enable OSDU Storage service deployment"
  type        = bool
  default     = true
}

variable "enable_search" {
  description = "Enable OSDU Search service deployment"
  type        = bool
  default     = true
}

variable "enable_indexer" {
  description = "Enable OSDU Indexer service deployment"
  type        = bool
  default     = true
}

variable "enable_indexer_queue" {
  description = "Enable OSDU Indexer Queue service deployment"
  type        = bool
  default     = true
}

variable "enable_file" {
  description = "Enable OSDU File service deployment"
  type        = bool
  default     = true
}

variable "enable_workflow" {
  description = "Enable OSDU Workflow service deployment"
  type        = bool
  default     = true
}

variable "enable_notification" {
  description = "Enable OSDU Notification service deployment"
  type        = bool
  default     = true
}

variable "enable_dataset" {
  description = "Enable OSDU Dataset service deployment"
  type        = bool
  default     = true
}

variable "enable_register" {
  description = "Enable OSDU Register service deployment"
  type        = bool
  default     = true
}

variable "enable_policy" {
  description = "Enable OSDU Policy service deployment"
  type        = bool
  default     = true
}

variable "enable_secret" {
  description = "Enable OSDU Secret service deployment (disabled: upstream image has Reactor Netty classpath conflict)"
  type        = bool
  default     = false
}
