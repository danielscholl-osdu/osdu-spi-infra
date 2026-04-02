---
title: Deployment Model
description: Three-layer deployment architecture with independent Terraform state
---

The platform deploys across three independent Terraform layers, each with its own state and lifecycle.

## Deployment Layers

### Layer 1: Infrastructure (`infra/`)

Provisioned by `azd provision` via Terraform.

Creates all Azure resources: AKS Automatic cluster, CosmosDB accounts, Service Bus namespaces, Storage accounts, Key Vault, Container Registry, and monitoring resources. AKS Managed Add-ons (Istio, Cilium, Karpenter) are enabled on the cluster and managed by Azure.

An optional access-bootstrap layer (`infra-access/`) separates privileged Azure authorization (RBAC grants, policy exemptions, DNS roles) from core infrastructure so it can be applied by a different identity.

### Layer 2: Foundation (`software/foundation/`)

Deployed by the `post-provision` hook via Terraform.

Installs cluster-wide operators via Helm: cert-manager, ECK (Elastic Cloud on Kubernetes), CNPG (CloudNativePG), and ExternalDNS. Shared primitives (Gateway API CRDs, StorageClasses) are applied via `kubectl_manifest`.

### Layer 3: Software Stack (`software/stack/`)

Deployed by the `pre-deploy` hook via Terraform.

Deploys middleware instances (Elasticsearch, PostgreSQL, Redis, Airflow) and all OSDU services. Middleware and services share a single Terraform state because services have explicit `depends_on` relationships with middleware modules. Each service is toggled independently via feature flags.

:::note[Why this split?]
The AKS cluster must exist before any Kubernetes resources can be deployed. Foundation components (operators, CRDs, StorageClasses) are cluster-wide singletons that all stacks share. The software stack deploys instances and services that can vary per stack.
:::

## Namespace Architecture

Each layer deploys into a dedicated namespace. Named stacks append a suffix for isolation:

| Namespace | Contents | Istio Injection | Multi-Stack |
|---|---|---|---|
| `foundation` | Operators (cert-manager, ECK, CNPG) | No (outside mesh) | Shared |
| `platform` | Middleware (Elasticsearch, PostgreSQL, Redis, Airflow) | Yes (STRICT mTLS) | `platform-{name}` |
| `osdu` | OSDU common resources and services | Yes (STRICT mTLS) | `osdu-{name}` |

## Multi-Stack Deployment

Multiple OSDU instances can share the same cluster. Each stack gets isolated namespaces and its own middleware, while the foundation layer is shared.

```bash
# Deploy the default stack
azd deploy

# Deploy a second stack
azd env set STACK_NAME blue
azd deploy
```

## Deployment Flow

The deployment lifecycle is orchestrated by Azure Developer CLI hooks:

```
azd up
  ├── prerestore ─── resolve-chart-versions.ps1 + resolve-image-tags.ps1
  ├── preprovision ── pre-provision.ps1 (validate tools, generate creds)
  ├── provision ───── terraform apply (infra/)
  ├── postprovision ─ post-provision.ps1 (RBAC, safeguards gate, foundation)
  └── predeploy ───── pre-deploy.ps1 (stack: middleware + services)
```

**Safeguards gate:** Azure Policy/Gatekeeper is eventually consistent. Fresh clusters have a window where policies aren't fully reconciled. The post-provision hook waits for safeguards readiness before deploying any workloads.

## Lifecycle Scripts

Each `azd` hook maps to a PowerShell script in `scripts/`:

### Provision Phase

| Script | Hook | Purpose |
|---|---|---|
| `resolve-chart-versions.ps1` | prerestore | Query OCI registry for latest chart versions |
| `resolve-image-tags.ps1` | prerestore | Fetch latest container image tags from GitLab registry |
| `pre-provision.ps1` | preprovision | Validate prerequisites, auto-generate credentials |
| `bootstrap-access.ps1` | manual | RBAC grants, policy exemptions, DNS roles |
| `post-provision.ps1` | postprovision | Wait for safeguards, deploy foundation layer |

### Deploy Phase

| Script | Hook | Purpose |
|---|---|---|
| `pre-deploy.ps1` | predeploy | Deploy software stack: middleware + OSDU services |

### Teardown Phase

| Script | Hook | Purpose |
|---|---|---|
| `pre-down.ps1` | predown | Destroy stack and foundation before cluster teardown |
| `post-down.ps1` | postdown | Clean up `.terraform` directories and stale state |

## Repository Structure

The repository layout mirrors the deployment layers:

```
osdu-spi-infra/
├── azure.yaml                    # azd orchestration
├── infra/                        # Layer 1: AKS + Azure PaaS
│   ├── aks.tf                    #   AKS Automatic (AVM module)
│   ├── cosmosdb.tf               #   CosmosDB (Gremlin + SQL per partition)
│   ├── servicebus.tf             #   Service Bus (topics per partition)
│   ├── storage.tf                #   Storage accounts
│   ├── keyvault.tf               #   Key Vault + secrets
│   ├── identity.tf               #   Workload Identity + federated credentials
│   └── ...
├── infra-access/                 # Layer 1a: Privileged RBAC
├── software/
│   ├── foundation/               # Layer 2: Operators & CRDs
│   │   └── charts/               #   cert-manager, ECK, CNPG, ExternalDNS
│   └── stack/                    # Layer 3: Middleware + Services
│       ├── charts/               #   osdu-spi-service Helm chart
│       └── modules/              #   Terraform modules per component
│           ├── elastic/          #   Elasticsearch + Kibana
│           ├── postgresql/       #   CNPG HA cluster
│           ├── redis/            #   Redis (master + replicas)
│           ├── airflow/          #   Apache Airflow
│           ├── gateway/          #   Gateway API routes + TLS
│           ├── osdu-common/      #   Namespace, ConfigMaps, Workload Identity
│           └── osdu-spi-service/ #   Reusable OSDU service wrapper
└── scripts/                      # azd lifecycle hooks (PowerShell)
```
