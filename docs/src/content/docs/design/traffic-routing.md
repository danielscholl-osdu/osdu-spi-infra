---
title: Traffic & Routing
description: How requests reach OSDU services and how services communicate
---

Traffic flows through three distinct paths: external ingress via Gateway API, internal service-to-service via Istio mesh, and asynchronous messaging via Azure Service Bus.

## External Ingress

### Gateway API

The gateway module (`software/spi-stack/modules/gateway/`) configures Kubernetes Gateway API resources for external access with automatic TLS via cert-manager and Let's Encrypt.

| Endpoint | Hostname Pattern | Purpose |
|---|---|---|
| OSDU API | `{prefix}.{zone}` | Path-based routing to all enabled OSDU services |
| Kibana | `{prefix}-kibana.{zone}` | Elasticsearch dashboard |
| Airflow | `{prefix}-airflow.{zone}` | DAG monitoring and task execution UI |

Each endpoint is optional, independently exposed, and backed by its own HTTPS listener, HTTPRoute, TLS Certificate, and cross-namespace ReferenceGrants.

### DNS

ExternalDNS (deployed in the foundation layer) automatically creates DNS records in an Azure DNS zone for Gateway API resources. It authenticates to the DNS zone via Workload Identity.

### TLS

cert-manager provisions TLS certificates from Let's Encrypt using the DNS-01 challenge type. Certificates are stored as Kubernetes Secrets and referenced by Gateway listeners.

## Service Mesh (Istio)

AKS Automatic provides managed Istio (Azure Service Mesh). Sidecar injection is enabled via namespace labels:

```yaml
labels:
  istio.io/rev: asm-1-28
```

### mTLS

All service-to-service traffic within labeled namespaces is encrypted via Istio STRICT mTLS. This is enforced at the mesh level — services don't need to manage TLS themselves.

### CNI Chaining

Standard Istio sidecar injection requires `NET_ADMIN` capabilities, which AKS Deployment Safeguards block. Istio CNI chaining replaces the privileged `istio-init` init container with a node-level CNI plugin, making injection safeguards-compliant. See [ADR-0004](/osdu-spi-infra/decisions/0004-istio-cni-chaining-for-sidecar-injection/).

## Internal Service Communication

OSDU services discover each other via Kubernetes DNS within the `osdu` namespace:

```
http://{service-name}.osdu.svc.cluster.local:8080
```

The partition service is the central registry — other services query it to discover connection details for Azure PaaS resources (CosmosDB endpoints, Service Bus connection strings, Storage URLs).

## Async Messaging

Azure Service Bus provides event-driven messaging between OSDU services. Per-partition Service Bus namespaces host 14 topics for:

- Storage record change events
- Legal tag compliance updates
- Schema change notifications
- Indexer processing events

Services authenticate to Service Bus via Workload Identity — no connection string secrets are stored in the cluster.
