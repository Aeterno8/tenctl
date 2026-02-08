#!/bin/bash
# Tenctl Bootstrap Installer
# Usage: bash -c "$(curl -fsSL https://raw.githubusercontent.com/Aeterno8/tenctl/master/bootstrap.sh)"

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

INSTALL_DIR="/opt/tenctl"
REPO_URL="https://github.com/Aeterno8/tenctl.git"
BRANCH="${BRANCH:-master}"  # Allow override via environment variable
PROJECT_DIR=""

# Banner
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║   Tenctl - Multi-Tenant Management for Proxmox VE v2.0   ║
║   Git-style CLI with standalone subcommands              ║
║   Automated tenant isolation with VLAN/Subnet/Pools      ║
╚═══════════════════════════════════════════════════════════╝
EOF

echo ""

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root"
    log_info "Please run: sudo bash -c \"\$(curl -fsSL <URL>)\""
    exit 1
fi

if ! command -v pvesh &> /dev/null; then
    log_error "This script must be run on a Proxmox VE node"
    log_error "pvesh command not found"
    exit 1
fi

PVE_VERSION=$(pveversion 2>/dev/null | grep -oP 'pve-manager/\K[0-9]+' || echo "0")
log_info "Detected Proxmox VE version: $(pveversion | head -1)"

if [ "$PVE_VERSION" -lt 8 ]; then
    log_warn "Proxmox VE 8.0+ recommended (you have version $PVE_VERSION)"
    log_warn "Resource pool limits may not be fully enforced"
fi

log_info "Checking dependencies..."
MISSING_DEPS=()

if ! command -v git &> /dev/null; then
    MISSING_DEPS+=("git")
fi

if ! command -v jq &> /dev/null; then
    MISSING_DEPS+=("jq")
fi

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    log_info "Installing missing dependencies: ${MISSING_DEPS[*]}"
    apt-get update -qq
    apt-get install -y -qq "${MISSING_DEPS[@]}"
    log_success "Dependencies installed"
else
    log_success "All dependencies present"
fi

if [ -d "$INSTALL_DIR" ]; then
    log_warn "Installation directory already exists: $INSTALL_DIR"

    if [ ! -t 0 ]; then
        log_info "Non-interactive mode detected, auto-proceeding with reinstall"
        REINSTALL="yes"
    else
        read -p "Do you want to reinstall/update? (yes/no): " REINSTALL
    fi

    if [ "$REINSTALL" != "yes" ]; then
        log_info "Installation cancelled"
        exit 0
    fi

    log_info "Backing up existing installation..."
    mv "$INSTALL_DIR" "${INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
    log_success "Backup created"
fi

log_info "Downloading Tenctl System..."
if ! git clone -b "$BRANCH" "$REPO_URL" "$INSTALL_DIR" 2>/dev/null; then
    log_error "Failed to clone repository"
    log_error "Please check the repository URL: $REPO_URL"
    exit 1
fi
log_success "Downloaded successfully"

PROJECT_DIR="$INSTALL_DIR"
if [ ! -f "$PROJECT_DIR/install.sh" ]; then
    if [ -d "$PROJECT_DIR/tenctl" ] && [ -f "$PROJECT_DIR/tenctl/install.sh" ]; then
        log_warn "Detected nested project directory, using: $PROJECT_DIR/tenctl"
        PROJECT_DIR="$PROJECT_DIR/tenctl"
    else
        log_error "install.sh not found in cloned repository"
        log_error "Checked: $INSTALL_DIR and $INSTALL_DIR/tenctl"
        exit 1
    fi
fi

cd "$PROJECT_DIR"

