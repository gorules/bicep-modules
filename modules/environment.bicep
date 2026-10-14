param namePrefix string
param location string
param tags object
param subnetId string
param zoneRedundant bool
param internal bool

@description('Identity that reads custom domain certificates from Key Vault.')
param identityId string?

resource logs 'Microsoft.OperationalInsights/workspaces@2026-03-01' = {
  name: '${namePrefix}-logs'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource environment 'Microsoft.App/managedEnvironments@2026-07-01' = {
  name: '${namePrefix}-env'
  location: location
  tags: tags
  identity: identityId == null
    ? null
    : {
        type: 'UserAssigned'
        userAssignedIdentities: {
          '${identityId}': {}
        }
      }
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logs.properties.customerId
        sharedKey: logs.listKeys().primarySharedKey
      }
    }
    vnetConfiguration: {
      infrastructureSubnetId: subnetId
      internal: internal
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
    zoneRedundant: zoneRedundant
  }
}

output id string = environment.id
output defaultDomain string = environment.properties.defaultDomain
output staticIp string = environment.properties.staticIp
output customDomainVerificationId string = environment.properties.customDomainConfiguration.customDomainVerificationId
