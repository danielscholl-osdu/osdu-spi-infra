---
status: accepted
contact: danielscholl
date: 2026-04-01
deciders: danielscholl
---

# Istio CNI Chaining for Sidecar Injection on AKS Automatic

## Context and Problem Statement

AKS Automatic with managed Istio (ASM) installs the Istio control plane in the exempted `aks-istio-system` namespace, but sidecar injection into user namespaces fails. The default injection mechanism adds an `istio-init` init container that requires `NET_ADMIN` and `NET_RAW` capabilities to configure iptables-based traffic redirection. AKS Automatic's Deployment Safeguards enforce baseline pod security via non-bypassable `ValidatingAdmissionPolicy` resources that block these capabilities in all user namespaces. The policy binding cannot be modified, and namespaces cannot be exempted on AKS Automatic.

## Decision Drivers

- AKS Automatic Deployment Safeguards are mandatory and block `NET_ADMIN`/`NET_RAW` in user namespaces
- Istio mTLS and traffic management are required for OSDU service-to-service security
- The `IstioCNIPreview` feature flag must be registered on the subscription before enabling
- The AVM Terraform module (v0.4.3) does not expose the `proxyRedirectionMechanism` property
- No newer Istio revision (e.g., asm-1-29) is available to resolve this — asm-1-28 is the latest

## Considered Options

- Istio CNI chaining (`az aks mesh enable-istio-cni`)
- Upgrade to a newer Istio revision with native sidecar support
- Exempt the osdu namespace from Deployment Safeguards
- Run without Istio mesh (no sidecars)

## Decision Outcome

Chosen option: "Istio CNI chaining", because it is the only supported mechanism for Istio sidecar injection on AKS Automatic. It replaces the privileged `istio-init` init container with a node-level CNI plugin DaemonSet that runs in the exempted `aks-istio-system` namespace.

### Consequences

- Good, because pods receive `istio-validation` (drops ALL capabilities) instead of `istio-init` (requires NET_ADMIN) — fully safeguards-compliant
- Good, because `istio-proxy` runs as a Kubernetes native sidecar (init container with `restartPolicy: Always`), improving startup ordering
- Good, because the CNI DaemonSet (`azure-service-mesh-istio-cni-addon-node`) runs on all nodes automatically
- Bad, because the `IstioCNIPreview` feature flag must be registered per subscription before first use
- Bad, because the setting cannot be managed declaratively in Terraform (AVM module gap) — requires a CLI call in post-provision

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

3. Label the namespace for sidecar injection (in Terraform):
   ```hcl
   labels = { "istio.io/rev" = var.istio_revision }
   ```

4. Pods must be restarted after enabling to pick up the sidecar.

### Verification

```bash
# CNI DaemonSet running
kubectl get daemonset -n aks-istio-system | grep cni

# Pods have 2 containers (app + istio-proxy)
kubectl get pods -n osdu

# No istio-init, only istio-validation init container
kubectl get pod <name> -n osdu -o jsonpath='{.spec.initContainers[*].name}'
```
