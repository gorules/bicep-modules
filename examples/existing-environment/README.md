# Existing environment

Deploys an Agent into the Container Apps environment of another deployment, e.g. the [full stack](../full-stack). See [Existing environment](../../README.md#existing-environment) for the requirements.

## Get the values

From the deployment that owns the environment:

```bash
az stack group show --name gorules --resource-group rg-gorules-prod \
  --query "outputs.{environmentId: environmentId.value, workspaceId: workspaceId.value, privateEndpointSubnetId: privateEndpointSubnetId.value, privateDnsZoneIds: privateDnsZoneIds.value}"
```

Put them in `main.bicepparam`.

## Deploy

From the repository root:

```bash
az group create --name rg-gorules-team-a --location swedencentral

az stack group create \
  --name gorules \
  --resource-group rg-gorules-team-a \
  --template-file main.bicep \
  --parameters examples/existing-environment/main.bicepparam \
  --action-on-unmanage deleteAll \
  --deny-settings-mode none
```

## Publish to it

The Agent loads releases from its own storage account. To publish to it from the BRMS of the full stack, give that deployment's `brmsPrincipalId` Storage Blob Data Contributor on the `rules` container:

```bash
az role assignment create \
  --assignee-object-id <brmsPrincipalId> --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope "$(az storage account show --name <storageAccountName> --query id -o tsv)/blobServices/default/containers/rules"
```

Then add an environment deployment in BRMS with this deployment's `storageBlobEndpoint`. See [Publishing rules](../../README.md#publishing-rules). BRMS reaches the storage through the shared virtual network.

## Outputs

Same as [agent-only](../agent-only/README.md#outputs). `environmentId` and `workspaceId` are the shared ones.

## Cleanup

Delete this stack before the deployment that owns the environment:

```bash
az stack group delete --name gorules --resource-group rg-gorules-team-a --action-on-unmanage deleteAll
```
