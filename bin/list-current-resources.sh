#!/bin/bash

# List all current DCRs, associations, and tables for inspection
# This script provides a comprehensive view of the current log collection setup

set -e

if [ -z "$RESOURCE_GROUP" ] || [ -z "$WORKSPACE_NAME" ]; then
    echo "Error: Required environment variables must be set"
    echo "Required variables:"
    echo "  RESOURCE_GROUP - Azure resource group name"
    echo "  WORKSPACE_NAME - Log Analytics workspace name"
    echo
    echo "Optional variables for association listing:"
    echo "  VM_ID - Full resource ID of scheduler VM"
    echo "  VMSS_ID - Full resource ID of compute VMSS"
    echo
    echo "Example:"
    echo "  export RESOURCE_GROUP='your-resource-group'"
    echo "  export WORKSPACE_NAME='your-workspace-name'"
    echo "  export VM_ID='/subscriptions/.../virtualMachines/scheduler-vm'"
    echo "  export VMSS_ID='/subscriptions/.../virtualMachineScaleSets/compute-vmss'"
    exit 1
fi

echo "=== Current Slurm Log Collection Resources ==="
echo "Resource Group: $RESOURCE_GROUP"
echo "Workspace: $WORKSPACE_NAME"
if [ -n "$VM_ID" ]; then
    echo "Scheduler VM: $VM_ID"
fi
if [ -n "$VMSS_ID" ]; then
    echo "Compute VMSS: $VMSS_ID"
fi
echo "Timestamp: $(date)"
echo

# Function to print section header
print_section() {
    local title=$1
    echo "=== $title ==="
    echo
}

# Function to print subsection header
print_subsection() {
    local title=$1
    echo "--- $title ---"
}

print_section "Data Collection Rules"

echo "All DCRs in resource group $RESOURCE_GROUP:"
DCR_LIST=$(az monitor data-collection rule list -g "$RESOURCE_GROUP" --query "[].{Name:name, Location:location, Description:description}" -o table 2>/dev/null || echo "")

if [ -z "$DCR_LIST" ] || [ "$DCR_LIST" = "Name    Location    Description" ]; then
    echo "No Data Collection Rules found"
else
    echo "$DCR_LIST"
fi

echo
print_subsection "Slurm-Related DCRs"
SLURM_DCRS=("slurmctld_raw_dcr" "slurmd_raw_dcr" "slurmdb_raw_dcr" "slurmrestd_raw_dcr" "jetpack_raw_dcr" "jetpackd_raw_dcr" "healthagent_raw_dcr" "dmesg_raw_dcr" "syslog_raw_dcr")

for dcr in "${SLURM_DCRS[@]}"; do
    DCR_EXISTS=$(az monitor data-collection rule show -g "$RESOURCE_GROUP" --name "$dcr" --query "name" -o tsv 2>/dev/null || echo "")
    if [ -n "$DCR_EXISTS" ]; then
        echo "✓ $dcr - EXISTS"
    else
        echo "✗ $dcr - NOT FOUND"
    fi
done

echo
print_section "Log Analytics Tables"

echo "All custom tables in workspace $WORKSPACE_NAME:"
TABLE_LIST=$(az monitor log-analytics workspace table list -g "$RESOURCE_GROUP" --workspace-name "$WORKSPACE_NAME" --query "[?contains(name, '_CL')].{Name:name, Plan:plan, Description:description}" -o table 2>/dev/null || echo "")

if [ -z "$TABLE_LIST" ] || [ "$TABLE_LIST" = "Name    Plan    Description" ]; then
    echo "No custom tables found"
else
    echo "$TABLE_LIST"
fi

echo
print_subsection "Slurm-Related Tables"
SLURM_TABLES=("slurmctld_raw_CL" "slurmd_raw_CL" "slurmdb_raw_CL" "slurmrestd_raw_CL" "jetpack_raw_CL" "jetpackd_raw_CL" "healthagent_raw_CL" "dmesg_raw_CL" "syslog_raw_CL")

for table in "${SLURM_TABLES[@]}"; do
    TABLE_EXISTS=$(az monitor log-analytics workspace table show -g "$RESOURCE_GROUP" --workspace-name "$WORKSPACE_NAME" --name "$table" --query "name" -o tsv 2>/dev/null || echo "")
    if [ -n "$TABLE_EXISTS" ]; then
        echo "✓ $table - EXISTS"
    else
        echo "✗ $table - NOT FOUND"
    fi
done

