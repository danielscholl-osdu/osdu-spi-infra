---
title: Prerequisites
description: Tools and Azure requirements for deploying OSDU SPI Infrastructure
---

## Azure Requirements

- An Azure subscription with [Contributor](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/privileged#contributor) and [User Access Administrator](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/privileged#user-access-administrator) roles
- (Optional) An [Azure DNS zone](https://learn.microsoft.com/en-us/azure/dns/dns-getstarted-portal) for external ingress with TLS

## Required Tools

| Tool | Version | Purpose |
|---|---|---|
| [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (`az`) | Latest | Azure resource management |
| [Azure Developer CLI](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd) (`azd`) | Latest | Deployment orchestration |
| [Terraform](https://developer.hashicorp.com/terraform/downloads) | >= 1.12 | Infrastructure as Code |
| [Helm](https://helm.sh/docs/intro/install/) | >= 3.x | Kubernetes package management |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | Latest | Kubernetes CLI |
| [kubelogin](https://github.com/Azure/kubelogin) | Latest | Azure AD auth for AKS |
| [PowerShell](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell) (`pwsh`) | >= 7.4 | Lifecycle hook scripts |

## Verification

Confirm all tools are installed and you are authenticated:

```bash
# Check tool versions
az version
azd version
terraform version
helm version
kubectl version --client
pwsh --version

# Authenticate
az login
azd auth login
```

## Feature Flags (One-Time)

If using Istio CNI chaining (required for sidecar injection on AKS Automatic), register the preview feature flag:

```bash
az feature register --namespace Microsoft.ContainerService --name IstioCNIPreview
az provider register -n Microsoft.ContainerService
```

This is a one-time operation per Azure subscription.
