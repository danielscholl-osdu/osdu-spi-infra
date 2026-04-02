---
title: Introduction
description: What OSDU SPI Infrastructure is and why it exists
---

OSDU SPI Infrastructure is an Infrastructure as Code project for deploying the [OSDU](https://osduforum.org/) Azure SPI (Service Provider Interface) implementation on [AKS Automatic](https://learn.microsoft.com/azure/aks/intro-aks-automatic).

## How is this different from CIMPL?

The [OSDU Community Implementation (CIMPL)](https://community.opengroup.org/osdu/platform/deployment-and-operations/cimpl-azure-provisioning) runs **all middleware in-cluster** — CosmosDB emulator, RabbitMQ, MinIO, Elasticsearch, PostgreSQL, Redis, and Keycloak all run as Kubernetes workloads.

The Azure SPI takes a **hybrid approach**: Azure PaaS services handle data persistence and messaging (CosmosDB, Service Bus, Azure Storage, Key Vault), while compute-oriented middleware (Elasticsearch, Redis, PostgreSQL, Airflow) runs in-cluster for faster provisioning and lower dev/test cost.

## Three-Layer Deployment Model

The project uses independent Terraform states for each deployment layer:

```
Layer 1:  infra/              Azure resources (AKS + PaaS)         ~15 min
Layer 1a: infra-access/       Privileged RBAC bootstrap            ~1 min
Layer 2:  software/foundation/ Cluster operators (cert-manager,     ~3 min
                               ECK, CNPG, ExternalDNS, Gateway API)
Layer 3:  software/spi-stack/   SPI middleware + OSDU services       ~5 min
Layer 3a: software/cimpl-stack/ CIMPL middleware + OSDU services    ~8 min
```

Each layer has its own lifecycle — infrastructure changes don't re-evaluate application releases, and the stack can be redeployed independently in ~5 minutes.

## Key Capabilities

- **One-command deployment** via Azure Developer CLI (`azd up`)
- **AKS Automatic** with managed Istio, Cilium, Deployment Safeguards, and Karpenter
- **Workload Identity** for credential-free access to Azure PaaS resources
- **Local Helm chart** (`osdu-spi-service`) with baked-in safeguards compliance
- **Feature flags** for granular service control
- **Multi-stack support** for blue/green deployments on a shared cluster

## Related Projects

- [cimpl-azure-provisioning](https://community.opengroup.org/osdu/platform/deployment-and-operations/cimpl-azure-provisioning) — OSDU Community Implementation (all in-cluster middleware)
- [osdu-developer](https://github.com/azure/osdu-developer) — Previous Bicep + GitOps solution for OSDU on Azure
- [osdu-spi-skills](https://github.com/danielscholl-osdu/osdu-spi-skills) — AI agent skills for the OSDU platform
