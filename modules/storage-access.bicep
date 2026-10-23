param accountName string
param containerName string

@description('Identities with read access to the container, [{ id, principalId }].')
param readers array = []

@description('Identities with read and write access to the container, [{ id, principalId }].')
param writers array = []

resource account 'Microsoft.Storage/storageAccounts@2026-06-01' existing = {
  name: accountName
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2026-06-01' existing = {
  parent: account
  name: 'default'
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2026-06-01' existing = {
  parent: blobService
  name: containerName
}

var roles = concat(
  map(readers, identity => {
    identity: identity
    roleId: '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
  }),
  map(writers, identity => {
    identity: identity
    roleId: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  })
)

resource access 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for role in roles: {
    name: guid(container.id, role.identity.id, role.roleId)
    scope: container
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', role.roleId)
      principalId: role.identity.principalId
      principalType: 'ServicePrincipal'
    }
  }
]
