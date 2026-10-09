using '../main.bicep'

param projectName = 'gorules'
param environmentName = 'prod'
param licenseKey = readEnvironmentVariable('GORULES_LICENSE_KEY')

param database = {
  sku: 'Standard_D2ds_v5'
  highAvailability: true
}

param brms = {
  minReplicas: 2
  maxReplicas: 4
  allowedCidrBlocks: ['0.0.0.0/0']
}

param agent = {
  minReplicas: 2
  maxReplicas: 20
  allowedCidrBlocks: ['0.0.0.0/0']
}