echo
print_subsection "Backup Tables"
for table in "${SLURM_TABLES[@]}"; do
    backup_table="${table%_CL}_old_CL"
    BACKUP_EXISTS=$(az monitor log-analytics workspace table show -g "$RESOURCE_GROUP" --workspace-name "$WORKSPACE_NAME" --name "$backup_table" --query "name" -o tsv 2>/dev/null || echo "")
    if [ -n "$BACKUP_EXISTS" ]; then
        echo "✓ $backup_table - EXISTS"
    else
        echo "✗ $backup_table - NOT FOUND"
    fi
done

if [ -n "$VM_ID" ] || [ -n "$VMSS_ID" ]; then
    echo
    print_section "DCR Associations"

    if [ -n "$VM_ID" ]; then
        print_subsection "Scheduler VM Associations"
        echo "VM: $VM_ID"
        VM_ASSOCIATIONS=$(az monitor data-collection rule association list --resource "$VM_ID" --query "[].{Name:name, DCR:dataCollectionRuleId}" -o table 2>/dev/null || echo "")
        if [ -z "$VM_ASSOCIATIONS" ] || [ "$VM_ASSOCIATIONS" = "Name    DCR" ]; then
            echo "No associations found for scheduler VM"
        else
            echo "$VM_ASSOCIATIONS"
        fi
        echo
    fi

    if [ -n "$VMSS_ID" ]; then
        print_subsection "VMSS Associations"
        echo "VMSS: $VMSS_ID"
        VMSS_ASSOCIATIONS=$(az monitor data-collection rule association list --resource "$VMSS_ID" --query "[].{Name:name, DCR:dataCollectionRuleId}" -o table 2>/dev/null || echo "")
        if [ -z "$VMSS_ASSOCIATIONS" ] || [ "$VMSS_ASSOCIATIONS" = "Name    DCR" ]; then
            echo "No associations found for compute VMSS"
        else
            echo "$VMSS_ASSOCIATIONS"
        fi
        echo
    fi
else
    echo
    print_section "DCR Associations"
    echo "VM_ID and/or VMSS_ID not set - skipping association listing"
    echo "Set VM_ID and VMSS_ID environment variables to see associations"
    echo
fi

print_section "Resource Summary"

# Count existing resources
DCR_COUNT=$(az monitor data-collection rule list -g "$RESOURCE_GROUP" --query "length([?contains(name, '_raw_dcr')])" -o tsv 2>/dev/null || echo "0")
TABLE_COUNT=$(az monitor log-analytics workspace table list -g "$RESOURCE_GROUP" --workspace-name "$WORKSPACE_NAME" --query "length([?contains(name, '_raw_CL')])" -o tsv 2>/dev/null || echo "0")
BACKUP_COUNT=$(az monitor log-analytics workspace table list -g "$RESOURCE_GROUP" --workspace-name "$WORKSPACE_NAME" --query "length([?contains(name, '_old_CL')])" -o tsv 2>/dev/null || echo "0")

VM_ASSOC_COUNT=0
VMSS_ASSOC_COUNT=0
if [ -n "$VM_ID" ]; then
    VM_ASSOC_COUNT=$(az monitor data-collection rule association list --resource "$VM_ID" --query "length(@)" -o tsv 2>/dev/null || echo "0")
fi
if [ -n "$VMSS_ID" ]; then
    VMSS_ASSOC_COUNT=$(az monitor data-collection rule association list --resource "$VMSS_ID" --query "length(@)" -o tsv 2>/dev/null || echo "0")
fi

echo "Data Collection Rules: $DCR_COUNT"
echo "Raw Tables (_raw_CL): $TABLE_COUNT"
echo "Backup Tables (_old_CL): $BACKUP_COUNT"
if [ -n "$VM_ID" ]; then
    echo "Scheduler VM Associations: $VM_ASSOC_COUNT"
fi
if [ -n "$VMSS_ID" ]; then
    echo "VMSS Associations: $VMSS_ASSOC_COUNT"
fi

echo
print_section "Next Steps"

if [ "$DCR_COUNT" -gt 0 ] || [ "$VM_ASSOC_COUNT" -gt 0 ] || [ "$VMSS_ASSOC_COUNT" -gt 0 ]; then
    echo "Current deployment detected. To clean up for testing:"
    echo "1. Run cleanup-associations.sh to remove DCR associations"
    echo "2. Run cleanup-dcrs.sh to remove Data Collection Rules"
    echo "3. Run backup-tables.sh to create backup tables (optional)"
else
    echo "No current deployment detected. You can proceed with:"
    echo "1. Run create-tables.sh to create Log Analytics tables"
    echo "2. Run deploy-dcrs.sh to deploy Data Collection Rules"
    echo "3. Run associate-dcrs.sh to associate DCRs with VMs"
fi

echo
echo "Resource listing completed at $(date)"
