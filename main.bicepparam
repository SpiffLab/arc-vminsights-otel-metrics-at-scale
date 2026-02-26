using './main.bicep'

// Required: Names of your existing Azure Arc-enabled Windows servers
param arcServerNames = [
  '<arc-server-1>'
  '<arc-server-2>'
]

// Optional: Customize these as needed
param azureMonitorWorkspaceName = 'amw-vminsights-otel'
param samplingFrequencyInSeconds = 60
param enableAdditionalMetrics = false

// Alert rule settings (requires enableAdditionalMetrics = true)
param enableCpuAlert = true
param cpuAlertThreshold = '0.70'
param cpuAlertSeverity = 2

param enableMemoryAlert = true
param memoryAlertThreshold = '0.90'
param memoryAlertSeverity = 2

param enableDiskAlert = true
param diskAlertThreshold = '0.90'
param diskAlertSeverity = 1

param tags = {
  environment: 'production'
  managedBy: 'bicep'
}
