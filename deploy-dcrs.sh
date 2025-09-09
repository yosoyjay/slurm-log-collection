#!/bin/bash

# Azure CLI script to deploy Data Collection Rules for Slurm log collection
# This script deploys all the DCR JSON files to Azure Monitor

# Set error handling
set -e

# Check if required environment variables are set
if [ -z "$RESOURCE_GROUP" ] || [ -z "$SUBSCRIPTION_ID" ] || [ -z "$WORKSPACE_NAME" ] || [ -z "$WORKSPACE_RESOURCE_ID" ]; then
    echo "Error: Required environment variables must be set"
    echo "Required variables:"
    echo "  RESOURCE_GROUP - Azure resource group name"
    echo "  SUBSCRIPTION_ID - Azure subscription ID"
    echo "  WORKSPACE_NAME - Log Analytics workspace name"
    echo "  WORKSPACE_RESOURCE_ID - Full resource ID of the workspace"
    echo
    echo "Example:"
    echo "  export RESOURCE_GROUP='your-resource-group'"
    echo "  export SUBSCRIPTION_ID='12345678-1234-1234-1234-123456789012'"
    echo "  export WORKSPACE_NAME='your-workspace-name'"
    echo "  export WORKSPACE_RESOURCE_ID='/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/your-rg/providers/Microsoft.OperationalInsights/workspaces/your-workspace'"
    exit 1
fi

# Set the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DCR_DIR="$SCRIPT_DIR/data-collection-rules"

echo "Deploying Data Collection Rules to Azure Monitor"
echo "Resource group: $RESOURCE_GROUP"
echo "Subscription: $SUBSCRIPTION_ID"
echo "Workspace: $WORKSPACE_NAME"
echo

# Function to update DCR template with actual values and deploy
deploy_dcr() {
    local dcr_file=$1
    local dcr_name=$2
    local description=$3

    if [ ! -f "$dcr_file" ]; then
        echo "❌ DCR file not found: $dcr_file"
        return 1
    fi

    echo "Deploying DCR: $dcr_name"
    echo "Description: $description"

    # Create a temporary file with substituted values
    temp_file=$(mktemp)

    # Replace placeholder values in the DCR JSON
    sed -e "s|{subscription-id}|$SUBSCRIPTION_ID|g" \
        -e "s|{resource-group}|$RESOURCE_GROUP|g" \
        -e "s|{workspace-name}|$WORKSPACE_NAME|g" \
        -e "s|/subscriptions/{subscription-id}/resourceGroups/{resource-group}/providers/Microsoft.OperationalInsights/workspaces/{workspace-name}|$WORKSPACE_RESOURCE_ID|g" \
        "$dcr_file" > "$temp_file"

    # Deploy the DCR
    az monitor data-collection rule create \
        --resource-group "$RESOURCE_GROUP" \
        --rule-file "$temp_file" \
        --name "$dcr_name"

    # Clean up temp file
    rm "$temp_file"

    echo "✓ Successfully deployed: $dcr_name"
    echo
}

# Deploy Slurm DCRs
echo "=== Deploying Slurm Data Collection Rules ==="
deploy_dcr "$DCR_DIR/slurm/slurmd_raw_dcr.json" "slurmd_raw_dcr" "DCR for Slurm node daemon logs"
deploy_dcr "$DCR_DIR/slurm/slurmdb_raw_dcr.json" "slurmdb_raw_dcr" "DCR for Slurm database daemon logs"
deploy_dcr "$DCR_DIR/slurm/slurmrestd_raw_dcr.json" "slurmrestd_raw_dcr" "DCR for Slurm REST API daemon logs"

# Deploy OS DCRs
echo "=== Deploying OS Data Collection Rules ==="
deploy_dcr "$DCR_DIR/os/syslog_raw_dcr.json" "syslog_raw_dcr" "DCR for system logs"
deploy_dcr "$DCR_DIR/os/dmesg_raw_dcr.json" "dmesg_raw_dcr" "DCR for kernel logs"

# Deploy CycleCloud DCRs
echo "=== Deploying CycleCloud Data Collection Rules ==="
deploy_dcr "$DCR_DIR/cyclecloud/jetpack_raw_dcr.json" "jetpack_raw_dcr" "DCR for CycleCloud jetpack logs"
deploy_dcr "$DCR_DIR/cyclecloud/jetpackd_raw_dcr.json" "jetpackd_raw_dcr" "DCR for CycleCloud jetpack daemon logs"

# Deploy AzSlurm DCRs
echo "=== Deploying AzSlurm Data Collection Rules ==="
deploy_dcr "$DCR_DIR/azslurm/healthagent_raw_dcr.json" "healthagent_raw_dcr" "DCR for AzSlurm health agent logs"

echo "=== DCR Deployment Complete ==="
echo
echo "Next steps:"
echo "1. Associate DCRs with your VMs using:"
echo "   az monitor data-collection rule association create \\"
echo "     --resource-group \$RESOURCE_GROUP \\"
echo "     --association-name \"<association-name>\" \\"
echo "     --rule-id \"/subscriptions/\$SUBSCRIPTION_ID/resourceGroups/\$RESOURCE_GROUP/providers/Microsoft.Insights/dataCollectionRules/<dcr-name>\" \\"
echo "     --resource \"/subscriptions/\$SUBSCRIPTION_ID/resourceGroups/<vm-resource-group>/providers/Microsoft.Compute/virtualMachines/<vm-name>\""
echo
echo "2. Wait approximately 15 minutes for the first logs to appear in Log Analytics"
echo
echo "3. Query your logs using KQL in Log Analytics workspace:"
echo "   slurmctld_raw_CL | limit 10"
echo "   slurmd_raw_CL | limit 10"
echo "   syslog_raw_CL | limit 10"
