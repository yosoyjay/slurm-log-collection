#!/bin/bash
# Delete all DCR associations for your VMs and VMSS

set -e

if [ -z "$RESOURCE_GROUP" ] || [ -z "$VM_ID" ] || [ -z "$VMSS_ID" ]; then
    echo "Error: Required environment variables must be set"
    echo "Required variables:"
    echo "  RESOURCE_GROUP - Azure resource group name"
    echo "  VM_ID - Full resource ID of scheduler VM"
    echo "  VMSS_ID - Full resource ID of compute VMSS"
    echo
    echo "Example:"
    echo "  export RESOURCE_GROUP='your-resource-group'"
    echo "  export VM_ID='/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/vm-rg/providers/Microsoft.Compute/virtualMachines/scheduler-vm'"
    echo "  export VMSS_ID='/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/vm-rg/providers/Microsoft.Compute/virtualMachineScaleSets/compute-vmss'"
    exit 1
fi

echo "=== Cleaning Up DCR Associations ==="
echo "Resource Group: $RESOURCE_GROUP"
echo "Scheduler VM: $VM_ID"
echo "Compute VMSS: $VMSS_ID"
echo

echo "=== Listing Current DCR Associations ==="
echo
echo "Scheduler VM associations:"
az monitor data-collection rule association list --resource "$VM_ID" --query "[].{Name:name, RuleName:dataCollectionRuleId}" -o table 2>/dev/null || echo "No associations found or error occurred"

echo
echo "VMSS associations:"
az monitor data-collection rule association list --resource "$VMSS_ID" --query "[].{Name:name, RuleName:dataCollectionRuleId}" -o table 2>/dev/null || echo "No associations found or error occurred"

echo
echo "=== Deleting Scheduler VM Associations ==="

# Get association names for scheduler VM
SCHEDULER_ASSOCIATIONS=$(az monitor data-collection rule association list --resource "$VM_ID" --query "[].name" -o tsv 2>/dev/null || echo "")

if [ -z "$SCHEDULER_ASSOCIATIONS" ]; then
    echo "No scheduler VM associations found"
else
    for association in $SCHEDULER_ASSOCIATIONS; do
        if [ -n "$association" ]; then
            echo "Deleting scheduler association: $association"
            az monitor data-collection rule association delete \
                --name "$association" \
                --resource "$VM_ID" \
                --yes || echo "Warning: Failed to delete $association"
        fi
    done
fi

echo
echo "=== Deleting VMSS Associations ==="

# Get association names for VMSS
VMSS_ASSOCIATIONS=$(az monitor data-collection rule association list --resource "$VMSS_ID" --query "[].name" -o tsv 2>/dev/null || echo "")

if [ -z "$VMSS_ASSOCIATIONS" ]; then
    echo "No VMSS associations found"
else
    for association in $VMSS_ASSOCIATIONS; do
        if [ -n "$association" ]; then
            echo "Deleting VMSS association: $association"
            az monitor data-collection rule association delete \
                --name "$association" \
                --resource "$VMSS_ID" \
                --yes || echo "Warning: Failed to delete $association"
        fi
    done
fi

echo
echo "=== Verification ==="
echo
echo "Remaining scheduler VM associations:"
az monitor data-collection rule association list --resource "$VM_ID" --query "[].name" -o table 2>/dev/null || echo "No associations found"

echo
echo "Remaining VMSS associations:"
az monitor data-collection rule association list --resource "$VMSS_ID" --query "[].name" -o table 2>/dev/null || echo "No associations found"

echo
echo "=== Association Cleanup Complete ==="
echo "All DCR associations have been deleted from:"
echo "- Scheduler VM: $(basename "$VM_ID")"
echo "- Compute VMSS: $(basename "$VMSS_ID")"
echo
echo "You can now safely delete the Data Collection Rules."
