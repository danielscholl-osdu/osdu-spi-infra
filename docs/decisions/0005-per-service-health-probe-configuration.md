---
status: accepted
contact: danielscholl
date: 2026-04-01
deciders: danielscholl
---

# Per-Service Health Probe Configuration for OSDU Services

## Context and Problem Statement

OSDU services are Spring Boot applications, but they are not uniform in how they expose health endpoints. Most core services (partition, entitlements, legal, schema, storage, search, indexer) run the Spring Boot management actuator on a separate port (8081) from the main application (8080). However, some reference services (unit, crs-conversion) use Tomcat on a single port (8080) with no separate management port, while others (crs-catalog) use Jetty on port 8081. A single default probe configuration causes liveness probe failures and CrashLoopBackOff for services that don't match the assumed port.

## Decision Drivers

- OSDU community services are maintained by different teams and have inconsistent embedded server configurations
- AKS Deployment Safeguards require all pods to have liveness and readiness probes
- Probe failures on the wrong port manifest as "connection refused" — the container runs but Kubernetes kills it
- The actuator path depends on whether `SERVER_SERVLET_CONTEXTPATH` is applied to management endpoints

## Considered Options

- Single default probe configuration for all services (port 8081, path `/actuator/health`)
- Per-service probe overrides in Terraform where needed
- Force all services to a common port via environment variable (`MANAGEMENT_SERVER_PORT=8081`)

## Decision Outcome

Chosen option: "Per-service probe overrides", because the probe port and path are determined by the upstream OSDU container image, which we do not control. Overriding via environment variables may not work for all services and creates a fragile coupling to Spring Boot internals.

### Consequences

- Good, because each service gets probes that match its actual health endpoint
- Good, because the default (port 8081, `/actuator/health`) works for the majority of services
- Good, because probe configuration is explicit and visible in the Terraform service definition
- Bad, because new services require investigation to determine the correct probe port/path
- Bad, because upstream image changes could silently break probe configuration

### Known Service Probe Matrix

| Service | Server | Probe Port | Probe Path | Notes |
|---|---|---|---|---|
| partition, entitlements, legal, schema, storage, search, indexer, indexer-queue, file, workflow | Tomcat | 8081 | `/actuator/health` | Separate management port (default) |
| crs-catalog | Jetty | 8081 | `/actuator/health` | Jetty on 8081, matches default |
| unit | Tomcat | 8080 | `/api/unit/actuator/health` | Single port, actuator under context path |
| crs-conversion | Tomcat | 8080 | `/api/crs/converter/actuator/health` | Single port, actuator under context path |

### Diagnostic Steps for New Services

1. Deploy the service with default probes
2. If pod enters CrashLoopBackOff, check events: `kubectl describe pod <name> -n osdu`
3. Look for "connection refused" on probe port — indicates wrong port
4. Check container logs for the startup line: `Tomcat started on port XXXX` or `Jetty started on port XXXX`
5. Override probes in the Terraform module accordingly
