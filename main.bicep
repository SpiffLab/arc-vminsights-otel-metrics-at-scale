// =============================================================================
// VM Insights with OpenTelemetry for Azure Arc-enabled Windows Servers
// =============================================================================
// Deploys: Azure Monitor Workspace, OTel Data Collection Rule, AMA extension,
//          DCR association, and Prometheus alert rules for Arc-enabled Windows
//          servers in a resource group.
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

// ---- Alert Parameters ----

@description('Enable CPU utilization alert rule.')
param enableCpuAlert bool = true

@description('CPU utilization threshold (0-1). Default 0.70 = 70%.')
param cpuAlertThreshold string = '0.70'

@description('Duration the CPU must exceed threshold before alerting (ISO 8601).')
param cpuAlertDuration string = 'PT3M'

@description('CPU alert severity (0 = Critical, 1 = Error, 2 = Warning, 3 = Informational, 4 = Verbose).')
@minValue(0)
@maxValue(4)
param cpuAlertSeverity int = 2

@description('Enable memory utilization alert rule.')
param enableMemoryAlert bool = true

@description('Memory utilization threshold (0-1). Default 0.90 = 90%.')
param memoryAlertThreshold string = '0.90'

@description('Duration memory must exceed threshold before alerting (ISO 8601).')
param memoryAlertDuration string = 'PT5M'

@description('Memory alert severity (0 = Critical, 1 = Error, 2 = Warning, 3 = Informational, 4 = Verbose).')
@minValue(0)
@maxValue(4)
param memoryAlertSeverity int = 2

@description('Enable disk utilization alert rule.')
param enableDiskAlert bool = true

@description('Disk utilization threshold (0-1). Default 0.90 = 90%.')
param diskAlertThreshold string = '0.90'

@description('Duration disk must exceed threshold before alerting (ISO 8601).')
param diskAlertDuration string = 'PT5M'

@description('Disk alert severity (0 = Critical, 1 = Error, 2 = Warning, 3 = Informational, 4 = Verbose).')
@minValue(0)
@maxValue(4)
param diskAlertSeverity int = 1

// ---- Variables ----

// Default + alert metrics are always collected so alerts work out of the box
var counterSpecifiers = [
  // Default metrics (free)
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
  // Required for alert rules
  'system.cpu.utilization'
  'system.memory.utilization'
  'system.filesystem.utilization'
]

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
    description: 'DCR for VM Insights OpenTelemetry metrics on Arc-enabled Windows servers'
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

// ---- Prometheus Alert Rule (CPU Utilization) ----

resource cpuAlertRuleGroup 'Microsoft.AlertsManagement/prometheusRuleGroups@2023-03-01' = if (enableCpuAlert) {
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

resource memoryAlertRuleGroup 'Microsoft.AlertsManagement/prometheusRuleGroups@2023-03-01' = if (enableMemoryAlert) {
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

resource diskAlertRuleGroup 'Microsoft.AlertsManagement/prometheusRuleGroups@2023-03-01' = if (enableDiskAlert) {
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

@description('Resource ID of the Data Collection Rule.')
output dataCollectionRuleId string = dataCollectionRule.id

@description('Names of Arc servers configured.')
output configuredServers array = arcServerNames
