# CycleCloud Slurm cluster log collection

## Data to be collected and forwarded to Azure Monitor via Azure Monitor Agent and Data Collection Rules (DCRs).

| component | file(s)                              | source             | table                | raw-table            | data-collection-rule   |
|-----------|--------------------------------------|--------------------|----------------------|----------------------|------------------------|
| Slurm     | /var/log/slurmctld/slurmctld.log     | scheduler          | slurmctld_CL         | slurmctld_raw_CL     | slurmctld_raw_dcr      |
| Slurm     | /var/log/slurmd/slurmd.log           | nodes              | slurmd_CL            | slurmd_raw_CL        | slurmd_raw_dcr         |
| Slurm     | /var/log/slurmctld/slurmdbd.log      | scheduler          | slurmdb_CL           | slurmdb_raw_CL       | slurmdb_raw_dcr        |
| Slurm     | /var/log/slurm/slurmrestd.log        | scheduler          | slurmrestd_CL        | slurmrestd_raw_CL    | slurmrestd_raw_dcr     |
| Slurm     | /shared/slurm-logs/*                 | scheduler          | slurmjobs_CL         | slurmjobs_raw_CL     | slurmjobs_raw_dcr      |
| CC        | /opt/cycle/jetpack/logs/jetpack.log  | scheduler (+nodes) | jetpack_CL           | jetpack_raw_CL       | jetpack_raw_dcr        |
| CC        | /opt/cycle/jetpack/logs/jetpackd.log | scheduler (+nodes) | jetpackd_CL          | jetpackd_raw_CL      | jetpackd_raw_dcr       |
| CC        | /opt/healthagent/healthagent.log     | scheduler          | healthagent_CL       | healthagent_raw_CL   | healthagent_raw_dcr    |
| OS        | /var/log/dmesg                       | nodes              | dmesg_CL             | dmesg_raw_CL         | dmesg_raw_dcr          |
| OS        | /var/log/syslog                      | scheduler (+nodes) | syslog_CL            | syslog_raw_CL        | syslog_raw_dcr         |

## Naming Template

The Data Collection Rules follow a consistent naming pattern:

- Log name: `{service}.log` (e.g., `slurmd.log`)
- Pattern: `{service}` (extracted from log name, e.g., `slurmd`)
- Table name: `{pattern}_raw_CL` (e.g., `slurmd_raw_CL`)
- DCR file name: `{pattern}_raw_dcr.json` (e.g., `slurmd_raw_dcr.json`)
- Stream: `Custom-Text-{pattern}_raw_CL` (e.g., `Custom-Text-slurmd_raw_CL`)

Note: The table name in Log Analytics is also the outputStream in the dataFlows defined in the data-collection-rule.

## Slurm Job Archive System

The Slurm job archive system automatically captures and stores job-related files for analysis and debugging. This system uses prolog and epilog scripts that run on compute nodes to archive:

- Job submission scripts:(`job_{jobid}.sh`) - The original sbatch script submitted by users
- Environment variables: (`job_{jobid}.env`) - Complete environment at job execution time
- Job output logs: (`job_{jobid}.out`) - Standard output from job execution
- Job error logs: (`job_{jobid}.err`) - Standard error from job execution

### Archive Location and Structure

All job files are stored in `/shared/slurm-logs/{username}/` with the following naming convention:
```
/shared/slurm-logs/
├── user1/
│   ├── job_12345.sh    # Job submission script
│   ├── job_12345.env   # Environment variables
│   ├── job_12345.out   # Standard output
│   ├── job_12345.err   # Standard error
│   └── job_12346.*     # Next job files
└── user2/
    └── job_12347.*     # Another user's jobs
```

### Prolog/Epilog Script Configuration

The archive system requires configuring Slurm prolog and epilog scripts, e.g. adding them to `/etc/slurm/{epilog,prolog}.d/` or directly in `slurm.conf`.

### Log Ingestion via Azure Monitor

The archived job files are ingested into Azure Monitor using:
- DCR: `slurmjobs_raw_dcr` - Monitors `/shared/slurm-logs/*/*`
- Table: `slurmjobs_raw_CL` - Stores raw file content with standard schema
- Association: Applied to scheduler VM where job archive files are accessible

### Sample KQL Queries

**View recent job submissions:**
```kql
slurmjobs_raw_CL
| where FilePath contains ".sh"
| where TimeGenerated > ago(1d)
| project TimeGenerated, Computer, FilePath, RawData
| order by TimeGenerated desc
```

**Analyze job failures:**
```kql
slurmjobs_raw_CL
| where FilePath contains ".err"
| where RawData contains "error" or RawData contains "failed"
| project TimeGenerated, Computer, FilePath, RawData
| order by TimeGenerated desc
```

**Extract job environment variables:**
```kql
slurmjobs_raw_CL
| where FilePath contains ".env"
| parse FilePath with * "/job_" JobId:string ".env"
| parse RawData with EnvVar "=" EnvValue
| where EnvVar startswith "SLURM_"
| project JobId, EnvVar, EnvValue, TimeGenerated
```

## Quick Start Guide

### Prerequisites

1. **Azure Monitor Agent** must be installed and configured on all VMs and VMSS
2. **VM and VMSS** must have system identity assigned otherwise Azure Monitor Agent will not work
3. **Log Analytics Workspace** must be created and accessible
4. **Azure priviliges** for creating DCRs and table associations must be granted (Monitoring Contributor role)
5. **Environment variables** set (see `.env` file example below)

### Required Environment Variables

See `.env` file for example values:
```bash
export RESOURCE_GROUP=resource-group-name
export WORKSPACE_NAME=job-analytics-workspace-name
export SLURMCTLD_TABLE_NAME=slurmctld-table-name_CL
export REGION=centralus
export SUBSCRIPTION_ID=00000000-0000-0000-0000-000000000000
export VMSS_RG=vmms-resource-group-name
export VMSS_NAME=vmss-name
export VMSS_ID=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/vmms-resource-group-name/providers/Microsoft.Compute/virtualMachineScaleSets/vmss-name
export DCR_ID=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/resource-group-name/providers/Microsoft.Insights/dataCollectionRules/dcr-name
export VM_ID=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/resource-group-name/providers/Microsoft.Compute/virtualMachines/vm-name
```

### Step-by-Step Setup

#### Step 1: Create Log Analytics Tables

Run the provided script to create all required tables:

```bash
./create-tables.sh
```

This creates the following raw data tables with standard schema:
- `slurmctld_raw_CL` - Slurm controller daemon logs
- `slurmd_raw_CL` - Slurm node daemon logs
- `slurmdb_raw_CL` - Slurm database daemon logs
- `slurmrestd_raw_CL` - Slurm REST API daemon logs
- `slurmjobs_raw_CL` - Slurm job archive files (scripts, env, output, errors)
- `syslog_raw_CL` - System logs (/var/log/syslog)
- `dmesg_raw_CL` - Kernel logs (/var/log/dmesg)
- `jetpack_raw_CL` - CycleCloud jetpack logs
- `jetpackd_raw_CL` - CycleCloud jetpack daemon logs
- `healthagent_raw_CL` - CycleCloud health agent logs

**Standard Raw Table Schema:**
```
TimeGenerated (datetime) - When the log entry was generated
RawData (string) - The complete raw log line
Computer (string) - Source computer/VM name
FilePath (string) - Path to the source log file
```

#### Step 2: Deploy Data Collection Rules

Deploy all DCR configurations:

```bash
chmod +x deploy-dcrs.sh
./deploy-dcrs.sh
```

This deploys DCR JSON files from the `data-collection-rules/` directory:
- `data-collection-rules/slurm/` - Slurm-related DCRs (slurmctld, slurmd, slurmdb, slurmrestd, slurmjobs)
- `data-collection-rules/os/` - Operating system DCRs (syslog, dmesg)
- `data-collection-rules/cyclecloud/` - CycleCloud DCRs (jetpack, jetpackd, healthagent)

#### Step 3: Associate DCRs with VMs

Associate all DCRs with the appropriate VMs using the provided script:

```bash
./bin/associate-dcrs.sh
```

This script automatically:
- Associates scheduler-specific DCRs with the scheduler VM (VM_ID from .env)
- Associates compute-node DCRs with the compute VMSS (VMSS_ID from .env)
- Associates shared DCRs (syslog, jetpack, etc.) with both scheduler and compute nodes
- Provides detailed output showing which DCRs are associated with which resources

**Required environment variables:**
- `RESOURCE_GROUP` - Resource group where DCRs are deployed
- `SUBSCRIPTION_ID` - Azure subscription ID
- `VM_ID` - Full resource ID of the scheduler VM
- `VMSS_ID` - Full resource ID of the compute nodes VMSS

#### Step 4: Verify Log Ingestion

Wait ~15 minutes for initial log ingestion, then verify in Log Analytics:

```kql
// Check slurmctld logs
slurmctld_raw_CL
| take 10

