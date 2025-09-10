# Azure Monitor Agent (AMA) Troubleshooting Guide for Log Collection

This guide provides a systematic approach to troubleshooting log collection issues with Azure Monitor Agent on VMs and Virtual Machine Scale Sets (VMSS).

## Table of Contents

1. [Problem Classification](#problem-classification)
2. [Basic Verification Steps](#basic-verification-steps)
3. [Configuration Diagnostics](#configuration-diagnostics)
4. [Azure Monitor Agent Deep Dive](#azure-monitor-agent-deep-dive)
5. [Fluent-bit Troubleshooting](#fluent-bit-troubleshooting)
6. [Architecture-Specific Issues](#architecture-specific-issues)
7. [Network and Authentication](#network-and-authentication)
8. [Performance and Resource Issues](#performance-and-resource-issues)
9. [Validation and Testing](#validation-and-testing)
10. [Resolution Patterns](#resolution-patterns)

## Problem Classification

### Symptom Categories

**No Logs Collected:**
- Built-in metrics (Heartbeat) work, but custom logs don't appear
- No data in Log Analytics workspace custom tables

**Partial Log Collection:**
- Logs work on some VMs but not others
- Some log types work, others don't
- Intermittent log collection

**Performance Issues:**
- High latency in log ingestion
- Missing log entries
- High resource usage by AMA

## Basic Verification Steps

### 1. Infrastructure Check

```bash
# Verify Azure Monitor Agent is installed and running
sudo systemctl status azuremonitoragent

# Check agent version
<fill-in with directions for Azure Monitor Extension>

# Verify system identity
#az vm identity show --ids $(curl -s -H 'Metadata:true' 'http://169.254.169.254/metadata/instance/compute/resourceId?api-version=2021-02-01')
<update command to actually work without assuming az cli exists on node.  `az vm identity show` needs RG and VM NAME
<need command for VMSS system ID>

```

### 2. Data Collection Rules (DCR) Verification

<missing definitions of these env vars>

```bash
# Check DCR exists
az monitor data-collection rule show --resource-group "$RESOURCE_GROUP" --name "$DCR_NAME"

# Verify DCR associations
az monitor data-collection rule association list --resource "$VM_RESOURCE_ID"

# Check association for VMSS
az monitor data-collection rule association list --resource "$VMSS_RESOURCE_ID"
```

### 3. Log File Accessibility

<create a list of files that you are attempting to forward>
```bash
# Verify target log files exist and are readable
ls -la /var/log/dmesg
ls -la /var/log/slurmd/slurmd.log
ls -la /var/log/syslog

<remove - file permissions do not matter>
# Check file permissions
stat /var/log/dmesg
stat /var/log/slurmd/slurmd.log

<remove - file permissions do not matter>
# Test file readability by AMA user
sudo -u root cat /var/log/dmesg > /dev/null && echo "Readable" || echo "Not readable"
```

## Configuration Diagnostics

### 1. Agent Configuration Cache

```bash
# Check configuration cache structure
sudo ls -la /etc/opt/microsoft/azuremonitoragent/config-cache/

# Look for DCR configurations
sudo find /etc/opt/microsoft/azuremonitoragent/config-cache/ -name "*.json" -exec grep -l "dmesg\|slurmd\|syslog" {} \;

# Examine configuration timestamps
sudo find /etc/opt/microsoft/azuremonitoragent/config-cache/ -name "*.json" -exec ls -la {} \; --time-style=full-iso
```

### 2. DCR Configuration Content

```bash
# Extract and examine DCR configuration
sudo find /etc/opt/microsoft/azuremonitoragent/config-cache/ -name "*.json" -exec cat {} \; | jq '.properties.dataSources.logFiles[]?'

# Check for specific file patterns
sudo grep -r "filePatterns" /etc/opt/microsoft/azuremonitoragent/config-cache/ | grep -E "dmesg|slurmd|syslog"
```

## Azure Monitor Agent Deep Dive

### 1. Agent Process Analysis

```bash
# Check all AMA-related processes
ps aux | grep -E "azuremonitor|agentlauncher" | grep -v grep

# Examine process hierarchy
sudo pstree -p $(pgrep azuremonitoragent)

# Check agent logs
sudo journalctl -u azuremonitoragent --since "1 hour ago" -f
```

### 2. Agent Internal Logs

```bash
# Check agent launcher logs (date-specific files)
sudo find /var/opt/microsoft/azuremonitoragent/log/ -name "agentlauncher*.log" -exec tail -20 {} \;

# Check agent state
sudo cat /var/opt/microsoft/azuremonitoragent/log/agentlauncher.state.log

# Look for configuration processing errors
sudo journalctl -u azuremonitoragent --since "24 hours ago" | grep -i -E "error|fail|exception|dcr|config"
```

## Fluent-bit Troubleshooting

### 1. Fluent-bit Process Detection

```bash
# Check if fluent-bit is running
ps aux | grep fluent-bit | grep -v grep

# Expected output on working system:
# root     1469838  agentlauncher --fluentBitPath /opt/microsoft/azuremonitoragent/bin/fluent-bit
# root     1469847  /opt/microsoft/azuremonitoragent/bin/fluent-bit -c /etc/opt/microsoft/azuremonitoragent/config-cache/fluentbit/td-agent.conf

# On broken system, you might only see agentlauncher without fluent-bit
```

### 2. Fluent-bit Startup Issues

```bash
# Check agentlauncher logs for fluent-bit startup failures
sudo tail -50 /var/opt/microsoft/azuremonitoragent/log/agentlauncher$(date +%Y%m%d).log

# Look for exit codes and restart patterns
grep -E "ExitCode|Restarting|Starting.*fluent-bit" /var/opt/microsoft/azuremonitoragent/log/agentlauncher*.log
```

### 3. Manual Fluent-bit Testing

```bash
# Test fluent-bit binary execution
/opt/microsoft/azuremonitoragent/bin/fluent-bit --version

# Test with configuration file
sudo /opt/microsoft/azuremonitoragent/bin/fluent-bit -c /etc/opt/microsoft/azuremonitoragent/config-cache/fluentbit/td-agent.conf --dry-run

# Run fluent-bit manually for troubleshooting
sudo /opt/microsoft/azuremonitoragent/bin/fluent-bit -c /etc/opt/microsoft/azuremonitoragent/config-cache/fluentbit/td-agent.conf -v
```

### 4. File Monitoring Verification

```bash
# Check what files fluent-bit is monitoring
sudo lsof | grep fluent-bit | grep "/var/log"

# Expected output shows open file handles:
# fluent-bi 1469847 root   77r REG  8,1  46363  15743 /var/log/dmesg
# fluent-bi 1469847 root   78r REG  8,1  12345  67890 /var/log/slurmd/slurmd.log

# If no output, fluent-bit is not monitoring files
```

## Architecture-Specific Issues

### 1. ARM64 Page Size Compatibility

**Problem:** Fluent-bit crashes with jemalloc "Unsupported system page size" errors on ARM64 systems with 64KB pages.

```bash
# Check system page size
getconf PAGESIZE

# If output is 65536 (64KB), this may cause issues with fluent-bit
# Check for jemalloc errors in logs:
sudo journalctl -u azuremonitoragent | grep -i jemalloc
```

**Solution: Compile fluent-bit for 64KB pages:**

```bash
# Clone fluent-bit repository
git clone https://github.com/fluent/fluent-bit.git
cd fluent-bit

# Build fluent-bit
mkdir build && cd build
cmake ..
make

# Test the compiled binary
bin/fluent-bit -i cpu -o stdout -f 1

# Replace the Azure Monitor Agent fluent-bit binary (backup original first)
sudo mv /opt/microsoft/azuremonitoragent/bin/fluent-bit /opt/microsoft/azuremonitoragent/bin/fluent-bit.orig_page_size
sudo cp bin/fluent-bit /opt/microsoft/azuremonitoragent/bin/fluent-bit

# Restart Azure Monitor Agent
sudo systemctl restart azuremonitoragent
```

### 2. Binary Architecture Verification

```bash
# Check binary architecture
file /opt/microsoft/azuremonitoragent/bin/fluent-bit

# Verify system architecture
uname -m

# Check for architecture mismatch
readelf -h /opt/microsoft/azuremonitoragent/bin/fluent-bit | grep Machine
```

## Network and Authentication

### 1. Connectivity Testing

```bash
# Test Azure Monitor endpoints
curl -I https://ods.opinsights.azure.com
curl -I https://global.handler.control.monitor.azure.com

# Test workspace-specific endpoint
WORKSPACE_ID="your-workspace-id"
curl -v "https://${WORKSPACE_ID}.ods.opinsights.azure.com/api/logs?api-version=2016-04-01"
```

### 2. Managed Identity Verification

```bash
# Test instance metadata service
curl -H "Metadata:true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01"

# Test managed identity token acquisition
curl -H "Metadata:true" "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://monitor.azure.com/"
```

## Performance and Resource Issues

### 1. Resource Monitoring

```bash
# Check agent resource usage
ps aux | grep azuremonitor
top -p $(pgrep azuremonitoragent)

# Monitor memory usage
free -h
cat /proc/meminfo | grep -E "MemFree|MemAvailable"

# Check file descriptor usage
sudo lsof -p $(pgrep azuremonitoragent) | wc -l
ulimit -n
```

### 2. System Limits

```bash
# Check process limits
cat /proc/$(pgrep azuremonitoragent)/limits

# Check for OOM killer activity
dmesg | grep -i "killed process"
sudo journalctl --since "1 hour ago" | grep -i "oom"
```

## Validation and Testing

### 1. Test Log Entry Creation

```bash
# Create test log entries
echo "AMA_TEST_$(date +%s)" | sudo tee -a /var/log/dmesg
echo "AMA_TEST_$(date +%s)" | sudo tee -a /var/log/slurmd/slurmd.log

# Monitor for agent response
sudo journalctl -u azuremonitoragent --since "1 minute ago" -f
```

### 2. KQL Validation Queries

```kql
// Check for recent log ingestion
union withsource=TableName *_CL
| where TimeGenerated > ago(30m)
| summarize count() by TableName, Computer
| order by TableName, Computer

// Look for test entries
dmesg_raw_CL
| where TimeGenerated > ago(30m)
| where RawData contains "AMA_TEST"
| project TimeGenerated, Computer, RawData

// Check ingestion patterns
dmesg_raw_CL
| where TimeGenerated > ago(24h)
| summarize count() by bin(TimeGenerated, 1h), Computer
| render timechart
```

### 3. End-to-End Testing

```bash
# Minimal DCR testing
cat > /tmp/test-dcr.json << 'EOF'
{
  "properties": {
    "dataSources": {
      "logFiles": [
        {
          "filePatterns": ["/tmp/ama-test.log"],
          "format": "text",
          "name": "Custom-Text-Test_CL",
          "streams": ["Custom-Text-Test_CL"]
        }
      ]
    },
    "destinations": {
      "logAnalytics": [
        {
          "name": "la-workspace",
          "workspaceResourceId": "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.OperationalInsights/workspaces/$WORKSPACE_NAME"
        }
      ]
    },
    "dataFlows": [
      {
        "streams": ["Custom-Text-Test_CL"],
        "destinations": ["la-workspace"],
        "outputStream": "Custom-Test_CL"
      }
    ]
  }
}
EOF

# Create test file and verify collection
echo "Test entry $(date)" | sudo tee /tmp/ama-test.log
```

## Resolution Patterns

### Pattern 1: DCR Association Missing
**Symptoms:** Agent running, files accessible, but no logs collected.
**Solution:** Create or verify DCR associations.

### Pattern 2: Fluent-bit Not Starting
**Symptoms:** Agentlauncher running, but fluent-bit process missing.
**Root Causes:**
- Configuration file issues
- Binary compatibility problems
- Memory allocation failures

### Pattern 3: Architecture Compatibility
**Symptoms:** Fluent-bit crashes immediately with memory errors on ARM64.
**Solution:** Recompile fluent-bit or use LD_PRELOAD workaround.

### Pattern 4: Permission Issues
**Symptoms:** Fluent-bit starts but doesn't monitor files.
**Solution:** Fix file permissions or SELinux/AppArmor policies.

### Pattern 5: Network Connectivity
**Symptoms:** Logs collected locally but not forwarded to Azure.
**Solution:** Fix network connectivity or firewall rules.

## Troubleshooting Workflow

1. **Basic Checks (5 minutes)**
   - Verify AMA service status
   - Check DCR associations
   - Confirm log file existence

2. **Configuration Analysis (10 minutes)**
   - Examine DCR configuration content
   - Verify file paths and permissions
   - Check agent configuration cache

3. **Process Analysis (15 minutes)**
   - Identify fluent-bit process status
   - Analyze agentlauncher logs
   - Test manual fluent-bit execution

4. **Deep Diagnostics (30 minutes)**
   - System compatibility checks
   - Resource and performance analysis
   - Network and authentication testing

5. **Resolution Implementation (Variable)**
   - Apply appropriate fix based on findings
   - Monitor for resolution
   - Validate end-to-end functionality

## Common Commands Reference

```bash
# Service management
sudo systemctl status azuremonitoragent
sudo systemctl restart azuremonitoragent
sudo journalctl -u azuremonitoragent -f

# Process monitoring
ps aux | grep -E "azuremonitor|fluent-bit" | grep -v grep
sudo lsof | grep fluent-bit | grep "/var/log"

# Configuration inspection
sudo find /etc/opt/microsoft/azuremonitoragent/config-cache/ -name "*.json" -exec grep -l "dmesg\|slurmd" {} \;
sudo cat /etc/opt/microsoft/azuremonitoragent/config-cache/fluentbit/td-agent.conf

# Testing
echo "TEST_$(date +%s)" | sudo tee -a /var/log/dmesg
sudo /opt/microsoft/azuremonitoragent/bin/fluent-bit --version
getconf PAGESIZE
```

## Success Criteria

A successful resolution should result in:

1. **Process Status:** Both agentlauncher and fluent-bit processes running
2. **File Monitoring:** `lsof` shows fluent-bit with open handles on target log files
3. **No Errors:** Agent logs free of startup or configuration errors
4. **Data Flow:** Test log entries appear in Azure Monitor within 15-20 minutes
5. **Consistency:** Same behavior across all VMs/VMSS instances

## Support Escalation

If issues persist after following this guide:

1. **Collect Diagnostics:**
   - Agent logs from all affected systems
   - Configuration files and DCR definitions
   - System information (architecture, page size, resource usage)
   - Network connectivity test results

2. **Document Findings:**
   - Steps attempted and results
   - Specific error messages or symptoms
   - Differences between working and non-working systems

3. **Contact Azure Support:**
   - Provide collected diagnostics
   - Reference this troubleshooting guide
   - Include specific symptoms and resolution attempts

This guide covers the systematic approach used to identify and resolve the ARM64 64KB page size compatibility issue with fluent-bit in Azure Monitor Agent.
