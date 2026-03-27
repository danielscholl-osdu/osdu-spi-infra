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

output "elastic_password" {
  description = "Elasticsearch elastic user password"
  value       = var.enable_bootstrap ? data.kubernetes_secret_v1.elasticsearch_password[0].data["elastic"] : ""
  sensitive   = true
}

output "elastic_ca_cert" {
  description = "ECK self-signed CA certificate (PEM, base64-encoded)"
  value       = var.enable_bootstrap ? data.kubernetes_secret_v1.elasticsearch_ca_cert[0].data["ca.crt"] : ""
}
