#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

REPO_URL="${REPO_URL:-https://github.com/Aeterno8/tenctl.git}"
BRANCH="${BRANCH:-master}"
INSTALL_DIR="/usr/local/share/tenctl"
CONFIG_FILE="${INSTALL_DIR}/config/tenant.conf"
TEMP_DIR="/tmp/tenctl-update-$$"
BACKUP_DIR="/root/tenctl-backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

YES_MODE=false
LOCAL_ONLY=false
for arg in "$@"; do
    case "$arg" in
        -y|--yes)
            YES_MODE=true
            ;;
        --local-only)
            LOCAL_ONLY=true
            ;;
    esac
done

if [ ! -t 0 ]; then
    YES_MODE=true
fi

trap "rm -rf '$TEMP_DIR'" EXIT

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: Must be run as root${NC}"
    exit 1
fi

if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "${RED}ERROR: Tenctl not installed${NC}"
    echo "Install first: cd /path/to/repo && ./install.sh"
    exit 1
fi

CURRENT_VERSION="unknown"
if [ -f "${INSTALL_DIR}/VERSION" ]; then
    CURRENT_VERSION=$(cat "${INSTALL_DIR}/VERSION")
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Tenctl CLI Update${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Current version: ${CURRENT_VERSION}"
echo "Repository: ${REPO_URL}"
echo "Branch: ${BRANCH}"
echo ""

if [ "$YES_MODE" = "false" ]; then
    read -p "Continue with update? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Update cancelled"
        exit 0
    fi
fi

echo ""
echo -e "${BLUE}Creating backup...${NC}"
mkdir -p "${BACKUP_DIR}"

BACKUP_PATH="${BACKUP_DIR}/backup_${TIMESTAMP}.tar.gz"
if tar -czf "${BACKUP_PATH}" -C "$(dirname "$INSTALL_DIR")" "$(basename "$INSTALL_DIR")" 2>/dev/null; then
    echo -e "${GREEN}✓ Backup created: ${BACKUP_PATH}${NC}"
else
    echo -e "${RED}ERROR: Failed to create backup${NC}"
    exit 1
fi

CONFIG_BACKUP=""
if [ -f "$CONFIG_FILE" ]; then
    CONFIG_BACKUP="${BACKUP_DIR}/tenant.conf.${TIMESTAMP}"
    cp "$CONFIG_FILE" "$CONFIG_BACKUP"
    echo -e "${GREEN}✓ Config backed up: ${CONFIG_BACKUP}${NC}"
fi

echo ""
echo -e "${BLUE}Checking dependencies...${NC}"
if ! command -v git &> /dev/null; then
    echo -e "${YELLOW}Git not found, installing...${NC}"
    if [ "$YES_MODE" = "true" ]; then
        apt-get update -qq && apt-get install -y git
    else
        read -p "Install git? (yes/no): " install_git
        if [ "$install_git" = "yes" ]; then
            apt-get update && apt-get install -y git
        else
            echo -e "${RED}ERROR: Git is required for updates${NC}"
            exit 1
        fi
    fi
    echo -e "${GREEN}✓ Git installed${NC}"
else
    echo -e "${GREEN}✓ Git is available${NC}"
fi

echo ""
echo -e "${BLUE}Downloading latest version...${NC}"
mkdir -p "$TEMP_DIR"

if ! git clone -b "$BRANCH" "$REPO_URL" "$TEMP_DIR" 2>/dev/null; then
    echo -e "${RED}ERROR: Failed to download from repository${NC}"
    echo "Please check:"
    echo "  - Network connection"
    echo "  - Repository URL: $REPO_URL"
    echo "  - Branch: $BRANCH"
    echo "  - Git installation: $(command -v git || echo 'not found')"
    exit 1
fi

PROJECT_DIR="$TEMP_DIR"
if [ ! -f "$PROJECT_DIR/install.sh" ]; then
    if [ -d "$PROJECT_DIR/tenctl" ] && [ -f "$PROJECT_DIR/tenctl/install.sh" ]; then
        PROJECT_DIR="$PROJECT_DIR/tenctl"
    else
        echo -e "${RED}ERROR: Invalid repository structure${NC}"
        echo "install.sh not found in downloaded repository"
        exit 1
    fi
fi

NEW_VERSION="unknown"
if [ -f "${PROJECT_DIR}/VERSION" ]; then
    NEW_VERSION=$(cat "${PROJECT_DIR}/VERSION")
fi

echo -e "${GREEN}✓ Downloaded version: ${NEW_VERSION}${NC}"

if [ "$CURRENT_VERSION" = "$NEW_VERSION" ]; then
    echo ""
    echo -e "${YELLOW}WARNING: Already on version ${CURRENT_VERSION}${NC}"
    if [ "$YES_MODE" = "false" ]; then
        read -p "Continue anyway? (yes/no): " force_update
        if [ "$force_update" != "yes" ]; then
            echo "Update cancelled"
            exit 0
        fi
    else
        echo "Continuing with reinstall (--yes mode)"
    fi
fi

PRESERVE_CONFIG=true
if [ -f "$CONFIG_FILE" ] && [ -f "${PROJECT_DIR}/config/tenant.conf" ]; then
    echo ""
    echo -e "${BLUE}Checking configuration changes...${NC}"

    OLD_CONFIG_MD5=$(md5sum "$CONFIG_FILE" | cut -d' ' -f1)
    NEW_CONFIG_MD5=$(md5sum "${PROJECT_DIR}/config/tenant.conf" | cut -d' ' -f1)

    if [ "$OLD_CONFIG_MD5" != "$NEW_CONFIG_MD5" ]; then
        echo -e "${YELLOW}WARNING: Configuration file has changed!${NC}"

        if [ "$YES_MODE" = "true" ]; then
            echo -e "${GREEN}Keeping current configuration (--yes mode)${NC}"
            PRESERVE_CONFIG=true
        else
            echo ""
            echo "Options:"
            echo "  1. Keep current config (recommended)"
            echo "  2. Use new config (WARNING: will overwrite custom settings)"
            echo "  3. Show diff and decide"
            echo "  4. Cancel update"
            read -p "Choice [1-4]: " config_choice

            case "$config_choice" in
                1)
                    echo -e "${GREEN}Keeping current configuration${NC}"
                    PRESERVE_CONFIG=true
                    ;;
                2)
                    echo -e "${YELLOW}Using new configuration${NC}"
                    PRESERVE_CONFIG=false
                    ;;
                3)
                    echo ""
                    echo "Differences (- current, + new):"
                    diff -u "$CONFIG_FILE" "${PROJECT_DIR}/config/tenant.conf" || true
                    echo ""
                    read -p "Keep current config? (yes/no): " keep
                    PRESERVE_CONFIG=$( [ "$keep" = "yes" ] && echo "true" || echo "false" )
                    ;;
                4)
                    echo "Update cancelled"
                    exit 0
                    ;;
                *)
                    echo "Invalid choice, keeping current config"
                    PRESERVE_CONFIG=true
                    ;;
            esac
        fi
    else
        echo -e "${GREEN}✓ No configuration changes${NC}"
        PRESERVE_CONFIG=true
    fi
