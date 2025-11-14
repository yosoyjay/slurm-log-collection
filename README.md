# CycleCloud Workspace for Slurm Log Collection

A turnkey, customizable log forwarding solution for CycleCloud Workspace for Slurm that centralizes all cluster logs into Azure Monitor Log Analytics. This project addresses the critical operational challenge of distributed AI/ML training: when jobs fail across hundreds or thousands of nodes, quickly identifying root causes from scattered logs becomes incredibly time-consuming, delaying recovery and reducing cluster utilization.

## Project Overview

### What This Project Does

This solution automatically collects logs from all components of your Slurm cluster and forwards them to Azure Monitor, providing:

- **Centralized Log Management**: All Slurm daemon logs, job archives, and system logs in one place
- **Job Analysis**: Automatic archival and analysis of Slurm job scripts, outputs, and environment variables
- **Troubleshooting**: Structured queries to quickly identify cluster issues and performance bottlenecks

### Key Benefits

- **Time-Series Correlation**: Azure Monitor's time-based indexing enables rapid identification of cascading failures. Trace network carrier flaps in syslog to corresponding slurmd communication errors to specific job failures - all within seconds
- **Centralized Visibility**: Query logs from thousands of nodes through a single interface instead of SSH-ing to individual machines. Correlate Slurm controller decisions with node-level errors and system events in one query
- **Log Persistence**: Logs survive node deallocations and reimaging - critical in cloud environments where compute nodes are ephemeral
- **Powerful Query Language**: KQL (Kusto Query Language) allows parsing raw logs into structured fields, filtering across multiple sources, and building operational dashboards
- **Production-Ready Scalability**: User-assigned managed identities automatically propagate to new VMSS instances, and DCR associations handle thousands of nodes without manual configuration

### Key Capabilities
- **Comprehensive Coverage**: Monitors scheduler, compute nodes, job lifecycle, and system components
- **Modular and Extensible**: Designed to be easily extended for new data sources and processing requirements
- **Automatic Job Archiving**: Captures job submission scripts, environment variables, stdout/stderr via prolog/epilog scripts
- **Azure Managed Solution**: Leverages Azure Monitor Agent and Data Collection Rules for reliable, production-ready ingestion

### Architecture Overview

The solution uses Azure Monitor Agent (AMA) with Data Collection Rules (DCRs) to:

1. **Collect** logs from multiple sources across scheduler and compute nodes
2. **Transform** raw log data into structured tables in Log Analytics
3. **Archive** job-related files automatically via prolog/epilog scripts
4. **Query** data using KQL for monitoring, alerting, and analysis

## Quick Start Guide

### Prerequisites

Before starting, ensure you have:

1. **Azure Monitor Agent** installed and configured on all VMs and VMSS
2. **System Identity** assigned to all VMs and VMSS (required for AMA)
3. **Log Analytics Workspace** created and accessible
4. **Azure Permissions**: Monitoring Contributor role for deploying DCRs
5. **GB200 Specific**: Custom fluentbit binary for 64K page size support (if applicable)

