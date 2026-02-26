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
| Prometheus Alert Rule | `Microsoft.AlertsManagement/prometheusRuleGroups` | Once per RG | Fires when CPU exceeds threshold for 3+ min |
| Prometheus Alert Rule | `Microsoft.AlertsManagement/prometheusRuleGroups` | Once per RG | Fires when memory exceeds threshold for 5+ min |
| Prometheus Alert Rule | `Microsoft.AlertsManagement/prometheusRuleGroups` | Once per RG | Fires when disk exceeds threshold for 5+ min |
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
- The `connectedmachine` Azure CLI extension (auto-installs on first use, or run `az extension add --name connectedmachine`)
- One or more Azure Arc-enabled Windows servers in the target resource group
- **Contributor** role on the target resource group

## Quick start

### Option 1: Deploy directly from GitHub (no clone needed)

Run this in **Azure CloudShell (Bash)** to auto-discover all Windows Arc servers in a resource group and deploy:

> **Note:** The `az connectedmachine` command may prompt to install the `connectedmachine` extension on first use. Type `Y` to continue.

```bash
rg="<your-resource-group>"

servers=$(az connectedmachine list \
  --resource-group $rg \
  --query "[?osType=='windows'].name" -o json)

az deployment group create \
  --resource-group $rg \
  --template-uri "https://raw.githubusercontent.com/SpiffLab/arc-vminsights-otel-metrics-at-scale/master/main.json" \
  --parameters arcServerNames="$servers" enableAdditionalMetrics=true
```

This auto-discovers all Windows Arc servers (filtering out Linux by `osType`), deploys OTel metrics collection **and** enables the CPU, memory, and disk alert rules.

> **PowerShell users:** The JSON array from `az connectedmachine list` may lose quotes when passed as a parameter. Use this approach instead:
> ```powershell
> $rg = "<your-resource-group>"
> $servers = (az connectedmachine list --resource-group $rg --query "[?osType=='windows'].name" -o tsv) -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
> $serverArray = "['" + ($servers -join "','") + "']"
> az deployment group create --resource-group $rg --template-file main.bicep --parameters arcServerNames="$serverArray" enableAdditionalMetrics=true
> ```

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

