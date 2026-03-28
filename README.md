# OSDU SPI Infrastructure

![Status: Experimental](https://img.shields.io/badge/status-experimental-orange.svg)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

### OSDU Azure SPI on AKS Automatic — Terraform + Helm

## What It Is

Infrastructure as Code for deploying the [OSDU](https://osduforum.org/) Azure SPI (Service Provider Interface) implementation on [AKS Automatic](https://learn.microsoft.com/azure/aks/intro-aks-automatic). Unlike the community implementation (CIMPL) which runs all middleware in-cluster, the Azure SPI leverages Azure PaaS services for data persistence and messaging while keeping compute workloads on Kubernetes.

| In-Cluster | Azure PaaS |
|---|---|
| Elasticsearch (search/indexer) | CosmosDB (SQL + Gremlin) |
| Redis (caching) | Azure Service Bus (messaging) |
| PostgreSQL via CNPG (Airflow metadata) | Azure Storage (blob/table) |
| Airflow (workflow orchestration) | Azure Key Vault (secrets) |
| Istio service mesh (managed by AKS) | Azure Container Registry |
| | Application Insights |

## Architecture

The project uses a **three-layer deployment model**, each with independent Terraform state:

```
Layer 1: infra/              Azure resources (AKS + PaaS)         ~15 min
Layer 1a: infra-access/       Privileged RBAC bootstrap            ~1 min
Layer 2: software/foundation/ Cluster operators (cert-manager,     ~3 min
                               ECK, CNPG, ExternalDNS, Gateway API)
Layer 3: software/stack/       Middleware + OSDU services           ~5 min
```

All layers are orchestrated by [Azure Developer CLI](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/) (`azd`) via lifecycle hooks.

### Azure PaaS Resources (per environment)

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

### Multi-Partition Support

Resources marked "Per-Partition" are created for each data partition via Terraform `for_each`. The default partition is `opendes`.

## What It Needs

### Azure

- An Azure subscription with [Contributor](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/privileged#contributor) and [User Access Administrator](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/privileged#user-access-administrator) roles
- (Optional) An [Azure DNS zone](https://learn.microsoft.com/en-us/azure/dns/dns-getstarted-portal) for external ingress

### Tools

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (`az`)
- [Azure Developer CLI](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd) (`azd`)
- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.12
- [Helm](https://helm.sh/docs/intro/install/) >= 3.x
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [kubelogin](https://github.com/Azure/kubelogin) (Azure AD auth for AKS)
- [PowerShell](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell) (`pwsh`) >= 7.4

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/danielscholl-osdu/osdu-spi-infra.git
cd osdu-spi-infra

# 2. Authenticate
az login
azd auth login

# 3. Deploy (prompts for environment name, subscription, and location)
azd up
```

The `azd up` command runs the full pipeline:
1. **Pre-provision** -- validates tools, auto-detects settings, generates credentials
2. **Provision** -- creates AKS cluster + Azure PaaS resources (~15 min)
3. **Post-provision** -- bootstraps RBAC, configures safeguards, deploys foundation operators
4. **Pre-deploy** -- deploys stack (Elasticsearch, PostgreSQL, Redis, Airflow, Gateway)

### Configuration

Set environment variables before provisioning:

```bash
azd env set AZURE_LOCATION eastus2
azd env set AZURE_CONTACT_EMAIL you@example.com

# Optional: disable Grafana to save costs
azd env set ENABLE_GRAFANA_WORKSPACE false

# Optional: add more data partitions
azd env set TF_VAR_data_partitions '["opendes","another-partition"]'
```

### Teardown

```bash
azd down --force --purge
```

## Project Structure

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
│       ├── modules/
│       │   ├── elastic/          #   3-node Elasticsearch + Kibana
│       │   ├── postgresql/       #   CNPG 3-instance HA (Airflow DB)
│       │   ├── redis/            #   In-cluster Redis (1 master + 2 replicas)
│       │   ├── airflow/          #   Apache Airflow
│       │   ├── gateway/          #   Gateway API routes + TLS
│       │   ├── osdu-common/      #   Namespace, ConfigMaps, Workload Identity
│       │   └── osdu-service/     #   Reusable OSDU service Helm wrapper
│       └── kustomize/            #   AKS Deployment Safeguards patches
└── scripts/                      # azd lifecycle hooks (PowerShell)
```

## Key Design Decisions

- **AKS Automatic** with managed Istio, Cilium networking, and Node Auto-Provisioning (Karpenter)
- **Azure PaaS for data** (CosmosDB, Service Bus, Storage) -- OSDU services authenticate via Workload Identity
- **In-cluster for compute** (Elasticsearch, Redis, PostgreSQL, Airflow) -- faster provisioning, lower cost for dev/test
- **Helm + Kustomize postrender** for AKS Deployment Safeguards compliance
- **Feature flags** for granular service control (`enable_partition`, `enable_search`, etc.)
- **Multi-stack support** via `STACK_NAME` for blue/green deployments on the same cluster

## Related Projects

- [cimpl-azure-provisioning](https://community.opengroup.org/osdu/platform/deployment-and-operations/cimpl-azure-provisioning) -- OSDU Community Implementation on Azure (all in-cluster middleware)
- [osdu-developer](https://github.com/azure/osdu-developer) -- Previous Bicep + GitOps solution for OSDU on Azure

## License

[Apache License 2.0](LICENSE)
