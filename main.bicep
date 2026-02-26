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

// ---- Outputs ----

@description('Resource ID of the Azure Monitor Workspace.')
output azureMonitorWorkspaceId string = azureMonitorWorkspace.id

@description('Resource ID of the Data Collection Rule.')
output dataCollectionRuleId string = dataCollectionRule.id

@description('Names of Arc servers configured.')
output configuredServers array = arcServerNames
