#!/bin/bash

# Wrapper for pvesh
ptm_run_pvesh() {
    local output
    local exit_code

    ptm_log DEBUG "Executing API call: pvesh $*"

    output=$(pvesh "$@" 2>&1)
    exit_code=$?

    if [ $exit_code -ne 0 ]; then
        ptm_log ERROR "pvesh command failed: pvesh $*"
        ptm_log ERROR "Error output: $output"
        return $exit_code
    fi

    ptm_log DEBUG "API call succeeded"
    echo "$output"
    return 0
}

# Check if a Proxmox resource exists
ptm_resource_exists() {
    local resource_type=$1
    local resource_id=$2

    ptm_log DEBUG "Checking if $resource_type exists: $resource_id"

    case "$resource_type" in
        pool)
            pvesh get "/pools/${resource_id}" --output-format json &>/dev/null
            ;;
        user)
            pvesh get "/access/users/${resource_id}" --output-format json &>/dev/null
            ;;
        vnet)
            pvesh get "/cluster/sdn/vnets/${resource_id}" --output-format json &>/dev/null
            ;;
        group)
            pvesh get "/access/groups/${resource_id}" --output-format json &>/dev/null
            ;;
        *)
            ptm_log ERROR "Unknown resource type: $resource_type"
            return 2
            ;;
    esac

    return $?
}

ptm_safe_api_get() {
    local endpoint=$1
    local context="${2:-resource}"

    ptm_log DEBUG "Fetching $context from API endpoint: $endpoint"

    local output
    output=$(pvesh get "$endpoint" --output-format json 2>&1)

    if [ $? -ne 0 ]; then
        ptm_log ERROR "Failed to retrieve $context from $endpoint"
        ptm_log ERROR "API error: $output"
        return 1
    fi

    ptm_log DEBUG "Successfully retrieved $context from $endpoint"
    echo "$output"
    return 0
}

ptm_check_proxmox_version() {
    local version
    version=$(pveversion | grep -oP 'pve-manager/\K[0-9]+' | head -1)
    echo "$version"
}
