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

# Derived names and partition processing for the infrastructure layer.

locals {
  # Resource naming: spi-<env_name> allows multiple deployments
  resource_group_name = "rg-spi-${var.environment_name}"
  cluster_name        = "spi-${var.environment_name}"

  # Azure Managed Grafana names are limited to 23 characters.
  grafana_name = trimsuffix(substr("${local.cluster_name}-grafana", 0, 23), "-")

  # Standard tags applied to all Azure resources.
  common_tags = merge(var.tags, {
    "azd-env-name" = var.environment_name
    "project"      = "osdu-spi"
    "Contact"      = var.contact_email
  })

  # Convert partition list to a set for for_each usage.
  partitions = toset(var.data_partitions)

  # The first partition hosts the system database.
  primary_partition = var.data_partitions[0]

  # ──────────────────────────────────────────────
  # CosmosDB container definitions
  # Source: osdu-developer blade_partition.bicep
  # ──────────────────────────────────────────────

  osdu_db_containers = {
    "Authority"                  = { partition_key = "/id" }
    "EntityType"                 = { partition_key = "/id" }
    "FileLocationEntity"         = { partition_key = "/id" }
    "IngestionStrategy"          = { partition_key = "/workflowType" }
    "LegalTag"                   = { partition_key = "/id" }
    "MappingInfo"                = { partition_key = "/sourceSchemaKind" }
    "RegisterAction"             = { partition_key = "/dataPartitionId" }
    "RegisterDdms"               = { partition_key = "/dataPartitionId" }
    "RegisterSubscription"       = { partition_key = "/dataPartitionId" }
    "RelationshipStatus"         = { partition_key = "/id" }
    "ReplayStatus"               = { partition_key = "/id" }
    "SchemaInfo"                 = { partition_key = "/partitionId" }
    "Source"                     = { partition_key = "/id" }
    "StorageRecord"              = { partition_key = "/id" }
    "StorageSchema"              = { partition_key = "/kind" }
    "TenantInfo"                 = { partition_key = "/id" }
    "UserInfo"                   = { partition_key = "/id" }
    "Workflow"                   = { partition_key = "/workflowId" }
    "WorkflowCustomOperatorInfo" = { partition_key = "/operatorId" }
    "WorkflowCustomOperatorV2"   = { partition_key = "/partitionKey" }
    "WorkflowRun"                = { partition_key = "/partitionKey" }
    "WorkflowRunV2"              = { partition_key = "/partitionKey" }
    "WorkflowRunStatus"          = { partition_key = "/partitionKey" }
    "WorkflowV2"                 = { partition_key = "/partitionKey" }
  }

  osdu_system_db_containers = {
    "Authority"  = { partition_key = "/id" }
    "EntityType" = { partition_key = "/id" }
    "SchemaInfo" = { partition_key = "/partitionId" }
    "Source"     = { partition_key = "/id" }
    "WorkflowV2" = { partition_key = "/partitionKey" }
  }

  # Flatten partition x container into a single map for for_each.
  partition_db_containers = merge([
    for p in var.data_partitions : {
      for name, spec in local.osdu_db_containers :
      "${p}/${name}" => {
        partition     = p
        container     = name
        partition_key = spec.partition_key
      }
    }
  ]...)

  # System DB containers (on primary partition's CosmosDB account only).
  system_db_containers = {
    for name, spec in local.osdu_system_db_containers :
    name => {
      partition     = local.primary_partition
      container     = name
      partition_key = spec.partition_key
    }
  }

  # ──────────────────────────────────────────────
  # Service Bus topic definitions
  # Source: osdu-developer blade_partition.bicep
  # ──────────────────────────────────────────────

  servicebus_topics = {
    "indexing-progress" = {
      max_size = 1024
      subscriptions = {
        "indexing-progresssubscription" = { max_delivery = 5, lock_duration = "PT5M" }
      }
    }
    "legaltags" = {
      max_size = 1024
      subscriptions = {
        "legaltagssubscription" = { max_delivery = 5, lock_duration = "PT5M" }
      }
    }
    "recordstopic" = {
      max_size = 1024
      subscriptions = {
        "recordstopicsubscription" = { max_delivery = 5, lock_duration = "PT5M" }
        "wkssubscription"          = { max_delivery = 5, lock_duration = "PT5M" }
      }
    }
    "recordstopicdownstream" = {
      max_size = 1024
      subscriptions = {
        "downstreamsub" = { max_delivery = 5, lock_duration = "PT5M" }
      }
    }
    "recordstopiceg" = {
      max_size = 1024
      subscriptions = {
        "eg_sb_wkssubscription" = { max_delivery = 5, lock_duration = "PT5M" }
      }
    }
    "schemachangedtopic" = {
      max_size = 1024
      subscriptions = {
        "schemachangedtopicsubscription" = { max_delivery = 5, lock_duration = "PT5M" }
      }
    }
    "schemachangedtopiceg" = {
      max_size = 1024
      subscriptions = {
        "eg_sb_schemasubscription" = { max_delivery = 5, lock_duration = "PT5M" }
      }
    }
    "legaltagschangedtopiceg" = {
      max_size = 1024
      subscriptions = {
        "eg_sb_legaltagssubscription" = { max_delivery = 5, lock_duration = "PT5M" }
      }
    }
    "statuschangedtopic" = {
      max_size = 5120
      subscriptions = {
        "statuschangedtopicsubscription" = { max_delivery = 5, lock_duration = "PT5M" }
      }
    }
    "statuschangedtopiceg" = {
      max_size = 1024
      subscriptions = {
        "eg_sb_statussubscription" = { max_delivery = 5, lock_duration = "PT5M" }
      }
    }
    "recordstopic-v2" = {
      max_size = 1024
      subscriptions = {
        "recordstopic-v2-subscription" = { max_delivery = 5, lock_duration = "PT5M" }
      }
    }
    "reindextopic" = {
      max_size = 1024
      subscriptions = {
        "reindextopicsubscription" = { max_delivery = 5, lock_duration = "PT5M" }
      }
    }
    "entitlements-changed" = {
      max_size      = 1024
      subscriptions = {}
    }
    "replaytopic" = {
      max_size = 1024
      subscriptions = {
        "replaytopicsubscription" = { max_delivery = 5, lock_duration = "PT5M" }
      }
    }
  }

  # Flatten partition x topic into a single map for for_each.
  partition_sb_topics = merge([
    for p in var.data_partitions : {
      for name, spec in local.servicebus_topics :
      "${p}/${name}" => {
        partition = p
        topic     = name
        max_size  = spec.max_size
      }
    }
  ]...)

  # Flatten partition x topic x subscription into a single map for for_each.
  partition_sb_subscriptions = merge([
    for p in var.data_partitions : merge([
      for tname, tspec in local.servicebus_topics : {
        for sname, sspec in tspec.subscriptions :
        "${p}/${tname}/${sname}" => {
          partition     = p
          topic         = tname
          subscription  = sname
          max_delivery  = sspec.max_delivery
          lock_duration = sspec.lock_duration
        }
      }
    ]...)
  ]...)

  # ──────────────────────────────────────────────
  # Storage container definitions
  # ──────────────────────────────────────────────

  common_storage_containers = [
    "system",
    "azure-webjobs-hosts",
    "azure-webjobs-eventhub",
    "airflow-logs",
    "airflow-dags",
    "share-unit",
    "share-crs",
    "share-crs-conversion",
  ]

  partition_storage_containers = [
    "legal-service-azure-configuration",
    "osdu-wks-mappings",
    "wdms-osdu",
    "file-staging-area",
    "file-persistent-area",
  ]

  # ──────────────────────────────────────────────
  # Workload Identity federated credentials
  # ──────────────────────────────────────────────

  federated_credentials = {
    "federated-ns-default"        = "system:serviceaccount:default:workload-identity-sa"
    "federated-ns-osdu-core"      = "system:serviceaccount:osdu-core:workload-identity-sa"
    "federated-ns-airflow"        = "system:serviceaccount:airflow:workload-identity-sa"
    "federated-ns-osdu-system"    = "system:serviceaccount:osdu-system:workload-identity-sa"
    "federated-ns-osdu-auth"      = "system:serviceaccount:osdu-auth:workload-identity-sa"
    "federated-ns-osdu-reference" = "system:serviceaccount:osdu-reference:workload-identity-sa"
    "federated-ns-osdu"           = "system:serviceaccount:osdu:workload-identity-sa"
    "federated-ns-platform"       = "system:serviceaccount:platform:workload-identity-sa"
  }
}
