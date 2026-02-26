// =============================================================================
// VM Insights with OpenTelemetry for Azure Arc-enabled Windows Servers
// =============================================================================
// Deploys: Azure Monitor Workspace, Data Collection Rule (OTel), AMA extension,
//          and DCR association for Arc-enabled Windows servers in a resource group.
// =============================================================================

targetScope = 'resourceGroup'

// ---- Parameters ----

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Names of the existing Azure Arc-enabled servers in the resource group.')
@minLength(1)
param arcServerNames string[]

@description('Name of the Azure Monitor Workspace for OTel metrics.')
param azureMonitorWorkspaceName string = 'amw-vminsights-otel'

@description('Name of the Data Collection Rule.')
param dcrName string = 'MSVMI-otel-${resourceGroup().name}'

@description('Sampling frequency in seconds for OTel performance counters.')
@minValue(10)
@maxValue(300)
param samplingFrequencyInSeconds int = 60

@description('Tags to apply to all resources.')
param tags object = {}

@description('Enable additional per-process and extended metrics (incurs extra cost).')
param enableAdditionalMetrics bool = false

@description('Enable classic performance counter DCR for Log Analytics-based metric alerts.')
param enableClassicMetrics bool = false

@description('Name of the Log Analytics workspace for classic performance counters.')
param logAnalyticsWorkspaceName string = 'law-vminsights-${resourceGroup().name}'

@description('Enable CPU utilization alert rule (requires enableAdditionalMetrics = true).')
param enableCpuAlert bool = true

@description('CPU utilization threshold (0-1). Default 0.70 = 70%.')
param cpuAlertThreshold string = '0.70'

@description('Duration the CPU must exceed threshold before alerting (ISO 8601). Default PT3M = 3 minutes.')
param cpuAlertDuration string = 'PT3M'

@description('Alert severity (0 = Critical, 1 = Error, 2 = Warning, 3 = Informational, 4 = Verbose).')
@minValue(0)
@maxValue(4)
param cpuAlertSeverity int = 2

@description('Enable memory utilization alert rule (requires enableAdditionalMetrics = true).')
param enableMemoryAlert bool = true

@description('Memory utilization threshold (0-1). Default 0.90 = 90%.')
param memoryAlertThreshold string = '0.90'

@description('Duration memory must exceed threshold before alerting (ISO 8601). Default PT5M = 5 minutes.')
param memoryAlertDuration string = 'PT5M'

@description('Memory alert severity (0 = Critical, 1 = Error, 2 = Warning, 3 = Informational, 4 = Verbose).')
@minValue(0)
@maxValue(4)
param memoryAlertSeverity int = 2

@description('Enable disk utilization alert rule (requires enableAdditionalMetrics = true).')
param enableDiskAlert bool = true

@description('Disk utilization threshold (0-1). Default 0.90 = 90%.')
param diskAlertThreshold string = '0.90'

@description('Duration disk must exceed threshold before alerting (ISO 8601). Default PT5M = 5 minutes.')
param diskAlertDuration string = 'PT5M'

@description('Disk alert severity (0 = Critical, 1 = Error, 2 = Warning, 3 = Informational, 4 = Verbose).')
@minValue(0)
@maxValue(4)
param diskAlertSeverity int = 1

// ---- Variables ----

var defaultCounterSpecifiers = [
  'system.uptime'
  'system.cpu.time'
  'system.memory.usage'
  'system.network.io'
  'system.network.dropped'
  'system.network.errors'
  'system.disk.io'
  'system.disk.operations'
  'system.disk.operation_time'
  'system.filesystem.usage'
]

var additionalCounterSpecifiers = [
  'system.cpu.utilization'
  'system.cpu.logical.count'
  'system.memory.utilization'
  'system.memory.limit'
  'system.filesystem.utilization'
  'system.disk.io_time'
  'system.disk.pending_operations'
  'system.network.packets'
  'system.network.connections'
  'process.uptime'
  'process.cpu.time'
  'process.cpu.utilization'
  'process.memory.usage'
  'process.memory.virtual'
  'process.memory.utilization'
  'process.disk.io'
  'process.disk.operations'
  'process.threads'
  'process.handles'
]

var counterSpecifiers = enableAdditionalMetrics
  ? concat(defaultCounterSpecifiers, additionalCounterSpecifiers)
  : defaultCounterSpecifiers

// ---- Azure Monitor Workspace ----

resource azureMonitorWorkspace 'Microsoft.Monitor/accounts@2023-04-03' = {
  name: azureMonitorWorkspaceName
  location: location
  tags: tags
}

// ---- Data Collection Rule (OpenTelemetry) ----

resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2024-03-11' = {
  name: dcrName
  location: location
  tags: tags
  properties: {
    description: 'DCR for VM Insights OpenTelemetry metrics on Arc-enabled Windows server'
    dataSources: {
      performanceCountersOTel: [
        {
          name: 'OtelDataSource'
          streams: [
            'Microsoft-OtelPerfMetrics'
          ]
          samplingFrequencyInSeconds: samplingFrequencyInSeconds
          counterSpecifiers: counterSpecifiers
        }
      ]
    }
    destinations: {
      monitoringAccounts: [
        {
          accountResourceId: azureMonitorWorkspace.id
          name: 'MonitoringAccountDestination'
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-OtelPerfMetrics'
        ]
        destinations: [
          'MonitoringAccountDestination'
        ]
      }
    ]
  }
}

// ---- Log Analytics Workspace (for classic metric alerts) ----

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (enableClassicMetrics) {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// ---- Data Collection Rule (Classic Performance Counters) ----

resource classicDataCollectionRule 'Microsoft.Insights/dataCollectionRules@2024-03-11' = if (enableClassicMetrics) {
  name: 'MSVMI-perf-${resourceGroup().name}'
  location: location
  tags: tags
  properties: {
    description: 'DCR for Windows performance counters sent to Log Analytics and Azure Monitor Metrics'
    dataSources: {
      performanceCounters: [
        {
          name: 'WindowsPerfCounters'
          streams: [
            'Microsoft-Perf'
            'Microsoft-InsightsMetrics'
          ]
          samplingFrequencyInSeconds: samplingFrequencyInSeconds
          counterSpecifiers: [
            '\\Processor(_Total)\\% Processor Time'
            '\\Memory\\% Committed Bytes In Use'
            '\\Memory\\Available MBytes'
            '\\LogicalDisk(_Total)\\% Free Space'
            '\\LogicalDisk(_Total)\\Free Megabytes'
            '\\LogicalDisk(_Total)\\Disk Reads/sec'
            '\\LogicalDisk(_Total)\\Disk Writes/sec'
            '\\LogicalDisk(_Total)\\Disk Transfers/sec'
            '\\Network Interface(*)\\Bytes Total/sec'
            '\\Network Interface(*)\\Bytes Sent/sec'
            '\\Network Interface(*)\\Bytes Received/sec'
            '\\System\\Processor Queue Length'
            '\\Process(_Total)\\Thread Count'
            '\\Process(_Total)\\Handle Count'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: enableClassicMetrics ? logAnalyticsWorkspace.id : ''
          name: 'LogAnalyticsDestination'
        }
      ]
      azureMonitorMetrics: {
        name: 'AzureMonitorMetricsDestination'
      }
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-Perf'
        ]
        destinations: [
          'LogAnalyticsDestination'
        ]
      }
      {
        streams: [
          'Microsoft-InsightsMetrics'
        ]
        destinations: [
          'AzureMonitorMetricsDestination'
        ]
      }
    ]
  }
}

// ---- Per-Server Resources (AMA Extension + DCR Association) ----

@batchSize(5)
resource arcServers 'Microsoft.HybridCompute/machines@2024-07-10' existing = [
  for name in arcServerNames: {
    name: name
  }
]

resource amaExtensions 'Microsoft.HybridCompute/machines/extensions@2024-07-10' = [
  for (name, i) in arcServerNames: {
    parent: arcServers[i]
    name: 'AzureMonitorWindowsAgent'
    location: location
    tags: tags
    properties: {
      publisher: 'Microsoft.Azure.Monitor'
      type: 'AzureMonitorWindowsAgent'
      autoUpgradeMinorVersion: true
      enableAutomaticUpgrade: true
    }
  }
]

resource dcrAssociations 'Microsoft.Insights/dataCollectionRuleAssociations@2024-03-11' = [
  for (name, i) in arcServerNames: {
    name: 'VMInsightsOTelAssociation'
    scope: arcServers[i]
    properties: {
      dataCollectionRuleId: dataCollectionRule.id
      description: 'Association of VM Insights OTel DCR with Arc-enabled server ${name}'
    }
    dependsOn: [
      amaExtensions[i]
    ]
  }
]

resource classicDcrAssociations 'Microsoft.Insights/dataCollectionRuleAssociations@2024-03-11' = [
  for (name, i) in arcServerNames: if (enableClassicMetrics) {
    name: 'VMInsightsPerfAssociation'
    scope: arcServers[i]
    properties: {
      dataCollectionRuleId: classicDataCollectionRule.id
      description: 'Association of classic perf counter DCR with Arc-enabled server ${name}'
    }
    dependsOn: [
      amaExtensions[i]
    ]
  }
]

// ---- Prometheus Alert Rule (CPU Utilization) ----

