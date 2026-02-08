#!/bin/bash

# Tracking dictionary for loaded modules
declare -A PTM_LOADED_MODULES

# Load a single module (idempotent)
# Usage: ptm_load_module "core/logging"
ptm_load_module() {
    local module_name=$1

    # Skip if already loaded
    if [ -n "${PTM_LOADED_MODULES[$module_name]:-}" ]; then
        return 0
    fi

    local module_path="${LIB_DIR}/${module_name}.sh"
    if [ ! -f "$module_path" ]; then
        echo "ERROR: Module not found: $module_name at $module_path" >&2
        return 1
    fi

    source "$module_path"
    PTM_LOADED_MODULES[$module_name]=1
}

# Load core modules
ptm_load_core() {
    ptm_load_module "core/constants"
    ptm_load_module "core/logging"
    ptm_load_module "core/validation"
    ptm_load_module "core/requirements"
    ptm_load_module "core/verbosity"
}

# Load API modules
ptm_load_api() {
    ptm_load_core
    ptm_load_module "proxmox/api"
}

# Load tenant management modules
ptm_load_tenant_management() {
    ptm_load_core
    ptm_load_api
    ptm_load_module "proxmox/users"
    ptm_load_module "proxmox/resources"
    ptm_load_module "proxmox/network"
    ptm_load_module "tenant/config"
    ptm_load_module "tenant/helpers"
    ptm_load_module "utils/password"
    ptm_load_module "core/notifications"
    ptm_load_module "vyos"
}

# Load VyOS modules
ptm_load_vyos() {
    ptm_load_core
    ptm_load_api
    ptm_load_module "vyos"
}

# Load cluster management modules
ptm_load_cluster() {
    ptm_load_core
    ptm_load_api
    ptm_load_module "cluster/state"
}

# Load notification modules
ptm_load_notifications() {
    ptm_load_core
    ptm_load_module "core/notifications"
}

# Load VM/CT management modules
ptm_load_vm_management() {
    ptm_load_core
    ptm_load_api
    ptm_load_module "proxmox/vm"
}

ptm_public_api() {
    cat <<'EOF'
Tenctl CLI - Public API (v2.0)
=============================================

All functions use the 'ptm_' prefix to avoid namespace conflicts.
Internal helper functions use '__ptm_' prefix (double underscore).

CORE FUNCTIONS (load with: ptm_load_core)
------------------------------------------
ptm_log LEVEL MESSAGE          - Log with levels: ERROR, WARN, INFO, DEBUG, SUCCESS
ptm_validate_tenant_name NAME  - Validate tenant name (alphanumeric + underscore)
ptm_validate_email EMAIL       - Validate email address format
ptm_validate_ip IP             - Validate IP address format
ptm_validate_cidr CIDR         - Validate CIDR notation
ptm_check_requirements         - Check for required dependencies (pvesh, jq, flock)
ptm_check_root                 - Verify script is running as root
ptm_check_proxmox_version      - Detect Proxmox VE version

API FUNCTIONS (load with: ptm_load_api)
----------------------------------------
ptm_run_pvesh ARGS...          - Execute Proxmox API call with error handling
ptm_safe_api_get PATH          - Safe GET request with error handling
ptm_safe_api_create PATH ARGS  - Safe CREATE request with error handling
ptm_safe_api_set PATH ARGS     - Safe SET request with error handling
ptm_safe_api_delete PATH       - Safe DELETE request with error handling
ptm_resource_exists TYPE NAME  - Check if resource exists (pool, user, vnet, etc.)

TENANT FUNCTIONS (load with: ptm_load_tenant_management)
---------------------------------------------------------
ptm_tenant_exists NAME         - Check if tenant exists
ptm_get_next_vlan              - Allocate next available VLAN ID (atomic with flock)
ptm_get_next_subnet            - Allocate next available subnet (atomic with flock)
ptm_create_resource_pool NAME  - Create Proxmox resource pool
ptm_set_pool_limits POOL CPU RAM - Set resource limits on pool (PVE 9.0+)
ptm_create_user NAME PASS      - Create Proxmox user with password
ptm_create_group NAME          - Create Proxmox group
ptm_set_acl_permission PATH ROLE USER/GROUP - Set ACL permission
ptm_allocate_vnet NAME VLAN    - Create SDN VNet for tenant
ptm_save_tenant_config NAME DATA - Save tenant configuration to /etc/pve/tenants/
ptm_load_tenant_config NAME    - Load tenant configuration
ptm_delete_tenant_config NAME  - Delete tenant configuration
ptm_list_tenants [--detailed]  - List all tenants

VM/CT FUNCTIONS (load with: ptm_load_vm_management)
----------------------------------------------------
ptm_get_pool_vms POOL          - Get all VMs in a resource pool
ptm_stop_vm VMID [TIMEOUT]     - Stop VM gracefully with timeout
ptm_wait_for_vm_stop VMID [TIMEOUT] - Wait for VM to stop
ptm_delete_vm VMID             - Delete VM
ptm_assign_vm_to_pool VMID POOL - Assign VM to resource pool

VYOS FUNCTIONS (load with: ptm_load_vyos)
------------------------------------------
ptm_vyos_check_requirements    - Check VyOS prerequisites
ptm_vyos_generate_config NAME VLAN SUBNET - Generate VyOS config for tenant
ptm_vyos_apply_config COMMANDS - Apply configuration to VyOS router
ptm_vyos_test_connectivity NAME - Test tenant network connectivity

CLUSTER FUNCTIONS (load with: ptm_load_cluster)
------------------------------------------------
ptm_cluster_get_nodes          - Get list of cluster nodes
ptm_cluster_get_version NODE   - Get CLI version on specific node
ptm_cluster_update_state VERSION - Update cluster state file
ptm_cluster_check_consistency  - Check if all nodes have same version
ptm_cluster_install_all        - Install CLI on all cluster nodes
ptm_cluster_update_all         - Update CLI on all cluster nodes

NOTIFICATION FUNCTIONS (load with: ptm_load_notifications)
-----------------------------------------------------------
ptm_send_email SUBJECT MESSAGE - Send email notification
ptm_send_webhook URL PAYLOAD   - Send webhook notification
ptm_notify_tenant_created NAME - Send tenant creation notification
ptm_notify_tenant_deleted NAME - Send tenant deletion notification

USAGE EXAMPLES
--------------

Example 1: Simple command (list tenants)
    ptm_load_core
    ptm_log INFO "Listing tenants"
    # ... list logic

Example 2: Complex command (add tenant)
    ptm_load_tenant_management
    ptm_check_requirements || exit 1
    ptm_check_root

    if ptm_tenant_exists "$TENANT_NAME"; then
        ptm_log ERROR "Tenant already exists"
        exit 1
    fi

    VLAN=$(ptm_get_next_vlan)
    SUBNET=$(ptm_get_next_subnet)
    ptm_create_resource_pool "tenant_${TENANT_NAME}"
    # ... rest of creation logic

Example 3: VyOS integration
    ptm_load_vyos
    ptm_vyos_check_requirements || exit 1
    CONFIG=$(ptm_vyos_generate_config "$NAME" "$VLAN" "$SUBNET")
    ptm_vyos_apply_config "$CONFIG"

For module loading strategies, see module group functions above.
EOF
}

ptm_list_loaded_modules() {
    echo "Loaded Modules:"
    for module in "${!PTM_LOADED_MODULES[@]}"; do
        echo "  - $module"
    done
}
