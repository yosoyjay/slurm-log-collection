# Fluent-bit Troubleshooting for Azure Monitor Agent on VMSS

## Problem Discovery

You've identified that fluent-bit has file listeners open on the scheduler (VM) for log forwarding, but there are no active listeners on the compute nodes (VMSS). This is the root cause of why logs aren't being collected from VMSS instances.

Azure Monitor Agent uses fluent-bit as its underlying log collection engine. When fluent-bit isn't monitoring files, no logs get forwarded to Azure Monitor.

## Understanding the Architecture

```
Azure Monitor Agent (AMA)
├── Configuration Manager (pulls DCRs from Azure)
├── fluent-bit (actual log collection engine)
│   ├── Input plugins (file monitoring)
│   ├── Filter plugins (parsing/transformation)
│   └── Output plugins (Azure Monitor forwarding)
└── Authentication Handler (managed identity)
```

## Fluent-bit Diagnostic Steps

### 1. Check Fluent-bit Process Status

Compare fluent-bit processes between VM and VMSS:

```bash
# Check if fluent-bit is running
ps aux | grep fluent-bit | grep -v grep

# Check fluent-bit service status (it may be managed by AMA)
sudo systemctl status fluent-bit 2>/dev/null || echo "fluent-bit not a separate service"

# Check if fluent-bit is running as part of azuremonitoragent
sudo pstree -p $(pgrep azuremonitoragent) | grep fluent

# Check fluent-bit processes and their command line arguments
ps aux | grep fluent-bit | grep -v grep | head -5
```

### 2. Locate Fluent-bit Binary and Configuration

Find where fluent-bit is installed and how it's configured:

```bash
# Find fluent-bit binary locations
sudo find /opt/microsoft -name "*fluent*" -type f 2>/dev/null
sudo find /opt -name "*fluent-bit*" 2>/dev/null
which fluent-bit 2>/dev/null || echo "fluent-bit not in PATH"

# Check for fluent-bit configuration files
sudo find /etc/opt/microsoft/azuremonitoragent -name "*fluent*" 2>/dev/null
sudo find /var/opt/microsoft/azuremonitoragent -name "*fluent*" 2>/dev/null
sudo find /opt/microsoft/azuremonitoragent -name "*fluent*" 2>/dev/null

# Look for fluent-bit configuration directories
sudo ls -la /etc/fluent-bit/ 2>/dev/null || echo "/etc/fluent-bit/ not found"
sudo ls -la /opt/microsoft/azuremonitoragent/etc/ 2>/dev/null || echo "AMA etc directory not found"
```

### 3. Examine Fluent-bit Configuration Files

Check the actual fluent-bit configuration:

```bash
# Find and examine main fluent-bit configuration
FLUENT_CONFIG=$(sudo find /opt/microsoft/azuremonitoragent -name "fluent-bit.conf" 2>/dev/null | head -1)
if [ -n "$FLUENT_CONFIG" ]; then
    echo "Found fluent-bit config: $FLUENT_CONFIG"
    sudo cat "$FLUENT_CONFIG"
else
    echo "fluent-bit.conf not found"
    # Look for alternative config file names
    sudo find /opt/microsoft/azuremonitoragent -name "*.conf" | grep -i fluent
fi

# Check for input configuration files (where file monitoring is defined)
sudo find /opt/microsoft/azuremonitoragent -name "*input*" -type f 2>/dev/null
sudo find /var/opt/microsoft/azuremonitoragent -name "*input*" -type f 2>/dev/null

# Look for DCR-generated fluent-bit configurations
sudo find /etc/opt/microsoft/azuremonitoragent -name "*.conf" 2>/dev/null | xargs sudo grep -l "dmesg\|slurmd" 2>/dev/null
```

### 4. Check Fluent-bit File Monitoring Configuration

Examine how fluent-bit is configured to monitor files:

```bash
# Look for input configurations that should monitor our target files
sudo grep -r "/var/log/dmesg" /opt/microsoft/azuremonitoragent/ /etc/opt/microsoft/azuremonitoragent/ /var/opt/microsoft/azuremonitoragent/ 2>/dev/null
sudo grep -r "slurmd.log" /opt/microsoft/azuremonitoragent/ /etc/opt/microsoft/azuremonitoragent/ /var/opt/microsoft/azuremonitoragent/ 2>/dev/null

# Check for INPUT sections in fluent-bit configs
sudo find /opt/microsoft/azuremonitoragent /etc/opt/microsoft/azuremonitoragent -name "*.conf" -exec grep -l "\[INPUT\]" {} \; 2>/dev/null | xargs sudo cat

# Look for tail plugin configurations (most common for file monitoring)
sudo grep -r "Name.*tail" /opt/microsoft/azuremonitoragent/ /etc/opt/microsoft/azuremonitoragent/ 2>/dev/null
```

### 5. Monitor Fluent-bit Startup and Configuration Loading

Watch fluent-bit start up and load configurations:

