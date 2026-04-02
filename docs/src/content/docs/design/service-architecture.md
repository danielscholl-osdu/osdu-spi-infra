---
title: Service Architecture
description: How OSDU services are packaged, deployed, and configured
---

All OSDU services follow a uniform deployment pattern using a local Helm chart and a reusable Terraform module. This eliminates the need for kustomize postrender and ensures AKS Deployment Safeguards compliance by construction.

## Local Helm Chart: `osdu-spi-service`

A single Helm chart (`software/stack/charts/osdu-spi-service/`) serves all 13+ OSDU services. The chart template bakes in all safeguards requirements:

| Requirement | Implementation |
|---|---|
| Non-root execution | `securityContext.runAsNonRoot: true` at pod level |
| Seccomp profile | `seccompProfile.type: RuntimeDefault` |
| No privilege escalation | `allowPrivilegeEscalation: false` per container |
| Dropped capabilities | `capabilities.drop: [ALL]` per container |
| Resource limits | `requests` and `limits` on all containers |
| Health probes | Configurable liveness and readiness probes |
| Topology spread | Zone and host distribution constraints |

This approach was chosen over consuming upstream OSDU community Helm charts with kustomize postrender patches. See [ADR-0003](/osdu-spi-infra/decisions/0003-local-helm-chart-for-safeguards-compliance/).

## Reusable Terraform Module

Each OSDU service is deployed via the `osdu-spi-service` Terraform module (`software/stack/modules/osdu-spi-service/`), which wraps the Helm chart with consistent configuration:

```hcl
module "partition_service" {
  source = "./modules/osdu-spi-service"

  name             = "partition"
  namespace        = local.osdu_namespace
  chart_path       = "${path.module}/charts/osdu-spi-service"
  image_repository = "community.opengroup.org:5555/osdu/platform/system/partition/partition-azure"
  image_tag        = local.image_tags["partition"]

  env_from_configmaps = [module.osdu_common.configmap_name]
  env_from_secrets    = [module.osdu_common.secret_name]
}
```

## Feature Flags

Each service is independently toggleable:

```hcl
variable "enable_partition" {
  type    = bool
  default = true
}

variable "enable_search" {
  type    = bool
  default = true
}
```

This enables incremental deployment — start with core services (partition, entitlements, legal) and add more as needed.

## Health Probe Configuration

OSDU services are not uniform in how they expose health endpoints. The Terraform module supports per-service probe overrides:

| Service Category | Probe Port | Probe Path |
|---|---|---|
| Most core services | 8081 | `/actuator/health` |
| unit | 8080 | `/api/unit/actuator/health` |
| crs-conversion | 8080 | `/api/crs/converter/actuator/health` |

See [ADR-0005](/osdu-spi-infra/decisions/0005-per-service-health-probe-configuration/) for the full probe matrix and diagnostic steps.

## Common Configuration

The `osdu-common` module (`software/stack/modules/osdu-common/`) creates shared resources consumed by all OSDU services:

- **Namespace** with Istio sidecar injection label
- **ConfigMap** with Azure PaaS connection details (CosmosDB endpoints, Service Bus connection strings, Storage URLs)
- **Secret** references for sensitive values from Key Vault
- **Workload Identity** service account binding

Services receive this configuration via `envFrom` on the ConfigMap and Secret.

## Image Resolution

Container image tags are resolved at deploy time by `scripts/resolve-image-tags.ps1`, which queries the OSDU GitLab container registry for the latest tags. This ensures deployments use the most recent published images without hardcoding versions.
