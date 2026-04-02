---
title: Infrastructure
description: Azure PaaS resources and AKS Automatic cluster configuration
---

The infrastructure layer (`infra/`) provisions all Azure resources via Terraform, using the Azure Developer CLI for orchestration.

## AKS Automatic

The cluster is provisioned using the [Azure Verified Module (AVM) for AKS](https://registry.terraform.io/modules/Azure/avm-res-containerservice-managedcluster/azurerm/latest) with AKS Automatic features:

| Feature | Description |
|---|---|
| **Managed Istio** | Service mesh with mTLS, traffic management, observability |
| **Cilium CNI** | eBPF-based networking with network policies |
| **Karpenter (NAP)** | Node Auto Provisioning — dynamic VM SKU selection per zone |
| **Deployment Safeguards** | Non-bypassable admission policies for pod security |
| **Managed Prometheus** | Metrics collection via Azure Monitor Workspace |
| **Container Insights** | Log collection via Log Analytics |

## CosmosDB

Two CosmosDB account types serve different OSDU needs:

### Gremlin (Graph)

A single Gremlin account hosts the entitlements graph database. This is shared across all data partitions.

### SQL (NoSQL)

Per-partition CosmosDB SQL accounts host OSDU operational data across 24 containers. Created via Terraform `for_each` over the data partitions list.

## Service Bus

Per-partition Service Bus namespaces with 14 topics for event-driven messaging between OSDU services. Topics include storage record changes, legal tag updates, schema notifications, and indexer events.

## Storage Accounts

### Common Storage

Shared across all partitions — holds system data, Airflow DAGs, and CRS (Coordinate Reference System) catalog files.

### Partition Storage

Per-partition storage accounts for legal configurations, file service areas, and WKS (Well Known Schema) mappings.

## Key Vault

Centralized secret management for connection strings, access keys, and generated credentials. OSDU services access secrets via:

1. **Workload Identity** for Azure PaaS resources (preferred)
2. **Key Vault references** in Kubernetes ConfigMaps for middleware connection strings

## Container Registry

Azure Container Registry stores OSDU service container images. The `resolve-image-tags.ps1` script fetches the latest image tags from the OSDU GitLab registry at deploy time.

## Monitoring

| Component | Purpose |
|---|---|
| Application Insights | Distributed tracing and service telemetry |
| Log Analytics Workspace | Container Insights and diagnostic logs |
| Azure Monitor Workspace | Managed Prometheus metrics collection |
| Grafana (optional) | Dashboards and alerting — can be disabled to save costs |

## Identity

### Workload Identity

A user-assigned managed identity with federated credentials enables OSDU services to authenticate to Azure PaaS resources without stored secrets. Federated credentials are created for each Kubernetes service account that needs Azure access.

### RBAC

The `infra-access/` layer applies privileged RBAC grants separately from core infrastructure:

- Cluster admin role assignments
- DNS zone contributor for ExternalDNS
- Key Vault access policies
- Storage account data roles
