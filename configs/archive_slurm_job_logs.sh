#!/bin/bash
# Archive job logs from stdout and stderr to centralized location from job head node.
# - Likely needs to be run from epliog to have permissions to write to shared location.
# Template: job_{jobid}.{out,err}

# Configuration
ARCHIVE_DIR="/shared/slurm-logs/${SLURM_JOB_USER}/"
LOG_PATH="/var/log/slurmd/epilog.log"

# Logging function (project template)
log() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local script="${BASH_SOURCE[1]##*/}"
    local lineno="${BASH_LINENO[0]}"
    echo "$ts $level $script:$lineno $msg" >> "$LOG_PATH"
}

# Resolve Slurm template variables in log file paths
resolve_slurm_template() {
    local path="$1"
    local jobid="$SLURM_JOB_ID"
    local batchhost="$job_batchhost"
    local user="$SLURM_JOB_USER"

    # Replace common Slurm template variables
    path="${path//%j/$jobid}"       # Job ID
    path="${path//%J/$jobid}"       # Array job ID (use jobid if needed)
    path="${path//%N/$batchhost}"   # First node in allocation
    path="${path//%u/$user}"        # User

    echo "$path"
}

# Copy log file to archive directory
copy_log_file() {
    local template="$1"
    local output_suffix="$2"
    local jobid="$SLURM_JOB_ID"

    if [ -z "$template" ]; then
        return 0
    fi

    local resolved_path
    resolved_path=$(resolve_slurm_template "$template")
    local archive_filename="job_${jobid}.${output_suffix}"

    log "INFO" "Copying $template -> $resolved_path to ${ARCHIVE_DIR}${archive_filename}"

    if cp "$resolved_path" "${ARCHIVE_DIR}${archive_filename}"; then
        log "INFO" "Successfully copied to ${ARCHIVE_DIR}${archive_filename}"
    else
        log "ERROR" "Failed to copy $resolved_path to ${ARCHIVE_DIR}${archive_filename}"
    fi
}

# ----------------------------------------------------------------------------
# Main execution
# ----------------------------------------------------------------------------

jobid="$SLURM_JOB_ID"

# Create archive directory
if [[ ! -d "$ARCHIVE_DIR" ]]; then
    mkdir -p "$ARCHIVE_DIR" || {
        log "ERROR" "Failed to create archive directory: $ARCHIVE_DIR"
        exit 1
    }
    log "INFO" "Created archive directory: $ARCHIVE_DIR"
fi

# Get job information once to avoid multiple scontrol calls
job_info=$(scontrol show job "$jobid") || {
    log "ERROR" "Failed to get job information for job $jobid"
    exit 1
}
job_batchhost=$(echo "$job_info" | awk -F= '/BatchHost/ {print $2}')
current_node=$(hostname)

# Only head node processes log files
if [ "$current_node" != "$job_batchhost" ]; then
    log "INFO" "Non-head node ($current_node), exiting"
    exit 0
fi

log "INFO" "Head node ($current_node) processing logs for job $jobid"

# Extract log file templates from job info
stdout_template=$(echo "$job_info" | awk -F= '/StdOut/ {print $2}')
stderr_template=$(echo "$job_info" | awk -F= '/StdErr/ {print $2}')

# Copy stdout and stderr logs
copy_log_file "$stdout_template" "out"
copy_log_file "$stderr_template" "err"

log "INFO" "Epilog processing completed for job $jobid"
