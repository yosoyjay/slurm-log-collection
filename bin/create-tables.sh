#!/bin/bash

# Azure CLI script to create Log Analytics tables for Slurm log collection
# This script creates the destination tables required for each Data Collection Rule

# Set error handling
set -e

# Check if required environment variables are set
if [ -z "$RESOURCE_GROUP" ] || [ -z "$WORKSPACE_NAME" ]; then
    echo "Error: RESOURCE_GROUP and WORKSPACE_NAME environment variables must be set"
    echo "Example: export RESOURCE_GROUP='your-resource-group'"
    echo "         export WORKSPACE_NAME='your-workspace-name'"
    exit 1
fi

echo "Creating Log Analytics tables in workspace: $WORKSPACE_NAME"
echo "Resource group: $RESOURCE_GROUP"
echo

# Function to create a table with standard raw log schema
create_raw_table() {
    local table_name=$1
    local description=$2

    echo "Creating table: $table_name"
    az monitor log-analytics workspace table create \
        -g "$RESOURCE_GROUP" \
        --workspace-name "$WORKSPACE_NAME" \
        --name "$table_name" \
        --plan Analytics \
        --description "$description" \
        --columns \
            TimeGenerated=datetime \
            RawData=string \
            Computer=string \
            FilePath=string

    echo "✓ Created table: $table_name"
    echo
}

# Create tables for Slurm logs
echo "=== Creating Slurm Log Tables ==="
create_raw_table "slurmctld_raw_CL" "Raw logs from slurmctld daemon (scheduler)"
create_raw_table "slurmd_raw_CL" "Raw logs from slurmd daemon (compute nodes)"
create_raw_table "slurmdb_raw_CL" "Raw logs from slurmdbd daemon (database)"
create_raw_table "slurmrestd_raw_CL" "Raw logs from slurmrestd daemon (REST API)"

# Create tables for OS logs
echo "=== Creating OS Log Tables ==="
create_raw_table "syslog_raw_CL" "Raw logs from /var/log/syslog"
create_raw_table "dmesg_raw_CL" "Raw logs from /var/log/dmesg"

# Create tables for CycleCloud logs
echo "=== Creating CycleCloud Log Tables ==="
create_raw_table "jetpack_raw_CL" "Raw logs from CycleCloud jetpack.log"
create_raw_table "jetpackd_raw_CL" "Raw logs from CycleCloud jetpackd.log"

# Create tables for CycleCloud health agent logs
echo "=== Creating CycleCloud Health Agent Log Tables ==="
create_raw_table "healthagent_raw_CL" "Raw logs from CycleCloud healthagent.log"

echo "=== Table Creation Complete ==="
echo
echo "Next steps:"
echo "1. Deploy the Data Collection Rules using:"
echo "   az monitor data-collection rule create -g \$RESOURCE_GROUP --rule-file <dcr-file>"
echo "2. Associate DCRs with VMs using:"
echo "   az monitor data-collection rule association create"
echo "3. Wait ~15 minutes for first logs to appear"
echo
echo "Available tables:"
echo "- slurmctld_raw_CL  (Slurm controller daemon)"
echo "- slurmd_raw_CL     (Slurm node daemon)"
echo "- slurmdb_raw_CL    (Slurm database daemon)"
echo "- slurmrestd_raw_CL (Slurm REST API daemon)"
echo "- syslog_raw_CL     (System logs)"
echo "- dmesg_raw_CL      (Kernel logs)"
echo "- jetpack_raw_CL    (CycleCloud jetpack)"
echo "- jetpackd_raw_CL   (CycleCloud jetpack daemon)"
echo "- healthagent_raw_CL (CycleCloud health agent)"