fi

echo ""
echo -e "${BLUE}Applying update...${NC}"

cd "$PROJECT_DIR"

INSTALL_OUTPUT=$(mktemp)
if ./install.sh -y > "$INSTALL_OUTPUT" 2>&1; then
    grep -E '(✓|ERROR|WARNING)' "$INSTALL_OUTPUT" || true
    echo -e "${GREEN}✓ Installation completed${NC}"
    rm -f "$INSTALL_OUTPUT"
else
    grep -E '(✓|ERROR|WARNING)' "$INSTALL_OUTPUT" || cat "$INSTALL_OUTPUT"
    rm -f "$INSTALL_OUTPUT"
    echo -e "${RED}ERROR: Installation failed${NC}"
    echo ""
    echo "To rollback:"
    echo "  rm -rf ${INSTALL_DIR}"
    echo "  tar -xzf ${BACKUP_PATH} -C /"
    exit 1
fi

if [ "$PRESERVE_CONFIG" = "true" ] && [ -n "$CONFIG_BACKUP" ] && [ -f "$CONFIG_BACKUP" ]; then
    echo -e "${BLUE}Restoring user configuration...${NC}"
    cp "$CONFIG_BACKUP" "$CONFIG_FILE"
    echo -e "${GREEN}✓ Configuration restored${NC}"
fi

echo ""
echo -e "${BLUE}Verifying update...${NC}"

