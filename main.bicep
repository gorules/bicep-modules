metadata description = 'GoRules BRMS and Agent on Azure Container Apps'

type cpu =
  | '0.25'
  | '0.5'
  | '0.75'
  | '1'
  | '1.25'
  | '1.5'
  | '1.75'
  | '2'
  | '2.25'
  | '2.5'
  | '2.75'
  | '3'
  | '3.25'
  | '3.5'
  | '3.75'
  | '4'

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

  @description('Make BRMS and the Agent reachable only from the virtual network. Can\'t be changed after the first deployment. Default false.')
  internal: bool?

  @description('Existing subnet for Container Apps, delegated to Microsoft.App/environments, /27 or larger. Omit to create a virtual network.')
  appsSubnetId: string?

  @description('Existing subnet for private endpoints, in the same virtual network as appsSubnetId.')
  privateEndpointSubnetId: string?

  @description('Existing private DNS zones for the private endpoints, already linked to the virtual network. Omit to create them.')
  privateDnsZoneIds: string[]?
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

  @description('Custom domain, e.g. agent.example.com. Create its DNS records first.')
  domain: string?

  @description('Key Vault secret resource ID of the certificate for domain, e.g. <vault ID>/secrets/<certificate name>. Omit for a free managed certificate.')
  certificateId: string?

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

  @description('Custom domain, e.g. brms.example.com. Create its DNS records first.')
  domain: string?

  @description('Key Vault secret resource ID of the certificate for domain, e.g. <vault ID>/secrets/<certificate name>. Omit for a free managed certificate.')
  certificateId: string?

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

@description('Spread the Container Apps environment, storage, the NAT gateway and a high-availability database across availability zones. Requires a region with zones. Can\'t be changed after the first deployment.')
param zoneRedundant bool = true

param network networkConfig = {}

param storage storageConfig = {}

@description('Resource ID of an Azure Container Registry to pull images from with managed identity.')
param containerRegistryId string?

@description('Resource ID of an action group that receives alert notifications. Omit to create the alerts without notifications.')
param alertActionGroupId string?

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

@secure()
@description('Extra secret environment variables for the Agent, e.g. { RELEASE_ZIP_PASSWORD: \'...\' }.')
param agentSecrets object = {}

var prefix = '${projectName}-${environmentName}'

var validName = empty(filter(
  range(0, length(prefix)),
  i => !contains('abcdefghijklmnopqrstuvwxyz0123456789-', substring(prefix, i, 1))
)) && contains('abcdefghijklmnopqrstuvwxyz', first(prefix)) && !endsWith(prefix, '-') && !contains(prefix, '--')

func domainErrors(name string, app object, internal bool) string[] =>
  filter(
    [
      app.?certificateId != null && app.?domain == null ? '${name}.certificateId needs ${name}.domain' : ''
      app.?certificateId != null && !(contains(toLower(app.?certificateId ?? ''), '/providers/microsoft.keyvault/vaults/') && contains(app.?certificateId ?? '', '/secrets/') && length(split(app.?certificateId ?? '', '/')) == 11)
        ? '${name}.certificateId must be a Key Vault secret resource ID'
        : ''
      app.?domain != null && app.?certificateId == null && internal
        ? '${name}.domain needs ${name}.certificateId in an internal environment'
        : ''
      app.?domain != null && app.?certificateId == null && !internal && !contains(app.?allowedCidrBlocks ?? [], '0.0.0.0/0')
        ? '${name}.domain without ${name}.certificateId needs 0.0.0.0/0 in ${name}.allowedCidrBlocks'
        : ''
    ],
    error => !empty(error)
  )

