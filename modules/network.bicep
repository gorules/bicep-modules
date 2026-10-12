param namePrefix string
param location string
param tags object
param addressPrefix string
param natGateway bool
param privateDnsZones string[]

resource natIp 'Microsoft.Network/publicIPAddresses@2026-01-01' = if (natGateway) {
  name: '${namePrefix}-nat-ip'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource nat 'Microsoft.Network/natGateways@2026-01-01' = if (natGateway) {
  name: '${namePrefix}-nat'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIpAddresses: [
      {
        id: natIp.id
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2026-01-01' = {
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

resource zones 'Microsoft.Network/privateDnsZones@2024-06-01' = [
  for zone in privateDnsZones: {
    name: zone
    location: 'global'
    tags: tags
  }
]

resource zoneLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [
  for (zone, i) in privateDnsZones: {
    parent: zones[i]
    name: vnet.name
    location: 'global'
    tags: tags
    properties: {
      virtualNetwork: {
        id: vnet.id
      }
      registrationEnabled: false
    }
  }
]

output appsSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'apps')
output privateEndpointSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'private-endpoints')
output vnetId string = vnet.id
output privateDnsZoneIds object = toObject(privateDnsZones, zone => zone, zone => resourceId('Microsoft.Network/privateDnsZones', zone))