3. **Deploy** (with alerts enabled)
   ```bash
   az deployment group create \
     --resource-group <your-resource-group> \
     --template-file main.bicep \
     --parameters main.bicepparam \
     --parameters enableAdditionalMetrics=true
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
| `enableCpuAlert` | bool | `true` | Enable Prometheus CPU utilization alert rule |
| `cpuAlertThreshold` | string | `'0.70'` | CPU threshold (0–1 ratio, e.g. 0.70 = 70%) |
| `cpuAlertDuration` | string | `'PT3M'` | Duration CPU must exceed threshold before firing |
| `cpuAlertSeverity` | int | `2` | Alert severity (0=Critical … 4=Verbose) |
| `enableMemoryAlert` | bool | `true` | Enable Prometheus memory utilization alert rule |
| `memoryAlertThreshold` | string | `'0.90'` | Memory threshold (0–1 ratio, e.g. 0.90 = 90%) |
| `memoryAlertDuration` | string | `'PT5M'` | Duration memory must exceed threshold before firing |
| `memoryAlertSeverity` | int | `2` | Memory alert severity (0=Critical … 4=Verbose) |
| `enableDiskAlert` | bool | `true` | Enable Prometheus disk utilization alert rule |
| `diskAlertThreshold` | string | `'0.90'` | Disk threshold (0–1 ratio, e.g. 0.90 = 90%) |
| `diskAlertDuration` | string | `'PT5M'` | Duration disk must exceed threshold before firing |
| `diskAlertSeverity` | int | `1` | Disk alert severity (0=Critical … 4=Verbose) |
| `tags` | object | `{}` | Tags applied to all resources |

## Deployment behavior

- **Shared resources** (Azure Monitor Workspace, DCR, alert rules) are deployed **once** per resource group.
- **Per-server resources** (AMA extension, DCR association) are deployed in a loop with `@batchSize(5)` for controlled rollout.
- The template is **idempotent** — re-running it with additional servers in the array will onboard only the new servers.

## Alert rules

When `enableAdditionalMetrics = true`, the template deploys three Prometheus alert rules:

| Alert | Metric | Default Threshold | Default Duration | Severity |
|-------|--------|--------------------|------------------|----------|
| **HighCpuUtilization** | `system_cpu_utilization` | 70% | 3 minutes | Warning (2) |
| **HighMemoryUtilization** | `system_memory_utilization` | 90% | 5 minutes | Warning (2) |
| **HighDiskUtilization** | `system_filesystem_utilization` | 90% | 5 minutes | Error (1) |

All alerts:
- Evaluate **per host** (`host_name` label) so you know which server is affected
- **Auto-resolve** once the condition clears (CPU/memory: 5 min, disk: 10 min)
- Can be connected to an **Action Group** in the Azure portal for email, SMS, or webhook notifications

The disk alert additionally groups by **`mountpoint`** so you can identify which drive is filling up. Its default severity is **Error (1)** since full disks can cause outages.

> **Note:** Alert rules require `enableAdditionalMetrics = true` since `system.cpu.utilization`, `system.memory.utilization`, and `system.filesystem.utilization` are additional metrics.

## Viewing metrics

OTel metrics are stored in the **Azure Monitor Workspace**, not on the individual Arc server resources. To view them:

1. In the Azure portal, navigate to **Azure Monitor → Azure Monitor Workspaces → `amw-vminsights-otel`**
2. Select **Metrics** to open Metrics Explorer with PromQL support
3. Query metrics like `system_cpu_utilization` or `system_memory_utilization`, filtering by `host_name`

Alternatively, go to **Azure Arc → Servers → [your server] → Monitoring → Insights** to see the VM Insights dashboards.

> **Important:** Do **not** look for OTel metrics by scoping to the Arc server resources in Metrics Explorer — they won't appear there. Always scope to the **Azure Monitor Workspace**.

## Viewing alert rules

Prometheus alert rules appear in a specific location in the portal:

1. Navigate to **Azure Monitor → Alerts → Alert rules**
2. Filter by your resource group
3. Set **Signal type** to **Prometheus** — these rules won't show if filtered to "Metric" or "Log"

You can also verify deployed rules via CLI:

```bash
az resource list \
  --resource-group <your-resource-group> \
  --resource-type "Microsoft.AlertsManagement/prometheusRuleGroups" \
  -o table
```

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| `az connectedmachine` prompts to install extension | First-time use of the CLI extension | Type `Y` or pre-install with `az extension add --name connectedmachine` |
| Server list is empty | `osType` filter is case-sensitive | Use lowercase `'windows'` (not `'Windows'`) |
| JSON parse error with `--parameters` in PowerShell | PowerShell strips quotes from JSON arrays | Use the TSV + string-building approach shown in the Quick Start |
| Metrics not visible on Arc server blade | OTel metrics go to Azure Monitor Workspace, not the server | Scope to the Azure Monitor Workspace in Metrics Explorer |
| Alert rules missing in portal | Portal defaults to "Metric" signal type | Change signal type filter to "Prometheus" |
| Charts stuck loading in VM Insights | Network traffic to `monitor.azure.com` is blocked | Disable ad blockers or allowlist `monitor.azure.com` |

## References

- [VM Insights OpenTelemetry — Microsoft Learn](https://learn.microsoft.com/en-us/azure/azure-monitor/vm/vminsights-opentelemetry)
- [Azure Monitor Agent on Arc-enabled servers](https://learn.microsoft.com/en-us/azure/azure-arc/servers/azure-monitor-agent-deployment)
- [Data Collection Rules overview](https://learn.microsoft.com/en-us/azure/azure-monitor/data-collection/data-collection-rule-overview)
- [Comprehensive VM Monitoring with OTel Performance Counters](https://techcommunity.microsoft.com/blog/azureobservabilityblog/comprehensive-vm-monitoring-with-opentelemetry-performance-counters/4470122)

## License

MIT
