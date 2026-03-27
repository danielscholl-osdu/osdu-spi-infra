# cert-manager Kustomize Patches

This directory contains Kustomize patches for the cert-manager Helm chart to enable compatibility with AKS Automatic Deployment Safeguards.

## Problem

The cert-manager Helm chart (v1.17.0 - v1.19.2) does not expose probe configuration for the cainjector component. AKS Automatic clusters require all containers to have both `livenessProbe` and `readinessProbe` configured, causing deployment failures.

## Solution

We use Helm's postrender feature to apply Kustomize patches after Helm renders the templates but before deploying to Kubernetes.

### Files

- **kustomization.yaml**: Main Kustomize configuration that references the patch
- **cainjector-probes.yaml**: Strategic merge patch that adds probes to the cainjector deployment
- **../postrender-cert-manager.sh**: Postrender script that applies these patches

### How It Works

1. Helm renders the cert-manager chart templates
2. The postrender script (`postrender-cert-manager.sh`) receives the rendered manifests via stdin
3. The script saves the manifests as `all.yaml` in this directory
4. `kubectl kustomize` applies the patches defined in `kustomization.yaml`
5. The patched manifests are output to stdout and deployed by Helm

### Probe Configuration

The cainjector component does not expose an HTTP healthz endpoint, only metrics on port 9402. We use tcpSocket probes on this port:

```yaml
livenessProbe:
  tcpSocket:
    port: 9402
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
  successThreshold: 1

readinessProbe:
  tcpSocket:
    port: 9402
  initialDelaySeconds: 10
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 3
  successThreshold: 1
```

## References

- [cert-manager issue #5626](https://github.com/cert-manager/cert-manager/issues/5626) - Upstream feature request
- [Helm postrender documentation](https://helm.sh/docs/topics/advanced/#post-rendering)
- [AKS Deployment Safeguards](https://learn.microsoft.com/en-us/azure/aks/deployment-safeguards)
