---
status: accepted
contact: danielscholl
date: 2026-03-15
deciders: danielscholl
---

# Azure PaaS for Data Persistence, In-Cluster for Compute Middleware

## Context and Problem Statement

OSDU requires multiple middleware services: a document database, message broker, object storage, search engine, relational database (Airflow), cache, and key management. The Azure SPI implementation must decide which services run as Azure PaaS and which run in-cluster on AKS. Running everything in-cluster (like CIMPL) simplifies networking but increases operational burden and cost. Running everything as PaaS eliminates some middleware entirely but may not be possible for all components.

## Decision Drivers

- Operational burden for a small team (minimize stateful workload management)
- Provisioning speed for dev/test environments
- Cost profile (PaaS vs compute for stateful workloads)
- OSDU SPI compatibility (services must find endpoints via partition service)
- Data durability requirements differ by component

## Considered Options

- All in-cluster (CIMPL model: CosmosDB emulator, RabbitMQ, MinIO, Elasticsearch, PostgreSQL, Redis)
- All Azure PaaS (including managed Elasticsearch, managed Redis)
- Hybrid: Azure PaaS for data persistence, in-cluster for compute middleware

## Decision Outcome

Chosen option: "Hybrid", because Azure PaaS provides durability and managed operations for critical data stores, while in-cluster Elasticsearch/Redis/PostgreSQL are faster to provision, cheaper for dev/test, and don't have managed equivalents that match OSDU's requirements exactly.

### Consequences

- Good, because CosmosDB, Service Bus, Storage, and Key Vault are fully managed with SLA-backed durability
- Good, because in-cluster Elasticsearch/Redis/PostgreSQL provision in minutes vs. 30+ minutes for managed equivalents
- Good, because Workload Identity provides credential-free access to PaaS resources
- Bad, because in-cluster stateful workloads (ECK, CNPG, Redis) require operator management and backup planning
- Bad, because two networking models: PaaS via Workload Identity, in-cluster via Kubernetes DNS

| In-Cluster | Azure PaaS |
|---|---|
| Elasticsearch (ECK) | CosmosDB (SQL + Gremlin) |
| Redis | Azure Service Bus |
| PostgreSQL (CNPG, Airflow only) | Azure Storage (blob/table) |
| Airflow | Azure Key Vault |
| | Azure Container Registry |
| | Application Insights |
