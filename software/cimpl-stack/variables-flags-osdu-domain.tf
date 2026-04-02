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

# Feature flags — OSDU Domain Services

variable "enable_osdu_domain_services" {
  description = "Master switch for all OSDU domain services (requires core)"
  type        = bool
  default     = true
}

variable "enable_wellbore" {
  description = "Enable OSDU Wellbore service deployment"
  type        = bool
  default     = true
}

variable "enable_wellbore_worker" {
  description = "Enable OSDU Wellbore Worker service deployment"
  type        = bool
  default     = true
}

variable "enable_eds_dms" {
  description = "Enable OSDU EDS-DMS service deployment"
  type        = bool
  default     = true
}

variable "enable_oetp_server" {
  description = "Enable OSDU OETP Server service deployment"
  type        = bool
  default     = true
}

