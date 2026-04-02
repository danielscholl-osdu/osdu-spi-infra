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

# Variables for the reusable OSDU SPI service module

variable "service_name" {
  description = "Helm release name and Kubernetes resource name"
  type        = string
}

variable "image_repository" {
  description = "Container image repository (e.g. community.opengroup.org:5555/.../partition-master)"
  type        = string
}

variable "image_tag" {
  description = "Container image tag"
  type        = string
  default     = "latest"
}

variable "enable" {
  description = "Service-level feature flag"
  type        = bool
}

variable "enable_common" {
  description = "Combined gate -- OSDU namespace must exist"
  type        = bool
}

variable "namespace" {
  description = "Kubernetes namespace for this service"
  type        = string
}

variable "replica_count" {
  description = "Number of pod replicas"
  type        = number
  default     = 1
}

variable "container_port" {
  description = "Port the service container listens on"
  type        = number
  default     = 8080
}

variable "elastic_tls" {
  description = "Enable Elasticsearch TLS init container (for search/indexer)"
  type        = bool
  default     = false
}

variable "redis_tls" {
  description = "Enable Redis TLS -- import self-signed CA into Java truststore"
  type        = bool
  default     = false
}

variable "istio_proxy_pin" {
  description = "Pin Istio sidecar proxy to a specific version"
  type        = bool
  default     = false
}

variable "env" {
  description = "Extra environment variables for the service container"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "resources" {
  description = "CPU/memory requests and limits"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = { cpu = "200m", memory = "512Mi" }
    limits   = { cpu = "1", memory = "1Gi" }
  }
}

variable "probes" {
  description = "Health probe configuration"
  type = object({
    liveness = object({
      path                = string
      port                = number
      initialDelaySeconds = number
      periodSeconds       = number
      timeoutSeconds      = number
      failureThreshold    = number
    })
    readiness = object({
      path                = string
      port                = number
      initialDelaySeconds = number
      periodSeconds       = number
      timeoutSeconds      = number
      failureThreshold    = number
    })
  })
  default = {
    liveness = {
      path                = "/actuator/health"
      port                = 8081
      initialDelaySeconds = 250
      periodSeconds       = 10
      timeoutSeconds      = 5
      failureThreshold    = 3
    }
    readiness = {
      path                = "/actuator/health"
      port                = 8081
      initialDelaySeconds = 10
      periodSeconds       = 10
      timeoutSeconds      = 5
      failureThreshold    = 3
    }
  }
}

variable "init_containers" {
  description = "Extra init containers (e.g., data download for reference services)"
  type        = any
  default     = []
}

variable "volume_mounts" {
  description = "Extra volume mounts for the main container"
  type        = any
  default     = []
}

variable "volumes" {
  description = "Extra volumes for the pod"
  type        = any
  default     = []
}

variable "preconditions" {
  description = "List of precondition checks evaluated before creating the Helm release"
  type = list(object({
    condition     = bool
    error_message = string
  }))
  default = []
}

variable "timeout" {
  description = "Helm release timeout in seconds"
  type        = number
  default     = 1200
}

variable "atomic" {
  description = "Purge the release on failure"
  type        = bool
  default     = false
}
