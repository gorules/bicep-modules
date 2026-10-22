param vaultName string
param secretName string
param principalId string

resource vault 'Microsoft.KeyVault/vaults@2026-05-15' existing = {
  name: vaultName
}

resource secret 'Microsoft.KeyVault/vaults/secrets@2026-05-15' existing = {
  parent: vault
  name: secretName
}

resource access 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(secret.id, principalId, 'Key Vault Secrets User')
  scope: secret
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
