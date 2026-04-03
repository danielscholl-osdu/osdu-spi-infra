---
status: accepted
contact: danielscholl
date: 2026-04-03
deciders: danielscholl
---

# Dual-Stack Architecture: Azure SPI and CIMPL Side-by-Side

## Context and Problem Statement

OSDU has two deployment models on Azure: the Azure SPI implementation (which uses Azure PaaS services for data persistence and messaging) and the CIMPL community implementation (which runs all middleware in-cluster). Each model has trade-offs — SPI reduces operational burden via managed services but requires Azure-specific configuration, while CIMPL is cloud-agnostic and self-contained but requires managing stateful workloads. Supporting both on the same AKS cluster enables validation, comparison, and migration flexibility.

## Decision Drivers

- Need to validate CIMPL services against SPI services on the same cluster for functional comparison
- Foundation operators (cert-manager, ECK, CNPG, ExternalDNS) are cluster-wide singletons — duplicating clusters for each model wastes resources
- Each model requires different middleware: SPI uses Azure PaaS (CosmosDB, Service Bus, Storage), CIMPL uses in-cluster equivalents (PostgreSQL, RabbitMQ, MinIO, Keycloak)
- Namespace-based isolation in Kubernetes provides sufficient workload separation

## Considered Options

- Separate clusters per deployment model
- Single cluster with one deployment model only
- Single cluster with both models running side-by-side in isolated namespaces

## Decision Outcome

Chosen option: "Single cluster with both models side-by-side", because it maximizes resource sharing at the infrastructure and foundation layers while maintaining full isolation at the application layer via namespaces and Karpenter NodePools.

### Stack Comparison

| Aspect | SPI Stack (`software/spi-stack/`) | CIMPL Stack (`software/cimpl-stack/`) |
|---|---|---|
| Database | Azure CosmosDB (SQL + Gremlin) | In-cluster PostgreSQL (CNPG) |
| Messaging | Azure Service Bus | In-cluster RabbitMQ |
| Object Storage | Azure Storage | In-cluster MinIO |
| Search/Index | In-cluster Elasticsearch (ECK) | In-cluster Elasticsearch (ECK) |
| Cache | In-cluster Redis | In-cluster Redis |
| Workflow | Apache Airflow (Azure-backed DAG storage) | Apache Airflow (MinIO-backed DAG storage) |
| Identity/Auth | Azure Entra ID + Workload Identity | In-cluster Keycloak |
| Secret Management | Azure Key Vault | Kubernetes Secrets |
| Service Deployment | Local Helm chart (`osdu-spi-service`) | Upstream OSDU charts + Kustomize postrender |
| Namespaces | `platform` / `osdu` | `platform-cimpl` / `osdu-cimpl` |

### Isolation Boundaries

- **Namespaces**: Each stack gets its own `platform-{id}` and `osdu-{id}` namespaces
- **Karpenter NodePools**: Dedicated node pools per stack with taints prevent cross-scheduling
- **Gateway API**: Each stack manages its own HTTPRoutes with listener passthrough for shared Gateway resources
- **Terraform State**: Each stack is a separate Terraform root module with independent state

### Consequences

- Good, because functional comparison between SPI and CIMPL is possible on a single cluster
- Good, because infrastructure and foundation layers are shared, reducing cost and management
- Good, because either stack can be deployed independently — the other is not required
- Good, because namespace isolation prevents resource naming conflicts
- Bad, because total cluster resource consumption increases when both stacks run simultaneously
- Bad, because Gateway routing must coordinate across stacks via listener passthrough
