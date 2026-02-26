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

param tags = {
  environment: 'production'
  managedBy: 'bicep'
}
