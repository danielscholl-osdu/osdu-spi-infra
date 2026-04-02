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

# Stack outputs (Azure SPI variant)

output "platform_namespace" {
  description = "Platform namespace name for this stack"
  value       = local.platform_namespace
}

output "osdu_namespace" {
  description = "OSDU namespace name for this stack"
  value       = local.osdu_namespace
}

output "elasticsearch_url" {
  description = "Elasticsearch internal URL"
  value       = var.enable_elasticsearch ? "https://${local.elasticsearch_host}:9200" : ""
}

output "kibana_url" {
  description = "Kibana external URL"
  value       = var.enable_elasticsearch && var.enable_gateway && local.has_ingress_hostname ? "https://${local.kibana_hostname}" : ""
}

output "osdu_api_url" {
  description = "OSDU API external base URL"
  value       = var.enable_osdu_api_ingress && var.enable_gateway && local.osdu_domain != "" ? "https://${local.osdu_domain}" : ""
}

output "airflow_url" {
  description = "Airflow external URL"
  value       = var.enable_airflow_ingress && var.enable_airflow && var.enable_gateway && local.airflow_hostname != "" ? "https://${local.airflow_hostname}" : ""
}
