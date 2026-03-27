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

# Foundation layer outputs -- values consumed by stacks

output "cluster_issuer_name" {
  description = "Active ClusterIssuer name (staging or production)"
  value       = var.enable_cert_manager ? module.cert_manager[0].active_cluster_issuer : ""
}

output "cluster_issuer_staging_name" {
  description = "Staging ClusterIssuer name"
  value       = var.enable_cert_manager ? "letsencrypt-staging" : ""
}

output "platform_namespace" {
  description = "Foundation namespace name"
  value       = kubernetes_namespace_v1.platform.metadata[0].name
}
