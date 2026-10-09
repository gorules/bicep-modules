metadata description = 'GoRules BRMS and Agent on Azure Container Apps'

type cpu = '0.25' | '0.5' | '0.75' | '1' | '1.25' | '1.5' | '1.75' | '2' | '2.25' | '2.5' | '2.75' | '3' | '3.25' | '3.5' | '3.75' | '4'

type envVar = {
  name: string
  value: string
}

@sealed()
type networkConfig = {
  @description('Virtual network address space, /22 or larger. Default 10.0.0.0/16.')
  addressPrefix: string?

  @description('Route egress through a NAT gateway with a static public IP. Default false.')
  natGateway: bool?
}

@sealed()
type storageConfig = {
  @description('Keep previous versions of overwritten blobs. Default true.')
  versioning: bool?
}

@sealed()
type agentConfig = {
  @description('Container image. Default docker.io/gorules/agent:latest.')
  image: string?

  @description('vCPU per replica; memory is twice the vCPU in GiB. Default 0.5.')
  cpu: cpu?

  @minValue(1)
  @description('Minimum replicas. Default 1; use 2 or more with zone redundancy.')
  minReplicas: int?

  @minValue(1)
  @maxValue(1000)
  maxReplicas: int

  @minValue(1)
  @maxValue(100)
  @description('Average CPU utilization percentage that triggers scaling. Default 60.')
  cpuTarget: int?

  @minLength(1)
  @description('Client CIDR ranges allowed to reach the Agent, e.g. ["0.0.0.0/0"].')
  allowedCidrBlocks: string[]

  @description('Extra environment variables.')
  env: envVar[]?
}

@sealed()
type vaultConfig = {
  @minValue(7)
  @maxValue(90)
  @description('Days a deleted vault and its secrets can be recovered. Default 90. Can\'t be changed later.')
  softDeleteRetentionDays: int?

  @description('Block permanent deletion during the retention period. Default true. Can\'t be turned off once on.')
  purgeProtection: bool?
}

@sealed()
type databaseConfig = {
  @description('PostgreSQL major version. Default 17.')
  version: ('16' | '17' | '18')?

  @description('Compute size, e.g. Standard_B2s, Standard_D2ds_v5. Default Standard_B2s.')
  sku: string?

  @description('Storage in GiB. Grows automatically. Default 32.')
  storageSizeGB: (32 | 64 | 128 | 256 | 512 | 1024 | 2048 | 4096 | 8192 | 16384 | 32767)?

  @description('Standby replica, zone redundant when zoneRedundant is true. Not available on Burstable sizes. Default false.')
  highAvailability: bool?

  @minValue(7)
  @maxValue(35)
  @description('Default 7.')
  backupRetentionDays: int?

  @description('Copy backups to the paired region. Can\'t be changed later. Default false.')
  geoRedundantBackup: bool?

  @description('Lock the server against deletion. Default true.')
  deletionProtection: bool?
}

@sealed()
type aiConfig = {
  provider: 'openai' | 'anthropic' | 'google' | 'azure-openai'
  model: string

  @description('Default 0.4.')
  temperature: string?

  @minValue(1)
  @description('Default 32000.')
  maxOutputTokens: int?

  @description('Default medium.')
  thinkingLevel: ('high' | 'medium')?

  @minValue(1)
  contextWindow: int?

  @description('Required for azure-openai.')
  azureResourceName: string?
}

@sealed()
type brmsConfig = {
  @description('Container image. Default docker.io/gorules/brms:latest.')
  image: string?

  @description('vCPU per replica; memory is twice the vCPU in GiB. Default 1.')
  cpu: cpu?

  @minValue(1)
  @description('Minimum replicas. Default 1; use 2 or more with zone redundancy.')
  minReplicas: int?

  @minValue(1)
  @maxValue(1000)
  maxReplicas: int

  @minValue(1)
  @maxValue(100)
  @description('Average CPU utilization percentage that triggers scaling. Default 60.')
  cpuTarget: int?

  @minLength(1)
  @description('Client CIDR ranges allowed to reach BRMS, e.g. ["0.0.0.0/0"].')
  allowedCidrBlocks: string[]

  @description('Key that encrypts secrets stored in BRMS: a generated master key (env) or a Key Vault RSA key. Default env.')
  secretsProvider: ('env' | 'azure-keyvault')?

  @description('AI assistant. Omit to turn it off.')
  ai: aiConfig?

  @description('Extra environment variables.')
  env: envVar[]?
}