// Check slurmd logs
slurmd_raw_CL
| take 10

// Check slurmjobs logs (job archives)
slurmjobs_raw_CL
| take 10

// Check system logs
syslog_raw_CL
| take 10
```

## Data Processing and Transformation

### Log Format Examples

**Slurm Log Format** (slurmctld.log, slurmd.log):
```
[2025-09-08T21:11:35.869] debug:  sched/backfill: _attempt_backfill: no jobs to backfill
[2025-09-08T21:12:05.013] debug:  sackd_mgr_dump_state: saved state of 0 nodes
```

### KQL Parsing Examples

**Parse Slurm logs** into structured fields:
```kql
slurmctld_raw_CL
| parse RawData with "[" Timestamp "] " Level ": " Component ": " Message
| where isnotempty(Timestamp)
| project TimeGenerated, Computer, Timestamp, Level, Component, Message
```

**Parse system logs**:
```kql
syslog_raw_CL
| parse RawData with Timestamp " " Computer " " Process ": " Message
| project TimeGenerated, Computer, Timestamp, Process, Message
```

## Manual Setup (Alternative to Scripts)

### Create Individual Table Example

```bash
az monitor log-analytics workspace table create \
    -g $RESOURCE_GROUP \
    --workspace-name $WORKSPACE_NAME \
    --name slurmctld_raw_CL \
    --plan Analytics \
    --description "Raw logs from slurmctld daemon" \
    --columns \
        TimeGenerated=datetime \
        RawData=string \
        Computer=string \
        FilePath=string
