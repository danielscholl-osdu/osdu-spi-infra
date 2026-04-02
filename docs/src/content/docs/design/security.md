---
title: Security
description: Security model from cluster to pod
---

The security model spans four layers: Azure RBAC for resource access, AKS platform security for cluster hardening, Istio mesh for service-to-service encryption, and pod-level security standards.

## Azure RBAC

### Cluster Access

AKS Automatic uses Azure RBAC for Kubernetes authorization. Cluster access is controlled via Azure AD role assignments rather than Kubernetes RBAC.

### Resource Access

The `infra-access/` layer applies privileged Azure RBAC grants separately from core infrastructure:

- **Cluster Admin** role for the deploying identity
- **DNS Zone Contributor** for ExternalDNS Workload Identity
- **Key Vault** access policies for secret management
- **Storage Account** data roles for OSDU services

This separation allows the access bootstrap to run under a more privileged identity than the main infrastructure provisioning.

## AKS Deployment Safeguards

AKS Automatic enforces non-bypassable `ValidatingAdmissionPolicy` resources that require:

| Policy | Requirement |
|---|---|
| Pod security | `runAsNonRoot: true`, `seccompProfile.type: RuntimeDefault` |
| Privilege escalation | `allowPrivilegeEscalation: false` |
| Capabilities | `capabilities.drop: [ALL]` |
| Resources | CPU/memory `requests` and `limits` on all containers |
| Probes | Liveness and readiness probes on all containers |

These policies cannot be exempted for user namespaces. The local `osdu-spi-service` Helm chart bakes in all requirements at authoring time, ensuring compliance without runtime patching.

## Workload Identity

Services authenticate to Azure PaaS resources using federated credentials — no secrets stored in the cluster:

1. A **user-assigned managed identity** is created in the infrastructure layer
2. **Federated credentials** are created for each Kubernetes service account
3. Services present a projected service account token that Azure AD validates
4. Azure RBAC grants the identity access to specific resources

This eliminates secret rotation and reduces the attack surface.

## Istio mTLS

All service-to-service traffic within Istio-labeled namespaces is encrypted via STRICT mTLS:

- **Platform namespace** (`platform`): Middleware services communicate over encrypted channels
- **OSDU namespace** (`osdu`): All OSDU services communicate over encrypted channels
- **Foundation namespace** (`foundation`): Operators run outside the mesh

Istio CNI chaining enables sidecar injection without the privileged `istio-init` container. See [ADR-0004](/osdu-spi-infra/decisions/0004-istio-cni-chaining-for-sidecar-injection/).

## Pod Security

The `osdu-spi-service` Helm chart enforces pod-level security for all OSDU services:

```yaml
# Pod-level
securityContext:
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault

# Container-level
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]
```

Middleware charts (Elasticsearch, Redis, PostgreSQL) use Kustomize postrender to apply equivalent security contexts where the upstream charts don't expose them directly.
