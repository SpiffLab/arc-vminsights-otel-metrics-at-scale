using './main.bicep'

// Required: Name of your existing Azure Arc-enabled Windows server
param arcServerName = '<your-arc-server-name>'

// Optional: Customize these as needed
param azureMonitorWorkspaceName = 'amw-vminsights-otel'
param samplingFrequencyInSeconds = 60
param enableAdditionalMetrics = false

param tags = {
  environment: 'production'
  managedBy: 'bicep'
}
