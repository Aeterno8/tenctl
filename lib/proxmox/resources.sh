#!/bin/bash

# Args: path, role, user
# Returns: 0 on success, 1 on failure
ptm_set_acl_permission() {
    local path=$1
    local role=$2
    local user=$3

    ptm_log INFO "Setting ACL: $role on $path for $user"

    if pvesh set /access/acl --path "${path}" --roles "${role}" --users "${user}" 2>/dev/null; then
        ptm_log INFO "ACL permissions set successfully"
        return 0
    else
        ptm_log ERROR "Failed to set ACL permissions"
        return 1
    fi
}

# Args: pool_id, cpu_limit, ram_limit, storage_limit
# Returns: 0 (always success - limits are tracked in config only)
ptm_set_pool_limits() {
    local pool_id=$1
    local cpu_limit=$2
    local ram_limit=$3
    local storage_limit=$4

    ptm_log DEBUG "Resource limits will be tracked in tenant configuration"
    ptm_log DEBUG "  CPU: $cpu_limit cores, RAM: $ram_limit MB, Storage: $storage_limit GB"
    ptm_log DEBUG "Note: Limits are enforced at VM/LXC creation time, not at pool level"

    return 0
}

# Args: requested_cpu, requested_ram, requested_storage, [exclude_tenant]
# Returns: 0 if resources available, 1 if insufficient
ptm_validate_cluster_resources() {
    local requested_cpu=$1
    local requested_ram=$2
    local requested_storage=$3
    local exclude_tenant="${4:-}"

    ptm_log INFO "Validating cluster resource availability..."

    local cluster_info
    cluster_info=$(pvesh get /cluster/resources --type node --output-format json 2>/dev/null)

    local total_cpu
    local total_mem

    total_cpu=$(echo "$cluster_info" | jq -r '[.[].maxcpu] | add')
    total_mem=$(echo "$cluster_info" | jq -r '[.[].maxmem] | add')

    local allocated_cpu=0
    local allocated_ram=0

    if [ -d "$TENANT_CONFIG_DIR" ]; then
        shopt -s nullglob
        for config in "$TENANT_CONFIG_DIR"/*.conf; do
            local config_tenant_name
            config_tenant_name=$(basename "$config" .conf)

            if [ -n "$exclude_tenant" ] && [ "$config_tenant_name" = "$exclude_tenant" ]; then
                continue
            fi

            local tenant_cpu
            local tenant_ram
            tenant_cpu=$(source "$config" 2>/dev/null && echo "${CPU_LIMIT:-0}")
            tenant_ram=$(source "$config" 2>/dev/null && echo "${RAM_LIMIT:-0}")

            allocated_cpu=$((allocated_cpu + tenant_cpu))
            allocated_ram=$((allocated_ram + tenant_ram))
        done
        shopt -u nullglob
    fi

    local available_cpu=$((total_cpu * CLUSTER_MAX_UTILIZATION_PERCENT / 100 - allocated_cpu))

    local total_mem_mb=$((total_mem / 1024 / 1024))
    local available_ram=$(( (total_mem_mb * CLUSTER_MAX_UTILIZATION_PERCENT / 100) - allocated_ram ))

    ptm_log INFO "Cluster capacity: ${total_cpu} CPU cores, $((total_mem / 1024 / 1024)) MB RAM"
    ptm_log INFO "Currently allocated: ${allocated_cpu} CPU cores, ${allocated_ram} MB RAM"
    ptm_log INFO "Available for allocation: ${available_cpu} CPU cores, ${available_ram} MB RAM"

    if [ "$requested_cpu" -gt "$available_cpu" ]; then
        ptm_log ERROR "Insufficient CPU: requested $requested_cpu cores, available $available_cpu cores"
        return 1
    fi

    if [ "$requested_ram" -gt "$available_ram" ]; then
        ptm_log ERROR "Insufficient RAM: requested $requested_ram MB, available $available_ram MB"
        return 1
    fi

    ptm_log INFO "Resource validation passed"
    return 0
}
