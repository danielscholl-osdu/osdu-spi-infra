---
title: Platform Services
description: In-cluster middleware that OSDU services depend on
---

The platform layer deploys stateful middleware workloads inside the AKS cluster. These components provide search, caching, workflow orchestration, and relational storage that OSDU services consume via Kubernetes DNS.

## Elasticsearch

Deployed via ECK (Elastic Cloud on Kubernetes) as a 3-node cluster with Kibana.

| Setting | Value |
|---|---|
| Nodes | 3 (one per availability zone) |
| Storage | Persistent volumes via AKS default StorageClass |
| TLS | Internal TLS enabled by ECK |
| Access | Kubernetes DNS (`elasticsearch-es-http.platform.svc`) |

OSDU search and indexer services connect to Elasticsearch for full-text indexing and query operations.

## Redis

In-cluster Redis with 1 master and 2 replicas for caching. Deployed via Helm with Kustomize postrender for safeguards compliance.

| Setting | Value |
|---|---|
| Topology | 1 master + 2 replicas |
| TLS | Enabled |
| Access | Kubernetes DNS (`redis-master.platform.svc`) |

OSDU services use Redis for caching partition information, entitlements, and schema data.

## PostgreSQL

Deployed via CNPG (CloudNativePG) as a 3-instance HA cluster. Used exclusively by Apache Airflow for metadata storage.

| Setting | Value |
|---|---|
| Instances | 3 (HA with automatic failover) |
| Purpose | Airflow metadata database |
| Access | Kubernetes DNS (`postgresql-rw.platform.svc`) |

## Airflow

Apache Airflow provides workflow orchestration for OSDU. Deployed via Helm with the Kubernetes executor.

| Setting | Value |
|---|---|
| Executor | Kubernetes (pods per task) |
| Database | CNPG PostgreSQL |
| DAG Storage | Azure Storage (common account) |

DAGs are versioned and synced from Azure Storage. The `render-dags.ps1` script prepares DAG files, and `download-dags.ps1` fetches community DAGs.

## Dependency Graph

Services have explicit deployment ordering via Terraform `depends_on`:

```
Foundation (cert-manager, ECK, CNPG)
  └── Platform Middleware
        ├── Elasticsearch (depends on ECK CRDs)
        ├── PostgreSQL (depends on CNPG CRDs)
        ├── Redis (standalone Helm)
        └── Airflow (depends on PostgreSQL)
              └── OSDU Services (depend on all middleware)
```

This ordering is enforced within a single Terraform state in `software/spi-stack/`.
