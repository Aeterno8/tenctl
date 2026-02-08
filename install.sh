#!/bin/bash

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

YES_MODE=false
CLUSTER_INSTALL=true
LOCAL_ONLY=false
for arg in "$@"; do
    case "$arg" in
        -y|--yes)
            YES_MODE=true
            ;;
        --local-only)
            LOCAL_ONLY=true
            CLUSTER_INSTALL=false
            ;;
        --no-cluster)
            CLUSTER_INSTALL=false
            ;;
    esac
done

if [ ! -t 0 ]; then
    YES_MODE=true
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Tenctl CLI Installation${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root${NC}"
    exit 1
fi

if ! command -v pvesh &> /dev/null; then
    echo -e "${YELLOW}WARNING: pvesh not found. Are you running this on a Proxmox node?${NC}"
    if [ "$YES_MODE" = "false" ]; then
        read -p "Continue anyway? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            exit 0
        fi
    else
        echo "Continuing anyway (--yes mode)"
    fi
fi

echo "Checking dependencies..."

MISSING_DEPS=()
command -v jq >/dev/null 2>&1 || MISSING_DEPS+=("jq")
command -v flock >/dev/null 2>&1 || MISSING_DEPS+=("flock")

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Missing dependencies: ${MISSING_DEPS[*]}${NC}"
    install_deps="no"
    if [ "$YES_MODE" = "true" ]; then
        install_deps="yes"
    else
        read -p "Install missing dependencies? (yes/no): " install_deps
    fi
    if [ "$install_deps" = "yes" ]; then
        apt-get update
        apt-get install -y "${MISSING_DEPS[@]}"
        echo -e "${GREEN}✓ Dependencies installed${NC}"
    else
        echo -e "${RED}ERROR: Cannot proceed without dependencies${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ All dependencies satisfied${NC}"
fi

INSTALL_DIR="/usr/local/share/tenctl"
BIN_DIR="/usr/local/bin"
LIB_DIR="${INSTALL_DIR}/lib"
CONFIG_DIR="${INSTALL_DIR}/config"

echo ""
echo "Installing to:"
echo "  Main:    ${INSTALL_DIR}"
echo "  Binary:  ${BIN_DIR}/tenctl"
echo "  Commands:${BIN_DIR}/tenctl-*"
echo "  Library: ${LIB_DIR}"
echo "  Config:  ${CONFIG_DIR}"
echo ""

if [ "$YES_MODE" = "false" ]; then
    read -p "Continue with installation? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Installation cancelled"
        exit 0
    fi
fi

echo ""
echo "Creating directories..."
mkdir -p "${INSTALL_DIR}"
mkdir -p "${LIB_DIR}"
mkdir -p "${CONFIG_DIR}"

echo "Copying files..."

echo "Copying library files..."
cp -r lib/* "${LIB_DIR}/"

echo "Copying config files..."
cp -v config/tenant.conf "${CONFIG_DIR}/"

echo "Installing main CLI..."
cp -v tenctl "${BIN_DIR}/"
chmod +x "${BIN_DIR}/tenctl"

echo "Installing standalone subcommands..."
for cmd in tenctl-*; do
    if [ -f "$cmd" ] && [ -x "$cmd" ]; then
        cp -v "$cmd" "${BIN_DIR}/"
        chmod +x "${BIN_DIR}/$cmd"
    fi
done
echo -e "${GREEN}✓ Installed $(ls -1 tenctl-* 2>/dev/null | wc -l) subcommands${NC}"

if [ -f VERSION ]; then
    cp -v VERSION "${INSTALL_DIR}/"
fi

if [ -f update.sh ]; then
    cp -v update.sh "${INSTALL_DIR}/"
    chmod +x "${INSTALL_DIR}/update.sh"
fi

if [ -f uninstall.sh ]; then
    cp -v uninstall.sh "${INSTALL_DIR}/"
    chmod +x "${INSTALL_DIR}/uninstall.sh"
fi

find "${LIB_DIR}" -type f -name "*.sh" -exec chmod +x {} \;

chmod 755 "${INSTALL_DIR}"
chmod 755 "${LIB_DIR}"
chmod 750 "${CONFIG_DIR}"
chmod 640 "${CONFIG_DIR}/tenant.conf"

echo -e "${GREEN}✓ Files installed${NC}"

echo ""
echo "Installing bash completion..."

COMPLETION_DIR="/etc/bash_completion.d"
if [ -d "$COMPLETION_DIR" ]; then
    cat > "${COMPLETION_DIR}/tenctl" << 'EOF'
# Bash completion for tenctl

_tenctl_get_tenants() {
    # Get list of existing tenants from config files
    # Use bash arrays to avoid command injection from filenames
    local tenants=()
    local conf_dir="/etc/pve/tenants"
    if [ -d "$conf_dir" ] && [ -r "$conf_dir" ]; then
        for conf in "$conf_dir"/*.conf; do
            [ -f "$conf" ] && tenants+=("$(basename "${conf%.conf}")")
        done
    fi
    echo "${tenants[@]}"
}

_tenctl() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Suggest tenant names after -n or --name flags
    case "$prev" in
        -n|--name)
            local tenants=$(_tenctl_get_tenants)
            COMPREPLY=( $(compgen -W "${tenants}" -- ${cur}) )
            return 0
            ;;
    esac

    # First level commands
    if [ $COMP_CWORD -eq 1 ]; then
        opts="init add modify remove list show health cluster-status update-cli uninstall version help"
        COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
        return 0
    fi

    # Second level options based on command
    case "${COMP_WORDS[1]}" in
        add|create)
            opts="-n --name -c --cpu -r --ram -s --storage -v --vlan -i --subnet -u --username -p --password -e --email --dry-run -h --help"
            ;;
        modify|update|edit)
            opts="-n --name -c --cpu -r --ram -s --storage --email --password --show-current -h --help"
            ;;
        remove|delete|rm)
            opts="-n --name -f --force -b --backup -h --help"
            ;;
        list|ls)
            opts="-j --json -d --detailed -n --name -h --help"
            ;;
        show|info|get)
            opts="-n --name -h --help"
            ;;
        health|check|status)
            opts="-n --name -j --json -v --verbose -h --help"
            ;;
        init|initialize)
            opts="-t --type -z --zone -b --bridge -p --peers -f --force -h --help"
            ;;
        version)
            # No options for version command
            return 0
            ;;
        help)
            # No options for help command
            return 0
            ;;
        *)
            opts=""
            ;;
    esac

    COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
    return 0
}

complete -F _tenctl tenctl
EOF
    chmod 644 "${COMPLETION_DIR}/tenctl"
    echo -e "${GREEN}✓ Bash completion installed${NC}"
    echo -e "${YELLOW}  Run 'source /etc/bash_completion.d/tenctl' or restart your shell${NC}"
else
    echo -e "${YELLOW}  Bash completion directory not found, skipping${NC}"
fi

echo ""
echo "Installing logrotate configuration..."

LOGROTATE_DIR="/etc/logrotate.d"
if [ -d "$LOGROTATE_DIR" ]; then
    if [ -f "logrotate.conf" ]; then
        cp -v logrotate.conf "${LOGROTATE_DIR}/tenctl"
        chmod 644 "${LOGROTATE_DIR}/tenctl"
        echo -e "${GREEN}✓ Logrotate configuration installed${NC}"
        echo -e "${YELLOW}  Log file will be rotated daily, keeping 14 days of history${NC}"
    else
        echo -e "${YELLOW}  logrotate.conf not found, skipping${NC}"
    fi
else
    echo -e "${YELLOW}  Logrotate directory not found, skipping${NC}"
fi

echo ""
echo "Testing installation..."
if command -v tenctl &> /dev/null; then
    echo -e "${GREEN}✓ CLI tool is accessible${NC}"
    tenctl version
else
    echo -e "${RED}✗ CLI tool not found in PATH${NC}"
    exit 1
fi

echo ""
echo "Installing Tenant Watcher Service..."

if ! command -v inotifywait &>/dev/null; then
    echo -e "${YELLOW}Installing inotify-tools for file watching...${NC}"
    apt-get install -y inotify-tools
fi

if [ -f "${SOURCE_DIR}/services/tenctl-watcher.sh" ]; then
    cp "${SOURCE_DIR}/services/tenctl-watcher.sh" /usr/local/bin/tenctl-watcher
    chmod +x /usr/local/bin/tenctl-watcher
    echo -e "${GREEN}✓ Watcher script installed${NC}"
else
    echo -e "${YELLOW}⚠ Watcher script not found, skipping${NC}"
fi

if [ -f "${SOURCE_DIR}/services/tenctl-watcher.service" ]; then
    cp "${SOURCE_DIR}/services/tenctl-watcher.service" /etc/systemd/system/
    systemctl daemon-reload

    systemctl enable tenctl-watcher.service

    if systemctl start tenctl-watcher.service; then
        echo -e "${GREEN}✓ Watcher service installed and started${NC}"
        echo -e "${GREEN}  Service will monitor VM/CT creation in real-time${NC}"
    else
        echo -e "${YELLOW}⚠ Watcher service installed but failed to start${NC}"
        echo -e "${YELLOW}  Check logs: journalctl -u tenctl-watcher -f${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Watcher service file not found, skipping${NC}"
fi

install_on_cluster_nodes() {
    local current_node=$(hostname)
    local version=$(cat "${INSTALL_DIR}/VERSION" 2>/dev/null || echo "unknown")
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Cluster-Wide Installation${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    if [ -f "${INSTALL_DIR}/lib/cluster/state.sh" ]; then
        source "${INSTALL_DIR}/lib/core/logging.sh" 2>/dev/null || true
        source "${INSTALL_DIR}/lib/proxmox/api.sh" 2>/dev/null || true
        source "${INSTALL_DIR}/lib/cluster/state.sh"
    else
        echo -e "${YELLOW}⚠ Cluster state module not found, skipping cluster installation${NC}"
        return 0
    fi

    ptm_init_cluster_state "$version"
    ptm_set_node_version "$current_node" "$version" "ok"

    local all_nodes=$(ptm_get_cluster_nodes)
    local online_nodes=$(ptm_get_online_nodes)
    
    echo "Cluster nodes detected:"
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
        echo "No other online nodes found, skipping cluster installation"
        return 0
    fi
    
    if [ "$YES_MODE" = "false" ]; then
        read -p "Install on all online cluster nodes? (yes/no): " install_cluster
        if [ "$install_cluster" != "yes" ]; then
            echo "Skipping cluster installation"
            return 0
        fi
    else
        echo "Installing on all online cluster nodes (--yes mode)"
    fi
    
    local success_nodes=()
    local failed_nodes=()
    local offline_nodes=()
    
    for node in $all_nodes; do
        [ "$node" = "$current_node" ] && continue
        
        if echo "$online_nodes" | grep -q "^${node}$"; then
            echo ""
            echo -e "${GREEN}Installing on node: $node${NC}"
            
            local ssh_output
            local ssh_exit_code
            ssh_output=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$node" \
                "command -v git >/dev/null 2>&1 || (apt-get update -qq && apt-get install -y git) && \
                 cd /tmp && rm -rf tenctl-install-$$ && \
                 git clone -q ${REPO_URL:-https://github.com/Aeterno8/tenctl.git} tenctl-install-$$ 2>/dev/null && \
                 cd tenctl-install-$$ && \
                 ./install.sh -y --local-only && \
                 cd /tmp && rm -rf tenctl-install-$$" 2>&1)
            ssh_exit_code=$?

            echo "$ssh_output" | grep -E '(✓|ERROR|WARNING)' || true

            if [ $ssh_exit_code -eq 0 ]; then
                success_nodes+=("$node")
                ptm_set_node_version "$node" "$version" "ok"
                echo -e "${GREEN}✓ Installed on $node${NC}"
            else
                failed_nodes+=("$node")
                ptm_set_node_version "$node" "" "failed"
                echo -e "${RED}✗ Failed to install on $node${NC}"
                echo -e "${RED}  Last error: $(echo "$ssh_output" | tail -3 | head -1)${NC}"
            fi
        else
            offline_nodes+=("$node")
            ptm_set_node_version "$node" "" "pending"
        fi
    done

    ptm_set_cluster_version "$version"
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Cluster Installation Summary${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Successfully installed: $current_node ${success_nodes[*]}"
    
    if [ ${#failed_nodes[@]} -gt 0 ]; then
        echo -e "${RED}Failed: ${failed_nodes[*]}${NC}"
        echo "You can retry manually on failed nodes"
    fi
    
    if [ ${#offline_nodes[@]} -gt 0 ]; then
        echo -e "${YELLOW}Offline (pending): ${offline_nodes[*]}${NC}"
        echo "These nodes will need manual installation when they come online"
    fi
    echo ""
}

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

if [ "$CLUSTER_INSTALL" = "true" ] && [ "$LOCAL_ONLY" = "false" ]; then
    install_on_cluster_nodes
fi

echo "Quick start:"
echo "  1. Configure: nano ${CONFIG_DIR}/tenant.conf"
echo "  2. Initialize: tenctl init"
echo "  3. Add tenant: tenctl add -n firma_a"
echo "  4. List:       tenctl list"
echo ""
echo "For help:"
echo "  tenctl help"
echo "  tenctl <command> --help"
echo ""
