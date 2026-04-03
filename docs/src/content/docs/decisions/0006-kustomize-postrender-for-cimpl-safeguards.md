---
title: "ADR-0006: Kustomize Postrender for CIMPL Safeguards"
description: Upstream OSDU Helm charts with Kustomize postrender patches for AKS Deployment Safeguards compliance
---

**Status:** Accepted  
**Date:** 2026-04-03  
**Deciders:** danielscholl

## Context and Problem Statement

The CIMPL stack deploys OSDU services using upstream community Helm charts from the OSDU OCI registry. These charts do not include all fields required by AKS Automatic Deployment Safeguards (seccomp profiles, resource limits, health probes, topology spread constraints). Unlike the SPI stack — which uses a local Helm chart with compliance baked in (see [ADR-0003](/osdu-spi-infra/decisions/0003-local-helm-chart-for-safeguards-compliance/)) — the CIMPL stack must consume upstream charts unmodified to stay aligned with community releases.

## Decision Drivers

- CIMPL charts are maintained by the OSDU community and cannot be modified locally without forking
- AKS Automatic Deployment Safeguards are non-bypassable ValidatingAdmissionPolicies
- The compliance gap is consistent across all OSDU service charts — same missing fields
- Kustomize strategic merge patches can target Deployment and StatefulSet resources by kind without knowing specific resource names

## Considered Options

1. Fork OSDU community Helm charts and add compliance fields
2. Local Helm chart wrapping upstream charts (same as SPI approach)
3. Helm postrender with Kustomize strategic merge patches

## Decision Outcome

Chosen option: **Helm postrender with Kustomize**, because it applies safeguards-required fields to upstream chart output without forking or wrapping, and the compliance patches are composable Kustomize components reusable across all services.

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

- **Good:** Upstream OSDU charts are consumed unmodified — no fork maintenance
- **Good:** Compliance patches are shared components, applied consistently across all services
- **Good:** Adding a new service requires only a service-specific overlay (probes + resources)
- **Bad:** The postrender pipeline adds complexity and a PowerShell dependency
- **Bad:** Upstream chart structure changes can break kustomize patch targets