```bash
# Restart AMA and monitor fluent-bit startup
sudo systemctl stop azuremonitoragent
sleep 5

# Monitor logs during startup
sudo journalctl -u azuremonitoragent -f &
JOURNAL_PID=$!

sudo systemctl start azuremonitoragent
sleep 30

# Stop log monitoring
kill $JOURNAL_PID

# Check specific fluent-bit startup messages
sudo journalctl -u azuremonitoragent --since "2 minutes ago" | grep -i fluent
```

### 6. Check Fluent-bit Logs and Debug Information

Look for fluent-bit specific logs and errors:

```bash
# Check for fluent-bit log files
sudo find /var/log -name "*fluent*" 2>/dev/null
sudo find /opt/microsoft/azuremonitoragent -name "*.log" 2>/dev/null | xargs sudo grep -l fluent 2>/dev/null

# Check AMA logs for fluent-bit related messages
sudo journalctl -u azuremonitoragent --since "1 hour ago" | grep -i -E "fluent|input|tail|file"

# Look for fluent-bit error messages
sudo journalctl -u azuremonitoragent --since "24 hours ago" | grep -i -E "error.*fluent|fluent.*error|failed.*input"

# Check for file permission errors in fluent-bit context
sudo journalctl -u azuremonitoragent --since "24 hours ago" | grep -i -E "permission|access|denied" | grep -i -E "dmesg|slurmd"
```

### 7. Test Fluent-bit Configuration Manually

Try running fluent-bit manually to test configuration:

```bash
# Find the fluent-bit binary
FLUENT_BIN=$(sudo find /opt/microsoft -name "fluent-bit" -type f -executable 2>/dev/null | head -1)
if [ -n "$FLUENT_BIN" ]; then
    echo "Found fluent-bit binary: $FLUENT_BIN"
    
    # Get version information
    sudo "$FLUENT_BIN" --version
    
    # Find configuration file
    FLUENT_CONF=$(sudo find /opt/microsoft/azuremonitoragent -name "fluent-bit.conf" 2>/dev/null | head -1)
    if [ -n "$FLUENT_CONF" ]; then
        echo "Testing configuration: $FLUENT_CONF"
        # Test configuration (dry run)
        sudo "$FLUENT_BIN" -c "$FLUENT_CONF" --dry-run
    fi
else
    echo "fluent-bit binary not found"
fi
```

### 8. Compare Working VM vs Non-Working VMSS

Run these commands on both systems and compare:

```bash
# Create comparison script for fluent-bit
cat > compare-fluentbit.sh << 'EOF'
#!/bin/bash
echo "=== FLUENT-BIT COMPARISON REPORT ==="
echo "Hostname: $(hostname)"
echo "Date: $(date)"
echo

echo "=== FLUENT-BIT PROCESSES ==="
ps aux | grep fluent-bit | grep -v grep
echo

echo "=== FLUENT-BIT FILES ==="
sudo find /opt/microsoft -name "*fluent*" -ls 2>/dev/null
echo

echo "=== FLUENT-BIT CONFIGURATION ==="
sudo find /opt/microsoft/azuremonitoragent -name "*.conf" -exec echo "=== {} ===" \; -exec sudo cat {} \; 2>/dev/null
echo

echo "=== OPEN FILES BY FLUENT-BIT ==="
sudo lsof | grep fluent-bit | grep "/var/log" 2>/dev/null || echo "No log files open by fluent-bit"
echo

echo "=== FLUENT-BIT IN AMA LOGS ==="
sudo journalctl -u azuremonitoragent --since "1 hour ago" | grep -i fluent | tail -20
EOF

chmod +x compare-fluentbit.sh
./compare-fluentbit.sh > fluentbit-comparison-$(hostname).txt
```

### 9. Check Configuration Generation Process

Understand how AMA generates fluent-bit configuration from DCRs:

```bash
# Check timestamps of configuration files vs DCR association
sudo ls -la /etc/opt/microsoft/azuremonitoragent/config-cache/ --time-style=full-iso
sudo find /opt/microsoft/azuremonitoragent -name "*.conf" -exec ls -la {} \; --time-style=full-iso 2>/dev/null

# Check for configuration generation processes
sudo journalctl -u azuremonitoragent --since "24 hours ago" | grep -i -E "config|generate|create|dcr"

# Look for configuration reload events
sudo journalctl -u azuremonitoragent --since "24 hours ago" | grep -i -E "reload|refresh|update"
```

### 10. Force Configuration Regeneration

Try to force AMA to regenerate fluent-bit configuration:

```bash
# Stop AMA
sudo systemctl stop azuremonitoragent

# Clear configuration cache (backup first)
sudo cp -r /etc/opt/microsoft/azuremonitoragent/config-cache/ /tmp/ama-config-backup-$(date +%s)
sudo rm -rf /etc/opt/microsoft/azuremonitoragent/config-cache/*

# Remove any fluent-bit configuration files
sudo find /opt/microsoft/azuremonitoragent -name "*.conf" -delete 2>/dev/null || true
sudo find /var/opt/microsoft/azuremonitoragent -name "*.conf" -delete 2>/dev/null || true

# Restart AMA and monitor configuration regeneration
sudo systemctl start azuremonitoragent

# Wait for configuration to be regenerated
sleep 60

# Check if configurations were recreated
sudo ls -la /etc/opt/microsoft/azuremonitoragent/config-cache/
sudo find /opt/microsoft/azuremonitoragent -name "*.conf" 2>/dev/null
```

