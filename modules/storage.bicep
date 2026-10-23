param namePrefix string
param location string
param tags object
param versioning bool
param zoneRedundant bool
param privateEndpointSubnetId string
param privateDnsZoneId string

@description('Existing blob container. Omit to create an account.')
param containerId string?

@description('Add a private endpoint to the account of containerId.')
param existingEndpoint bool = false

var ref = split(containerId ?? '', '/')

resource account 'Microsoft.Storage/storageAccounts@2026-06-01' = if (containerId == null) {
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

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2026-06-01' = if (containerId == null) {
  parent: account
  name: 'default'
  properties: {
    isVersioningEnabled: versioning
  }
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2026-06-01' = if (containerId == null) {
  parent: blobService
  name: 'rules'
}

resource endpoint 'Microsoft.Network/privateEndpoints@2026-01-01' = if (containerId == null || existingEndpoint) {
  // an endpoint can't change its target, so one per account
  name: containerId == null ? '${namePrefix}-blob-pe' : '${namePrefix}-${ref[8]}-pe'
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
          privateLinkServiceId: containerId == null ? account.id : join(take(ref, 9), '/')
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

resource endpointDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2026-01-01' = if (containerId == null || existingEndpoint) {
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

output accountName string = containerId == null ? account.name : ref[8]
output containerName string = containerId == null ? container.name : ref[12]
output blobEndpoint string = containerId == null
  ? account!.properties.primaryEndpoints.blob
  : 'https://${ref[8]}.blob.${environment().suffixes.storage}/'
