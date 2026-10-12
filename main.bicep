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

var prefix = '${projectName}-${environmentName}'

var errors = filter(
  [
    length(prefix) > 26 ? 'projectName and environmentName together must be at most 25 characters' : ''
    parseCidr(addressPrefix).cidr > 22 ? 'network.addressPrefix must be /22 or larger' : ''
    (agent.?minReplicas ?? 1) > (agent.?maxReplicas ?? 1000)
      ? 'agent.minReplicas must be less than or equal to agent.maxReplicas'
      : ''
  ],
  error => !empty(error)
)

var namePrefix = empty(errors) ? prefix : fail(join(errors, '; '))

var addressPrefix = network.?addressPrefix ?? '10.0.0.0/16'

var blobDnsZone = 'privatelink.blob.${environment().suffixes.storage}'

var allTags = union(
  {
    Project: projectName
    Environment: environmentName
    ManagedBy: 'bicep'
  },
  tags
)

var deployApps = agent != null

var registryRef = containerRegistryId == null ? null : split(containerRegistryId!, '/')

resource agentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = if (agent != null) {
  name: '${namePrefix}-agent'
  location: location
  tags: allTags
}

var agentPrincipal = agent == null ? [] : [{ id: agentIdentity.id, principalId: agentIdentity!.properties.principalId }]

module networkModule 'modules/network.bicep' = if (deployApps) {
  params: {
    namePrefix: namePrefix
    location: location
    tags: allTags
    addressPrefix: addressPrefix
    natGateway: network.?natGateway ?? false
    privateDnsZones: [
      blobDnsZone
    ]
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
    identities: agentPrincipal
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

output agentUrl string? = agent == null ? null : 'https://${agentApp!.outputs.fqdn}'
output agentPrincipalId string? = agentIdentity.?properties.principalId
output storageAccountName string? = storageModule.?outputs.accountName
output storageContainerName string? = storageModule.?outputs.containerName
output vnetId string? = networkModule.?outputs.vnetId
