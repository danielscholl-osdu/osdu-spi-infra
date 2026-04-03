---
status: accepted
contact: danielscholl
date: 2026-04-03
deciders: danielscholl
---

# Karpenter NodePools for Workload Isolation

## Context and Problem Statement

AKS Automatic uses Karpenter (via Node Auto-Provisioning) for dynamic node scaling. The cluster runs both stateful middleware (Elasticsearch, PostgreSQL, Redis) and stateless OSDU microservices, with potentially multiple stacks side-by-side. Without workload isolation, all pods compete for the same nodes, and stateful workloads requiring premium storage or specific VM SKUs may be scheduled on inadequate nodes.

## Decision Drivers

- Elasticsearch and PostgreSQL require premium storage-capable VMs for persistent volumes
- Stateful middleware benefits from larger VMs (D4/D8) while OSDU services have lighter per-pod requirements
- Side-by-side stacks must not cross-schedule pods onto each other's nodes
- Karpenter NodePools support taints, labels, and VM SKU requirements for workload targeting
- Cost control: consolidation policies should reclaim underutilized nodes

## Considered Options

- Single system node pool for all workloads (AKS Automatic default)
- Static node pools with fixed VM sizes
- Karpenter NodePools with per-workload-class isolation

## Decision Outcome

Chosen option: "Karpenter NodePools with per-workload-class isolation", because it combines dynamic scaling with workload-appropriate VM selection and taint-based isolation between stacks.

### NodePool Layout

Each stack creates two NodePools:

| NodePool | Purpose | VM Family | Premium Storage | Taint |
|---|---|---|---|---|
| `platform` / `platform-{id}` | Middleware (Elasticsearch, PostgreSQL, Redis) | D-series, 4-8 vCPU | Required | `workload=platform:NoSchedule` |
| `osdu` / `osdu-{id}` | OSDU microservices | D-series, 4-8 vCPU, >15 GiB memory | Required | `workload=osdu:NoSchedule` |

Pods target their NodePool via `nodeSelector` on the `agentpool` label and a matching toleration for the `workload` taint.

### Consolidation

Both NodePools use `WhenEmptyOrUnderutilized` consolidation with a 5-minute delay, allowing Karpenter to reclaim nodes when workloads scale down.

### Consequences

- Good, because stateful middleware gets premium storage-capable VMs automatically
- Good, because OSDU service pods are isolated from middleware node disruption
- Good, because per-stack NodePools prevent cross-scheduling in side-by-side deployments
- Good, because Karpenter dynamically selects the cheapest VM SKU meeting requirements
- Bad, because NodePool isolation can lead to more nodes than a shared pool (less bin-packing)
- Bad, because agentpool label values cannot contain hyphens (AKS Karpenter restriction), requiring label/name divergence for stacks with hyphenated IDs
