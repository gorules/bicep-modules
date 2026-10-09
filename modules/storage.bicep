param namePrefix string
param location string
param tags object
param versioning bool
param zoneRedundant bool
param privateEndpointSubnetId string
param privateDnsZoneId string

@description('Identities with read access to the rules container, [{ id, principalId }].')
param readers array = []

@description('Identities with read and write access to the rules container, [{ id, principalId }].')
param writers array = []

resource account 'Microsoft.Storage/storageAccounts@2026-06-01' = {
  name: 'st${uniqueString(resourceGroup().id, namePrefix)}'
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: zoneRedundant ? 'Standard_ZRS' : 'Standard_LRS'
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    allowCrossTenantReplication: false
    publicNetworkAccess: 'Disabled'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2026-06-01' = {
  parent: account
  name: 'default'
  properties: {
    isVersioningEnabled: versioning
  }
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2026-06-01' = {
  parent: blobService
  name: 'rules'
}

resource endpoint 'Microsoft.Network/privateEndpoints@2026-01-01' = {
  name: '${namePrefix}-blob-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'blob'
        properties: {
          privateLinkServiceId: account.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

resource endpointDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2026-01-01' = {
  parent: endpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blob'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
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

output accountName string = account.name
output containerName string = container.name
output blobEndpoint string = account.properties.primaryEndpoints.blob
