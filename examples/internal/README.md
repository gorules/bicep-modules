# Internal

Deploys the [full stack](../full-stack) in an internal Container Apps environment. BRMS and the Agent get private addresses only, reachable from the virtual network and networks connected to it. See [Internal environment](../../README.md#internal-environment).

- Everything in the full-stack example
- Container Apps environment with a private IP and no public address
- Private DNS zone that resolves the app addresses inside the virtual network

## Deploy

Review `main.bicepparam` first. Set `allowedCidrBlocks` to the private ranges your clients use.

From the repository root:

```bash
az group create --name rg-gorules-prod --location swedencentral

export GORULES_LICENSE_KEY=...

az stack group create \
  --name gorules \
  --resource-group rg-gorules-prod \
  --template-file main.bicep \
  --parameters examples/internal/main.bicepparam \
  --action-on-unmanage deleteAll \
  --deny-settings-mode none
```

## Verify

```bash
az stack group show --name gorules --resource-group rg-gorules-prod \
  --query "{brms: outputs.brmsUrl.value, agent: outputs.agentUrl.value, ip: outputs.environmentIp.value}"
```

The addresses only resolve and answer inside the virtual network. From a machine there:

```bash
curl <brmsUrl>/api/health
```

To reach them from peered or on-premises networks, see [Internal environment](../../README.md#internal-environment).

## Outputs

Same as [full-stack](../full-stack/README.md#outputs). `environmentIp` is the environment's private IP.

## Cleanup

Same as [full-stack](../full-stack/README.md#cleanup).
