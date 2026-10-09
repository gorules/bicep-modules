param namePrefix string
param location string
param tags object
param privateEndpointSubnetId string
param privateDnsZoneId string
param version string
param sku string
param storageSizeGB int
param highAvailability bool
param zoneRedundant bool
param backupRetentionDays int
param geoRedundantBackup bool
param deletionProtection bool

@description('Identity that owns the database through Entra ID, { id, name, principalId }.')
param admin object

var tier = startsWith(sku, 'Standard_B')
  ? 'Burstable'
  : startsWith(sku, 'Standard_E') ? 'MemoryOptimized' : 'GeneralPurpose'

resource server 'Microsoft.DBforPostgreSQL/flexibleServers@2025-08-01' = {
  name: '${namePrefix}-${uniqueString(resourceGroup().id, namePrefix)}'
  location: location
  tags: tags
  sku: {
    name: sku
    tier: tier
  }
  properties: {
    version: version
    storage: {
      storageSizeGB: storageSizeGB
      autoGrow: 'Enabled'
    }
    backup: {
      backupRetentionDays: backupRetentionDays
      geoRedundantBackup: geoRedundantBackup ? 'Enabled' : 'Disabled'
    }
    highAvailability: {
      mode: highAvailability ? (zoneRedundant ? 'ZoneRedundant' : 'SameZone') : 'Disabled'
    }
    network: {
      publicNetworkAccess: 'Disabled'
    }
    authConfig: {
      activeDirectoryAuth: 'Enabled'
      passwordAuth: 'Disabled'
      tenantId: subscription().tenantId
    }
  }
}

resource administrator 'Microsoft.DBforPostgreSQL/flexibleServers/administrators@2025-08-01' = {
  parent: server
  name: admin.principalId
  properties: {
    principalName: admin.name
    principalType: 'ServicePrincipal'
    tenantId: subscription().tenantId
  }
}

resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2025-08-01' = {
  parent: server
  name: 'gorules'
  dependsOn: [
    administrator
  ]
}

resource endpoint 'Microsoft.Network/privateEndpoints@2026-01-01' = {
  name: '${namePrefix}-postgres-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'postgres'
        properties: {
          privateLinkServiceId: server.id
          groupIds: [
            'postgresqlServer'
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
        name: 'postgres'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

resource lock 'Microsoft.Authorization/locks@2020-05-01' = if (deletionProtection) {
  name: 'do-not-delete'
  scope: server
  properties: {
    level: 'CanNotDelete'
    notes: 'Remove this lock before deleting the GoRules database.'
  }
  dependsOn: [
    database
    endpointDns
  ]
}

output host string = server.properties.fullyQualifiedDomainName
output name string = database.name
