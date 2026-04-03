---
title: Troubleshooting
description: Common issues and diagnostic steps
---

## Deployment Issues

### Safeguards Gate Timeout

**Symptom:** `post-provision.ps1` hangs waiting for Deployment Safeguards readiness.

**Cause:** Azure Policy/Gatekeeper is eventually consistent. Fresh clusters can take several minutes before ValidatingAdmissionPolicies are reconciled.

**Resolution:** Wait up to 10 minutes. If it persists, verify the cluster is running:

```bash
az aks show -g <rg> -n <cluster> --query powerState
kubectl get validatingadmissionpolicies
```

### Terraform State Conflicts

**Symptom:** `terraform apply` fails with state lock errors.

**Cause:** A previous run was interrupted, leaving the state lock.

**Resolution:** Each layer has independent state — identify which layer failed:

```bash
# Check which layer has the lock
cd infra && terraform force-unlock <lock-id>
# or
cd software/foundation && terraform force-unlock <lock-id>
# or
cd software/spi-stack && terraform force-unlock <lock-id>
```

## Pod Issues

### CrashLoopBackOff on OSDU Services

**Symptom:** Pod enters CrashLoopBackOff shortly after creation.

**Common causes:**

1. **Wrong probe port** — the service uses a different health endpoint than the default (8081). Check [ADR-0005](/osdu-spi-infra/decisions/0005-per-service-health-probe-configuration/) for the probe matrix.

   ```bash
   kubectl describe pod <name> -n osdu | grep -A5 "Liveness"
   kubectl logs <name> -n osdu | grep "started on port"
   ```

2. **Missing ConfigMap values** — the service can't connect to Azure PaaS resources.

   ```bash
   kubectl get configmap -n osdu
   kubectl describe pod <name> -n osdu | grep -A5 "Environment"
   ```

3. **Workload Identity not ready** — the federated credential hasn't propagated.

   ```bash
   kubectl describe pod <name> -n osdu | grep -A3 "azure.workload.identity"
   ```

### Istio Sidecar Not Injected

**Symptom:** Pods have 1 container instead of 2 (missing `istio-proxy`).

**Resolution:**

1. Verify namespace labels:
   ```bash
   kubectl get namespace osdu --show-labels | grep istio
   ```

2. Verify CNI chaining is enabled:
   ```bash
   kubectl get daemonset -n aks-istio-system | grep cni
   ```

3. Restart pods to pick up sidecar:
   ```bash
   kubectl rollout restart deployment -n osdu
   ```

### Deployment Safeguards Rejection

**Symptom:** Pod creation fails with `admission webhook denied the request`.

**Resolution:** Check which policy is blocking:

```bash
kubectl get events -n osdu --field-selector reason=FailedCreate
```

Common violations:
- Missing `seccompProfile` — ensure the Helm chart sets `RuntimeDefault`
- Missing resource limits — all containers must have `requests` and `limits`
- Running as root — `runAsNonRoot: true` must be set

## Middleware Issues

### Elasticsearch Cluster Health Yellow/Red

```bash
# Check cluster health
kubectl exec -n platform elasticsearch-es-default-0 -- \
  curl -s -k https://localhost:9200/_cluster/health | jq

# Check unassigned shards
kubectl exec -n platform elasticsearch-es-default-0 -- \
  curl -s -k https://localhost:9200/_cat/shards?v | grep UNASSIGNED
```

### Redis Connection Refused

Verify Redis TLS is enabled and the client is connecting with TLS:

```bash
kubectl exec -n platform redis-master-0 -- redis-cli --tls ping
```

### PostgreSQL (CNPG) Not Ready

```bash
# Check cluster status
kubectl get cluster -n platform
kubectl describe cluster postgresql -n platform
```

## Connectivity Issues

### Services Can't Reach Azure PaaS

Verify Workload Identity:

```bash
# Check service account annotation
kubectl get sa -n osdu -o yaml | grep azure.workload.identity

# Check pod identity injection
kubectl get pod <name> -n osdu -o jsonpath='{.spec.containers[0].env}' | jq
```

### DNS Resolution Failures

```bash
# Check ExternalDNS is running
kubectl get pods -n foundation | grep external-dns

# Check DNS records
kubectl logs -n foundation deployment/external-dns | grep "Desired"
```
