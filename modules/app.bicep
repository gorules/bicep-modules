param name string
param location string
param tags object
param environmentId string
param identityId string
param identityClientId string
param registryServer string?
param image string
param cpu string
param port int
param minReplicas int
param maxReplicas int
param cpuTarget int
param allowedCidrBlocks string[]
param env array

@description('Key Vault secrets exposed as environment variables, [{ name, keyVaultUrl }].')
param secrets array = []

var memoryByCpu = {
  '0.25': '0.5Gi'
  '0.5': '1Gi'
  '0.75': '1.5Gi'
  '1': '2Gi'
  '1.25': '2.5Gi'
  '1.5': '3Gi'
  '1.75': '3.5Gi'
  '2': '4Gi'
  '2.25': '4.5Gi'
  '2.5': '5Gi'
  '2.75': '5.5Gi'
  '3': '6Gi'
  '3.25': '6.5Gi'
  '3.5': '7Gi'
  '3.75': '7.5Gi'
  '4': '8Gi'
}

var healthCheck = {
  path: '/api/health'
  port: port
}

resource app 'Microsoft.App/containerApps@2026-07-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    environmentId: environmentId
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: port
        allowInsecure: false
        ipSecurityRestrictions: map(allowedCidrBlocks, (cidr, i) => {
          name: 'allow-${i}'
          ipAddressRange: cidr
          action: 'Allow'
        })
      }
      registries: registryServer == null
        ? []
        : [
            {
              server: registryServer
              identity: identityId
            }
          ]
      secrets: map(secrets, secret => {
        name: toLower(replace(secret.name, '_', '-'))
        keyVaultUrl: secret.keyVaultUrl
        identity: identityId
      })
    }
    template: {
      containers: [
        {
          name: name
          image: image
          resources: {
            cpu: json(cpu)
            memory: memoryByCpu[cpu]
          }
          env: concat(
            [
              { name: 'AZURE_CLIENT_ID', value: identityClientId }
            ],
            env,
            map(secrets, secret => {
              name: secret.name
              secretRef: toLower(replace(secret.name, '_', '-'))
            })
          )
          probes: [
            {
              type: 'Startup'
              httpGet: healthCheck
              periodSeconds: 5
              failureThreshold: 24
            }
            {
              type: 'Liveness'
              httpGet: healthCheck
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: healthCheck
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'cpu'
            custom: {
              type: 'cpu'
              metadata: {
                type: 'Utilization'
                value: string(cpuTarget)
              }
            }
          }
        ]
      }
    }
  }
}

output fqdn string = app.properties.configuration.ingress.fqdn
