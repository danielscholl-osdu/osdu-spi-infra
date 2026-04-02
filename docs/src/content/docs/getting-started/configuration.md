---
title: Configuration
description: Environment variables and feature flags for customizing the deployment
---

## Environment Variables

Set variables before provisioning with `azd env set`:

```bash
# Required
azd env set AZURE_LOCATION eastus2
azd env set AZURE_CONTACT_EMAIL you@example.com

# Optional: disable Grafana to save costs
azd env set ENABLE_GRAFANA_WORKSPACE false

# Optional: add more data partitions
azd env set TF_VAR_data_partitions '["opendes","another-partition"]'
```

## Azure Resources per Environment

| Resource | Purpose | Per-Partition |
|---|---|---|
| AKS Automatic | Kubernetes cluster (K8s 1.33, Istio, Cilium) | No |
| CosmosDB (Gremlin) | Entitlements graph | No |
| CosmosDB (SQL) | OSDU operational data (24 containers) | Yes |
| Service Bus | Event-driven messaging (14 topics) | Yes |
| Storage Account (common) | System data, Airflow DAGs, CRS | No |
| Storage Account (partition) | Legal configs, file areas, WKS mappings | Yes |
| Key Vault | Connection strings, keys, credentials | No |
| Container Registry | Container images | No |
| Application Insights | Service telemetry | No |
| Log Analytics | Container Insights | No |
| Azure Monitor Workspace | Managed Prometheus metrics | No |

## Multi-Partition Support

Resources marked "Per-Partition" are created for each data partition via Terraform `for_each`. The default partition is `opendes`. Add more partitions via:

```bash
azd env set TF_VAR_data_partitions '["opendes","second-partition"]'
```

## Multi-Stack Support

Deploy multiple isolated OSDU instances on the same cluster:

```bash
# Deploy the default stack
azd deploy

# Deploy a second stack with a different name
azd env set STACK_NAME blue
azd deploy
```

Each stack gets its own namespaces (`platform-{name}`, `osdu-{name}`) and independent Terraform state, while sharing the foundation layer.

## Feature Flags

Individual OSDU services can be toggled via Terraform variables:

```bash
azd env set TF_VAR_enable_partition true
azd env set TF_VAR_enable_search true
azd env set TF_VAR_enable_storage true
```

This allows incremental deployment — start with core services and enable additional ones as needed.
