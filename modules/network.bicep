param namePrefix string
param location string
param tags object
param addressPrefix string
param natGateway bool
param zoneRedundant bool
param appsSubnetId string?
param privateEndpointSubnetId string?

@description('Private DNS zones the private endpoints need.')
param privateDnsZones string[]

@description('Existing zones for privateDnsZones. Empty to create them.')
param privateDnsZoneIds string[] = []

var createZones = empty(privateDnsZoneIds)

var natSku = zoneRedundant ? 'StandardV2' : 'Standard'
var natZones = zoneRedundant ? ['1', '2', '3'] : null

resource natIp 'Microsoft.Network/publicIPAddresses@2026-01-01' = if (natGateway) {
  name: '${namePrefix}-nat-ip'
  location: location
  tags: tags
  sku: {
    name: natSku
  }
  zones: natZones
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource nat 'Microsoft.Network/natGateways@2026-01-01' = if (natGateway) {
  name: '${namePrefix}-nat'
  location: location
  tags: tags
  sku: {
    name: natSku
  }
  zones: natZones
  properties: {
    publicIpAddresses: [
      {
        id: natIp.id
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2026-01-01' = if (appsSubnetId == null) {
  name: '${namePrefix}-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        name: 'apps'
        properties: {
          addressPrefix: cidrSubnet(addressPrefix, 23, 0)
          delegations: [
            {
              name: 'apps'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
          natGateway: natGateway ? { id: nat.id } : null
        }
      }
      {
        name: 'private-endpoints'
        properties: {
          addressPrefix: cidrSubnet(addressPrefix, 24, 2)
        }
      }
    ]
  }
}

var vnetId = appsSubnetId == null ? vnet.id : split(appsSubnetId!, '/subnets/')[0]

resource zones 'Microsoft.Network/privateDnsZones@2024-06-01' = [
  for zone in createZones ? privateDnsZones : []: {
    name: zone
    location: 'global'
    tags: tags
  }
]

resource zoneLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [
  for (zone, i) in createZones ? privateDnsZones : []: {
    parent: zones[i]
    name: last(split(vnetId, '/'))
    location: 'global'
    tags: tags
    properties: {
      virtualNetwork: {
        id: vnetId
      }
      registrationEnabled: false
    }
  }
]

output appsSubnetId string = appsSubnetId ?? resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'apps')
output privateEndpointSubnetId string = privateEndpointSubnetId ?? resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'private-endpoints')
output vnetId string = vnetId
output privateDnsZoneIds object = createZones
  ? toObject(privateDnsZones, zone => zone, zone => resourceId('Microsoft.Network/privateDnsZones', zone))
  : toObject(privateDnsZoneIds, id => last(split(id, '/')), id => id)
