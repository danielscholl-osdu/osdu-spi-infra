---
status: accepted
contact: danielscholl
date: 2026-04-03
deciders: danielscholl
---

# Kustomize Postrender for CIMPL Stack Safeguards Compliance

## Context and Problem Statement

The CIMPL stack deploys OSDU services using upstream community Helm charts from the OSDU OCI registry. These charts do not include all fields required by AKS Automatic Deployment Safeguards (seccomp profiles, resource limits, health probes, topology spread constraints). Unlike the SPI stack — which uses a local Helm chart with compliance baked in (see [ADR-0003](0003-local-helm-chart-for-safeguards-compliance.md)) — the CIMPL stack must consume upstream charts unmodified to stay aligned with community releases.

## Decision Drivers

- CIMPL charts are maintained by the OSDU community and cannot be modified locally without forking
- AKS Automatic Deployment Safeguards are non-bypassable ValidatingAdmissionPolicies
- The compliance gap is consistent across all OSDU service charts — same missing fields
- Kustomize strategic merge patches can target Deployment and StatefulSet resources by kind without knowing specific resource names

## Considered Options

- Fork OSDU community Helm charts and add compliance fields
- Local Helm chart wrapping upstream charts (same as SPI approach)
- Helm postrender with Kustomize strategic merge patches

## Decision Outcome

Chosen option: "Helm postrender with Kustomize", because it applies safeguards-required fields to upstream chart output without forking or wrapping, and the compliance patches are composable Kustomize components reusable across all services.

### Architecture

```
software/cimpl-stack/kustomize/
├── postrender.ps1                # Helm postrender entry point
├── components/
│   ├── seccomp/                  # RuntimeDefault seccomp profile
│   ├── security-context/         # runAsNonRoot, drop ALL capabilities
│   ├── topology-spread/          # Zone + host distribution
│   ├── nodepool/                 # Node selector + toleration for dedicated pool
│   └── pin-istio-proxy/          # Pin istio-proxy image version
└── services/
    ├── partition/                # Per-service probes + resources
    ├── entitlements/
    └── ...
```

Each service overlay (`services/<name>/kustomization.yaml`) includes the shared components and adds service-specific patches for health probes and resource sizing.

### Consequences

- Good, because upstream OSDU charts are consumed unmodified — no fork maintenance
- Good, because compliance patches are shared components, applied consistently across all services
- Good, because adding a new service requires only a service-specific overlay (probes + resources)
- Bad, because the postrender pipeline adds complexity and a PowerShell dependency
- Bad, because upstream chart structure changes can break kustomize patch targets
