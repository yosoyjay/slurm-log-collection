#!/bin/bash
# Assign Monitoring Metrics Publisher role to managed identity for each DCR
# This grants the identity permissions to publish logs and metrics to each Data Collection Rule
set -e

# Check if required environment variables are set
if [ -z "$RESOURCE_GROUP" ] || [ -z "$SUBSCRIPTION_ID" ]; then
    echo "Error: Required environment variables must be set"
    echo "Required variables:"
    echo "  RESOURCE_GROUP - Azure resource group name"
    echo "  SUBSCRIPTION_ID - Azure subscription ID"
    echo ""
    exit 1
fi

IDENTITY_NAME="ama-monitoring-identity"

echo "Assigning DCR permissions to managed identity"
echo "Resource Group: $RESOURCE_GROUP"
echo "Identity Name: $IDENTITY_NAME"
echo ""

# Get the principal ID of the managed identity
echo "Retrieving managed identity principal ID"
PRINCIPAL_ID=$(az identity show --name "$IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" --query principalId -o tsv)

if [ -z "$PRINCIPAL_ID" ]; then
    echo "Error: Could not find managed identity '$IDENTITY_NAME' in resource group '$RESOURCE_GROUP'"
    echo "Please run create-managed-identity.sh first"
    exit 1
fi

echo "Principal ID: $PRINCIPAL_ID"
echo ""

# List of all DCRs to assign permissions to
DCR_NAMES=(
    "slurmctld_raw_dcr"
    "slurmd_raw_dcr"
    "slurmdb_raw_dcr"
    "slurmrestd_raw_dcr"
    "slurmjobs_raw_dcr"
    "syslog_raw_dcr"
    "dmesg_raw_dcr"
    "jetpack_raw_dcr"
    "jetpackd_raw_dcr"
    "healthagent_raw_dcr"
)

echo "=== Assigning Monitoring Metrics Publisher Role to DCRs ==="
echo ""

# Counter for successful assignments
SUCCESS_COUNT=0
TOTAL_COUNT=${#DCR_NAMES[@]}

# Assign role to each DCR
for dcr_name in "${DCR_NAMES[@]}"; do
    echo "Processing DCR: $dcr_name"

    DCR_RESOURCE_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Insights/dataCollectionRules/${dcr_name}"

    # Check if DCR exists before attempting role assignment
    if az monitor data-collection rule show --name "$dcr_name" --resource-group "$RESOURCE_GROUP" > /dev/null 2>&1; then
        echo "  DCR exists, assigning role..."

        if az role assignment create \
            --assignee "$PRINCIPAL_ID" \
            --role "Monitoring Metrics Publisher" \
            --scope "$DCR_RESOURCE_ID" 2>/dev/null; then
            echo "  Successfully assigned role to $dcr_name"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            echo "  Warning: Role assignment failed or already exists for $dcr_name"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        fi
    else
        echo "  Warning: DCR '$dcr_name' not found, skipping"
    fi

    echo ""
done

echo "=== DCR Permission Assignment Complete ==="
echo ""
echo "Summary:"
echo "  Total DCRs processed: $TOTAL_COUNT"
echo "  Successful assignments: $SUCCESS_COUNT"
echo "  Identity: $IDENTITY_NAME"
echo "  Role: Monitoring Metrics Publisher"
echo ""
