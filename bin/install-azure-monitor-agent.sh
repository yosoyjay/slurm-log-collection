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

# Install on Scheduler VM
echo "Installing AzureMonitorLinuxAgent VM extension on VM: ${VM_ID}"
az vm extension set --name AzureMonitorLinuxAgent --publisher Microsoft.Azure.Monitor --ids $VM_ID --enable-auto-upgrade true
if az vm extension list --ids $VM_ID | \
   jq -e '.[] | select(.name == "AzureMonitorLinuxAgent")' > /dev/null; then
  echo "AzureMonitorLinuxAgent extension installed "
else
  echo "AzureMonitorLinuxAgent extension NOT installed"
fi

# Install on VMSS
echo "Adding AzureMonitorLinuxAgent VM extension to VMSS: ${VMSS_NAME}"
az vmss extension set --name AzureMonitorLinuxAgent --publisher Microsoft.Azure.Monitor -g $RESOURCE_GROUP --vmss-name $VMSS_NAME --enable-auto-upgrade true
# Update VMSS model so extension will install
echo "Updating VMSS model to install AzureMonitorLinuxAgent on VMs"
az vmss update-instances --instance-ids '*' -g $RESOURCE_GROUP -n $VMSS_NAME
if az vmss extension list -g $RESOURCE_GROUP --vmss-name $VMSS_NAME | \
   jq -e '.[] | select(.name == "AzureMonitorLinuxAgent")' > /dev/null; then
  echo "AzureMonitorLinuxAgent extension installed "
else
  echo "AzureMonitorLinuxAgent extension NOT installed"
fi
