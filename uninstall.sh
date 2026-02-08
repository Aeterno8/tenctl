#!/bin/bash

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FULL_CLEANUP=false
PURGE_TENANTS=false
FORCE=false

usage() {
    cat << 'EOF'
Tenctl - Uninstallation

Usage: ./uninstall.sh [OPTIONS]

Options:
  --full              Remove CLI tool, configs, and credentials (preserves Proxmox resources)
  --purge-tenants     Also delete all tenant resources from Proxmox (pools, users, vnets, VMs)
  -f, --force         Skip confirmation prompts
  -h, --help          Show this help

Cleanup Levels:
  1. Default (no flags):
     - Removes CLI tool from /usr/local/bin
     - Removes installation from /usr/local/share/tenctl
     - Removes bash completion
     - PRESERVES: tenant configs, credentials, Proxmox resources

  2. --full:
     - All of level 1, plus:
     - Removes tenant configs in /etc/pve/tenants
     - Removes credentials in /root/tenctl-credentials
     - PRESERVES: Proxmox resources (pools, users, vnets, VMs)

  3. --full --purge-tenants:
     - All of level 2, plus:
     - Deletes all VMs and containers in tenant pools
     - Deletes resource pools
     - Deletes tenant users and groups
     - Deletes SDN VNets
     - Removes ACL entries
     - COMPLETE SYSTEM WIPE

WARNING: --purge-tenants is DESTRUCTIVE and IRREVERSIBLE!

Examples:
  ./uninstall.sh                    # Remove CLI only (safe)
  ./uninstall.sh --full             # Remove CLI and configs
  ./uninstall.sh --full --purge-tenants --force  # Complete wipe

EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --full)
            FULL_CLEANUP=true
            shift
            ;;
        --purge-tenants)
            PURGE_TENANTS=true
            FULL_CLEANUP=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            ;;
    esac
done

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: Must be run as root${NC}"
    exit 1