resource cpuAlertRuleGroup 'Microsoft.AlertsManagement/prometheusRuleGroups@2023-03-01' = if (enableCpuAlert && enableAdditionalMetrics) {
  name: 'CPU-High-Utilization-${resourceGroup().name}'
  location: location
  tags: tags
  properties: {
    description: 'Alert when CPU utilization exceeds ${cpuAlertThreshold} for ${cpuAlertDuration}'
    enabled: true
    interval: 'PT1M'
    scopes: [
      azureMonitorWorkspace.id
    ]
    rules: [
      {
        alert: 'HighCpuUtilization'
        expression: 'avg by (host_name) (avg_over_time(system_cpu_utilization[3m])) > ${cpuAlertThreshold}'
        for: cpuAlertDuration
        severity: cpuAlertSeverity
        enabled: true
        annotations: {
          summary: 'High CPU utilization detected'
          description: 'CPU utilization on {{ $labels.host_name }} has been above ${cpuAlertThreshold} for more than ${cpuAlertDuration}'
        }
        labels: {
          source: 'vminsights-otel'
          resourceGroup: resourceGroup().name
        }
        resolveConfiguration: {
          autoResolved: true
          timeToResolve: 'PT5M'
        }
      }
    ]
  }
}

// ---- Prometheus Alert Rule (Memory Utilization) ----

resource memoryAlertRuleGroup 'Microsoft.AlertsManagement/prometheusRuleGroups@2023-03-01' = if (enableMemoryAlert && enableAdditionalMetrics) {
  name: 'Memory-High-Utilization-${resourceGroup().name}'
  location: location
  tags: tags
  properties: {
    description: 'Alert when memory utilization exceeds ${memoryAlertThreshold} for ${memoryAlertDuration}'
    enabled: true
    interval: 'PT1M'
    scopes: [
      azureMonitorWorkspace.id
    ]
    rules: [
      {
        alert: 'HighMemoryUtilization'
        expression: 'avg by (host_name) (avg_over_time(system_memory_utilization[5m])) > ${memoryAlertThreshold}'
        for: memoryAlertDuration
        severity: memoryAlertSeverity
        enabled: true
        annotations: {
          summary: 'High memory utilization detected'
          description: 'Memory utilization on {{ $labels.host_name }} has been above ${memoryAlertThreshold} for more than ${memoryAlertDuration}'
        }
        labels: {
          source: 'vminsights-otel'
          resourceGroup: resourceGroup().name
        }
        resolveConfiguration: {
          autoResolved: true
          timeToResolve: 'PT5M'
        }
      }
    ]
  }
}

// ---- Prometheus Alert Rule (Disk Utilization) ----

resource diskAlertRuleGroup 'Microsoft.AlertsManagement/prometheusRuleGroups@2023-03-01' = if (enableDiskAlert && enableAdditionalMetrics) {
  name: 'Disk-High-Utilization-${resourceGroup().name}'
  location: location
  tags: tags
  properties: {
    description: 'Alert when logical disk utilization exceeds ${diskAlertThreshold} for ${diskAlertDuration}'
    enabled: true
    interval: 'PT1M'
    scopes: [
      azureMonitorWorkspace.id
    ]
    rules: [
      {
        alert: 'HighDiskUtilization'
        expression: 'max by (host_name, mountpoint) (avg_over_time(system_filesystem_utilization[5m])) > ${diskAlertThreshold}'
        for: diskAlertDuration
        severity: diskAlertSeverity
        enabled: true
        annotations: {
          summary: 'High disk utilization detected'
          description: 'Disk utilization on {{ $labels.host_name }} mount {{ $labels.mountpoint }} has been above ${diskAlertThreshold} for more than ${diskAlertDuration}'
        }
        labels: {
          source: 'vminsights-otel'
          resourceGroup: resourceGroup().name
        }
        resolveConfiguration: {
          autoResolved: true
          timeToResolve: 'PT10M'
        }
      }
    ]
  }
}

// ---- Outputs ----

@description('Resource ID of the Azure Monitor Workspace.')
output azureMonitorWorkspaceId string = azureMonitorWorkspace.id

@description('Resource ID of the OTel Data Collection Rule.')
output dataCollectionRuleId string = dataCollectionRule.id

@description('Resource ID of the Log Analytics workspace (if enabled).')
output logAnalyticsWorkspaceId string = enableClassicMetrics ? logAnalyticsWorkspace.id : ''

@description('Resource ID of the classic perf counter DCR (if enabled).')
output classicDataCollectionRuleId string = enableClassicMetrics ? classicDataCollectionRule.id : ''

@description('Names of Arc servers configured.')
output configuredServers array = arcServerNames
