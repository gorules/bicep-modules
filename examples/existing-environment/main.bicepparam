using '../../main.bicep'

param projectName = 'gorules'
param environmentName = 'team-a'

param existingEnvironment = {
  id: '/subscriptions/<subscription-id>/resourceGroups/rg-gorules-prod/providers/Microsoft.App/managedEnvironments/gorules-prod-env'
  workspaceId: '/subscriptions/<subscription-id>/resourceGroups/rg-gorules-prod/providers/Microsoft.OperationalInsights/workspaces/gorules-prod-logs'
}

param network = {
  privateEndpointSubnetId: '/subscriptions/<subscription-id>/resourceGroups/rg-gorules-prod/providers/Microsoft.Network/virtualNetworks/gorules-prod-vnet/subnets/private-endpoints'
  privateDnsZoneIds: [
    '/subscriptions/<subscription-id>/resourceGroups/rg-gorules-prod/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net'
    '/subscriptions/<subscription-id>/resourceGroups/rg-gorules-prod/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net'
  ]
}

param agent = {
  minReplicas: 2
  maxReplicas: 20
  allowedCidrBlocks: ['0.0.0.0/0']
}
