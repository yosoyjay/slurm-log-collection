#!/bin/bash
# Create user-assigned managed identity and assign it to scheduler VM and compute VMSS
# Grants the identity permissions to publish logs and metrics to Log Analytics workspace
set -e

# Check if required environment variables are set
if [ -z "$RESOURCE_GROUP" ] || [ -z "$SUBSCRIPTION_ID" ] || [ -z "$VM_ID" ] || [ -z "$VMSS_ID" ]; then
    echo "Error: Required environment variables must be set"
    echo "Required variables:"
    echo "  RESOURCE_GROUP - Azure resource group name"
    echo "  SUBSCRIPTION_ID - Azure subscription ID"
    echo "  VM_ID - Resource ID of the scheduler VM"
    echo "  VMSS_ID - Resource ID of the compute nodes VMSS"
    echo ""
    exit 1
fi

IDENTITY_NAME="ama-monitoring-identity"

echo "Creating user-assigned managed identity for Azure Monitor Agent"
echo "Resource Group: $RESOURCE_GROUP"
echo "Identity Name: $IDENTITY_NAME"
echo ""

# Create the monitoring identity
echo "Creating managed identity: $IDENTITY_NAME"
az identity create \
  --name "$IDENTITY_NAME" \
  --resource-group "$RESOURCE_GROUP" || echo "Warning: Identity may already exist"

# Get identity details
echo "Retrieving identity details"
IDENTITY_ID=$(az identity show --name "$IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv)
CLIENT_ID=$(az identity show --name "$IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" --query clientId -o tsv)
PRINCIPAL_ID=$(az identity show --name "$IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" --query principalId -o tsv)

echo "Identity Resource ID: $IDENTITY_ID"
echo "Client ID: $CLIENT_ID"
echo "Principal ID: $PRINCIPAL_ID"
echo ""

# Assign identity to scheduler VM
echo "Assigning identity to scheduler VM"
echo "VM ID: $VM_ID"
az vm identity assign \
  --ids "$VM_ID" \
  --identities "$IDENTITY_ID"
echo "Successfully assigned identity to scheduler VM"
echo ""

# Assign identity to VMSS
echo "Assigning identity to VMSS"
echo "VMSS ID: $VMSS_ID"
VMSS_NAME=$(basename "$VMSS_ID")
VMSS_RESOURCE_GROUP=$(echo "$VMSS_ID" | cut -d'/' -f5)
az vmss identity assign \
  --name "$VMSS_NAME" \
  --resource-group "$VMSS_RESOURCE_GROUP" \
  --identities "$IDENTITY_ID"
echo "Successfully assigned identity to VMSS"
echo ""

echo "Managed identity setup complete"
echo ""
echo "Summary:"
echo "  Identity Name: $IDENTITY_NAME"
echo "  Identity ID: $IDENTITY_ID"
echo "  Assigned to VM: $VM_ID"
echo "  Assigned to VMSS: $VMSS_ID"
echo ""
echo "Note: Role permissions will be assigned after DCRs are created"
echo ""