if command -v tenctl &> /dev/null; then
    INSTALLED_VERSION=$(cat "${INSTALL_DIR}/VERSION" 2>/dev/null || echo "unknown")
    echo -e "${GREEN}✓ CLI is functional${NC}"
    echo "Installed version: ${INSTALLED_VERSION}"
else
    echo -e "${RED}✗ CLI not found after update${NC}"
    exit 1
fi

if systemctl is-active --quiet tenctl-watcher 2>/dev/null; then
    echo ""
    echo -e "${BLUE}Restarting tenant watcher service...${NC}"
    if systemctl restart tenctl-watcher; then
        echo -e "${GREEN}✓ Watcher service restarted${NC}"
    else
        echo -e "${YELLOW}⚠ Failed to restart watcher service${NC}"
    fi
fi

update_cluster_nodes() {
    local current_node=$(hostname)
    
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Cluster-Wide Update${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    if [ -f "${INSTALL_DIR}/lib/cluster/state.sh" ]; then
        source "${INSTALL_DIR}/lib/cluster/state.sh"
    else
        echo -e "${YELLOW}⚠ Cluster state module not found, skipping cluster update${NC}"
        return 0
    fi
    
    local all_nodes=$(ptm_get_cluster_nodes)
    local online_nodes=$(ptm_get_online_nodes)
    
    echo "Cluster nodes:"
    for node in $all_nodes; do
        if echo "$online_nodes" | grep -q "^${node}$"; then
            echo "  $node (online)"
        else
            echo "  $node (offline)"
        fi
    done
    echo ""
    
    local other_nodes=$(echo "$online_nodes" | grep -v "^${current_node}$" || true)
    if [ -z "$other_nodes" ]; then
        echo "No other online nodes found"
        ptm_set_cluster_version "$NEW_VERSION"
        ptm_set_node_version "$current_node" "$NEW_VERSION" "ok"
        return 0
    fi
    
    local updated_nodes=()
    local failed_nodes=()
    local offline_nodes=()
    
    for node in $all_nodes; do
        [ "$node" = "$current_node" ] && continue
        
        if echo "$online_nodes" | grep -q "^${node}$"; then
            echo ""
            echo -e "${BLUE}Updating node: $node${NC}"
            
            if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$node" \
                'command -v git >/dev/null 2>&1 || (apt-get update -qq && apt-get install -y git) && tenctl update-cli -y --local-only' 2>&1 | grep -E '(✓|ERROR|WARNING|Version:)' || true; then
                updated_nodes+=("$node")
                ptm_set_node_version "$node" "$NEW_VERSION" "ok"
                echo -e "${GREEN}✓ Updated $node${NC}"
            else
                failed_nodes+=("$node")
                ptm_set_node_version "$node" "" "failed"
                echo -e "${RED}✗ Failed to update $node${NC}"
            fi
        else
            offline_nodes+=("$node")
            ptm_set_node_version "$node" "" "pending"
        fi
    done
    
    ptm_set_cluster_version "$NEW_VERSION"
    ptm_set_node_version "$current_node" "$NEW_VERSION" "ok"
    
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Cluster Update Summary${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "Updated: $current_node ${updated_nodes[*]}"
    
    if [ ${#failed_nodes[@]} -gt 0 ]; then
        echo -e "${RED}Failed: ${failed_nodes[*]}${NC}"
        echo "You can retry manually: ssh <node> 'tenctl update-cli'"
    fi

    if [ ${#offline_nodes[@]} -gt 0 ]; then
        echo -e "${YELLOW}Offline (pending): ${offline_nodes[*]}${NC}"
        echo "These nodes will show a warning when they come online"
        echo "Update them with: ssh <node> 'tenctl update-cli'"
    fi
    echo ""
}

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Update Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Version: ${CURRENT_VERSION} → ${NEW_VERSION}"
echo ""

if [ "$LOCAL_ONLY" != "true" ]; then
    update_cluster_nodes
fi

echo "Backup location: ${BACKUP_PATH}"
if [ -n "$CONFIG_BACKUP" ] && [ -f "$CONFIG_BACKUP" ]; then
    echo "Config backup: ${CONFIG_BACKUP}"
fi
echo ""
echo "To rollback if needed:"
echo "  rm -rf ${INSTALL_DIR}"
echo "  tar -xzf ${BACKUP_PATH} -C /"
echo ""
