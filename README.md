# GoRules Bicep Modules

Bicep modules for deploying [GoRules](https://gorules.io) on Azure Container Apps.

## What is GoRules?

GoRules is a Business Rules Management System (BRMS) for managing and executing business rules. It has two components:

- **BRMS** - Management UI and API for creating, editing and publishing rules. Requires a database and blob storage.
- **Agent** - Stateless rule execution engine that pulls published rules from blob storage. Scales independently from BRMS.

## Architecture

```mermaid
flowchart TB
    Internet((Internet))

    subgraph VNet["Virtual network"]
        subgraph Apps["apps subnet"]
            BRMS[BRMS]
            Agent[Agent]
        end

        subgraph Endpoints["private-endpoints subnet"]
            BlobPE[Blob]
            VaultPE[Key Vault]
            PostgresPE[PostgreSQL]
        end
    end

    Storage[(Storage account)]
    Vault[(Key Vault)]
    Postgres[(PostgreSQL<br/>flexible server)]

    Internet -->|HTTPS| BRMS
    Internet -->|HTTPS| Agent
    BRMS --> PostgresPE --> Postgres
    BRMS --> VaultPE --> Vault
    BRMS --> BlobPE
    Agent --> BlobPE --> Storage
```

- BRMS and the Agent run in a Container Apps environment inside the virtual network. Each gets an HTTPS address under `*.azurecontainerapps.io`, so BRMS works without a custom domain.
- PostgreSQL, Key Vault and storage are private, reached through private endpoints.
- The apps use managed identities, not passwords or keys. BRMS signs in to PostgreSQL with Microsoft Entra ID, reads Key Vault and writes to storage. The Agent reads storage and its own Key Vault secrets.
- Logs go to a Log Analytics workspace.

## Deployment patterns

| Pattern | Components | Example |
| ------- | ---------- | ------- |
| Full stack | BRMS + Agent + PostgreSQL + Key Vault + storage | [full-stack](examples/full-stack) |
| Agent only | Agent + storage | [agent-only](examples/agent-only) |
| Internal | Full stack, reachable only from the virtual network | [internal](examples/internal) |
| Existing virtual network | Full stack in your own subnets | [existing-vnet](examples/existing-vnet) |

## Requirements

| Name | Version |
| ---- | ------- |
| Azure CLI | >= 2.61 |
| Bicep CLI | >= 0.48.1 |
| GoRules Agent | >= 2.0.2 |

The deployer needs Owner on the resource group. With `database.deletionProtection` off, Contributor plus Role Based Access Control Administrator is enough. A private registry also needs role assignment rights on the registry.

## Quick start

```bash
az group create --name rg-gorules-prod --location swedencentral

export GORULES_LICENSE_KEY=...

az stack group create \
  --name gorules \
  --resource-group rg-gorules-prod \
  --template-file main.bicep \
  --parameters examples/full-stack/main.bicepparam \
  --action-on-unmanage deleteAll \
  --deny-settings-mode none
```

The `brmsUrl` and `agentUrl` outputs are the HTTPS addresses. To preview changes, run `az deployment group what-if` with the same template and parameters. It skips the Key Vault resources because they take secure parameters.

To remove everything the stack created, first delete the database lock if deletion protection is on:

```bash
az lock delete --name do-not-delete --resource-group rg-gorules-prod \
  --resource-type Microsoft.DBforPostgreSQL/flexibleServers --resource-name <server>

az stack group delete --name gorules --resource-group rg-gorules-prod --action-on-unmanage deleteAll
```

## Parameters

| Name | Default | Description |
| ---- | ------- | ----------- |
| `projectName` | required | Used in resource names. Together with `environmentName` at most 25 characters. |
| `environmentName` | required | Used in resource names, e.g. `dev`, `prod`. |
| `location` | resource group location | Azure region. |
| `tags` | `{}` | Merged with `Project`, `Environment` and `ManagedBy`. |
| `zoneRedundant` | `true` | Spreads the Container Apps environment, storage, the NAT gateway and a high-availability database across availability zones. Set `false` in regions without zones. Can't be changed later. |
| `network.addressPrefix` | `10.0.0.0/16` | Virtual network range, `/22` or larger. |
| `network.natGateway` | `false` | Sends outbound traffic through a NAT gateway with a static public IP. With `zoneRedundant` on, not available in India South Central. |
| `network.internal` | `false` | Makes BRMS and the Agent reachable only from the virtual network. See [Internal environment](#internal-environment). Can't be changed later. |
| `network.appsSubnetId` | none | Existing subnet for Container Apps. See [Existing virtual network](#existing-virtual-network). Can't be changed later. |
| `network.privateEndpointSubnetId` | none | Existing subnet for the private endpoints. |
| `network.privateDnsZoneIds` | none | Existing private DNS zones for the private endpoints. |
| `storage.versioning` | `true` | Keeps previous versions of overwritten blobs. |
| `containerRegistryId` | none | Azure Container Registry to pull images from with managed identity. |
| `brms` | none | BRMS settings, see below. Omit to skip BRMS. |
| `agent` | none | Agent settings, see below. Omit to skip the Agent. |
| `database` | `{}` | PostgreSQL settings for BRMS, see below. |
| `vault` | `{}` | Key Vault settings, see below. |
| `licenseKey` | required with BRMS | GoRules license key. Secure. |
| `aiApiKey` | required with `brms.ai` | API key for the AI provider. Secure. |
| `brmsSecrets` | `{}` | Extra secret environment variables for BRMS, e.g. `{ SSO_OAUTH2_CLIENT_SECRET: '...' }`. Stored in Key Vault. Secure. |
| `agentSecrets` | `{}` | Extra secret environment variables for the Agent, e.g. `{ RELEASE_ZIP_PASSWORD: '...' }`. Stored in Key Vault. Secure. |

### BRMS and Agent

Both take the same settings, plus the BRMS-only ones marked below.

| Name | Default | Description |
| ---- | ------- | ----------- |
| `image` | `docker.io/gorules/brms:latest`, `docker.io/gorules/agent:latest` | Container image. |
| `cpu` | `1` (BRMS), `0.5` (Agent) | vCPU per replica, `0.25` to `4` in steps of `0.25`. Memory is twice the vCPU in GiB. |
| `minReplicas` | `1` | Use 2 or more with zone redundancy. |
| `maxReplicas` | required | Up to 1000. |
| `cpuTarget` | `60` | Average CPU percentage that triggers scaling. |
| `allowedCidrBlocks` | required | Client ranges allowed in, e.g. `["0.0.0.0/0"]`. |
| `domain` | none | Custom domain. See [Custom domains](#custom-domains). |
| `certificateId` | none | Key Vault certificate for `domain`. Omit for a free managed certificate. |
| `env` | `[]` | Extra environment variables, `[{ name, value }]`. |
| `secretsProvider` | `env` | BRMS only. See [Secrets encryption](#secrets-encryption). |
| `ai` | none | BRMS only. See [AI assistant](#ai-assistant). |

### Database

| Name | Default | Description |
| ---- | ------- | ----------- |
| `version` | `17` | PostgreSQL major version: `16`, `17` or `18`. |
| `sku` | `Standard_B2s` | Compute size. Burstable sizes (`Standard_B*`) suit development; use General Purpose (`Standard_D2ds_v5` and up) for production. |
| `storageSizeGB` | `32` | Grows automatically. Redeploys keep the grown size. |
| `highAvailability` | `false` | Standby replica, zone redundant when `zoneRedundant` is on. Not available on Burstable sizes. |
| `backupRetentionDays` | `7` | 7 to 35. |
| `geoRedundantBackup` | `false` | Copies backups to the paired region. Can't be changed later. |
| `deletionProtection` | `true` | Locks the server against deletion. |

### Key Vault

Agent-only deployments get a Key Vault only when `agentSecrets` is set.

| Name | Default | Description |
| ---- | ------- | ----------- |
| `softDeleteRetentionDays` | `90` | Days a deleted vault and its secrets can be recovered, 7 to 90. Can't be changed later. |
| `purgeProtection` | `true` | Blocks permanent deletion during the retention period. Can't be turned off once on. |

## Internal environment

```bicep
param network = {
  internal: true
}
```

BRMS and the Agent then get a private IP in the virtual network and no public address. They are reachable from the virtual network and from networks connected to it by peering, VPN or ExpressRoute. Set `allowedCidrBlocks` to those private ranges.

The template creates a private DNS zone for the environment's default domain and links it to the virtual network, so `brmsUrl` and `agentUrl` resolve there. Other networks need the same names. Link the zone to them or point a wildcard record for the domain at the `environmentIp` output in your own DNS.

The apps keep HTTPS on the default domain. Outbound traffic still reaches the internet, which BRMS needs for its license check.

## Existing virtual network

```bicep
param network = {
  appsSubnetId: '/subscriptions/.../virtualNetworks/vnet-prod/subnets/gorules-apps'
  privateEndpointSubnetId: '/subscriptions/.../virtualNetworks/vnet-prod/subnets/gorules-endpoints'
}
```

- Both subnets must be in the same virtual network, in the subscription and region of the deployment.
- The apps subnet is only for Container Apps. Delegate it to `Microsoft.App/environments` and make it `/27` or larger. A `/27` runs up to 90 replicas.
- Routes and network security groups on the subnets must let the apps reach the internet and Azure. BRMS checks its license online. See [securing a virtual network](https://learn.microsoft.com/azure/container-apps/firewall-integration) for the rules Container Apps needs.
- `natGateway` and `addressPrefix` don't apply. Outbound traffic follows your routes.
- The deployer also needs Network Contributor on the virtual network.

The template creates private DNS zones for storage, Key Vault and PostgreSQL and links them to the virtual network. A virtual network can be linked to only one zone per name, so if yours already uses central `privatelink` zones, pass them instead:

```bicep
privateDnsZoneIds: [
  '/subscriptions/.../privateDnsZones/privatelink.blob.core.windows.net'
  '/subscriptions/.../privateDnsZones/privatelink.vaultcore.azure.net'
  '/subscriptions/.../privateDnsZones/privatelink.postgres.database.azure.com'
]
```

The private endpoints then register in these zones. The PostgreSQL zone is only needed with BRMS. The deployer needs Private DNS Zone Contributor on the zones. Your DNS has to resolve them.

## Custom domains

```bicep
param brms = {
  // ...
  domain: 'brms.example.com'
}
```

BRMS and the Agent can each have a custom domain. Before setting `domain`, add two records at your DNS provider:

| Type | Name | Value |
| ---- | ---- | ----- |
| CNAME | `brms.example.com` | The app's default host, e.g. `gorules-prod-brms.<unique>.<region>.azurecontainerapps.io` |
| TXT | `asuid.brms.example.com` | The `customDomainVerificationId` output |

`brmsUrl` shows the default host until `domain` is set. Then set `domain` and deploy again. `brmsUrl` and the links BRMS sends switch to the domain.

Without `certificateId`, Container Apps issues a free certificate and renews it. The certificate authority checks the domain over the internet, so:

- `allowedCidrBlocks` must include `0.0.0.0/0` and the environment can't be internal.
- The CNAME must point straight at the app, not through a proxy or CDN.
- The domain must be a subdomain like `brms.example.com`.
- If the domain has CAA records, one of them must allow `digicert.com`.

To use your own certificate, import it into Key Vault and set `certificateId` to the vault resource ID followed by `/secrets/<certificate name>`. The vault must use Azure RBAC. The template gives a `<project>-<environment>-env` identity Key Vault Secrets User on the certificate, so the deployer needs Owner or Role Based Access Control Administrator on the vault. Container Apps picks up a renewed certificate within 12 hours. If the vault blocks public access, the environment's virtual network needs a private endpoint to it. Without one the import fails with a permission error.

In an internal environment Azure doesn't check the DNS records. Point the domain at `environmentIp` in your DNS and use `certificateId`.

## Secrets encryption

BRMS encrypts secrets stored in rules with a key that the template creates:

- `env` (default): a random master key, generated once and stored in Key Vault.
- `azure-keyvault`: an RSA key in Key Vault. The key never leaves the vault.

> [!CAUTION]
> **Never delete or rotate the key.** Deleting the master key secret or the RSA key makes all BRMS secrets unreadable. BRMS always uses the newest RSA key version, so rotating it breaks secrets encrypted with an older one. Keep purge protection on in production.
>
> **Choose `secretsProvider` before first use.** Switching it later makes existing BRMS secrets unreadable. The stack also deletes the old master key secret.

The cookie secret and master key are generated on the first deployment only. Later deployments keep them.

## AI assistant

```bicep
param brms = {
  // ...
  ai: {
    provider: 'anthropic'
    model: 'claude-sonnet-4-6'
  }
}
param aiApiKey = readEnvironmentVariable('ANTHROPIC_API_KEY')
```

| Name | Default | Description |
| ---- | ------- | ----------- |
| `provider` | required | `openai`, `anthropic`, `google` or `azure-openai`. |
| `model` | required | Model name. For `azure-openai`, the deployment name. |
| `temperature` | `0.4` | 0 to 2, as a string. |
| `maxOutputTokens` | `32000` | |
| `thinkingLevel` | `medium` | `high` or `medium`. |
| `contextWindow` | none | Overrides the context window size. |
| `azureResourceName` | none | Required for `azure-openai`. |

Container Apps times out requests after 240 seconds, enough for slow first responses from large models.

## Publishing rules

BRMS publishes releases to the `rules` container and the Agent loads them from there. In BRMS, add an environment deployment of type Azure Storage. Turn IAM on, set the blob service URL to the `storageBlobEndpoint` output and the container to `rules`.

Storage only accepts traffic through its private endpoint. A publisher outside this deployment needs network access to it and Storage Blob Data Contributor on the container.

To password-protect releases, set the same `RELEASE_ZIP_PASSWORD` in `brmsSecrets` and `agentSecrets`. BRMS encrypts the release zips with it and the Agent decrypts them.

## Container images

Container Apps pulls public images anonymously from Docker Hub, which rate-limits pulls. For production, copy the images to your own Azure Container Registry and set `containerRegistryId` and the `image` fields:

```bash
az acr import --name myregistry --source docker.io/gorules/brms:latest --image gorules/brms:latest
az acr import --name myregistry --source docker.io/gorules/agent:latest --image gorules/agent:latest
```

## License

[MIT](LICENSE)
