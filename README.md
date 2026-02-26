# Arc VMInsights OTel Metrics @ Scale

Deploy **VM Insights with OpenTelemetry** metrics collection to multiple Azure Arc-enabled Windows servers in a resource group using Bicep.

## Overview

This template enables the new OpenTelemetry-based VM Insights experience across all your Arc-enabled Windows servers at scale. It deploys shared monitoring infrastructure once (Azure Monitor Workspace + Data Collection Rule) and loops over your server list to install the Azure Monitor Agent and associate the DCR with each server.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Resource Group                                     │
│                                                     │
│  ┌─────────────────────┐  ┌──────────────────────┐  │
│  │ Azure Monitor        │  │ Data Collection Rule │  │
│  │ Workspace (OTel)     │◄─│ (OTel perf counters) │  │
│  └─────────────────────┘  └──────────┬───────────┘  │
│                                      │ DCR Assoc.   │
│          ┌───────────────────────────┼───────┐      │
│          │                           │       │      │
│  ┌───────▼───────┐  ┌───────────────▼┐  ┌───▼───┐  │
│  │ Arc Server 1  │  │ Arc Server 2   │  │  ...  │  │
│  │ + AMA Agent   │  │ + AMA Agent    │  │       │  │
│  └───────────────┘  └────────────────┘  └───────┘  │
└─────────────────────────────────────────────────────┘
```

## What it deploys

| Resource | Type | Scope | Purpose |
|----------|------|-------|---------|
| Azure Monitor Workspace | `Microsoft.Monitor/accounts` | Once per RG | Cost-efficient OTel metrics storage |
| Data Collection Rule | `Microsoft.Insights/dataCollectionRules` | Once per RG | Configures OTel performance counter collection |
| Azure Monitor Agent | `Microsoft.HybridCompute/machines/extensions` | Per server | Collects telemetry from each Arc server |
| DCR Association | `Microsoft.Insights/dataCollectionRuleAssociations` | Per server | Links DCR to each Arc server |

## Default metrics (free)

| Metric | Description |
|--------|-------------|
| `system.uptime` | Time since last reboot |
| `system.cpu.time` | Total CPU time consumed |
| `system.memory.usage` | Memory in use (bytes) |
| `system.network.io` | Bytes transmitted/received |
| `system.network.dropped` | Dropped packets |
| `system.network.errors` | Network errors |
| `system.disk.io` | Disk I/O (bytes read/written) |
| `system.disk.operations` | Disk operations (read/write counts) |
| `system.disk.operation_time` | Average disk operation time |
| `system.filesystem.usage` | Filesystem usage in bytes |

## Additional metrics (optional, extra cost)

Set `enableAdditionalMetrics = true` to collect extended system and per-process metrics including:

| Category | Metrics |
|----------|---------|
| CPU | `system.cpu.utilization`, `system.cpu.logical.count` |
| Memory | `system.memory.utilization`, `system.memory.limit` |
| Disk | `system.disk.io_time`, `system.disk.pending_operations` |
| Network | `system.network.packets`, `system.network.connections` |
| Per-process | `process.cpu.time`, `process.cpu.utilization`, `process.memory.usage`, `process.memory.virtual`, `process.memory.utilization`, `process.disk.io`, `process.disk.operations`, `process.threads`, `process.handles`, `process.uptime` |

See the full list in [Microsoft's documentation](https://learn.microsoft.com/en-us/azure/azure-monitor/vm/vminsights-opentelemetry).

## Prerequisites

- Azure CLI with Bicep support (`az bicep install`)
- One or more Azure Arc-enabled Windows servers in the target resource group
- **Contributor** role on the target resource group

## Quick start

### Option 1: Deploy directly from GitHub (no clone needed)

Run this in **Azure CloudShell (Bash)** to auto-discover all Windows Arc servers in a resource group and deploy:

```bash
rg="<your-resource-group>"

servers=$(az resource list \
  --resource-group $rg \
  --resource-type "Microsoft.HybridCompute/machines" \
  --query "[?properties.osType=='windows'].name" -o json)

az deployment group create \
  --resource-group $rg \
  --template-uri "https://raw.githubusercontent.com/SpiffLab/arc-vminsights-otel-metrics-at-scale/master/main.json" \
  --parameters arcServerNames="$servers"
```

### Option 2: Clone and customize

1. **Clone the repo**
   ```bash
   git clone https://github.com/SpiffLab/arc-vminsights-otel-metrics-at-scale.git
   cd arc-vminsights-otel-metrics-at-scale
   ```

2. **Edit parameters** — update `main.bicepparam` with your Arc server names:
   ```bicep
   param arcServerNames = [
     'SERVER-01'
     'SERVER-02'
     'SERVER-03'
   ]
   ```

3. **Deploy**
   ```bash
   az deployment group create \
     --resource-group <your-resource-group> \
     --template-file main.bicep \
     --parameters main.bicepparam
   ```

4. **Verify** — In the Azure portal, navigate to **Azure Arc → Servers → [your server] → Monitoring → Insights** to confirm OTel metrics are flowing.

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | Resource group location | Azure region for all resources |
| `arcServerNames` | string[] | *(required)* | List of Arc-enabled server names in the resource group |
| `azureMonitorWorkspaceName` | string | `amw-vminsights-otel` | Azure Monitor Workspace name |
| `dcrName` | string | `MSVMI-otel-<resource-group>` | Data Collection Rule name (auto-derived from RG) |
| `samplingFrequencyInSeconds` | int | `60` | Metric polling interval (10–300 seconds) |
| `enableAdditionalMetrics` | bool | `false` | Enable extended per-process metrics (extra cost) |
| `tags` | object | `{}` | Tags applied to all resources |

## Deployment behavior

- **Shared resources** (Azure Monitor Workspace, DCR) are deployed **once** per resource group.
- **Per-server resources** (AMA extension, DCR association) are deployed in a loop with `@batchSize(5)` for controlled rollout.
- The template is **idempotent** — re-running it with additional servers in the array will onboard only the new servers.

## References

- [VM Insights OpenTelemetry — Microsoft Learn](https://learn.microsoft.com/en-us/azure/azure-monitor/vm/vminsights-opentelemetry)
- [Azure Monitor Agent on Arc-enabled servers](https://learn.microsoft.com/en-us/azure/azure-arc/servers/azure-monitor-agent-deployment)
- [Data Collection Rules overview](https://learn.microsoft.com/en-us/azure/azure-monitor/data-collection/data-collection-rule-overview)
- [Comprehensive VM Monitoring with OTel Performance Counters](https://techcommunity.microsoft.com/blog/azureobservabilityblog/comprehensive-vm-monitoring-with-opentelemetry-performance-counters/4470122)

## License

MIT
