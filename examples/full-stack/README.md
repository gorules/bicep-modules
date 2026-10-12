# Full stack

Deploys BRMS and the Agent with PostgreSQL, Key Vault and storage. See [Architecture](../../README.md#architecture).

- Virtual network with an apps subnet and a private endpoint subnet
- PostgreSQL flexible server with zone redundant high availability and Microsoft Entra ID sign-in only
- Key Vault with the license key, cookie secret and secrets master key
- Storage account with a `rules` container
- BRMS and the Agent on Container Apps, each with an HTTPS address

## Requirements

- Azure CLI 2.61 or later
- GoRules license key
- Owner on the resource group. See [Requirements](../../README.md#requirements) for narrower roles.

## Deploy

Review `main.bicepparam` first. The example allows requests from any address and uses `Standard_D2ds_v5` with high availability. For development, remove the `database` block to get a Burstable server without high availability.

From the repository root:

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

The first deployment takes about 15 minutes.

## Verify

```bash
az stack group show --name gorules --resource-group rg-gorules-prod \
  --query "{brms: outputs.brmsUrl.value, agent: outputs.agentUrl.value}"
```

Open the BRMS address and sign in with your email. The first user becomes admin.

A successful deployment does not mean the apps are healthy. If BRMS or the Agent does not respond, look at the revision and the logs:

```bash
az containerapp revision list --name gorules-prod-brms --resource-group rg-gorules-prod -o table
az containerapp logs show --name gorules-prod-brms --resource-group rg-gorules-prod --follow
```

`environment_credentials_mismatch` in the BRMS logs means the license key is bound to another installation. Contact support to reset it.

## Publishing rules

In BRMS, add an environment deployment of type Azure Storage. Turn IAM on, set the blob service URL to the `storageBlobEndpoint` output and the container to `rules`. Then deploy a release to that environment.

To evaluate a published decision:

```bash
curl -X POST <agentUrl>/api/projects/<project-key>/evaluate/<decision> \
  -H "X-Access-Token: <project-access-token>" \
  -H "Content-Type: application/json" \
  -d '{"context": {}}'
```

## Outputs

| Name | Description |
| ---- | ----------- |
| `brmsUrl` | BRMS HTTPS address. |
| `brmsPrincipalId` | BRMS managed identity. Also the PostgreSQL admin. |
| `agentUrl` | Agent HTTPS address. |
| `agentPrincipalId` | Agent managed identity. |
| `databaseHost` | PostgreSQL host name. |
| `keyVaultUri` | Key Vault URI. |
| `storageAccountName` | Storage account. |
| `storageContainerName` | Container BRMS publishes to, `rules`. |
| `storageBlobEndpoint` | Blob service URL for the BRMS environment deployment. |
| `vnetId` | Virtual network. |

## Cleanup

Remove the database lock, then delete the stack:

```bash
SERVER=$(az postgres flexible-server list --resource-group rg-gorules-prod --query "[0].name" -o tsv)

az lock delete --name do-not-delete --resource-group rg-gorules-prod \
  --resource-type Microsoft.DBforPostgreSQL/flexibleServers --resource-name $SERVER

az stack group delete --name gorules --resource-group rg-gorules-prod --action-on-unmanage deleteAll
az group delete --name rg-gorules-prod
```

Deleting the stack takes about 30 minutes.

Key Vault keeps a deleted vault for `vault.softDeleteRetentionDays`, 90 by default. Its name can't be reused until then, so deploying again with the same resource group and names fails. For test environments, set `vault.purgeProtection` to `false` before the first deployment and purge the vault after cleanup:

```bash
az keyvault purge --name <vault>
```