### Environment Setup

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd slurm-log-collection
   ```

2. **Configure environment variables** by copying and editing the `.env` file:
   ```bash
   cp .env.example .env
   # Edit .env with your Azure resource details
   source .env
   ```

   Required variables:
   - `RESOURCE_GROUP` - Your resource group name
   - `WORKSPACE_NAME` - Log Analytics workspace name
   - `SUBSCRIPTION_ID` - Azure subscription ID
   - `VM_NAME` - Scheduler VM name
   - `VMSS_NAME` - Compute nodes VMSS name
   - `REGION` - Azure region (e.g., centralus)

### Deployment Steps

#### Step 1: Create Log Analytics Tables
```bash
bash ./bin/create-tables.sh
```
Creates all required tables with standardized schema for different log types.

#### Step 2: Deploy Data Collection Rules
```bash
bash ./bin/deploy-dcrs.sh
```
Deploys DCR configurations for all log sources (Slurm, OS, CycleCloud components).

#### Step 3: Associate DCRs with Resources
```bash
bash ./bin/associate-dcrs.sh
```
Automatically associates appropriate DCRs with scheduler VM and compute VMSS.

#### Step 4: [GB200 Only] Update Fluentbit
```bash
bash ./bin/update-fluent-bit.sh
```
Replaces fluentbit binary with 64K page size compatible version.

### Verification

Wait 15 minutes for initial log ingestion (normal ingestion latency is 30 seconds to 3 minutes), then verify in Log Analytics:

```kql
// Check if logs are flowing
union slurmctld_raw_CL, slurmd_raw_CL, syslog_raw_CL
| where TimeGenerated > ago(1h)
| summarize count() by $table
```

Expected result: Non-zero counts for active log tables.

### Quick Troubleshooting

**No data appearing?**
- Verify AMA is running: `systemctl status azuremonitoragent`
- Check DCR associations in Azure portal
- Ensure log files exist and have proper permissions

**GB200 issues?**
- Verify custom fluentbit binary is deployed
- Check for 64K page size compatibility errors

## Sample Queries and Use Cases

### Time-Series Correlation Example

One of the most powerful capabilities is tracing cascading failures across the cluster. For example, correlate a network carrier flap detected in syslog to corresponding slurmd communication errors to specific job failures - all within seconds:

```kql
// Step 1: Identify network carrier changes in the past hour
let NetworkEvents = syslog_raw_CL
| where TimeGenerated > ago(1h)
| where RawData contains "carrier"
| project NetworkTime=TimeGenerated, NetworkComputer=Computer, NetworkEvent=RawData;
// Step 2: Find slurmd errors around the same time
let SlurmErrors = slurmd_raw_CL
| where TimeGenerated > ago(1h)
| where RawData contains "error" or RawData contains "timeout"
| project SlurmTime=TimeGenerated, SlurmComputer=Computer, SlurmError=RawData;
// Step 3: Correlate events within a 5-minute window
NetworkEvents
| join kind=inner (SlurmErrors) on $left.NetworkComputer == $right.SlurmComputer
| where abs(datetime_diff('minute', NetworkTime, SlurmTime)) <= 5
| project NetworkTime, SlurmTime, Computer=NetworkComputer, NetworkEvent, SlurmError
```

### Job Monitoring and Analysis

**Recent Job Submissions**:
```kql
slurmjobs_raw_CL
| where FilePath contains ".sh"
| where TimeGenerated > ago(24h)
| parse FilePath with * "/job_" JobId:string ".sh"
| project TimeGenerated, JobId, Computer, RawData
| order by TimeGenerated desc
```

**Job Failure Analysis**:
```kql
slurmjobs_raw_CL
| where FilePath contains ".err"
| where RawData contains "error" or RawData contains "failed"
| parse FilePath with * "/job_" JobId:string ".err"
| project TimeGenerated, JobId, Computer, RawData
| order by TimeGenerated desc
```

**Job Resource Usage Patterns**:
```kql
slurmjobs_raw_CL
| where FilePath contains ".env"
| parse FilePath with * "/job_" JobId:string ".env"
| parse RawData with EnvVar "=" EnvValue
| where EnvVar in ("SLURM_CPUS_PER_TASK", "SLURM_MEM_PER_NODE", "SLURM_NNODES")
| project JobId, EnvVar, EnvValue, TimeGenerated
```

### Cluster Health and Performance

**Node Communication Issues**:
```kql
syslog_raw_CL
| where TimeGenerated > ago(24h)
| where RawData contains "carrier" or RawData contains "link"
| project TimeGenerated, Computer, RawData
| order by TimeGenerated desc
```

1. [Azure Monitor Agent](https://learn.microsoft.com/en-us/azure/azure-monitor/agents/azure-monitor-agent-manage?tabs=azure-portal) must be installed and configured on all VMs and Azure Virtual Machine Scale Set (VMSS)
    - For GB200: The fluentbit binary installed with Azure Monitor Agent must be replaced with a custome build that supports 64K page size.  (See Step 0: Update Fluentbit)"
2. VM and VMSS must have [system identity](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/how-to-configure-managed-identities-scale-sets?pivots=identity-mi-methods-azp#enable-system-assigned-managed-identity-on-an-existing-virtual-machine-scale-set) assigned otherwise Azure Monitor Agent will not work
    - For production deployments: It is recommended to use [user-assigned identity](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/how-to-configure-managed-identities-scale-sets?pivots=identity-mi-methods-azp#user-assigned-managed-identity) for Virtual Machine Scale Sets. User-assigned identities automatically propagate to individual VMs as they are dynamically created, whereas system-assigned identities must be assigned to each VM at creation time. The user-assigned identity requires the [Monitoring Metrics Publisher](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/monitor#monitoring-metrics-publisher) role to publish logs and metrics to Azure Monitor.
3. [Log Analytics Workspace](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/quick-create-workspace?tabs=azure-portal) must be created and accessible
4. Azure priviliges for creating DCRs and table associations must be granted ([Monitoring Contributor role](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/monitor#monitoring-contributor)) for entity deploying the script
5. Environment variables must be set (see `.env` file example below)

**Resource Allocation Patterns**:
```kql
slurmctld_raw_CL
| where RawData contains "backfill"
| where TimeGenerated > ago(24h)
| parse RawData with * "backfill: " Message
| summarize count() by bin(TimeGenerated, 1h), Message
| render timechart
```

### System Monitoring

See `.env` file for example values:
```bash
export RESOURCE_GROUP="<resource-group-name>"
export WORKSPACE_NAME="<job-analytics-workspace-name>"
export WORKSPACE_TABLE_NAME="<slurmctld-table-name>"
export REGION="<centralus>"
export SUBSCRIPTION_ID="<00000000-0000-0000-0000-000000000000>"
export VMSS_RG="<vmms-resource-group-name>"
export VMSS_NAME="<vmss-name>"
export SLURM_SCHEDULER_VM="<vm-name>"
export DATA_COLLECTION_RULES_NAME="<dcr-name>"

