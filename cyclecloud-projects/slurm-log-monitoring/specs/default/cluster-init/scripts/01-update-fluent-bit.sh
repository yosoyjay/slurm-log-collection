#!/bin/bash
# CycleCloud cluster-init script to update fluent-bit binary on 64KB page size systems
# This script checks if the system has 64KB page size and updates the fluent-bit binary if needed
set -e

echo "Checking system page size for fluent-bit compatibility"

# Check current page size
PAGE_SIZE=$(getconf PAGESIZE)
echo "System page size: $PAGE_SIZE bytes"

# Only proceed if page size is 64KB
if [ "$PAGE_SIZE" -ne 65536 ]; then
    echo "Page size is not 64KB, skipping fluent-bit update"
    exit 0
fi

echo "64KB page size detected, proceeding with fluent-bit update"
echo ""

# Get the script from files directory
SCRIPT_DIR="$CYCLECLOUD_SPEC_PATH/files"
UPDATE_SCRIPT="$SCRIPT_DIR/update-fluent-bit.sh"

if [ ! -f "$UPDATE_SCRIPT" ]; then
    echo "Error: update-fluent-bit.sh not found at $UPDATE_SCRIPT"
    exit 1
fi

# Make script executable
chmod +x "$UPDATE_SCRIPT"

# Get fluent-bit source path from CycleCloud configuration if set
FLUENT_BIT_PATH=$(jetpack config slurm-log-monitoring.fluent_bit_source_path 2>/dev/null || echo "")

if [ -n "$FLUENT_BIT_PATH" ]; then
    echo "Using configured fluent-bit binary path: $FLUENT_BIT_PATH"
    export FLUENT_BIT_SOURCE_PATH="$FLUENT_BIT_PATH"
else
    echo "Using default fluent-bit binary path from update script"
fi

# Run the update script
echo "Running fluent-bit update script"
bash "$UPDATE_SCRIPT"

echo "Fluent-bit update complete"