@minLength(2)
@maxLength(16)
@description('Project name used in resource names. Lowercase letters, digits and hyphens.')
param projectName string

@minLength(2)
@maxLength(16)
@description('Environment name used in resource names, e.g. dev, staging, prod.')
param environmentName string

param location string = resourceGroup().location

@description('Tags added to every resource, merged with Project, Environment and ManagedBy.')
param tags object = {}

@description('Spread the Container Apps environment and storage across availability zones. Requires a region with zones. Can\'t be changed after the first deployment.')
param zoneRedundant bool = true

param network networkConfig = {}

param storage storageConfig = {}

@description('Resource ID of an Azure Container Registry to pull images from with managed identity.')
param containerRegistryId string?

@description('GoRules Agent. Omit to skip it.')
param agent agentConfig?

@description('GoRules BRMS. Omit to skip it.')
param brms brmsConfig?

param database databaseConfig = {}

param vault vaultConfig = {}

@secure()
@description('GoRules license key. Required with BRMS.')
param licenseKey string = ''

@secure()
@description('API key for the AI provider.')
param aiApiKey string = ''

@secure()
@description('Extra secret environment variables for BRMS, e.g. { SSO_OAUTH2_CLIENT_SECRET: \'...\' }.')
param brmsSecrets object = {}

var prefix = '${projectName}-${environmentName}'

var errors = filter(
  [
    length(prefix) > 26 ? 'projectName and environmentName together must be at most 25 characters' : ''
    parseCidr(addressPrefix).cidr > 22 ? 'network.addressPrefix must be /22 or larger' : ''
    (agent.?minReplicas ?? 1) > (agent.?maxReplicas ?? 1000)
      ? 'agent.minReplicas must be less than or equal to agent.maxReplicas'
      : ''
    (brms.?minReplicas ?? 1) > (brms.?maxReplicas ?? 1000)
      ? 'brms.minReplicas must be less than or equal to brms.maxReplicas'
      : ''
    brms != null && empty(licenseKey) ? 'licenseKey is required with BRMS' : ''
    brms.?ai != null && empty(aiApiKey) ? 'aiApiKey is required with brms.ai' : ''
    brms.?ai.?provider == 'azure-openai' && brms.?ai.?azureResourceName == null
      ? 'brms.ai.azureResourceName is required for azure-openai'
      : ''
    (database.?highAvailability ?? false) && startsWith(database.?sku ?? 'Standard_B2s', 'Standard_B')
      ? 'database.highAvailability is not available on Burstable sizes'
      : ''
  ],
  error => !empty(error)
)

var namePrefix = empty(errors) ? prefix : fail(join(errors, '; '))

var addressPrefix = network.?addressPrefix ?? '10.0.0.0/16'

var blobDnsZone = 'privatelink.blob.${environment().suffixes.storage}'
var vaultDnsZone = 'privatelink.vaultcore.azure.net'
var postgresDnsZone = 'privatelink.postgres.database.azure.com'

var allTags = union(
  {
    Project: projectName
    Environment: environmentName
    ManagedBy: 'bicep'
  },
  tags
)

var deployApps = agent != null || brms != null

var registryRef = containerRegistryId == null ? null : split(containerRegistryId!, '/')

resource agentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = if (agent != null) {
  name: '${namePrefix}-agent'
  location: location
  tags: allTags
}

var agentPrincipal = agent == null ? [] : [{ id: agentIdentity.id, principalId: agentIdentity!.properties.principalId }]

resource brmsIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = if (brms != null) {
  name: '${namePrefix}-brms'
  location: location
  tags: allTags
}