var errors = concat(domainErrors('brms', brms ?? {}, internal), domainErrors('agent', agent ?? {}, internal), filter(
  [
    length(prefix) > 26 ? 'projectName and environmentName together must be at most 25 characters' : ''
    !validName
      ? 'projectName and environmentName must use lowercase letters, digits and single hyphens, start with a letter and not end with a hyphen'
      : ''
    parseCidr(addressPrefix).cidr > 22 ? 'network.addressPrefix must be /22 or larger' : ''
    (agent.?minReplicas ?? 1) > (agent.?maxReplicas ?? 1000)
      ? 'agent.minReplicas must be less than or equal to agent.maxReplicas'
      : ''
    (brms.?minReplicas ?? 1) > (brms.?maxReplicas ?? 1000)
      ? 'brms.minReplicas must be less than or equal to brms.maxReplicas'
      : ''
    brms.?ai.?provider == 'azure-openai' && brms.?ai.?azureResourceName == null
      ? 'brms.ai.azureResourceName is required for azure-openai'
      : ''
    (database.?highAvailability ?? false) && startsWith(database.?sku ?? 'Standard_B2s', 'Standard_B')
      ? 'database.highAvailability is not available on Burstable sizes'
      : ''
    (network.?appsSubnetId == null) != (network.?privateEndpointSubnetId == null)
      ? 'network.appsSubnetId and network.privateEndpointSubnetId must be set together'
      : ''
    network.?appsSubnetId != null && (network.?addressPrefix != null || (network.?natGateway ?? false))
      ? 'network.addressPrefix and network.natGateway can\'t be used with existing subnets'
      : ''
    network.?appsSubnetId == null
      ? ''
      : split(network.?appsSubnetId!, '/subnets/')[0] != split(network.?privateEndpointSubnetId ?? '', '/subnets/')[0]
          ? 'network.appsSubnetId and network.privateEndpointSubnetId must be in the same virtual network'
          : toLower(split(network.?appsSubnetId!, '/')[2]) != toLower(subscription().subscriptionId)
              ? 'the virtual network must be in the deployment subscription'
              : ''
    alertActionGroupId != null && !(contains(toLower(alertActionGroupId ?? ''), '/providers/microsoft.insights/actiongroups/') && length(split(alertActionGroupId ?? '', '/')) == 9)
      ? 'alertActionGroupId must be an action group resource ID'
      : ''
    network.?privateDnsZoneIds != null && network.?appsSubnetId == null
      ? 'network.privateDnsZoneIds needs network.appsSubnetId'
      : ''
    network.?privateDnsZoneIds != null && !empty(missingZones)
      ? 'network.privateDnsZoneIds is missing ${join(missingZones, ', ')}'
      : ''
  ],
  error => !empty(error)
))

var namePrefix = empty(errors) ? prefix : fail(join(errors, '; '))

var addressPrefix = network.?addressPrefix ?? '10.0.0.0/16'
var internal = network.?internal ?? false

var blobDnsZone = 'privatelink.blob.${environment().suffixes.storage}'
var vaultDnsZone = 'privatelink.vaultcore.azure.net'
var postgresDnsZone = 'privatelink.postgres.database.azure.com'
var dnsZones = concat([blobDnsZone, vaultDnsZone], brms == null ? [] : [postgresDnsZone])
var missingZones = filter(dnsZones, zone => empty(filter(network.?privateDnsZoneIds ?? [], id => toLower(last(split(id, '/'))) == zone)))

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

// Secure values are checked here, not in namePrefix, so what-if can resolve resource names.
var secretErrors = filter(
  [
    empty(licenseKey) ? 'licenseKey is required with BRMS' : ''
    brms.?ai != null && empty(aiApiKey) ? 'aiApiKey is required with brms.ai' : ''
  ],
  error => !empty(error)
)

resource brmsIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = if (brms != null) {
  name: '${namePrefix}-brms'
  location: location
  tags: empty(secretErrors) ? allTags : fail(join(secretErrors, '; '))
}

var brmsPrincipal = brms == null ? [] : [{ id: brmsIdentity.id, principalId: brmsIdentity!.properties.principalId }]

