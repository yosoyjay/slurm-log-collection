#!/bin/bash
# Install Azure Monitor Agent on VMs and VM Scale Sets
set -e

if [ -z "$RESOURCE_GROUP" ] || [ -z "$VM_ID" ] || [ -z "$VMSS_NAME" ]; then
    echo "Error: Required environment variables must be set"
    echo "Required variables:"
    echo "  RESOURCE_GROUP - Azure resource group name"
    echo "  VM_ID - Full resource ID of scheduler VM"
    echo "  VMSS_NAME - Name of VMSS to install logging"
    echo ""
    exit 1
fi

# AMA must be told which identity to use for DCR ingestion. When a node carries
# multiple user-assigned identities (or any UAMI without a system-assigned
# identity), AMA cannot pick a credential on its own: the extension still reports
# provisioningState=Succeeded but ingests ZERO rows. Pin AMA to the monitoring
# identity created by create-managed-identity.sh via the authentication.managedIdentity
# selector so ingestion actually authenticates.
IDENTITY_NAME="ama-monitoring-identity"
IDENTITY_ID=$(az identity show --name "$IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv)
if [ -z "$IDENTITY_ID" ]; then
    echo "Error: Could not find managed identity '$IDENTITY_NAME' in resource group '$RESOURCE_GROUP'"
    echo "Please run create-managed-identity.sh first"
    exit 1
fi
AMA_SETTINGS=$(jq -nc --arg id "$IDENTITY_ID" \
    '{authentication:{managedIdentity:{"identifier-name":"mi_res_id","identifier-value":$id}}}')
echo "Pinning AMA to managed identity: $IDENTITY_ID"

# Install on Scheduler VM
echo "Installing AzureMonitorLinuxAgent VM extension on VM: ${VM_ID}"
az vm extension set --name AzureMonitorLinuxAgent --publisher Microsoft.Azure.Monitor --ids $VM_ID --enable-auto-upgrade true --settings "$AMA_SETTINGS"
if az vm extension list --ids $VM_ID | \
   jq -e '.[] | select(.name | endswith("AzureMonitorLinuxAgent"))' > /dev/null; then
  echo "AzureMonitorLinuxAgent extension installed "
else
  echo "AzureMonitorLinuxAgent extension NOT installed"
fi

# Install on VMSS
echo "Adding AzureMonitorLinuxAgent VM extension to VMSS: ${VMSS_NAME}"
az vmss extension set --name AzureMonitorLinuxAgent --publisher Microsoft.Azure.Monitor -g $RESOURCE_GROUP --vmss-name $VMSS_NAME --enable-auto-upgrade true --settings "$AMA_SETTINGS"
# Update VMSS model so extension will install
echo "Updating VMSS model to install AzureMonitorLinuxAgent on VMs"
az vmss update-instances --instance-ids '*' -g $RESOURCE_GROUP -n $VMSS_NAME
if az vmss extension list -g $RESOURCE_GROUP --vmss-name $VMSS_NAME | \
   jq -e '.[] | select(.name | endswith("AzureMonitorLinuxAgent"))' > /dev/null; then
  echo "AzureMonitorLinuxAgent extension installed "
else
  echo "AzureMonitorLinuxAgent extension NOT installed"
fi
