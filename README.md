# Arc VMInsights OTel Metrics @ Scale

Deploy **VM Insights with OpenTelemetry** metrics collection to Azure Arc-enabled Windows servers using Bicep.

## What it deploys

| Resource | Type | Purpose |
|----------|------|---------|
| Azure Monitor Workspace | `Microsoft.Monitor/accounts` | Cost-efficient OTel metrics storage |
| Data Collection Rule | `Microsoft.Insights/dataCollectionRules` | Configures OTel performance counter collection |
| Azure Monitor Agent | `Microsoft.HybridCompute/machines/extensions` | Collects telemetry from the Arc server |
| DCR Association | `Microsoft.Insights/dataCollectionRuleAssociations` | Links DCR to the Arc server |

## Default metrics (free)

- `system.uptime` — Time since last reboot
- `system.cpu.time` — Total CPU time consumed
- `system.memory.usage` — Memory in use (bytes)
- `system.network.io` — Bytes transmitted/received
- `system.network.dropped` / `system.network.errors` — Network issues
- `system.disk.io` / `system.disk.operations` / `system.disk.operation_time` — Disk activity
- `system.filesystem.usage` — Filesystem usage in bytes

## Additional metrics (optional, extra cost)

Set `enableAdditionalMetrics = true` to collect extended system and per-process metrics including:

- CPU utilization, logical CPU count
- Memory utilization and limits
- Filesystem utilization
- Per-process CPU, memory, disk I/O, threads, and handles (Windows)

See the full list in [Microsoft's documentation](https://learn.microsoft.com/en-us/azure/azure-monitor/vm/vminsights-opentelemetry).

## Prerequisites

- Azure CLI with Bicep support
- An existing Azure Arc-enabled Windows server
- Contributor role on the target resource group

## Quick start

1. **Clone the repo**
   ```bash
   git clone https://github.com/<your-username>/arc-vminsights-otel-metrics-at-scale.git
   cd arc-vminsights-otel-metrics-at-scale
   ```

2. **Edit parameters**
   ```bash
   # Update main.bicepparam with your Arc server name
   ```

3. **Deploy**
   ```bash
   az deployment group create \
     --resource-group <your-resource-group> \
     --template-file main.bicep \
     --parameters main.bicepparam
   ```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | Resource group location | Azure region |
| `arcServerName` | string | *(required)* | Name of the Arc-enabled server |
| `azureMonitorWorkspaceName` | string | `amw-vminsights-otel` | Monitor workspace name |
| `dcrName` | string | `MSVMI-otel-<server>` | Data Collection Rule name |
| `samplingFrequencyInSeconds` | int | `60` | Metric polling interval (10–300s) |
| `enableAdditionalMetrics` | bool | `false` | Enable extended per-process metrics |
| `tags` | object | `{}` | Tags for all resources |

## References

- [VM Insights OpenTelemetry — Microsoft Learn](https://learn.microsoft.com/en-us/azure/azure-monitor/vm/vminsights-opentelemetry)
- [Azure Monitor Agent on Arc-enabled servers](https://learn.microsoft.com/en-us/azure/azure-arc/servers/azure-monitor-agent-deployment)
- [Data Collection Rules overview](https://learn.microsoft.com/en-us/azure/azure-monitor/data-collection/data-collection-rule-overview)

## License

MIT
