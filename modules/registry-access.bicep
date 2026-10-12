param registryName string

@description('Identities that pull images, [{ id, principalId }].')
param identities array

resource registry 'Microsoft.ContainerRegistry/registries@2025-11-01' existing = {
  name: registryName
}

// AcrPull for RBAC registries, Container Registry Repository Reader for ABAC registries.
var pullRoles = [
  '7f951dda-4ed3-4680-a7ca-43fe172d538d'
  'b93aa761-3e63-49ed-ac28-beffa264f7ac'
]

resource pull 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for grant in flatten(map(identities, identity => map(pullRoles, roleId => { identity: identity, roleId: roleId }))): {
    name: guid(registry.id, grant.identity.id, grant.roleId)
    scope: registry
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', grant.roleId)
      principalId: grant.identity.principalId
      principalType: 'ServicePrincipal'
    }
  }
]

output loginServer string = registry.properties.loginServer
