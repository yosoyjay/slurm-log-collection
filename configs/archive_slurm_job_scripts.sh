#!/bin/bash
# Archive job submission script and environment variables from job head node.
# - Run as prolog to capture job script and env before job starts.
# Template: job_{jobid}.{sh,env}

# Configuration
ARCHIVE_DIR="/shared/slurm-logs/"
LOG_PATH="/var/log/slurmd/prolog.log"

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

# Archive job script to centralized location
archive_job_script() {
    local jobid="$1"
    local archive_filename="job_${jobid}.sh"
    local archive_path="${ARCHIVE_DIR}${archive_filename}"

    log "INFO" "Archiving job script to ${archive_path}"

    if scontrol write batch_script "$jobid" "$archive_path"; then
        log "INFO" "Successfully archived job script to ${archive_path}"
        return 0
    else
        log "ERROR" "Failed to archive job script to ${archive_path}"
        return 1
    fi
}

# Archive environment variables to centralized location
archive_environment() {
    local jobid="$1"
    local archive_filename="job_${jobid}.env"
    local archive_path="${ARCHIVE_DIR}${archive_filename}"

    log "INFO" "Archiving environment variables to ${archive_path}"

    if env > "$archive_path"; then
        log "INFO" "Successfully archived environment variables to ${archive_path}"
        return 0
    else
        log "ERROR" "Failed to archive environment variables to ${archive_path}"
        return 1
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
    }
    log "INFO" "Created archive directory: $ARCHIVE_DIR"
fi

# Get job information
job_info=$(scontrol show job "$jobid") || {
    log "ERROR" "Failed to get job information for job $jobid"
}
job_batchhost=$(echo "$job_info" | awk -F= '/BatchHost/ {print $2}')
current_node=$(hostname)

# Only head node processes archival
if [ "$current_node" != "$job_batchhost" ]; then
    log "INFO" "Non-head node ($current_node), exiting"
    exit 0
fi

log "INFO" "Head node ($current_node) archiving job $jobid"

# Archive job script and environment
archive_job_script "$jobid"
archive_environment "$jobid"

log "INFO" "Prolog processing completed for job $jobid"
