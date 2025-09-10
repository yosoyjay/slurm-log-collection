# Troubleshooting VMSS Log Collection Issues

## Problem Summary

Log collection is not working for some log types on VMSS (Virtual Machine Scale Set) nodes:
- `dmesg_raw` log collection not working on nodes (VMSS)
- `slurmd` not working on nodes (VMSS)

Currently working logs:
- **VM (Scheduler)**: Built-in: Heartbeat. Custom: dmesg_raw, healthagent_raw, jetpackd_raw, slurmcctld_raw, syslog_raw
- **VMSS (Nodes)**: Built-in: Heartbeat. Custom: none

## Environment Details

From `.env` file:
- VMSS Resource Group: `gb200-ccw-centralus-01-rg`
- VMSS Name: `gpu-q4beybvxzrcvx`
- VMSS ID: `/subscriptions/75d1e0d5-9fed-4ae1-aec7-2ecc19de26fa/resourceGroups/gb200-ccw-centralus-01-rg/providers/Microsoft.Compute/virtualMachineScaleSets/gpu-q4beybvxzrcvx`

## Troubleshooting Steps

### [x - DCR and associations exist] Step 1: Verify DCR Associations

Check if DCRs are properly associated with the VMSS:

```bash
# Check all associations for the VMSS
az monitor data-collection rule association list --resource "$VMSS_ID"

# Specifically check for the failing DCRs
az monitor data-collection rule association list --resource "$VMSS_ID" --query "[?contains(id, 'dmesg')]"
az monitor data-collection rule association list --resource "$VMSS_ID" --query "[?contains(id, 'slurmd')]"
```

### [x - VMs running] Step 2: Verify VMSS Instance Status

Check if VMSS instances are running and accessible:

```bash
# List all VMSS instances
az vmss list-instances --resource-group "$VMSS_RG" --name "$VMSS_NAME" --output table

# Get detailed instance information
az vmss list-instances --resource-group "$VMSS_RG" --name "$VMSS_NAME" --query "[].{Name:name, ProvisioningState:provisioningState, PowerState:instanceView.statuses[1].displayStatus}"
```

### [x] Step 3: Check Azure Monitor Agent on VMSS Instances

Connect to individual VMSS instances to verify Azure Monitor Agent:

```bash
# Get connection info for a specific instance (replace X with instance ID)
az vmss list-instance-connection-info --resource-group "$VMSS_RG" --name "$VMSS_NAME"

# SSH to instance and check agent status
sudo systemctl status azuremonitoragent
sudo systemctl status azure-monitor-agent

# Check agent logs
sudo journalctl -u azuremonitoragent -f
sudo journalctl -u azure-monitor-agent -f
```

### [x - paths correct] Step 4: Verify Log File Paths on VMSS Instances

Check if the expected log files exist on VMSS instances:

```bash
# SSH to VMSS instance and check file paths
ls -la /var/log/dmesg
ls -la /var/log/slurmd/slurmd.log
ls -la /var/log/slurm/slurmd.log

# Check file permissions
ls -la /var/log/dmesg
ls -la /var/log/slurmd/
ls -la /var/log/slurm/

# Check if files have content
tail -10 /var/log/dmesg
tail -10 /var/log/slurmd/slurmd.log
tail -10 /var/log/slurm/slurmd.log
```

### [x - DCR correct.  dmesg works with VM.] Step 5: Verify DCR Configuration

Check the deployed DCRs to ensure they have correct configuration:

```bash
# Get DCR details
az monitor data-collection rule show --resource-group "$RESOURCE_GROUP" --name "dmesg_raw_dcr"
az monitor data-collection rule show --resource-group "$RESOURCE_GROUP" --name "slurmd_raw_dcr"
```

### [x - associations exist] Step 6: Create Missing Associations

If associations are missing, create them:

```bash
# Source environment variables
source .env

# Associate dmesg DCR with VMSS
az monitor data-collection rule association create \
    --association-name "dmesg-${VMSS_NAME}-association" \
    --rule-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Insights/dataCollectionRules/dmesg_raw_dcr" \
    --resource "$VMSS_ID"

# Associate slurmd DCR with VMSS
az monitor data-collection rule association create \
    --association-name "slurmd-${VMSS_NAME}-association" \
    --rule-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Insights/dataCollectionRules/slurmd_raw_dcr" \
    --resource "$VMSS_ID"
```

### [x - configurations exist on VM and VMSS] Step 7: Check Agent Configuration Files

On VMSS instances, verify agent configuration:

```bash
# Check agent configuration directory
ls -la /etc/opt/microsoft/azuremonitoragent/config-cache/

# Look for DCR configurations
find /etc/opt/microsoft/azuremonitoragent/config-cache/ -name "*.json" -exec grep -l "dmesg\|slurmd" {} \;

# Check agent status and configuration reload
sudo systemctl restart azuremonitoragent
sudo systemctl status azuremonitoragent
```

### [x - system assigned identity for VMSS] Step 8: Verify System Identity and Permissions

Ensure VMSS has system-assigned managed identity:

```bash
# Check VMSS identity
az vmss identity show --resource-group "$VMSS_RG" --name "$VMSS_NAME"

# Assign system identity if missing
az vmss identity assign --resource-group "$VMSS_RG" --name "$VMSS_NAME"
```

