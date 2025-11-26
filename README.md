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

1. **Azure Permissions**: The deployment scripts require the following permissions:
    - [Monitoring Contributor role](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/monitor#monitoring-contributor) - Required to create DCRs, tables, and assign permissions
    - Permissions to create and assign managed identities to VMs and VMSS
    - Note: Step 1 automatically creates a user-assigned identity and Step 5 assigns the necessary [Monitoring Metrics Publisher](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/monitor#monitoring-metrics-publisher) role
2. **Azure Resources**: Existing Slurm cluster with:
    - Scheduler VM
    - Compute node VMSS
    - Log Analytics workspace (or the scripts will create one)
3. **Environment variables** must be set (see Environment Setup section below)

### Environment Setup

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd slurm-log-collection
   ```

2. **Configure environment variables** by copying and editing the `.env` file:
   ```bash
   cp env.sample .env
   # Edit .env with your Azure resource details
   source .env
   ```

   Required variables:
   - `SUBSCRIPTION_ID` - Azure subscription ID
   - `REGION` - Azure region (e.g., centralus)
   - `RESOURCE_GROUP` - Your resource group name for compute nodes
   - `WORKSPACE_RESOURCE_GROUP` - Your resource group name for Log Analytics workspace
   - `WORKSPACE_NAME` - Log Analytics workspace name
   - `SCHEDULER_VM_NAME` - Scheduler VM name
   - `VMSS_NAME` - Compute nodes VMSS name

#### Step 1: Create and Assign Managed Identity

```bash
bash ./bin/create-managed-identity.sh
```
Creates a user-assigned managed identity named "ama-monitoring-identity" and assigns it to the scheduler VM and compute VMSS. Permissions will be granted in Step 5 after DCRs are created.

#### Step 2: Install Azure Monitor Agent on VMs and VM Scale Sets that you will be collecting logs from

```bash
bash ./bin/install-azure-monitor-agent.sh
```

#### Step 3: Create Log Analytics Tables
```bash
bash ./bin/create-tables.sh
```
Creates all required tables with standardized schema for different log types.

#### Step 4: Deploy Data Collection Rules
```bash
bash ./bin/deploy-dcrs.sh
```
Deploys DCR configurations for all log sources (Slurm, OS, CycleCloud components).

#### Step 5: Assign DCR Permissions to Managed Identity
```bash
bash ./bin/assign-dcr-permissions.sh
```
Grants the managed identity the Monitoring Metrics Publisher role on each Data Collection Rule.

#### Step 6: Associate DCRs with Resources
```bash
bash ./bin/associate-dcrs.sh
```
Automatically associates appropriate DCRs with scheduler VM and compute VMSS.

#### Step 7: [GB200 Only] Update Fluentbit on each GB200 node.  Assumes fluentbit has been recompiled for 64K pages and is on shared disk.
```bash
(on-node) ./bin/update-fluent-bit.sh
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

### Utility Scripts

**FYI**: The repository includes a utility script for inspecting your current deployment:

```bash
bash ./bin/list-current-logging-resources.sh
```

This script lists all deployed Data Collection Rules, DCR associations with VMs/VMSS, and Log Analytics tables. Useful for troubleshooting and verifying your deployment configuration.

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


**Resource Allocation Patterns**:
```kql
slurmctld_raw_CL
| where RawData contains "backfill"
| where TimeGenerated > ago(24h)
| parse RawData with * "backfill: " Message
| summarize count() by bin(TimeGenerated, 1h), Message
| render timechart
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
| Kernel Logs | /var/log/dmesg | All | dmesg_raw_CL | dmesg_raw_dcr |
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

Azure Batch GPU nodes with 64K page size require a special fluent-bit binary:

1. **Build or obtain** a 64K page size compatible fluent-bit binary
2. **Place binary** on a shared path accessible to all nodes (default: `/shared/fluent-bit`)
3. **Deploy to nodes** using one of these methods:

   **Option A: CycleCloud Project (Recommended for CycleCloud Clusters)**

   Upload and attach the `cyclecloud-projects/slurm-log-monitoring` project to your cluster. The project:
   - Automatically detects nodes with 64KB page size during cluster-init
   - Updates fluent-bit binary from the configured path
   - Default path: `/shared/fluent-bit` (configurable via `slurm-log-monitoring.fluent_bit_source_path`)
   - See `cyclecloud-projects/slurm-log-monitoring/README.md` for detailed setup instructions

   **Option B: Manual Execution**

   Run `bin/update-fluent-bit.sh` directly on each node that requires the update. Useful for existing provisioned nodes or non-CycleCloud deployments.

### Directory Structure

```
slurm-log-collection/
├── bin/                               # Deployment scripts
│   ├── create-managed-identity.sh     # Create and assign managed identity
│   ├── install-azure-monitor-agent.sh # Install Azure Monitor Agent
│   ├── create-tables.sh               # Create Log Analytics tables
│   ├── deploy-dcrs.sh                 # Deploy all DCRs
│   ├── assign-dcr-permissions.sh      # Assign permissions to managed identity
│   ├── associate-dcrs.sh              # Associate DCRs with resources
│   └── update-fluent-bit.sh           # GB200 fluentbit update
├── cyclecloud-projects/               # CycleCloud projects
│   └── slurm-log-monitoring/          # Auto-update fluent-bit on 64KB nodes
│       ├── project.ini                # Project metadata
│       ├── README.md                  # Project documentation
│       └── specs/default/cluster-init/
│           ├── scripts/               # Cluster-init scripts
│           └── files/                 # Project files
├── bin/                               # Deployment scripts
|   |-- install-azure-monitor-agent.sh # Install Azure Monitor Agent
│   ├── create-tables.sh               # Create Log Analytics tables
│   ├── deploy-dcrs.sh                 # Deploy all DCRs
│   ├── associate-dcrs.sh              # Associate DCRs with resources
│   └── update-fluent-bit.sh           # GB200 fluentbit update
├── data-collection-rules/             # DCR JSON configurations
│   ├── slurm/                         # Slurm component DCRs
│   ├── os/                            # Operating system DCRs
│   └── cyclecloud/                    # CycleCloud component DCRs
├── sample-logs/                       # Test data for validation
├── env.sample                         # Environment variable template
└── README.md                          # This documentation
```
