#!/bin/bash
# Update fluent-bit binary used with Azure Monitor Agent to locally compiled version supporting 64K page sizes
# This script replaces the Azure Monitor Agent's fluent-bit binary with a locally compiled version
# that supports ARM64 systems with 64KB page sizes
set -e

FLUENT_BIT_SOURCE_PATH="${FLUENT_BIT_SOURCE_PATH:-/shared/fluent-bit}"
AMA_FLUENT_BIT_PATH="/opt/microsoft/azuremonitoragent/bin/fluent-bit"
BACKUP_SUFFIX="orig_page_size"

echo "Fluent-bit Binary Update for 64KB Page Size Support"
echo "Source binary: $FLUENT_BIT_SOURCE_PATH"
echo "Target binary: $AMA_FLUENT_BIT_PATH"
echo ""

# Check if source binary exists
if [ ! -f "$FLUENT_BIT_SOURCE_PATH" ]; then
    echo "Error: Source fluent-bit binary not found at $FLUENT_BIT_SOURCE_PATH"
    echo "Please compile fluent-bit first using:"
    echo "  git clone https://github.com/fluent/fluent-bit.git"
    echo "  cd fluent-bit"
    echo "  mkdir build && cd build"
    echo "  cmake .."
    echo "  make"
    echo "  bin/fluent-bit -i cpu -o stdout -f 1"
    echo ""
    exit 1
fi

# Check if target binary exists
if [ ! -f "$AMA_FLUENT_BIT_PATH" ]; then
    echo "Error: Azure Monitor Agent fluent-bit binary not found at $AMA_FLUENT_BIT_PATH"
    echo "Please ensure Azure Monitor Agent is installed"
    echo ""
    exit 1
fi

# Test source binary
echo "Testing source fluent-bit binary"
if ! "$FLUENT_BIT_SOURCE_PATH" --version >/dev/null 2>&1; then
    echo "Error: Source fluent-bit binary failed version check"
    exit 1
fi
echo "Source binary test passed"
echo ""

# Check current binary architecture
echo "Checking binary architectures"
SOURCE_ARCH=$(file "$FLUENT_BIT_SOURCE_PATH" | grep -o "ARM aarch64\|x86-64")
TARGET_ARCH=$(file "$AMA_FLUENT_BIT_PATH" | grep -o "ARM aarch64\|x86-64")
SYSTEM_ARCH=$(uname -m)

echo "Source binary architecture: $SOURCE_ARCH"
echo "Current AMA binary architecture: $TARGET_ARCH"
echo "System architecture: $SYSTEM_ARCH"

if [[ "$SYSTEM_ARCH" == "aarch64" && "$SOURCE_ARCH" != *"ARM aarch64"* ]]; then
    echo "Warning: Source binary architecture does not match ARM64 system"
fi

# Check page size
PAGE_SIZE=$(getconf PAGESIZE)
echo "System page size: $PAGE_SIZE bytes"
if [ "$PAGE_SIZE" -eq 65536 ]; then
    echo "64KB page size detected - this update should resolve jemalloc compatibility issues"
fi
echo ""

# Stop Azure Monitor Agent
echo "Stopping Azure Monitor Agent"
sudo systemctl stop azuremonitoragent
echo ""

# Backup original binary if not already backed up
BACKUP_PATH="${AMA_FLUENT_BIT_PATH}.${BACKUP_SUFFIX}"
if [ ! -f "$BACKUP_PATH" ]; then
    echo "Creating backup of original fluent-bit binary"
    sudo mv "$AMA_FLUENT_BIT_PATH" "$BACKUP_PATH"
    echo "Original binary backed up to $BACKUP_PATH"
else
    echo "Backup already exists at $BACKUP_PATH"
    sudo rm -f "$AMA_FLUENT_BIT_PATH"
fi
echo ""

# Copy new binary
echo "Installing new fluent-bit binary"
sudo cp "$FLUENT_BIT_SOURCE_PATH" "$AMA_FLUENT_BIT_PATH"
sudo chmod +x "$AMA_FLUENT_BIT_PATH"
echo "New binary installed"
echo ""

# Verify installed binary
echo "Verifying installed binary"
if sudo "$AMA_FLUENT_BIT_PATH" --version >/dev/null 2>&1; then
    echo "Installed binary verification passed"
    sudo "$AMA_FLUENT_BIT_PATH" --version
else
    echo "Error: Installed binary failed verification"
    echo "Restoring original binary"
    sudo mv "$BACKUP_PATH" "$AMA_FLUENT_BIT_PATH"
    exit 1
fi
echo ""

# Start Azure Monitor Agent
echo "Starting Azure Monitor Agent"
sudo systemctl start azuremonitoragent
echo ""

# Wait for startup
sleep 10

# Verify agent is running
if sudo systemctl is-active azuremonitoragent >/dev/null 2>&1; then
    echo "Azure Monitor Agent started successfully"
else
    echo "Error: Azure Monitor Agent failed to start"
    echo "Check logs with: sudo journalctl -u azuremonitoragent -f"
    exit 1
fi
echo ""

# Check if fluent-bit process is running
sleep 5
if pgrep -f "fluent-bit.*td-agent.conf" >/dev/null; then
    echo "Fluent-bit process is running"
    ps aux | grep fluent-bit | grep -v grep
else
    echo "Warning: Fluent-bit process not detected yet"
    echo "Monitor with: ps aux | grep fluent-bit"
fi
echo ""

echo "Update Complete"
echo "Fluent-bit binary has been updated to support 64KB page sizes"
echo ""