### [x - different endpoint in config.  But accessible.] Step 9: Test Log Analytics Connectivity

From VMSS instances, test connectivity to Log Analytics:

```bash
# Test DNS resolution
nslookup ods.opinsights.azure.com

# Test connectivity to Log Analytics endpoints
curl -I https://ods.opinsights.azure.com
telnet ods.opinsights.azure.com 443
```

## Common Issues and Solutions

### [x - files exist] Issue 1: Log Files Don't Exist

**Problem**: Log files `/var/log/dmesg` or `/var/log/slurmd/slurmd.log` don't exist on VMSS instances.

**Solutions**:
- For dmesg: Run `sudo dmesg > /var/log/dmesg` to create the file
- For slurmd: Check if slurmd service is running: `sudo systemctl status slurmd`
- Verify Slurm log directory configuration in `/etc/slurm/slurm.conf`

### [x - Agent runs as root] Issue 2: File Permission Issues

**Problem**: Azure Monitor Agent can't read log files.

**Solutions**:
```bash
# Make dmesg readable
sudo chmod 644 /var/log/dmesg

# Fix slurmd log permissions
sudo chmod 644 /var/log/slurmd/slurmd.log
sudo chmod 755 /var/log/slurmd/
```

### [x - Association exists] Issue 3: DCR Association Failed

**Problem**: DCR association creation failed.

**Solutions**:
- Verify VMSS has system-assigned managed identity
- Check Azure RBAC permissions for the identity
- Ensure DCR exists before creating association

### [x - AMA servcie running] Issue 4: Azure Monitor Agent Not Running

**Problem**: Agent service is not active on VMSS instances.

**Solutions**:
```bash
# Start and enable the service
sudo systemctl start azuremonitoragent
sudo systemctl enable azuremonitoragent

# If service fails, check installation
dpkg -l | grep azure-monitor
# or for RHEL/CentOS
rpm -qa | grep azure-monitor
```

### [x - paths are correct] Issue 5: Wrong Log File Paths

**Problem**: Slurm logs are in different location than expected.

**Check common locations**:
```bash
# Check various possible locations
ls -la /var/log/slurm/
ls -la /var/log/slurmd/
ls -la /opt/slurm/log/
```

**Update DCR if needed**: Modify `slurmd_raw_dcr.json` filePatterns to match actual path.

## Validation Queries

After implementing fixes, validate log ingestion:

```kql
// Check if dmesg logs are coming from VMSS instances
dmesg_raw_CL
| where TimeGenerated > ago(30m)
| distinct Computer
| sort by Computer

// Check if slurmd logs are coming from VMSS instances
slurmd_raw_CL
| where TimeGenerated > ago(30m)
| distinct Computer
| sort by Computer

// Compare log sources
union
    (dmesg_raw_CL | extend LogType = "dmesg"),
    (slurmd_raw_CL | extend LogType = "slurmd"),
    (syslog_raw_CL | extend LogType = "syslog")
| where TimeGenerated > ago(1h)
| summarize count() by LogType, Computer
| order by Computer, LogType
```

## Automated Fix Script

Create and run this script to automatically fix common issues:

```bash
#!/bin/bash
# fix-vmss-logging.sh

source .env

echo "=== Fixing VMSS Log Collection Issues ==="

# 1. Verify DCR associations
echo "Checking DCR associations..."
DMESG_ASSOC=$(az monitor data-collection rule association list --resource "$VMSS_ID" --query "[?contains(id, 'dmesg')]" --output tsv)
SLURMD_ASSOC=$(az monitor data-collection rule association list --resource "$VMSS_ID" --query "[?contains(id, 'slurmd')]" --output tsv)

# 2. Create missing associations
if [ -z "$DMESG_ASSOC" ]; then
    echo "Creating dmesg DCR association..."
    az monitor data-collection rule association create \
        --association-name "dmesg-${VMSS_NAME}-association" \
        --rule-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Insights/dataCollectionRules/dmesg_raw_dcr" \
        --resource "$VMSS_ID"
fi

if [ -z "$SLURMD_ASSOC" ]; then
    echo "Creating slurmd DCR association..."
    az monitor data-collection rule association create \
        --association-name "slurmd-${VMSS_NAME}-association" \
        --rule-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Insights/dataCollectionRules/slurmd_raw_dcr" \
        --resource "$VMSS_ID"
fi

# 3. Ensure VMSS has system identity
echo "Checking VMSS system identity..."
az vmss identity assign --resource-group "$VMSS_RG" --name "$VMSS_NAME" 2>/dev/null || echo "Identity already assigned"

echo "=== Fix script completed ==="
echo "Wait 15-20 minutes for log ingestion to begin"
```

## Next Steps

1. Run the automated fix script above
2. Wait 15-20 minutes for changes to take effect
3. Run the validation queries to confirm log ingestion
4. If issues persist, check individual VMSS instances manually
5. Consider restarting Azure Monitor Agent on problematic instances

## Support Information

If issues persist after following this guide:
1. Collect Azure Monitor Agent logs from VMSS instances
2. Check Azure Activity Log for DCR association errors
3. Verify network connectivity from VMSS to Azure Monitor endpoints
4. Consider opening Azure support ticket with diagnostic information
