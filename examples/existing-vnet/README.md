# Existing virtual network

Deploys the [full stack](../full-stack) into subnets you already have. See [Existing virtual network](../../README.md#existing-virtual-network) for the requirements.

## Prepare the subnets

```bash
az network vnet subnet create --resource-group rg-network --vnet-name vnet-prod \
  --name gorules-apps --address-prefixes 10.0.4.0/27 --delegations Microsoft.App/environments

az network vnet subnet create --resource-group rg-network --vnet-name vnet-prod \
  --name gorules-endpoints --address-prefixes 10.0.4.32/27
```

Put the subnet IDs in `main.bicepparam`:

```bash
az network vnet subnet show --resource-group rg-network --vnet-name vnet-prod --name gorules-apps --query id -o tsv
```

If the virtual network already uses central `privatelink` DNS zones, add them as `network.privateDnsZoneIds`.

## Deploy

From the repository root:

```bash
az group create --name rg-gorules-prod --location swedencentral

export GORULES_LICENSE_KEY=...

az stack group create \
  --name gorules \
  --resource-group rg-gorules-prod \
  --template-file main.bicep \
  --parameters examples/existing-vnet/main.bicepparam \
  --action-on-unmanage deleteAll \
  --deny-settings-mode none
```

## Verify and outputs

Same as [full-stack](../full-stack/README.md#verify). `vnetId` is your virtual network.

## Cleanup

Same as [full-stack](../full-stack/README.md#cleanup). Your virtual network and subnets stay.
