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

param domain string?

@description('Key Vault secret URL of the certificate for domain. Omit for a managed certificate.')
param certificateUrl string?

@description('Environment identity that reads certificateUrl.')
param certificateIdentityId string?

@description('Log Analytics workspace of the environment.')
param workspaceId string

@description('Action group that receives alert notifications.')
param actionGroupId string?

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

resource environment 'Microsoft.App/managedEnvironments@2026-07-01' existing = {
  name: last(split(environmentId, '/'))
}

resource certificate 'Microsoft.App/managedEnvironments/certificates@2026-07-01' = if (domain != null && certificateUrl != null) {
  parent: environment
  name: name
  location: location
  tags: tags
  properties: {
    certificateKeyVaultProperties: {
      identity: certificateIdentityId
      keyVaultUrl: certificateUrl
    }
  }
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
        customDomains: domain == null
          ? []
          : [
              certificateUrl == null
                ? { name: domain!, bindingType: 'Auto' }
                : { name: domain!, bindingType: 'SniEnabled', certificateId: certificate.id }
            ]
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
            {
              type: 'Startup'
              httpGet: healthCheck
              periodSeconds: 12
              failureThreshold: 10
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

var environmentRef = split(environmentId, '/')

module managedCertificate 'managed-certificate.bicep' = if (domain != null && certificateUrl == null) {
  scope: resourceGroup(environmentRef[2], environmentRef[4])
  params: {
    environmentName: environmentRef[8]
    domain: domain!
    location: location
    tags: tags
  }
  dependsOn: [
    app
  ]
}

var metricAlerts = [
  {
    name: 'cpu-high'
    description: 'Average CPU above 80%'
    metric: 'CpuPercentage'
    aggregation: 'Average'
    threshold: 80
    dimensions: []
  }
  {
    name: 'memory-high'
    description: 'Average memory above 80%'
    metric: 'MemoryPercentage'
    aggregation: 'Average'
    threshold: 80
    dimensions: []
  }
  {
    name: '5xx'
    description: 'More than 50 server errors in 5 minutes'
    metric: 'Requests'
    aggregation: 'Total'
    threshold: 50
    dimensions: [
      {
        name: 'statusCodeCategory'
        operator: 'Include'
        values: ['5xx']
      }
    ]
  }
]

resource alerts 'Microsoft.Insights/metricAlerts@2018-03-01' = [
  for alert in metricAlerts: {
    name: '${name}-${alert.name}'
    location: 'global'
    tags: tags
    properties: {
      description: alert.description
      severity: 2
      enabled: true
      scopes: [app.id]
      evaluationFrequency: 'PT1M'
      windowSize: 'PT5M'
      criteria: {
        'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
        allOf: [
          {
            criterionType: 'StaticThresholdCriterion'
            name: alert.metric
            metricName: alert.metric
            timeAggregation: alert.aggregation
            operator: 'GreaterThan'
            threshold: alert.threshold
            dimensions: alert.dimensions
          }
        ]
      }
      autoMitigate: true
      actions: actionGroupId == null ? [] : [{ actionGroupId: actionGroupId! }]
    }
  }
]

resource unhealthy 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = {
  name: '${name}-unhealthy'
  location: location
  tags: tags
  kind: 'LogAlert'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    description: 'Replicas failing health checks'
    severity: 2
    enabled: true
    scopes: [workspaceId]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    criteria: {
      allOf: [
        {
          query: 'ContainerAppSystemLogs_CL | where ContainerAppName_s == \'${name}\' and Reason_s == \'ProbeFailed\' and Log_s has_any (\'Readiness\', \'Liveness\')'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
    // the logs table only exists once the environment has written to it
    skipQueryValidation: true
    actions: {
      actionGroups: actionGroupId == null ? [] : [actionGroupId!]
    }
  }
}

var workspaceRef = split(workspaceId, '/')

module unhealthyReader 'workspace-access.bicep' = {
  scope: resourceGroup(workspaceRef[2], workspaceRef[4])
  params: {
    workspaceName: workspaceRef[8]
    ruleId: unhealthy.id
    principalId: unhealthy.identity.principalId
  }
}

output fqdn string = app.properties.configuration.ingress.fqdn