# DO NOT EDIT BELOW ENV VARS
export SLURMCTLD_TABLE_NAME="${WORKSPACE_TABLE_NAME}_CL"
export VMSS_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Compute/virtualMachineScaleSets/${VMSS_NAME}"
export DCR_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Insights/dataCollectionRules/${DATA_COLLECTION_RULES_NAME}"
export VM_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Compute/virtualMachines/${SLURM_SCHEDULER_VM}"
```

## Architecture and Design

### Data Collection Overview

The solution monitors three main categories of components:

#### Slurm Components
- **slurmctld**: Controller daemon logs from scheduler
- **slurmd**: Node daemon logs from compute nodes
- **slurmdb**: Database daemon logs from scheduler
- **slurmrestd**: REST API daemon logs from scheduler
- **Job Archives**: Automated collection of job scripts, outputs, and environment

#### System Components
- **syslog**: System logs from all nodes
- **dmesg**: Kernel logs from compute nodes

### CycleCloud Components
- **jetpack/jetpackd**: CycleCloud agent logs for cluster management operations
- **healthagent**: CycleCloud Healthagent which automatically tests nodes for hardware health and drains nodes that fail tests

### Log Sources and Destinations

| Component | Source File(s) | Nodes | Table | DCR |
|-----------|----------------|-------|-------|-----|
| Slurm Controller | /var/log/slurmctld/slurmctld.log | Scheduler | slurmctld_raw_CL | slurmctld_raw_dcr |
| Slurm Node | /var/log/slurmd/slurmd.log | Compute | slurmd_raw_CL | slurmd_raw_dcr |
| Slurm Database | /var/log/slurmctld/slurmdbd.log | Scheduler | slurmdb_raw_CL | slurmdb_raw_dcr |
| Slurm REST API | /var/log/slurm/slurmrestd.log | Scheduler | slurmrestd_raw_CL | slurmrestd_raw_dcr |
| Job Archives | /shared/slurm-logs/* | Scheduler | slurmjobs_raw_CL | slurmjobs_raw_dcr |
| System Logs | /var/log/syslog | All | syslog_raw_CL | syslog_raw_dcr |
| Kernel Logs | /var/log/dmesg | Compute | dmesg_raw_CL | dmesg_raw_dcr |
| CycleCloud Agent | /opt/cycle/jetpack/logs/jetpack.log | All | jetpack_raw_CL | jetpack_raw_dcr |
| CycleCloud Daemon | /opt/cycle/jetpack/logs/jetpackd.log | All | jetpackd_raw_CL | jetpackd_raw_dcr |
| Health Agent | /opt/healthagent/healthagent.log | Scheduler | healthagent_raw_CL | healthagent_raw_dcr |

### Naming Conventions

All components follow a consistent naming pattern:

- **Log Pattern**: `{service}` (extracted from log filename)
- **Table Name**: `{pattern}_raw_CL`
- **DCR Filename**: `{pattern}_raw_dcr.json`
- **Stream Name**: `Custom-Text-{pattern}_raw_CL`

Example: `slurmd.log` → `slurmd` → `slurmd_raw_CL` → `slurmd_raw_dcr.json` → `Custom-Text-slurmd_raw_CL`

### Standard Table Schema

All raw log tables use this unified schema:

| Column | Type | Description |
|--------|------|-------------|
| TimeGenerated | datetime | When the log entry was generated |
| RawData | string | Complete raw log line content |
| Computer | string | Source computer/VM hostname |
| FilePath | string | Full path to source log file |

## Advanced Configuration

### Job Archive System

The Slurm job archive system automatically captures comprehensive job data for analysis:

#### Archived Files
- **Job Scripts** (`job_{jobid}.sh`): Original sbatch submission script
- **Environment** (`job_{jobid}.env`): Complete environment variables at execution
- **Standard Output** (`job_{jobid}.out`): Job execution stdout
- **Standard Error** (`job_{jobid}.err`): Job execution stderr

#### Archive Structure
```
/shared/slurm-logs/
├── job_12345.sh     # Job submission script
├── job_12345.env    # Environment variables
├── job_12345.out    # Standard output
├── job_12345.err    # Standard error
└── job_12346.*      # Next job files
```

#### Implementation Requirements
Configure Slurm prolog and epilog scripts by either:
1. Adding scripts to `/etc/slurm/{epilog,prolog}.d/`
2. Setting `Prolog` and `Epilog` parameters directly in `slurm.conf`

**Recommendation**: Implement periodic (weekly) compression and archival of older job files to manage storage growth.

### Custom DCR Creation

To create additional DCRs for custom log sources:

1. **Copy existing DCR** from `data-collection-rules/` directory
2. **Modify key fields**:
   - `dataFlows[].outputStream` - Must match table name
   - `dataSources.logFiles[].filePatterns` - Log file paths
   - `dataSources.logFiles[].name` - Unique stream identifier
3. **Deploy using**: `az monitor data-collection rule create`

### GB200 Configuration

Azure Batch GPU nodes with 64K page size require special fluentbit binary:

1. **Build or obtain** 64K page size compatible fluentbit
2. **Place binary** in path specified by `FLUENT_BIT_SOURCE_PATH`
3. **Deploy to nodes** using `bin/update-fluent-bit.sh`
4. **Automate deployment** via VMSS custom script extension


### Verify Log Ingestion

### Environment Variables

#### Required Variables
```bash
# Azure Resource Configuration
export RESOURCE_GROUP="<resource-group-name>"
export SUBSCRIPTION_ID="<subscription-id>"
export REGION="<azure-region>"