fi

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Tenctl Uninstallation${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

INSTALL_DIR="/usr/local/share/tenctl"
BIN_FILE="/usr/local/bin/tenctl"
COMPLETION_FILE="/etc/bash_completion.d/tenctl"
TENANT_CONFIG_DIR="/etc/pve/tenants"
CREDENTIALS_DIR="/root/tenctl-credentials"
LOG_DIR="/var/log/tenctl"
LOCK_DIR="/var/lock/tenctl"

echo "Removal plan:"
echo ""
echo -e "${BLUE}Always removed:${NC}"
echo "  - CLI tool: ${BIN_FILE}"
echo "  - Installation: ${INSTALL_DIR}"
echo "  - Bash completion: ${COMPLETION_FILE}"
echo ""

if [ "$FULL_CLEANUP" = true ]; then
    echo -e "${YELLOW}Also removing (--full):${NC}"
    if [ -d "$TENANT_CONFIG_DIR" ]; then
        TENANT_COUNT=$(find "$TENANT_CONFIG_DIR" -name "*.conf" 2>/dev/null | wc -l)
        echo "  - Tenant configs: ${TENANT_COUNT} tenant(s) in ${TENANT_CONFIG_DIR}"
    else
        echo "  - Tenant configs: (directory not found)"
    fi

    if [ -d "$CREDENTIALS_DIR" ]; then
        CRED_COUNT=$(find "$CREDENTIALS_DIR" -name "*.json" 2>/dev/null | wc -l)
        echo "  - Credentials: ${CRED_COUNT} file(s) in ${CREDENTIALS_DIR}"
    else
        echo "  - Credentials: (directory not found)"
    fi

    echo "  - Logs: ${LOG_DIR}"
    echo "  - Lock files: ${LOCK_DIR}"
    echo ""
fi

if [ "$PURGE_TENANTS" = true ]; then
    echo -e "${RED}ALSO DELETING PROXMOX RESOURCES (--purge-tenants):${NC}"

    TENANT_LIST=()
    if [ -d "$TENANT_CONFIG_DIR" ]; then
        for conf in "$TENANT_CONFIG_DIR"/*.conf; do
            if [ -f "$conf" ]; then
                TENANT_LIST+=("$(basename "${conf%.conf}")")
            fi
        done
    fi

    if [ ${#TENANT_LIST[@]} -gt 0 ]; then
        echo "  - ${#TENANT_LIST[@]} tenant(s) will be deleted from Proxmox:"
        for tenant in "${TENANT_LIST[@]}"; do
            echo "    * $tenant"
        done
        echo ""
        echo -e "${RED}  This includes:${NC}"
        echo "    - All VMs and containers in tenant pools"
        echo "    - Resource pools"
        echo "    - User accounts and groups"
        echo "    - SDN VNets"
        echo "    - ACL permissions"
    else
        echo "  - No tenants found"
    fi
    echo ""
    echo -e "${RED}WARNING: THIS IS IRREVERSIBLE!${NC}"
    echo ""
fi

if [ "$FULL_CLEANUP" = false ]; then
    echo -e "${GREEN}Preserved:${NC}"
    echo "  - Tenant configs: ${TENANT_CONFIG_DIR}"
    echo "  - Credentials: ${CREDENTIALS_DIR}"
    echo "  - Proxmox resources (pools, users, vnets, VMs)"
    echo ""
fi

if [ "$FORCE" = false ]; then
    if [ "$PURGE_TENANTS" = true ]; then
        echo -e "${RED}═══════════════════════════════════════${NC}"
        echo -e "${RED}FINAL WARNING - DESTRUCTIVE OPERATION${NC}"
        echo -e "${RED}═══════════════════════════════════════${NC}"
        echo ""
        read -p "Type 'DELETE EVERYTHING' to confirm purge: " confirm
        if [ "$confirm" != "DELETE EVERYTHING" ]; then
            echo "Purge cancelled"
            exit 0
        fi
    else
        read -p "Continue with uninstallation? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            echo "Uninstallation cancelled"
            exit 0
        fi
    fi
fi

if [ "$PURGE_TENANTS" = true ]; then
    if [ -f "${INSTALL_DIR}/lib/common.sh" ]; then
        source "${INSTALL_DIR}/lib/common.sh" 2>/dev/null || {
            echo -e "${YELLOW}WARNING: Could not load common.sh, purge may be incomplete${NC}"
        }
    fi
fi

if [ "$PURGE_TENANTS" = true ] && [ ${#TENANT_LIST[@]} -gt 0 ]; then
    echo ""
    echo -e "${BLUE}Purging tenant resources from Proxmox...${NC}"

    for tenant in "${TENANT_LIST[@]}"; do
        echo ""
        echo -e "${YELLOW}Purging tenant: $tenant${NC}"

        TENANT_CONF="${TENANT_CONFIG_DIR}/${tenant}.conf"
        if [ ! -f "$TENANT_CONF" ]; then
            echo -e "${YELLOW}  Config not found, skipping${NC}"
            continue
        fi

        source "$TENANT_CONF"

        if command -v pvesh &> /dev/null; then
            VM_LIST_JSON=$(pvesh get "/pools/${POOL_ID}" --output-format json 2>/dev/null || echo "[]")
            mapfile -t vm_list < <(echo "$VM_LIST_JSON" | jq -r '.[].vmid // empty' 2>/dev/null || echo "")

            if [ ${#vm_list[@]} -gt 0 ]; then
                echo "  Deleting ${#vm_list[@]} VM(s)/Container(s)..."
                for vmid in "${vm_list[@]}"; do
                    [ -z "$vmid" ] && continue

                    VM_INFO=$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null | jq --argjson id "$vmid" '.[] | select(.vmid == $id)' || echo "{}")
                    vm_type=$(echo "$VM_INFO" | jq -r '.type // "unknown"')
                    node=$(echo "$VM_INFO" | jq -r '.node // "unknown"')

                    if [ "$vm_type" = "qemu" ]; then
                        pvesh delete "/nodes/${node}/qemu/${vmid}" 2>/dev/null && echo "    ✓ Deleted VM $vmid" || echo "    ✗ Failed to delete VM $vmid"
                    elif [ "$vm_type" = "lxc" ]; then
                        pvesh delete "/nodes/${node}/lxc/${vmid}" 2>/dev/null && echo "    ✓ Deleted CT $vmid" || echo "    ✗ Failed to delete CT $vmid"
                    else
                        echo "    ✗ Unknown VM type for $vmid"
                    fi
                done
            fi

            if [ -n "${VNET_NAME:-}" ]; then
                pvesh delete "/cluster/sdn/vnets/${VNET_NAME}" 2>/dev/null && echo "  ✓ Deleted VNet ${VNET_NAME}" || echo "  ✗ VNet deletion failed or already removed"
            fi

            pvesh delete "/pools/${POOL_ID}" 2>/dev/null && echo "  ✓ Deleted pool ${POOL_ID}" || echo "  ✗ Pool deletion failed"

            if [ -n "${USERNAME:-}" ]; then
                pvesh delete "/access/users/${USERNAME}@pve" 2>/dev/null && echo "  ✓ Deleted user ${USERNAME}@pve" || echo "  ✗ User deletion failed"
            fi

            if [ -n "${GROUP_NAME:-}" ]; then
                pvesh delete "/access/groups/${GROUP_NAME}" 2>/dev/null && echo "  ✓ Deleted group ${GROUP_NAME}" || echo "  ✗ Group deletion failed"
            fi

        else
            echo -e "${YELLOW}  pvesh not found, skipping Proxmox resource deletion${NC}"
        fi
    done

    if command -v pvesh &> /dev/null; then
        echo ""
        echo "Applying SDN configuration changes..."
        pvesh set /cluster/sdn 2>/dev/null && echo -e "${GREEN}✓ SDN configuration applied${NC}" || echo -e "${YELLOW}Warning: SDN apply failed${NC}"
    fi
fi

echo ""
echo -e "${BLUE}Removing filesystem resources...${NC}"

if [ -f "$BIN_FILE" ]; then
    rm -f "$BIN_FILE"
    echo -e "${GREEN}✓ Removed CLI tool${NC}"
fi

if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    echo -e "${GREEN}✓ Removed installation directory${NC}"
fi

if [ -f "$COMPLETION_FILE" ]; then
    rm -f "$COMPLETION_FILE"
    echo -e "${GREEN}✓ Removed bash completion${NC}"
fi

LOGROTATE_FILE="/etc/logrotate.d/tenctl"
if [ -f "$LOGROTATE_FILE" ]; then
    rm -f "$LOGROTATE_FILE"
    echo -e "${GREEN}✓ Removed logrotate configuration${NC}"
fi

if [ "$FULL_CLEANUP" = true ]; then
    if [ -d "$TENANT_CONFIG_DIR" ]; then
        rm -rf "$TENANT_CONFIG_DIR"
        echo -e "${GREEN}✓ Removed tenant configs${NC}"
    fi

    if [ -d "$CREDENTIALS_DIR" ]; then
        rm -rf "$CREDENTIALS_DIR"
        echo -e "${GREEN}✓ Removed credentials${NC}"
    fi

    if [ -d "$LOG_DIR" ]; then
        rm -rf "$LOG_DIR"
        echo -e "${GREEN}✓ Removed logs${NC}"
    fi

    if [ -d "$LOCK_DIR" ]; then
        rm -rf "$LOCK_DIR"
        echo -e "${GREEN}✓ Removed lock files${NC}"
    fi
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Uninstallation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

if [ "$FULL_CLEANUP" = false ]; then
    echo -e "${BLUE}Preserved data:${NC}"
    if [ -d "$TENANT_CONFIG_DIR" ]; then
        tenant_count=$(find "$TENANT_CONFIG_DIR" -name "*.conf" 2>/dev/null | wc -l || echo 0)
        echo "  - Tenant configs: ${tenant_count} tenant(s) in ${TENANT_CONFIG_DIR}"
    fi
    if [ -d "$CREDENTIALS_DIR" ]; then
        cred_count=$(find "$CREDENTIALS_DIR" -name "*.json" 2>/dev/null | wc -l || echo 0)
        echo "  - Credentials: ${cred_count} file(s) in ${CREDENTIALS_DIR}"
    fi
    echo "  - Proxmox resources (use Proxmox UI or CLI to manage)"
    echo ""
    echo "To completely remove all data, run:"
    echo "  ./uninstall.sh --full --purge-tenants"
elif [ "$PURGE_TENANTS" = true ]; then
    echo "Complete system purge finished."
    echo "All CLI tools, configs, credentials, and Proxmox resources have been removed."
else
    echo "Full cleanup finished."
    echo "CLI and configs removed. Proxmox resources preserved."
    echo ""
    echo "To also remove Proxmox resources, run:"
    echo "  ./uninstall.sh --full --purge-tenants"
fi

echo ""