```

### Create Individual DCR Example

```bash
az monitor data-collection rule create \
    -g $RESOURCE_GROUP \
    --name 'slurmctld_raw_dcr' \
    --rule-file data-collection-rules/slurm/slurmctld_raw_dcr.json
```

### Log File Locations

**Slurm logs** (may vary by distribution):
- `/var/log/slurm/slurmctld.log`
- `/var/log/slurm/slurmd.log`
- `/var/log/slurm/slurmdbd.log`
- `/var/log/slurm/slurmrestd.log`

**System logs:**
- `/var/log/syslog` (Debian/Ubuntu)
- `/var/log/messages` (RHEL/CentOS - update DCR if needed)
- `/var/log/dmesg`

**Application logs:**
- `/opt/cycle/jetpack/logs/jetpack.log`
- `/opt/cycle/jetpack/logs/jetpackd.log`
- `/opt/healthagent/healthagent.log`

## Data Flow Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐
│   Slurm VMs     │    │  Data Collection │    │  Log Analytics      │
│                 │────│      Rules       │────│     Workspace       │
│ Azure Monitor   │    │                  │    │                     │
│     Agent       │    │   Transform      │    │  Raw Tables (_CL)   │
└─────────────────┘    │     & Route      │    │                     │
                       └──────────────────┘    │  Future: Processed  │
                                               │  Tables (KQL)       │
                                               └─────────────────────┘
```

## Hackathon connection

The goal of the hackathon is to develop tooling to enable LLM-based AI agents to interact with compute clusters to aid in assesssing cluster health, debugging cluster issues, debugging failed jobs, etc.

Tooling to be developed includes potentially:
- MCP server for logs and metrics
- MCP server for cluster access
- Microsoft MCP server

that should work on both Slurm and AKS based clusters.

### References