# Log Analytics Configuration
export WORKSPACE_NAME="<workspace-name>"
export WORKSPACE_TABLE_NAME="<base-table-name>"

# VM and VMSS Configuration
export VM_NAME="<scheduler-vm-name>"
export VMSS_RG="<vmss-resource-group>"
export VMSS_NAME="<vmss-name>"
export DATA_COLLECTION_RULES_NAME="<dcr-base-name>"
```

#### Auto-Generated Variables
```bash
# These are automatically derived - do not modify
export SLURMCTLD_TABLE_NAME="${WORKSPACE_TABLE_NAME}_CL"
export VMSS_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Compute/virtualMachineScaleSets/${VMSS_NAME}"
export DCR_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Insights/dataCollectionRules/${DATA_COLLECTION_RULES_NAME}"
export VM_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Compute/virtualMachines/${VM_NAME}"
```

### Directory Structure

```
slurm-log-collection/
├── bin/                          # Deployment scripts
│   ├── create-tables.sh          # Create Log Analytics tables
│   ├── deploy-dcrs.sh            # Deploy all DCRs
│   ├── associate-dcrs.sh         # Associate DCRs with resources
│   └── update-fluent-bit.sh      # GB200 fluentbit update
├── data-collection-rules/        # DCR JSON configurations
│   ├── slurm/                    # Slurm component DCRs
│   ├── os/                       # Operating system DCRs
│   └── cyclecloud/              # CycleCloud component DCRs
├── sample-logs/                  # Test data for validation
├── .env.example                  # Environment variable template
└── README.md                     # This documentation
```

### Sample Log Formats

#### Slurm Logs
```
[2025-09-08T21:11:35.869] debug: sched/backfill: _attempt_backfill: no jobs to backfill
[2025-09-08T21:12:05.013] debug: sackd_mgr_dump_state: saved state of 0 nodes
```

#### System Logs
```
Sep  8 21:11:35 node001 kernel: [12345.678901] usb 1-1: new high-speed USB device number 2 using ehci-pci
Sep  8 21:12:05 node001 NetworkManager[1234]: <info> device (eth0): carrier is ON
```

#### Job Archive Files
```bash
# job_12345.sh
#!/bin/bash
#SBATCH --job-name=test_job
#SBATCH --output=output_%j.out
#SBATCH --ntasks=1
echo "Hello World"

# job_12345.env
SLURM_JOB_ID=12345
SLURM_NTASKS=1
SLURM_CPUS_PER_TASK=1
```

### KQL Parsing Patterns

#### Parse Slurm Structured Logs
```kql
slurmctld_raw_CL
| parse RawData with "[" Timestamp "] " Level ": " Component ": " Message
| where isnotempty(Timestamp)
| project TimeGenerated, Computer, Timestamp, Level, Component, Message
```

#### Parse System Logs
```kql
syslog_raw_CL
| parse RawData with Timestamp " " Computer " " Process ": " Message
| project TimeGenerated, Computer, Timestamp, Process, Message
```
