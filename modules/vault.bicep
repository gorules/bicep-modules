param namePrefix string
param location string
param tags object
param privateEndpointSubnetId string
param privateDnsZoneId string
param softDeleteRetentionDays int
param purgeProtection bool

@description('Identity that reads the secrets and uses the key, { id, principalId }.')
param reader object

@description('Create the RSA key for the azure-keyvault secrets provider.')
param createKey bool

@description('Generate the master key for the env secrets provider.')
param createMasterKey bool

@secure()
param licenseKey string

@secure()
@description('Secrets to store, keyed by environment variable name.')
param secrets object = {}

@secure()
param cookieSecret string = replace('${newGuid()}${newGuid()}', '-', '')

@secure()
param masterKey string = replace('${newGuid()}${newGuid()}', '-', '')

func secretName(name string) string => toLower(replace(name, '_', '-'))

resource vault 'Microsoft.KeyVault/vaults@2026-02-01' = {
  name: 'kv${uniqueString(resourceGroup().id, namePrefix)}'
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    softDeleteRetentionInDays: softDeleteRetentionDays
    enablePurgeProtection: purgeProtection ? true : null
    publicNetworkAccess: 'Disabled'
  }
}

resource license 'Microsoft.KeyVault/vaults/secrets@2026-02-01' = {
  parent: vault
  name: 'license-key'
  properties: {
    value: licenseKey
  }
}

@onlyIfNotExists()
resource cookie 'Microsoft.KeyVault/vaults/secrets@2026-02-01' = {
  parent: vault
  name: 'cookie-secret'
  properties: {
    value: cookieSecret
  }
}

@onlyIfNotExists()
resource master 'Microsoft.KeyVault/vaults/secrets@2026-02-01' = if (createMasterKey) {
  parent: vault
  name: 'secrets-master-key'
  properties: {
    value: masterKey
  }
}

resource extra 'Microsoft.KeyVault/vaults/secrets@2026-02-01' = [
  for item in items(secrets): {
    parent: vault
    name: secretName(item.key)
    properties: {
      value: item.value
    }
  }
]

resource key 'Microsoft.KeyVault/vaults/keys@2026-02-01' = if (createKey) {
  parent: vault
  name: 'brms-secrets'
  properties: {
    kty: 'RSA'
    keySize: 3072
    keyOps: [
      'wrapKey'
      'unwrapKey'
    ]
  }
}

resource secretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vault.id, reader.id, 'Key Vault Secrets User')
  scope: vault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: reader.principalId
    principalType: 'ServicePrincipal'
  }
}

resource keyUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (createKey) {
  name: guid(key.id, reader.id, 'Key Vault Crypto Service Encryption User')
  scope: key
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'e147488a-f6f5-4113-8e2d-b22465e65bf6')
    principalId: reader.principalId
    principalType: 'ServicePrincipal'
  }
}

resource endpoint 'Microsoft.Network/privateEndpoints@2026-01-01' = {
  name: '${namePrefix}-vault-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'vault'
        properties: {
          privateLinkServiceId: vault.id
          groupIds: [
            'vault'
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
        name: 'vault'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

output uri string = vault.properties.vaultUri
output keyName string = createKey ? key.name : ''

@description('Secrets for the BRMS container, [{ name, keyVaultUrl }].')
output appSecrets array = concat(
  [
    { name: 'LICENSE_KEY', keyVaultUrl: '${vault.properties.vaultUri}secrets/${license.name}' }
    { name: 'COOKIE_SECRET', keyVaultUrl: '${vault.properties.vaultUri}secrets/${cookie.name}' }
  ],
  createMasterKey ? [{ name: 'SECRETS_MASTER_KEY', keyVaultUrl: '${vault.properties.vaultUri}secrets/${master.name}' }] : [],
  #disable-next-line outputs-should-not-contain-secrets
  map(items(secrets), item => { name: item.key, keyVaultUrl: '${vault.properties.vaultUri}secrets/${secretName(item.key)}' })
)
