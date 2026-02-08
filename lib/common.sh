#!/bin/bash
# Tenctl Management - Common Library Entry Point

set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${LIB_DIR}/../config/tenant.conf"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE" || {
        echo "ERROR: Failed to source configuration file"
        exit 1
    }

    required_vars=(
        VLAN_START VLAN_END BASE_SUBNET
        DEFAULT_CPU_LIMIT DEFAULT_RAM_LIMIT DEFAULT_STORAGE_LIMIT
        NETWORK_BRIDGE SDN_ZONE_TYPE LOG_DIR TENANT_CONFIG_DIR
    )

    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            echo "ERROR: Required config variable '$var' not set in $CONFIG_FILE"
            exit 1
        fi
    done

    if ! [[ "$VLAN_START" =~ ^[0-9]+$ ]] || ! [[ "$VLAN_END" =~ ^[0-9]+$ ]]; then
        echo "ERROR: VLAN_START and VLAN_END must be numeric"
        exit 1
    fi

    if [ "$VLAN_START" -lt 1 ] || [ "$VLAN_START" -gt 4094 ]; then
        echo "ERROR: VLAN_START must be 1-4094"
        exit 1
    fi

    if [ "$VLAN_END" -lt "$VLAN_START" ] || [ "$VLAN_END" -gt 4094 ]; then
        echo "ERROR: VLAN_END must be >= VLAN_START and <= 4094"
        exit 1
    fi

    if ! [[ "$BASE_SUBNET" =~ ^[0-9]+\.[0-9]+$ ]]; then
        echo "ERROR: BASE_SUBNET must be in format 'X.Y' (e.g., '10.100')"
        exit 1
    fi
else
    echo "ERROR: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Core modules
source "${LIB_DIR}/core/constants.sh"
source "${LIB_DIR}/core/logging.sh"
source "${LIB_DIR}/core/verbosity.sh"
source "${LIB_DIR}/core/validation.sh"
source "${LIB_DIR}/core/requirements.sh"
source "${LIB_DIR}/core/notifications.sh"

init_directories

# Proxmox modules
source "${LIB_DIR}/proxmox/api.sh"
source "${LIB_DIR}/proxmox/users.sh"
source "${LIB_DIR}/proxmox/network.sh"
source "${LIB_DIR}/proxmox/vms.sh"
source "${LIB_DIR}/proxmox/resources.sh"
source "${LIB_DIR}/proxmox/storage.sh"

# Tenant modules
source "${LIB_DIR}/tenant/config.sh"
source "${LIB_DIR}/tenant/credentials.sh"
source "${LIB_DIR}/tenant/helpers.sh"
source "${LIB_DIR}/tenant/resource_validation.sh"

# Utility
source "${LIB_DIR}/utils/password.sh"

# Cluster modules
if [ -f "${LIB_DIR}/cluster/state.sh" ]; then
    source "${LIB_DIR}/cluster/state.sh"
fi

if [ -f "${LIB_DIR}/common_functions.sh" ]; then
    source "${LIB_DIR}/common_functions.sh"
fi

# Load VyOS management
if [ -f "${LIB_DIR}/vyos.sh" ]; then
    source "${LIB_DIR}/vyos.sh"
fi