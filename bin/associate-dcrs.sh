#!/bin/bash
# Azure CLI script to associate Data Collection Rules with VMs for Slurm log collection
# This script creates associations between DCRs and VMs based on VM roles
# - Scheduler: Single VM (VM_ID from .env)
# - Compute nodes: VMSS instances (VMSS_ID from .env)

# Set error handling
set -e

# Check if required environment variables are set
if [ -z "$RESOURCE_GROUP" ] || [ -z "$SUBSCRIPTION_ID" ] || [ -z "$VM_ID" ] || [ -z "$VMSS_ID" ]; then
    echo "Error: Required environment variables must be set"
    echo "Required variables:"
    echo "  RESOURCE_GROUP - Azure resource group where DCRs are deployed"
    echo "  SUBSCRIPTION_ID - Azure subscription ID"
    echo "  VM_ID - Resource ID of the scheduler VM"
    echo "  VMSS_ID - Resource ID of the compute nodes VMSS"
    echo
    echo "Example:"
    echo "  export RESOURCE_GROUP='dcr-resource-group'"
    echo "  export SUBSCRIPTION_ID='12345678-1234-1234-1234-123456789012'"
    echo "  export VM_ID='/subscriptions/.../virtualMachines/scheduler-vm'"
    echo "  export VMSS_ID='/subscriptions/.../virtualMachineScaleSets/compute-vmss'"
    exit 1
fi

# Extract resource groups from resource IDs
VM_RESOURCE_GROUP=$(echo "$VM_ID" | cut -d'/' -f5)
VMSS_RESOURCE_GROUP=$(echo "$VMSS_ID" | cut -d'/' -f5)

# Get VMSS name from VMSS_ID for naming associations
VMSS_NAME=$(basename "$VMSS_ID")

# Get VM name from VM_ID for naming associations
SCHEDULER_VM_NAME=$(basename "$VM_ID")

echo "Associating Data Collection Rules with VMs"
echo "DCR Resource Group: $RESOURCE_GROUP"
echo "Scheduler VM Resource Group: $VM_RESOURCE_GROUP"
echo "VMSS Resource Group: $VMSS_RESOURCE_GROUP"
echo "Scheduler VM ID: $VM_ID"
echo "Compute VMSS ID: $VMSS_ID"
echo

# Function to create DCR association
create_dcr_association() {
    local dcr_name=$1
    local resource_id=$2
    local association_name=$3
    local description=$4

    echo "Creating association: $association_name"
    echo "  DCR: $dcr_name"
    echo "  Description: $description"

    local dcr_resource_id="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Insights/dataCollectionRules/$dcr_name"

    az monitor data-collection rule association create \
        --association-name "$association_name" \
        --rule-id "$dcr_resource_id" \
        --resource "$resource_id" || echo "Warning: Failed to create $association_name"
    echo
}

echo "=== Creating Scheduler VM Associations ==="
echo "Associating scheduler-specific DCRs with: $SCHEDULER_VM_NAME"
echo

# Scheduler-only DCRs (logs only exist on scheduler or can be centrally collected there)
create_dcr_association "slurmctld_raw_dcr" "$VM_ID" "slurmctld-${SCHEDULER_VM_NAME}-association" "Slurm controller daemon logs"
create_dcr_association "slurmdb_raw_dcr" "$VM_ID" "slurmdb-${SCHEDULER_VM_NAME}-association" "Slurm database daemon logs"
create_dcr_association "slurmrestd_raw_dcr" "$VM_ID" "slurmrestd-${SCHEDULER_VM_NAME}-association" "Slurm REST API daemon logs"
create_dcr_association "slurmjobs_raw_dcr" "$VM_ID" "slurmjobs-${SCHEDULER_VM_NAME}-association" "Slurm job archive logs"
create_dcr_association "healthagent_raw_dcr" "$VM_ID" "healthagent-${SCHEDULER_VM_NAME}-association" "CycleCloud health agent logs"

# Scheduler + nodes DCRs (logs exist on both scheduler and nodes)
create_dcr_association "syslog_raw_dcr" "$VM_ID" "syslog-${SCHEDULER_VM_NAME}-association" "System logs from scheduler"
create_dcr_association "jetpack_raw_dcr" "$VM_ID" "jetpack-${SCHEDULER_VM_NAME}-association" "CycleCloud jetpack logs from scheduler"
create_dcr_association "jetpackd_raw_dcr" "$VM_ID" "jetpackd-${SCHEDULER_VM_NAME}-association" "CycleCloud jetpack daemon logs from scheduler"

echo "=== Creating VMSS Compute Node Associations ==="
echo "Associating compute-node DCRs with VMSS: $VMSS_NAME"
echo

# VMSS-specific DCRs (logs only exist on compute nodes)
create_dcr_association "slurmd_raw_dcr" "$VMSS_ID" "slurmd-${VMSS_NAME}-association" "Slurm node daemon logs"
create_dcr_association "dmesg_raw_dcr" "$VMSS_ID" "dmesg-${VMSS_NAME}-association" "Kernel logs from compute nodes"

# Scheduler + nodes DCRs (logs exist on both scheduler and nodes)
create_dcr_association "syslog_raw_dcr" "$VMSS_ID" "syslog-${VMSS_NAME}-association" "System logs from compute nodes"
create_dcr_association "jetpack_raw_dcr" "$VMSS_ID" "jetpack-${VMSS_NAME}-association" "CycleCloud jetpack logs from compute nodes"
create_dcr_association "jetpackd_raw_dcr" "$VMSS_ID" "jetpackd-${VMSS_NAME}-association" "CycleCloud jetpack daemon logs from compute nodes"

echo "Completed associations for VMSS: $VMSS_NAME"
echo

echo "=== DCR Association Summary ==="
echo
echo "Association Mapping by Resource Type:"
echo
echo "Scheduler VM ($SCHEDULER_VM_NAME):"
echo "  slurmctld_raw_dcr - Slurm controller logs"
echo "  slurmdb_raw_dcr - Slurm database logs"
echo "  slurmrestd_raw_dcr - Slurm REST API logs"
echo "  slurmjobs_raw_dcr - Slurm job archive logs"
echo "  healthagent_raw_dcr - CycleCloud health agent logs"
echo "  syslog_raw_dcr - System logs"
echo "  jetpack_raw_dcr - CycleCloud jetpack logs"
echo "  jetpackd_raw_dcr - CycleCloud jetpack daemon logs"
echo
echo "Compute VMSS ($VMSS_NAME):"
echo "  slurmd_raw_dcr - Slurm node daemon logs"
echo "  dmesg_raw_dcr - Kernel logs"
echo "  syslog_raw_dcr - System logs"
echo "  jetpack_raw_dcr - CycleCloud jetpack logs"
echo "  jetpackd_raw_dcr - CycleCloud jetpack daemon logs"
echo
