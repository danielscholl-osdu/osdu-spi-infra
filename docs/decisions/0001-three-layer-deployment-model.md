---
status: accepted
contact: danielscholl
date: 2026-03-15
deciders: danielscholl
---

# Three-Layer Deployment Model with Independent Terraform State

## Context and Problem Statement

Deploying OSDU on AKS requires provisioning Azure PaaS resources, installing cluster operators (cert-manager, ECK, CNPG), and deploying application workloads. A single Terraform state creates fragile coupling — a chart upgrade can trigger unnecessary re-evaluation of Azure infrastructure, and foundation operators must exist before application Helm releases can reference their CRDs.

## Decision Drivers

- CRD ordering: Helm releases for Elasticsearch, PostgreSQL, etc. require CRDs from ECK/CNPG to exist at plan time
- Blast radius: infrastructure changes should not re-evaluate application releases
- Iteration speed: developers need to redeploy the stack layer without re-running a 15-minute infra provision
- `azd` orchestration must drive all layers through lifecycle hooks

## Considered Options

- Single Terraform root module
- Three-layer model with independent state (infra → foundation → stack)
- GitOps with Flux/ArgoCD

## Decision Outcome

Chosen option: "Three-layer model with independent state", because it isolates blast radius per layer, respects CRD ordering, and enables fast stack-only iteration via `azd deploy` while `azd provision` handles infrastructure.

### Consequences

- Good, because stack redeployment takes ~5 minutes instead of re-evaluating all 3 layers
- Good, because foundation CRDs are guaranteed to exist before stack Helm releases reference them
- Good, because infra-access layer enables privileged RBAC bootstrap with minimal scope
- Bad, because cross-layer data passing requires Terraform outputs → azd env → Terraform variables plumbing
- Bad, because `azd down` must tear down in reverse order via lifecycle hooks
