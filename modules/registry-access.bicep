param registryName string

@description('Identities that pull images, [{ id, principalId }].')
param identities array

resource registry 'Microsoft.ContainerRegistry/registries@2025-11-01' existing = {
  name: registryName
}

resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for identity in identities: {
    name: guid(registry.id, identity.id, 'AcrPull')
    scope: registry
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
      principalId: identity.principalId
      principalType: 'ServicePrincipal'
    }
  }
]

output loginServer string = registry.properties.loginServer
