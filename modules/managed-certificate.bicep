param environmentName string
param domain string
param location string
param tags object

resource environment 'Microsoft.App/managedEnvironments@2026-07-01' existing = {
  name: environmentName
}

resource certificate 'Microsoft.App/managedEnvironments/managedCertificates@2026-07-01' = {
  parent: environment
  name: replace(domain, '.', '-')
  location: location
  tags: tags
  properties: {
    subjectName: domain
    domainControlValidation: 'CNAME'
  }
}