var brmsPrincipal = brms == null ? [] : [{ id: brmsIdentity.id, principalId: brmsIdentity!.properties.principalId }]

module networkModule 'modules/network.bicep' = if (deployApps) {
  params: {
    namePrefix: namePrefix
    location: location
    tags: allTags
    addressPrefix: addressPrefix
    natGateway: network.?natGateway ?? false
    privateDnsZones: concat([blobDnsZone], brms == null ? [] : [vaultDnsZone, postgresDnsZone])
  }
}

module storageModule 'modules/storage.bicep' = if (deployApps) {
  params: {
    namePrefix: namePrefix
    location: location
    tags: allTags
    versioning: storage.?versioning ?? true
    zoneRedundant: zoneRedundant
    privateEndpointSubnetId: networkModule!.outputs.privateEndpointSubnetId
    privateDnsZoneId: networkModule!.outputs.privateDnsZoneIds[blobDnsZone]
    readers: agentPrincipal
    writers: brmsPrincipal
  }
}

module environmentModule 'modules/environment.bicep' = if (deployApps) {
  params: {
    namePrefix: namePrefix
    location: location
    tags: allTags
    subnetId: networkModule!.outputs.appsSubnetId
    zoneRedundant: zoneRedundant
  }
}

module registryAccess 'modules/registry-access.bicep' = if (deployApps && registryRef != null) {
  scope: resourceGroup(registryRef![2], registryRef![4])
  params: {
    registryName: last(registryRef!)
    identities: concat(agentPrincipal, brmsPrincipal)
  }
}

module agentApp 'modules/app.bicep' = if (agent != null) {
  params: {
    name: '${namePrefix}-agent'
    location: location
    tags: allTags
    environmentId: environmentModule!.outputs.id
    identityId: agentIdentity.id
    identityClientId: agentIdentity!.properties.clientId
    registryServer: registryAccess.?outputs.loginServer
    image: agent.?image ?? 'docker.io/gorules/agent:latest'
    cpu: agent.?cpu ?? '0.5'
    port: 8080
    minReplicas: agent.?minReplicas ?? 1
    maxReplicas: agent!.maxReplicas
    cpuTarget: agent.?cpuTarget ?? 60
    allowedCidrBlocks: agent!.allowedCidrBlocks
    env: concat(
      [
        { name: 'PROVIDER__TYPE', value: 'AzureStorage' }
        { name: 'PROVIDER__ACCOUNT_NAME', value: storageModule!.outputs.accountName }
        { name: 'PROVIDER__CONTAINER', value: storageModule!.outputs.containerName }
      ],
      agent.?env ?? []
    )
  }
}

var ai = brms.?ai
var databaseSku = database.?sku ?? 'Standard_B2s'
var secretsProvider = brms.?secretsProvider ?? 'env'

module vaultModule 'modules/vault.bicep' = if (brms != null) {
  params: {
    namePrefix: namePrefix
    location: location
    tags: allTags
    privateEndpointSubnetId: networkModule!.outputs.privateEndpointSubnetId
    privateDnsZoneId: networkModule!.outputs.privateDnsZoneIds[vaultDnsZone]
    softDeleteRetentionDays: vault.?softDeleteRetentionDays ?? 90
    purgeProtection: vault.?purgeProtection ?? true
    reader: {
      id: brmsIdentity.id
      principalId: brmsIdentity!.properties.principalId
    }
    createKey: secretsProvider == 'azure-keyvault'
    createMasterKey: secretsProvider == 'env'
    licenseKey: licenseKey
    secrets: union(
      brmsSecrets,
      ai == null
        ? {}
        : {
            LLM_API_KEY: aiApiKey
          }
    )
  }
}

