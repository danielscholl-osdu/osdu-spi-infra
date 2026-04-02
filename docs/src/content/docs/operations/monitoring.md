---
title: Monitoring
description: Observability stack for the OSDU SPI Infrastructure platform
---

The platform provides monitoring across three pillars: metrics, logs, and traces — all backed by Azure-managed services.

## Metrics (Prometheus + Grafana)

### Azure Monitor Workspace

AKS Automatic ships built-in Prometheus metrics collection via Azure Monitor Workspace. This captures:

- Kubernetes control plane metrics (API server, scheduler, etcd)
- Node-level metrics (CPU, memory, disk, network)
- Pod-level metrics (container resource usage)
- Istio mesh metrics (request volume, latency, error rate)

### Grafana

When enabled (`ENABLE_GRAFANA_WORKSPACE=true`), Azure Managed Grafana provides pre-built dashboards for:

- Cluster health and node utilization
- Pod resource consumption
- Istio service mesh traffic
- Karpenter node provisioning

:::tip
Disable Grafana (`azd env set ENABLE_GRAFANA_WORKSPACE false`) for dev/test environments to reduce costs. Prometheus metrics are still collected.
:::

## Logs (Container Insights)

### Log Analytics Workspace

Container Insights collects logs from all containers and forwards them to Log Analytics. Query logs via Azure Portal or `az monitor log-analytics query`:

```kusto
// Pod logs for a specific service
ContainerLogV2
| where PodNamespace == "osdu"
| where PodName startswith "partition"
| project TimeGenerated, LogMessage
| order by TimeGenerated desc
| take 100
```

### Common Log Queries

```kusto
// Services in CrashLoopBackOff
KubePodInventory
| where Namespace == "osdu"
| where PodStatus == "Failed"
| summarize count() by Name, PodStatus
```

```kusto
// OOM kills
ContainerLogV2
| where LogMessage contains "OOMKilled"
| project TimeGenerated, PodName, LogMessage
```

## Traces (Application Insights)

OSDU services emit distributed traces to Application Insights via the APPLICATIONINSIGHTS_CONNECTION_STRING environment variable. This enables:

- End-to-end request tracing across services
- Dependency maps showing service-to-service and service-to-PaaS calls
- Exception tracking and failure analysis
- Performance analysis (latency percentiles, throughput)

## Middleware Monitoring

### Elasticsearch

Kibana is optionally exposed via the gateway module. Access the Kibana dashboard to monitor:

- Cluster health (green/yellow/red)
- Index status and document counts
- Search query performance
- Shard allocation across nodes

### Airflow

The Airflow web UI is optionally exposed via the gateway module. Monitor:

- DAG execution status
- Task run history and durations
- Worker pod scheduling
