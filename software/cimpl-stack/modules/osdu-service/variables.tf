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

# Variables for the reusable OSDU service module

variable "service_name" {
  description = "Helm release name, service account name, and postrender SERVICE_NAME"
  type        = string
}

variable "chart" {
  description = "Helm chart name (e.g. core-plus-partition-deploy)"
  type        = string
}

variable "repository" {
  description = "OCI registry URL for the Helm chart"
  type        = string
}

variable "chart_version" {
  description = "Helm chart version"
  type        = string
  default     = "0.0.7-latest"
}

variable "enable" {
  description = "Service-level feature flag"
  type        = bool
}

variable "enable_common" {
  description = "Combined gate — OSDU namespace must exist"
  type        = bool
}

variable "namespace" {
  description = "Kubernetes namespace for this service"
  type        = string
}

variable "osdu_domain" {
  description = "OSDU domain (e.g. prefix.dnszone)"
  type        = string
}

variable "cimpl_tenant" {
  description = "Data partition ID"
  type        = string
}

variable "cimpl_project" {
  description = "CIMPL project identifier"
  type        = string
}

variable "subscriber_private_key_id" {
  description = "Subscriber private key identifier (sensitive)"
  type        = string
  sensitive   = true
}

variable "kustomize_path" {
  description = "Absolute path to the stack instance directory for postrender script resolution"
  type        = string
}

variable "extra_set" {
  description = "Service-specific Helm set overrides merged after common values"
  type = list(object({
    name  = string
    value = string
    type  = optional(string)
  }))
  default = []
}

variable "nodepool_name" {
  description = "Karpenter NodePool label for pod scheduling (agentpool label value)"
  type        = string
  default     = ""
}

variable "platform_namespace" {
  description = "Platform namespace for cross-namespace service references (Keycloak JWKS URI rewrite)"
  type        = string
  default     = ""
}

variable "preconditions" {
  description = "List of precondition checks evaluated before creating the Helm release"
  type = list(object({
    condition     = bool
    error_message = string
  }))
  default = []
}
