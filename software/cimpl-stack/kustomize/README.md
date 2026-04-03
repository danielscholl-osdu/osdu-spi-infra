# OSDU Service Postrender Framework

This directory provides a shared Helm postrender + Kustomize framework to make OSDU service charts compliant with AKS Automatic safeguards (probes, resources, seccomp, security context, topology spread).

## How it works
1. Helm renders the service chart.
2. The postrender script (`postrender.sh`) receives the manifests via stdin.
3. The script writes Helm output to `all.yaml`, injects shared components, and applies the service overlay with `kubectl kustomize`.

## Components
- **components/seccomp**: Adds `seccompProfile: RuntimeDefault` to Deployments/StatefulSets.
- **components/security-context**: Enforces `runAsNonRoot`, `allowPrivilegeEscalation: false`, and drops all capabilities.
- **components/topology-spread**: Adds zone + hostname topology spread constraints using the Helm release name.

## Service overlays
Each service has an overlay under `services/<service-name>/`:
- `kustomization.yaml` includes `all.yaml`, shared components, and service patches.
- `probes.yaml` and `resources.yaml` add required probes and resource requests/limits.

## Adding a new service
1. Copy `services/partition/` to `services/<service>/`.
2. Update `probes.yaml` and `resources.yaml` for the service endpoints and sizing.
3. Ensure `kustomization.yaml` references the shared components.
4. In the Helm release, set postrender to:
   - `binary_path = "/usr/bin/env"`
   - `args = ["SERVICE_NAME=<service>", "${path.module}/kustomize/postrender.sh"]`

This ensures the shared compliance patches are applied consistently across all OSDU services.
