---
title: Quick Start
description: Deploy OSDU SPI Infrastructure in minutes
---

## Deploy

```bash
# 1. Clone the repository
git clone https://github.com/danielscholl-osdu/osdu-spi-infra.git
cd osdu-spi-infra

# 2. Authenticate
az login
azd auth login

# 3. Deploy (prompts for environment name, subscription, and location)
azd up
```

## What happens during `azd up`

The deployment runs through four phases, orchestrated by Azure Developer CLI lifecycle hooks:

| Phase | Hook | Script | What it does |
|---|---|---|---|
| Pre-provision | `preprovision` | `pre-provision.ps1` | Validates tools, auto-detects settings, generates credentials |
| Provision | — | `infra/` | Creates AKS cluster + Azure PaaS resources (~15 min) |
| Post-provision | `postprovision` | `post-provision.ps1` | Bootstraps RBAC, waits for safeguards, deploys foundation operators |
| Pre-deploy | `predeploy` | `pre-deploy.ps1` | Deploys stack: middleware + OSDU services (~5 min) |

## Verify

After deployment completes:

```bash
# Check cluster access
kubectl get nodes

# Check OSDU services are running
kubectl get pods -n osdu

# Check middleware
kubectl get pods -n platform
```

## Teardown

```bash
azd down --force --purge
```

This runs teardown hooks in reverse order: stack, foundation, then infrastructure.
