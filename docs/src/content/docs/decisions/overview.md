---
title: Architectural Decisions
description: Index of Architectural Decision Records (ADRs) for the project
---

This project documents significant architectural decisions using Architectural Decision Records (ADRs). Each record captures the context, options considered, and rationale for a decision.

## Decision Log

### Deployment Architecture

| ADR | Decision | Status |
|---|---|---|
| [ADR-0001](/osdu-spi-infra/decisions/0001-three-layer-deployment-model/) | Three-layer deployment model with independent Terraform state | Accepted |
| [ADR-0002](/osdu-spi-infra/decisions/0002-dual-stack-spi-and-cimpl-side-by-side/) | Dual-stack architecture: Azure SPI and CIMPL side-by-side | Accepted |

### Runtime & Platform

| ADR | Decision | Status |
|---|---|---|
| [ADR-0004](/osdu-spi-infra/decisions/0004-istio-cni-chaining-for-sidecar-injection/) | Istio CNI chaining for sidecar injection on AKS Automatic | Accepted |
| [ADR-0007](/osdu-spi-infra/decisions/0007-karpenter-nodepools-for-workload-isolation/) | Karpenter NodePools for workload isolation | Accepted |

### Service Patterns

| ADR | Decision | Status |
|---|---|---|
| [ADR-0003](/osdu-spi-infra/decisions/0003-local-helm-chart-for-safeguards-compliance/) | Local Helm chart for SPI stack safeguards compliance | Accepted |
| [ADR-0005](/osdu-spi-infra/decisions/0005-per-service-health-probe-configuration/) | Per-service health probe configuration for OSDU services | Accepted |
| [ADR-0006](/osdu-spi-infra/decisions/0006-kustomize-postrender-for-cimpl-safeguards/) | Kustomize postrender for CIMPL stack safeguards compliance | Accepted |

## Creating New ADRs

Use the template at `docs/decisions/adr-template.md`. Number sequentially and follow the format:

```yaml
---
status: proposed | accepted | deprecated | superseded
contact: author
date: YYYY-MM-DD
deciders: who decided
---
```
