param vaultName string
param keyName string
param principalId string

resource vault 'Microsoft.KeyVault/vaults@2026-05-15' existing = {
  name: vaultName
}

resource key 'Microsoft.KeyVault/vaults/keys@2026-05-15' existing = {
  parent: vault
  name: keyName
}

resource access 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(key.id, principalId, 'Key Vault Crypto Service Encryption User')
  scope: key
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'e147488a-f6f5-4113-8e2d-b22465e65bf6')
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
