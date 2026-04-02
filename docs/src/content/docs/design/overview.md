---
title: Design Overview
description: Architecture and design of the OSDU SPI Infrastructure platform
---

The OSDU SPI Infrastructure deploys on AKS Automatic across three independent layers: **infrastructure**, **foundation operators**, and **application stacks**, each with its own Terraform state and lifecycle.

Infrastructure evolves without redeploying services, operators upgrade independently, and multiple OSDU stacks share the same foundation safely. Upstream Helm charts stay unforked through a local chart with baked-in compliance.

## Design Topics

### [Deployment Model](../design/deployment-model/)

How three layers, implemented through four Terraform states, enable independent lifecycle management and multi-stack isolation.

### [Infrastructure](../design/infrastructure/)

The Azure and AKS foundation: cluster provisioning, PaaS resources, networking, and identity.

### [Platform Services](../design/platform-services/)

The in-cluster middleware layer that OSDU depends on: Elasticsearch, Redis, PostgreSQL, and Airflow.

### [Service Architecture](../design/service-architecture/)

How OSDU services are packaged using a local Helm chart, deployed via a reusable Terraform module, and controlled with feature flags.

### [Traffic & Routing](../design/traffic-routing/)

How requests reach services: Gateway API ingress, DNS, TLS, Istio mesh, and async messaging via Service Bus.

### [Security](../design/security/)

The security model from cluster to pod: AKS Deployment Safeguards, Istio mTLS, Workload Identity, and pod security standards.