## Common Fluent-bit Issues and Solutions

### Issue 1: Fluent-bit Not Starting
```bash
# Check if fluent-bit binary is present and executable
sudo find /opt/microsoft -name "fluent-bit" -executable
sudo ldd $(sudo find /opt/microsoft -name "fluent-bit" -executable | head -1) # Check dependencies

# Check for startup errors
sudo journalctl -u azuremonitoragent | grep -A5 -B5 "fluent"
```

### Issue 2: Configuration Not Generated
```bash
# Verify DCR association exists
az monitor data-collection rule association list --resource "$VMSS_ID"

# Check if AMA can read DCR configuration
sudo journalctl -u azuremonitoragent | grep -i "association\|dcr"

# Force configuration refresh
sudo systemctl restart azuremonitoragent
```

### Issue 3: File Permissions for Fluent-bit
```bash
# Check what user fluent-bit runs as
ps aux | grep fluent-bit | head -1 | awk '{print $1}'

# Check if that user can read target files
FLUENT_USER=$(ps aux | grep fluent-bit | grep -v grep | head -1 | awk '{print $1}')
if [ -n "$FLUENT_USER" ]; then
    sudo -u "$FLUENT_USER" cat /var/log/dmesg > /dev/null 2>&1 && echo "dmesg readable" || echo "dmesg NOT readable"
    sudo -u "$FLUENT_USER" cat /var/log/slurmd/slurmd.log > /dev/null 2>&1 && echo "slurmd.log readable" || echo "slurmd.log NOT readable"
fi
```

### Issue 4: Fluent-bit Configuration Syntax Errors
```bash
# Test fluent-bit configuration syntax
FLUENT_BIN=$(sudo find /opt/microsoft -name "fluent-bit" -executable | head -1)
FLUENT_CONF=$(sudo find /opt/microsoft/azuremonitoragent -name "fluent-bit.conf" | head -1)

if [ -n "$FLUENT_BIN" ] && [ -n "$FLUENT_CONF" ]; then
    sudo "$FLUENT_BIN" -c "$FLUENT_CONF" --dry-run
fi
```

## Advanced Fluent-bit Debugging

### Enable Fluent-bit Debug Logging
```bash
# Look for fluent-bit log level configuration
sudo grep -r "Log_Level\|log_level" /opt/microsoft/azuremonitoragent/ 2>/dev/null

# Try to enable debug logging (varies by AMA version)
# This may require modifying configuration files or environment variables
```

### Manual Fluent-bit Test Configuration
Create a minimal test configuration to verify fluent-bit functionality:

```bash
# Create test configuration
sudo mkdir -p /tmp/fluent-test
cat > /tmp/fluent-test/test.conf << 'EOF'
[INPUT]
    Name tail
    Path /var/log/dmesg
    Tag test.dmesg
    Refresh_Interval 5

[OUTPUT]
    Name stdout
    Match test.*
EOF

# Test with this configuration
FLUENT_BIN=$(sudo find /opt/microsoft -name "fluent-bit" -executable | head -1)
if [ -n "$FLUENT_BIN" ]; then
    echo "Testing fluent-bit with minimal config..."
    timeout 30 sudo "$FLUENT_BIN" -c /tmp/fluent-test/test.conf
fi
```

## Validation Steps

After making changes:

1. **Verify fluent-bit is monitoring files:**
```bash
sudo lsof | grep fluent-bit | grep "/var/log"
```

2. **Check fluent-bit is processing file changes:**
```bash
echo "TEST_FLUENT_$(date)" | sudo tee -a /var/log/dmesg
sudo journalctl -u azuremonitoragent --since "1 minute ago" | grep -i fluent
```

3. **Confirm logs appear in Azure Monitor:**
```kql
dmesg_raw_CL
| where TimeGenerated > ago(30m)
| where RawData contains "TEST_FLUENT"
| project TimeGenerated, Computer, RawData
```

## Expected Resolution

Once fluent-bit is properly configured and monitoring files on VMSS instances, you should see:

1. Fluent-bit processes with open file handles on log files
2. No more fluent-bit related errors in AMA logs  
3. Log entries appearing in Azure Monitor within 5-15 minutes
4. Consistent behavior between VM and VMSS instances

## Next Steps if Issue Persists

If fluent-bit still isn't working on VMSS:

1. **Compare complete AMA installations** between VM and VMSS
2. **Check for VMSS-specific restrictions** (security policies, resource constraints)
3. **Verify identical AMA extension versions** on VM and VMSS
4. **Contact Azure Support** with fluent-bit configuration differences and logs

The key is ensuring fluent-bit has the same configuration and file access on VMSS as it does on the working VM.