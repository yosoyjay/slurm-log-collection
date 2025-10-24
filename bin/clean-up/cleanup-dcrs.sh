#!/bin/bash
# Delete all Slurm-related Data Collection Rules

set -e

if [ -z "$RESOURCE_GROUP" ]; then
    echo "Error: Required environment variables must be set"
    echo "Required variables:"
    echo "  RESOURCE_GROUP - Azure resource group name"
    echo
    echo "Example:"
    echo "  export RESOURCE_GROUP='your-resource-group'"
    exit 1
fi

# List of DCRs to delete (based on your naming convention)
DCRS=(
    "slurmctld_raw_dcr"
    "slurmd_raw_dcr"
    "slurmjobs_raw_dcr"
    "slurmdb_raw_dcr"
    "slurmrestd_raw_dcr"
    "jetpack_raw_dcr"
    "jetpackd_raw_dcr"
    "healthagent_raw_dcr"
    "dmesg_raw_dcr"
    "syslog_raw_dcr"
)

echo "=== Cleaning Up Data Collection Rules ==="
echo "Resource Group: $RESOURCE_GROUP"
echo

echo "=== Listing Current DCRs ==="
echo "All DCRs in resource group:"
az monitor data-collection rule list -g "$RESOURCE_GROUP" --query "[].{Name:name, Location:location, Description:description}" -o table 2>/dev/null || echo "No DCRs found or error occurred"

echo
echo "=== Deleting Slurm-Related DCRs ==="

for dcr in "${DCRS[@]}"; do
    echo "Checking DCR: $dcr"

    # Check if DCR exists before attempting to delete
    DCR_EXISTS=$(az monitor data-collection rule show -g "$RESOURCE_GROUP" --name "$dcr" --query "name" -o tsv 2>/dev/null || echo "")

    if [ -n "$DCR_EXISTS" ]; then
        echo "Deleting DCR: $dcr"
        az monitor data-collection rule delete \
            -g "$RESOURCE_GROUP" \
            --name "$dcr" \
            --yes || echo "Warning: Failed to delete $dcr"
        echo "✓ Deleted: $dcr"
    else
        echo "✗ DCR not found: $dcr (may have been already deleted)"
    fi
    echo
done

echo "=== Verification ==="
echo "Remaining DCRs in resource group:"
az monitor data-collection rule list -g "$RESOURCE_GROUP" --query "[].{Name:name, Location:location}" -o table 2>/dev/null || echo "No DCRs found"

echo
echo "=== DCR Cleanup Summary ==="
echo "Attempted to delete the following DCRs:"
for dcr in "${DCRS[@]}"; do
    DCR_EXISTS=$(az monitor data-collection rule show -g "$RESOURCE_GROUP" --name "$dcr" --query "name" -o tsv 2>/dev/null || echo "")
    if [ -z "$DCR_EXISTS" ]; then
        echo "✓ $dcr - Successfully deleted or did not exist"
    else
        echo "✗ $dcr - Still exists (deletion may have failed)"
    fi
done

echo
echo "=== DCR Cleanup Complete ==="
echo "All Slurm-related Data Collection Rules have been processed."
echo "You can now safely redeploy your DCRs using the deployment scripts."
