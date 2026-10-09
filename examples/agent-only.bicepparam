using '../main.bicep'

param projectName = 'gorules'
param environmentName = 'prod'

param agent = {
  minReplicas: 2
  maxReplicas: 20
  allowedCidrBlocks: ['0.0.0.0/0']
}
