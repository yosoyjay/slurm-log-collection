#!/bin/bash
# Update fluent-bit binary used with Azure Monitor Agent to locally compiled version supporting 64K page sizes
# This script replaces the Azure Monitor Agent's fluent-bit binary with a locally compiled version
# that supports ARM64 systems with 64KB page sizes.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

FLUENT_BIT_SOURCE_PATH="/shared/fluent-bit"
AMA_FLUENT_BIT_PATH="/opt/microsoft/azuremonitoragent/bin/fluent-bit"
BACKUP_SUFFIX="orig_page_size"

echo -e "${BLUE}=== Fluent-bit Binary Update for 64KB Page Size Support ===${NC}"
echo "Source binary: $FLUENT_BIT_SOURCE_PATH"
echo "Target binary: $AMA_FLUENT_BIT_PATH"
echo

# Check if source binary exists
if [ ! -f "$FLUENT_BIT_SOURCE_PATH" ]; then
    echo -e "${RED}Error: Source fluent-bit binary not found at $FLUENT_BIT_SOURCE_PATH${NC}"
    echo "Please compile fluent-bit first using:"
    echo "  git clone https://github.com/fluent/fluent-bit.git"
    echo "  cd fluent-bit"
    echo "  mkdir build && cd build"
    echo "  cmake .."
    echo "  make"
    echo "  bin/fluent-bit -i cpu -o stdout -f 1  # Test the binary"
    exit 1
fi

# Check if target binary exists
if [ ! -f "$AMA_FLUENT_BIT_PATH" ]; then
    echo -e "${RED}Error: Azure Monitor Agent fluent-bit binary not found at $AMA_FLUENT_BIT_PATH${NC}"
    echo "Please ensure Azure Monitor Agent is installed."
    exit 1
fi

# Test source binary
echo -e "${YELLOW}Testing source fluent-bit binary...${NC}"
if ! "$FLUENT_BIT_SOURCE_PATH" --version >/dev/null 2>&1; then
    echo -e "${RED}Error: Source fluent-bit binary failed version check${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Source binary test passed${NC}"

# Check current binary architecture
echo -e "${YELLOW}Checking binary architectures...${NC}"
SOURCE_ARCH=$(file "$FLUENT_BIT_SOURCE_PATH" | grep -o "ARM aarch64\|x86-64")
TARGET_ARCH=$(file "$AMA_FLUENT_BIT_PATH" | grep -o "ARM aarch64\|x86-64")
SYSTEM_ARCH=$(uname -m)

echo "Source binary architecture: $SOURCE_ARCH"
echo "Current AMA binary architecture: $TARGET_ARCH"
echo "System architecture: $SYSTEM_ARCH"

if [[ "$SYSTEM_ARCH" == "aarch64" && "$SOURCE_ARCH" != *"ARM aarch64"* ]]; then
    echo -e "${RED}Warning: Source binary architecture doesn't match ARM64 system${NC}"
fi

# Check page size
PAGE_SIZE=$(getconf PAGESIZE)
echo "System page size: $PAGE_SIZE bytes"
if [ "$PAGE_SIZE" -eq 65536 ]; then
    echo -e "${YELLOW}64KB page size detected - this update should resolve jemalloc compatibility issues${NC}"
fi

# Stop Azure Monitor Agent
echo -e "${YELLOW}Stopping Azure Monitor Agent...${NC}"
sudo systemctl stop azuremonitoragent

# Backup original binary if not already backed up
BACKUP_PATH="${AMA_FLUENT_BIT_PATH}.${BACKUP_SUFFIX}"
if [ ! -f "$BACKUP_PATH" ]; then
    echo -e "${YELLOW}Creating backup of original fluent-bit binary...${NC}"
    sudo mv "$AMA_FLUENT_BIT_PATH" "$BACKUP_PATH"
    echo -e "${GREEN}✓ Original binary backed up to $BACKUP_PATH${NC}"
else
    echo -e "${YELLOW}Backup already exists at $BACKUP_PATH${NC}"
    sudo rm -f "$AMA_FLUENT_BIT_PATH"
fi

# Copy new binary
echo -e "${YELLOW}Installing new fluent-bit binary...${NC}"
sudo cp "$FLUENT_BIT_SOURCE_PATH" "$AMA_FLUENT_BIT_PATH"
sudo chmod +x "$AMA_FLUENT_BIT_PATH"
echo -e "${GREEN}✓ New binary installed${NC}"

# Verify installed binary
echo -e "${YELLOW}Verifying installed binary...${NC}"
if sudo "$AMA_FLUENT_BIT_PATH" --version >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Installed binary verification passed${NC}"
    sudo "$AMA_FLUENT_BIT_PATH" --version
else
    echo -e "${RED}Error: Installed binary failed verification${NC}"
    echo "Restoring original binary..."
    sudo mv "$BACKUP_PATH" "$AMA_FLUENT_BIT_PATH"
    exit 1
fi

# Start Azure Monitor Agent
echo -e "${YELLOW}Starting Azure Monitor Agent...${NC}"
sudo systemctl start azuremonitoragent

# Wait for startup
sleep 10

# Verify agent is running
if sudo systemctl is-active azuremonitoragent >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Azure Monitor Agent started successfully${NC}"
else
    echo -e "${RED}Error: Azure Monitor Agent failed to start${NC}"
    echo "Check logs with: sudo journalctl -u azuremonitoragent -f"
    exit 1
fi

# Check if fluent-bit process is running
sleep 5
if pgrep -f "fluent-bit.*td-agent.conf" >/dev/null; then
    echo -e "${GREEN}✓ Fluent-bit process is running${NC}"
    ps aux | grep fluent-bit | grep -v grep
else
    echo -e "${YELLOW}Warning: Fluent-bit process not detected yet${NC}"
    echo "Monitor with: ps aux | grep fluent-bit"
fi

echo
echo -e "${BLUE}=== Update Complete ===${NC}"
echo -e "${GREEN}Fluent-bit binary has been updated to support 64KB page sizes${NC}"
echo
