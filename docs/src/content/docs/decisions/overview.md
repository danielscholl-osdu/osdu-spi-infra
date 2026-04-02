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

### Runtime & Platform

| ADR | Decision | Status |
|---|---|---|
| [ADR-0002](/osdu-spi-infra/decisions/0002-azure-paas-with-in-cluster-middleware/) | Azure PaaS for data persistence, in-cluster for compute middleware | Accepted |
| [ADR-0004](/osdu-spi-infra/decisions/0004-istio-cni-chaining-for-sidecar-injection/) | Istio CNI chaining for sidecar injection on AKS Automatic | Accepted |

### Service Patterns

| ADR | Decision | Status |
|---|---|---|
| [ADR-0003](/osdu-spi-infra/decisions/0003-local-helm-chart-for-safeguards-compliance/) | Local Helm chart with baked-in safeguards compliance | Accepted |
| [ADR-0005](/osdu-spi-infra/decisions/0005-per-service-health-probe-configuration/) | Per-service health probe configuration for OSDU services | Accepted |

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
