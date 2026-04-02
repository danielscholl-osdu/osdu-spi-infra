---
title: "ADR-0004: Istio CNI Chaining"
description: Istio CNI chaining for sidecar injection on AKS Automatic
---

**Status:** Accepted  
**Date:** 2026-04-01  
**Deciders:** danielscholl

## Context and Problem Statement

AKS Automatic with managed Istio installs the Istio control plane in the exempted `aks-istio-system` namespace, but sidecar injection into user namespaces fails. The default injection mechanism adds an `istio-init` init container that requires `NET_ADMIN` and `NET_RAW` capabilities. AKS Automatic's Deployment Safeguards block these capabilities in all user namespaces via non-bypassable `ValidatingAdmissionPolicy` resources.

## Decision Drivers

- AKS Automatic Deployment Safeguards are mandatory and block `NET_ADMIN`/`NET_RAW` in user namespaces
- Istio mTLS and traffic management are required for OSDU service-to-service security
- The `IstioCNIPreview` feature flag must be registered on the subscription before enabling
- The AVM Terraform module does not expose the `proxyRedirectionMechanism` property

## Considered Options

1. Istio CNI chaining (`az aks mesh enable-istio-cni`)
2. Upgrade to a newer Istio revision with native sidecar support
3. Exempt the osdu namespace from Deployment Safeguards
4. Run without Istio mesh (no sidecars)

## Decision Outcome

Chosen option: **Istio CNI chaining**, because it is the only supported mechanism for Istio sidecar injection on AKS Automatic. It replaces the privileged `istio-init` init container with a node-level CNI plugin DaemonSet that runs in the exempted `aks-istio-system` namespace.

### Consequences

- **Good:** Pods receive `istio-validation` (drops ALL capabilities) instead of `istio-init` (requires NET_ADMIN) — fully safeguards-compliant
- **Good:** `istio-proxy` runs as a Kubernetes native sidecar (init container with `restartPolicy: Always`), improving startup ordering
- **Good:** The CNI DaemonSet runs on all nodes automatically
- **Bad:** The `IstioCNIPreview` feature flag must be registered per subscription before first use
- **Bad:** The setting cannot be managed declaratively in Terraform — requires a CLI call in post-provision

### Implementation

1. Register the preview feature flag (one-time per subscription):
   ```bash
   az feature register --namespace Microsoft.ContainerService --name IstioCNIPreview
   az provider register -n Microsoft.ContainerService
   ```

2. Enable CNI chaining (idempotent, runs in post-provision.ps1):
   ```bash
   az aks mesh enable-istio-cni -g <rg> -n <cluster>
   ```

3. Label the namespace for sidecar injection:
   ```hcl
   labels = { "istio.io/rev" = var.istio_revision }
   ```

### Verification

```bash
# CNI DaemonSet running
kubectl get daemonset -n aks-istio-system | grep cni

# Pods have 2 containers (app + istio-proxy)
kubectl get pods -n osdu

# No istio-init, only istio-validation init container
kubectl get pod <name> -n osdu -o jsonpath='{.spec.initContainers[*].name}'
```