module networkModule 'modules/network.bicep' = if (deployApps) {
  params: {
    namePrefix: namePrefix
    location: location
    tags: allTags
    addressPrefix: addressPrefix
    natGateway: network.?natGateway ?? false
    zoneRedundant: zoneRedundant
    appsSubnetId: network.?appsSubnetId
    privateEndpointSubnetId: network.?privateEndpointSubnetId
    privateDnsZones: dnsZones
    privateDnsZoneIds: network.?privateDnsZoneIds ?? []
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

resource environmentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = if (brms.?certificateId != null || agent.?certificateId != null) {
  name: '${namePrefix}-env'
  location: location
  tags: allTags
}

var brmsCertificateRef = brms.?certificateId == null ? null : split(brms.?certificateId!, '/')

module brmsCertificate 'modules/certificate-access.bicep' = if (brmsCertificateRef != null) {
  scope: resourceGroup(brmsCertificateRef![2], brmsCertificateRef![4])
  params: {
    vaultName: brmsCertificateRef![8]
    secretName: brmsCertificateRef![10]
    principalId: environmentIdentity!.properties.principalId
  }
}

var agentCertificateRef = agent.?certificateId == null ? null : split(agent.?certificateId!, '/')

module agentCertificate 'modules/certificate-access.bicep' = if (agentCertificateRef != null) {
  scope: resourceGroup(agentCertificateRef![2], agentCertificateRef![4])
  params: {
    vaultName: agentCertificateRef![8]
    secretName: agentCertificateRef![10]
    principalId: environmentIdentity!.properties.principalId
  }
}

module environmentModule 'modules/environment.bicep' = if (deployApps) {
  params: {
    namePrefix: namePrefix
    location: location
    tags: allTags
    subnetId: networkModule!.outputs.appsSubnetId
    zoneRedundant: zoneRedundant
    internal: internal
    identityId: environmentIdentity.?id
  }
}

module environmentDns 'modules/private-zone.bicep' = if (deployApps && internal) {
  params: {
    name: environmentModule!.outputs.defaultDomain
    tags: allTags
    vnetId: networkModule!.outputs.vnetId
    ipAddress: environmentModule!.outputs.staticIp
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
    secrets: vaultModule.?outputs.agentAppSecrets ?? []
    domain: agent.?domain
    certificateUrl: agentCertificateRef == null
      ? null
      : 'https://${agentCertificateRef![8]}${environment().suffixes.keyvaultDns}/secrets/${agentCertificateRef![10]}'
    certificateIdentityId: environmentIdentity.?id
    workspaceId: environmentModule!.outputs.workspaceId
    actionGroupId: alertActionGroupId
  }
  dependsOn: [
    agentCertificate
  ]
}

var ai = brms.?ai
var databaseSku = database.?sku ?? 'Standard_B2s'
var secretsProvider = brms.?secretsProvider ?? 'env'

module vaultModule 'modules/vault.bicep' = if (brms != null || (agent != null && !empty(agentSecrets))) {
  params: {
    namePrefix: namePrefix
    location: location
    tags: allTags
    privateEndpointSubnetId: networkModule!.outputs.privateEndpointSubnetId
    privateDnsZoneId: networkModule!.outputs.privateDnsZoneIds[vaultDnsZone]
    softDeleteRetentionDays: vault.?softDeleteRetentionDays ?? 90
    purgeProtection: vault.?purgeProtection ?? true
    brmsReader: first(brmsPrincipal)
    agentReader: first(agentPrincipal)
    createKey: brms != null && secretsProvider == 'azure-keyvault'
    createMasterKey: brms != null && secretsProvider == 'env'
    licenseKey: licenseKey
    secrets: brms == null
      ? {}
      : union(
          brmsSecrets,
          ai == null
            ? {}
            : {
                LLM_API_KEY: aiApiKey
              }
        )
    agentSecrets: agent == null ? {} : agentSecrets
  }
}

var databaseName = '${namePrefix}-${uniqueString(resourceGroup().id, namePrefix)}'

// Storage only grows, so never ask for less than autogrow has reached.
@nullIfNotFound()
resource currentDatabase 'Microsoft.DBforPostgreSQL/flexibleServers@2025-08-01' existing = if (brms != null) {
  name: databaseName
}

module databaseModule 'modules/database.bicep' = if (brms != null) {
  params: {
    name: databaseName
    namePrefix: namePrefix
    location: location
    tags: allTags
    privateEndpointSubnetId: networkModule!.outputs.privateEndpointSubnetId
    privateDnsZoneId: networkModule!.outputs.privateDnsZoneIds[postgresDnsZone]
    version: database.?version ?? '17'
    sku: databaseSku
    storageSizeGB: max(database.?storageSizeGB ?? 32, currentDatabase.?properties.storage.storageSizeGB ?? 0)
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
        { name: 'APP_URL', value: 'https://${brms.?domain ?? '${brmsName}.${environmentModule!.outputs.defaultDomain}'}' }
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
    domain: brms.?domain
    certificateUrl: brmsCertificateRef == null
      ? null
      : 'https://${brmsCertificateRef![8]}${environment().suffixes.keyvaultDns}/secrets/${brmsCertificateRef![10]}'
    certificateIdentityId: environmentIdentity.?id
    workspaceId: environmentModule!.outputs.workspaceId
    actionGroupId: alertActionGroupId
  }
  dependsOn: [
    brmsCertificate
  ]
}

output agentUrl string? = agent == null ? null : 'https://${agent.?domain ?? agentApp!.outputs.fqdn}'
output agentPrincipalId string? = agentIdentity.?properties.principalId
output brmsUrl string? = brms == null ? null : 'https://${brms.?domain ?? brmsApp!.outputs.fqdn}'
output brmsPrincipalId string? = brmsIdentity.?properties.principalId
output databaseHost string? = databaseModule.?outputs.host
output keyVaultUri string? = vaultModule.?outputs.uri
output storageAccountName string? = storageModule.?outputs.accountName
output storageContainerName string? = storageModule.?outputs.containerName
output storageBlobEndpoint string? = storageModule.?outputs.blobEndpoint
output vnetId string? = networkModule.?outputs.vnetId
output environmentIp string? = environmentModule.?outputs.staticIp
output customDomainVerificationId string? = environmentModule.?outputs.customDomainVerificationId