log_info "Setting up permissions..."
chmod +x scripts/*.sh 2>/dev/null || true
chmod +x lib/*.sh 2>/dev/null || true
chmod +x tenctl 2>/dev/null || true
chmod +x tenctl-* 2>/dev/null || true
chmod +x install.sh 2>/dev/null || true
chmod +x update.sh 2>/dev/null || true
chmod +x uninstall.sh 2>/dev/null || true
log_success "Permissions configured"

echo ""
log_info "=========================================="
log_info "Configuration Setup"
log_info "=========================================="
echo ""

create_default_config() {
    local config_file="$1"

    cat > "$config_file" <<'EOF'
# Tenctl Configuration
# ==================================
# This file contains global settings for multi-tenant environment
# Edit values according to your Proxmox cluster needs

# VLAN Range za Tenante
# ---------------------
# Each tenant gets a unique VLAN ID from this range
# Range: 1-4094 (IEEE 802.1Q standard)
VLAN_START=100
VLAN_END=999

# Subnet Range za Tenante
# ------------------------
# Each tenant gets a dedicated /24 subnet
# Example: BASE_SUBNET="10.100" -> 10.100.0.0/24, 10.100.1.0/24, etc.
# Supports up to 256 tenants (10.100.0.0 - 10.100.255.0)
BASE_SUBNET="10.100"

# Network Bridge
# --------------
# VLAN-aware bridge to be used for tenant networks
# Check which bridge you're using: ip a | grep vmbr
# Common: vmbr0 (management) or vmbr1 (tenant networks)
NETWORK_BRIDGE="vmbr1"

# Tenant Configuration Directory
# -------------------------------
# Directory where tenant config files are stored
# Don't change unless you know what you're doing
TENANT_CONFIG_DIR="/etc/pve/tenants"

# Default Resource Limiti (po tenantu)
# -------------------------------------
# These limits can be overridden when creating tenant
# Adjust according to your cluster hardware

# CPU cores per tenant (whole number)
DEFAULT_CPU_LIMIT=8

# RAM per tenant (in MB)
# Examples: 8192=8GB, 16384=16GB, 32768=32GB, 65536=64GB
DEFAULT_RAM_LIMIT=16384

# Storage per tenant (in GB)
# Examples: 500=500GB, 1000=1TB, 2000=2TB
DEFAULT_STORAGE_LIMIT=500

# SDN (Software-Defined Networking) Configuration
# ------------------------------------------------
# Zone type determines how tenant networks will be configured

# SDN_ZONE_TYPE opcije:
#   - "vxlan"  : For multi-node cluster (recommended for 2+ nodes)
#                Creates overlay network, VMs can migrate between nodes
#   - "vlan"   : For single-node or if you have VLAN-aware switch between nodes
#   - "simple" : Without additional encapsulation (rarely used)
SDN_ZONE_TYPE="vxlan"

# SDN zone name (don't change unless you know what you're doing)
SDN_ZONE_NAME="tenant-zone"

# VxLAN Port (only if using vxlan)
# Standard VxLAN port je 4789
VXLAN_PORT=4789

# Tenant Admin Role
# -----------------
# Proxmox role for tenant admin users
# "PVEPoolAdmin" allows managing VMs in their own pool
# Don't change unless you have custom role
TENANT_ADMIN_ROLE="PVEPoolAdmin"

# Log Directory
# -------------
# Directory where operation logs are stored
LOG_DIR="/var/log/tenctl"

# ==================================
# NOTES:
# - After config changes, run: tenctl init (if not already done)
# - Check SDN zones: pvesh get /cluster/sdn/zones --output-format json
# - Check bridge: ip a | grep vmbr
# - For VxLAN cluster: all nodes must have network connectivity
# ==================================
EOF

    chmod 644 "$config_file"
}

if [ ! -t 0 ]; then
    log_info "Non-interactive mode: Using default configuration"
    CUSTOMIZE="no"
else
    read -p "Do you want to customize configuration now? (yes/no, default: no): " CUSTOMIZE
fi

if [ "$CUSTOMIZE" = "yes" ]; then
    log_info "Opening configuration file for editing..."

    if ! command -v vim &> /dev/null; then
        log_info "vim not found, installing..."
        apt-get update -qq
        apt-get install -y -qq vim
        log_success "vim installed"
    fi

    CONFIG_FILE="${PROJECT_DIR}/config/tenant.conf"
    if [ ! -f "$CONFIG_FILE" ]; then
        log_warn "Configuration file not found, creating default..."
        mkdir -p "$(dirname "$CONFIG_FILE")"
        create_default_config "$CONFIG_FILE"
        log_success "Default configuration created"
    fi

    chmod 644 "$CONFIG_FILE"

    log_info "Press ENTER to open vim editor..."
    log_info "In vim: Edit values, then press ESC -> :wq -> ENTER to save"
    read

    vim "$CONFIG_FILE"
else
    log_info "Using default configuration"
    log_warn "You can edit later: $PROJECT_DIR/config/tenant.conf"
fi

log_info "Running CLI installation..."
if ./install.sh; then
    log_success "CLI tool installed successfully"
else
    log_error "Installation failed"
    exit 1
fi

echo ""
log_info "=========================================="
log_info "Cluster Initialization"
log_info "=========================================="
echo ""
log_warn "Next step: Initialize Proxmox cluster for multi-tenant use"
log_info "This will create SDN zones and apply configuration"
echo ""

if [ ! -t 0 ]; then
    log_info "Non-interactive mode: Skipping cluster initialization"
    log_warn "Run manually when ready: tenctl init"
    INITIALIZE="no"
else
    read -p "Do you want to initialize the cluster now? (yes/no): " INITIALIZE
fi

if [ "$INITIALIZE" = "yes" ]; then
    log_info "Running cluster initialization..."
    if tenctl init; then
        log_success "Cluster initialized successfully"
    else
        log_error "Initialization failed"
        log_warn "You can retry later with: tenctl init"
    fi
else
    log_info "Skipping initialization"
    log_warn "Run manually when ready: tenctl init"
fi

echo ""
log_success "=========================================="
log_success "Installation Complete!"
log_success "=========================================="
echo ""
log_info "Tenctl v2.0 is ready to use!"
echo ""
log_info "What's new in v2.0:"
echo "  ✓ Git-style architecture with 13 standalone subcommands"
echo "  ✓ ~50-70% faster startup time with lazy module loading"
echo "  ✓ All functions namespaced with ptm_ prefix"
echo ""
log_info "Quick start commands:"
echo "  tenctl --help                    # Show help"
echo "  tenctl version                   # Show version info"
echo "  tenctl init                      # Initialize cluster (if not done)"
echo "  tenctl add -n <name>             # Add tenant"
echo "  tenctl list                      # List tenants"
echo "  tenctl health                    # System health check"
echo ""
log_info "Configuration file: $PROJECT_DIR/config/tenant.conf"
log_info "Documentation: See docs/ directory"
log_info "Logs: /var/log/tenctl/tenant-management.log"
echo ""
log_info "Credentials are stored in: /root/tenctl-credentials/"
log_warn "Keep credentials secure! Files are mode 600 (owner-only access)"
echo ""

if [ ! -t 0 ]; then
    log_info "Non-interactive mode: Skipping first tenant creation"
    CREATE_TENANT="no"
else
    read -p "Would you like to create your first tenant now? (yes/no): " CREATE_TENANT
fi

if [ "$CREATE_TENANT" = "yes" ]; then
    echo ""
    read -p "Enter tenant name (e.g., company_a): " TENANT_NAME

    if [ -n "$TENANT_NAME" ]; then
        log_info "Creating tenant: $TENANT_NAME"
        log_info "Using default resource limits (edit config/tenant.conf to change)"

        if tenctl add -n "$TENANT_NAME"; then
            log_success "Tenant created successfully!"
            log_info "View credentials: cat /root/tenctl-credentials/tenant_${TENANT_NAME}_*.json"
        else
            log_error "Failed to create tenant"
        fi
    fi
fi

echo ""
log_success "Setup complete! Enjoy your multi-tenant Proxmox environment!"
echo ""