module databaseModule 'modules/database.bicep' = if (brms != null) {
  params: {
    namePrefix: namePrefix
    location: location
    tags: allTags
    privateEndpointSubnetId: networkModule!.outputs.privateEndpointSubnetId
    privateDnsZoneId: networkModule!.outputs.privateDnsZoneIds[postgresDnsZone]
    version: database.?version ?? '17'
    sku: databaseSku
    storageSizeGB: database.?storageSizeGB ?? 32
    highAvailability: database.?highAvailability ?? false
    zoneRedundant: zoneRedundant
    backupRetentionDays: database.?backupRetentionDays ?? 7
    geoRedundantBackup: database.?geoRedundantBackup ?? false
    deletionProtection: database.?deletionProtection ?? true
    admin: {
      id: brmsIdentity.id
      name: brmsIdentity.name
      principalId: brmsIdentity!.properties.principalId
    }
  }
}

var brmsName = '${namePrefix}-brms'

module brmsApp 'modules/app.bicep' = if (brms != null) {
  params: {
    name: brmsName
    location: location
    tags: allTags
    environmentId: environmentModule!.outputs.id
    identityId: brmsIdentity.id
    identityClientId: brmsIdentity!.properties.clientId
    registryServer: registryAccess.?outputs.loginServer
    image: brms.?image ?? 'docker.io/gorules/brms:latest'
    cpu: brms.?cpu ?? '1'
    port: 80
    minReplicas: brms.?minReplicas ?? 1
    maxReplicas: brms!.maxReplicas
    cpuTarget: brms.?cpuTarget ?? 60
    allowedCidrBlocks: brms!.allowedCidrBlocks
    env: concat(
      [
        { name: 'APP_URL', value: 'https://${brmsName}.${environmentModule!.outputs.defaultDomain}' }
        { name: 'DB_HOST', value: databaseModule!.outputs.host }
        { name: 'DB_PORT', value: '5432' }
        { name: 'DB_NAME', value: databaseModule!.outputs.name }
        { name: 'DB_USER', value: brmsIdentity.name }
        { name: 'DB_CREDENTIALS_PROVIDER', value: 'azure-iam' }
        { name: 'SECRETS_PROVIDER', value: secretsProvider }
      ],
      secretsProvider == 'azure-keyvault'
        ? [
            { name: 'SECRETS_AZURE_KEYVAULT_URL', value: vaultModule!.outputs.uri }
            { name: 'SECRETS_AZURE_KEYVAULT_KEY_NAME', value: vaultModule!.outputs.keyName }
          ]
        : [],
      ai == null
        ? []
        : concat(
            [
              { name: 'LLM_PROVIDER', value: ai!.provider }
              { name: 'LLM_MODEL', value: ai!.model }
              { name: 'LLM_TEMPERATURE', value: ai.?temperature ?? '0.4' }
              { name: 'LLM_MAX_OUTPUT_TOKENS', value: string(ai.?maxOutputTokens ?? 32000) }
              { name: 'LLM_THINKING_LEVEL', value: ai.?thinkingLevel ?? 'medium' }
            ],
            ai.?contextWindow == null ? [] : [{ name: 'LLM_CONTEXT_WINDOW', value: string(ai.?contextWindow) }],
            ai!.provider != 'azure-openai'
              ? []
              : [
                  {
                    name: 'LLM_AZURE_RESOURCE_NAME'
                    value: ai.?azureResourceName ?? ''
                  }
                ]
          ),
      brms.?env ?? []
    )
    secrets: vaultModule!.outputs.appSecrets
  }
}

output agentUrl string? = agent == null ? null : 'https://${agentApp!.outputs.fqdn}'
output agentPrincipalId string? = agentIdentity.?properties.principalId
output brmsUrl string? = brms == null ? null : 'https://${brmsApp!.outputs.fqdn}'
output brmsPrincipalId string? = brmsIdentity.?properties.principalId
output databaseHost string? = databaseModule.?outputs.host
output keyVaultUri string? = vaultModule.?outputs.uri
output storageAccountName string? = storageModule.?outputs.accountName
output storageContainerName string? = storageModule.?outputs.containerName
output storageBlobEndpoint string? = storageModule.?outputs.blobEndpoint
output vnetId string? = networkModule.?outputs.vnetId