- [Tasks](https://loop.cloud.microsoft/p/eyJ1IjoiaHR0cHM6Ly9taWNyb3NvZnQuc2hhcmVwb2ludC5jb20vY29udGVudHN0b3JhZ2UvQ1NQXzE5Mjg4ODA0LTUwNGMtNDQwOC1hNTFlLTMwZGNkMThhYWE4MD9uYXY9Y3owbE1rWmpiMjUwWlc1MGMzUnZjbUZuWlNVeVJrTlRVRjh4T1RJNE9EZ3dOQzAxTURSakxUUTBNRGd0WVRVeFpTMHpNR1JqWkRFNFlXRmhPREFtWkQxaUpUSXhRa2xuYjBkVmVGRkRSVk5zU0dwRVl6QlpjWEZuVHpBelUwOXJkMnBXYkU1dFVrTmxTVkZqYm5kVk9IbFNTbkpCU0dSb2NGUkpNM3B6U0ZoWWJYaERYeVptUFRBeFJrbFNRVTlYVERkRldVSXpSelZWV2twT1JESkRRVWxKVGpZMlRGUTJUa1FtWXowbE1rWW1ZVDFNYjI5d1FYQndKbkE5SlRRd1pteDFhV1I0SlRKR2JHOXZjQzF3WVdkbExXTnZiblJoYVc1bGNpWjRQU1UzUWlVeU1uY2xNaklsTTBFbE1qSlVNRkpVVlVoNGRHRlhUbmxpTTA1MldtNVJkV015YUdoamJWWjNZakpzZFdSRE5XcGlNakU0V1dsR1ExTlhaSFpTTVZZMFZWVk9SbFV5ZUVsaGExSnFUVVpzZUdOWFpGQk5SRTVVVkRKME0yRnNXbk5VYlRGVFVUSldTbFZYVG5Wa01WVTBaVlpLUzJOclJrbGFSMmgzVmtWcmVtVnVUa2xYUm1oMFpVVk9abVpFUVhoU2EyeFRVVlU1V0ZSc1p6RlRSVlpNVWpCS1dWWlZXa2RTUldzeVZGVm9RbEpHVmtaWFJrSkZWR3hqSlRORUpUSXlKVEpESlRJeWFTVXlNaVV6UVNVeU1tTmxOV1V5WXpZeUxURmxZek10TkdNMU9DMWlNR1E1TFRabU5EWXpZMlkxWkdSaFlTVXlNaVUzUkE9PSJ9?ct=1757363270925&&LOF=1)
- [Workflows to be supported](https://microsoft.sharepoint.com/:fl:/g/contentstorage/CSP_19288804-504c-4408-a51e-30dcd18aaa80/EZDTwS24KR9FkLA7RhGUkyMBiQAGzB44JRZL1FTWdgJGoQ?e=jhvL4n&nav=cz0lMkZjb250ZW50c3RvcmFnZSUyRkNTUF8xOTI4ODgwNC01MDRjLTQ0MDgtYTUxZS0zMGRjZDE4YWFhODAmZD1iJTIxQklnb0dVeFFDRVNsSGpEYzBZcXFnTzAzU09rd2pWbE5tUkNlSVFjbndVOHlSSnJBSGRocFRJM3pzSFhYbXhDXyZmPTAxRklSQU9XTVEyUEFTM09CSkQ1Q1pCTUIzSVlJWkpFWkQmYz0lMkYmYT1Mb29wQXBwJnA9JTQwZmx1aWR4JTJGbG9vcC1wYWdlLWNvbnRhaW5lciZ4PSU3QiUyMnclMjIlM0ElMjJUMFJUVUh4dGFXTnliM052Wm5RdWMyaGhjbVZ3YjJsdWRDNWpiMjE4WWlGQ1NXZHZSMVY0VVVORlUyeElha1JqTUZseGNXZFBNRE5UVDJ0M2FsWnNUbTFTUTJWSlVXTnVkMVU0ZVZKS2NrRklaR2h3VkVremVuTklXRmh0ZUVOZmZEQXhSa2xTUVU5WFRsZzFTRVZMUjBKWVZVWkdSRWsyVFVoQlJGVkZXRkJFVGxjJTNEJTIyJTJDJTIyaSUyMiUzQSUyMmMxMzAyMmY2LTVhZjAtNGY3NS04ZjVmLTg4MTM3ZWJkMTY1NCUyMiU3RA%3D%3D)
- [Sample example MCP server](https://github.com/edwardsp/mcpserver)
