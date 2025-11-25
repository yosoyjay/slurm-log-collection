# Slurm Log Monitoring CycleCloud Project

This CycleCloud project automatically updates the fluent-bit binary for Azure Monitor Agent on nodes with 64KB page sizes.

## Overview

This project addresses compatibility issues with Azure Monitor Agent's fluent-bit binary on ARM64 systems with 64KB page sizes (such as GB200 nodes). The project automatically:

1. Detects if a node has a 64KB page size
2. Updates the fluent-bit binary with a compatible version if needed
3. Restarts the Azure Monitor Agent with the updated binary

## Prerequisites

- CycleCloud cluster with Slurm installed
- Azure Monitor Agent installed on nodes
- Compiled fluent-bit binary for 64KB page sizes available on a shared path accessible to all nodes
  - Default location: `/shared/fluent-bit`
  - Custom location can be configured via `slurm-log-monitoring.fluent_bit_source_path` attribute (see Configuration section below)

## Installation

### 1. Upload the Project to CycleCloud

From the CycleCloud CLI:

```bash
cd cyclecloud-projects
cyclecloud project upload slurm-log-monitoring
```

### 2. Add to Existing Slurm Cluster

Edit your Slurm cluster template to include this project in the compute node configuration:

```ini
[cluster slurm]
...

[[nodearray compute]]
...
    [[[cluster-init slurm-log-monitoring:default]]]
    [[[configuration]]]
    # Optional: Configure custom fluent-bit binary path
    # Default is /shared/fluent-bit
    # slurm-log-monitoring.fluent_bit_source_path = /custom/path/to/fluent-bit
```

Alternatively, add via the CycleCloud UI:
1. Edit the cluster
2. Go to the compute node array
3. Add "slurm-log-monitoring" to the cluster-init projects list
4. (Optional) Add cluster-init configuration attribute `slurm-log-monitoring.fluent_bit_source_path` to specify custom binary path
5. Save and apply changes

### 3. New Nodes

The script will automatically run on newly created nodes during cluster-init.

### 4. Existing Nodes

For existing nodes, you can manually run the update script:

```bash
# On each node with 64KB page size
sudo /shared/fluent-bit && bash /path/to/update-fluent-bit.sh
```

## Project Structure

```
slurm-log-monitoring/
├── project.ini                                    # Project metadata
├── README.md                                      # This file
└── specs/
    └── default/
        └── cluster-init/
            ├── scripts/
            │   └── 01-update-fluent-bit.sh       # Main cluster-init script
            └── files/
                └── update-fluent-bit.sh           # Fluent-bit update script
```

## How It Works

1. During cluster-init, `01-update-fluent-bit.sh` runs automatically
2. The script checks the system page size using `getconf PAGESIZE`
3. If page size is 64KB (65536 bytes), it proceeds with the update
4. If page size is not 64KB, it skips the update
5. The update script stops Azure Monitor Agent, backs up the original binary, installs the new binary, and restarts the agent

## Configuration

### Fluent-bit Binary Path

The location of the 64KB-compatible fluent-bit binary can be configured in two ways:

**Option 1: CycleCloud Cluster Configuration (Recommended)**

Set the path in your cluster template configuration:

```ini
[[nodearray compute]]
    [[[cluster-init slurm-log-monitoring:default]]]
    [[[configuration]]]
    slurm-log-monitoring.fluent_bit_source_path = /custom/path/to/fluent-bit
```

Or via the CycleCloud UI:
- Navigate to the compute node array configuration
- Add attribute: `slurm-log-monitoring.fluent_bit_source_path`
- Set value to your custom path

**Option 2: Environment Variable**

Set the environment variable before running the script manually:

```bash
export FLUENT_BIT_SOURCE_PATH=/custom/path/to/fluent-bit
```

**Default Path**: `/shared/fluent-bit`

The script will use the CycleCloud configuration if set, otherwise fall back to the environment variable, and finally default to `/shared/fluent-bit`.

## Troubleshooting

### Check configured fluent-bit binary path

```bash
# Check what path is configured in CycleCloud
jetpack config slurm-log-monitoring.fluent_bit_source_path

# Verify the binary exists at the configured location
ls -la /shared/fluent-bit  # or your custom path
```

### Check if the script ran

```bash
# Check cluster-init logs
sudo grep -r "fluent-bit" /opt/cycle/jetpack/logs/
```

### Verify fluent-bit binary was updated

```bash
# Check for backup
ls -la /opt/microsoft/azuremonitoragent/bin/fluent-bit*

# Verify Azure Monitor Agent is running
sudo systemctl status azuremonitoragent
```

### Manual execution

If needed, you can manually run the update:

```bash
# Check page size first
getconf PAGESIZE

# Run the update script
sudo bash /opt/cycle/jetpack/work/slurm-log-monitoring/default/cluster-init/files/update-fluent-bit.sh
```
