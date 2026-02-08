#!/bin/bash

# Get list of VM IDs in a resource pool
# Args: pool_id
# Returns: Space-separated list of VMIDs (or empty string)
ptm_get_pool_vm_list() {
    local pool_id=$1

    if [ -z "$pool_id" ]; then
        ptm_log ERROR "ptm_get_pool_vm_list: pool_id required"
        return 1
    fi

    pvesh get "/pools/${pool_id}" --output-format json 2>/dev/null | \
        jq -r '.members[]? | select(.vmid != null) | .vmid' || echo ""
}

# Get VM metadata from Proxmox cluster
# Args: vmid
# Output: JSON object with VM details (or {})
ptm_get_vm_metadata() {
    local vmid=$1

    if [ -z "$vmid" ]; then
        echo "{}"
        return 1
    fi

    pvesh get /cluster/resources --type vm --output-format json 2>/dev/null | \
        jq --argjson id "$vmid" '.[] | select(.vmid == $id)' || echo "{}"
}

# Get VM's pool assignment
# Args: vmid, [vmtype]
# Output: Pool ID (or empty string if not in a pool)
# vmtype: optional, can be "qemu" or "lxc"
ptm_get_vm_pool() {
    local vmid=$1
    local vmtype=${2:-}

    if [ -z "$vmid" ]; then
        echo ""
        return 1
    fi

    local vm_data
    vm_data=$(ptm_get_vm_metadata "$vmid")

    if [ "$vm_data" = "{}" ]; then
        echo ""
        return 1
    fi

    local pool
    pool=$(echo "$vm_data" | jq -r '.pool // ""')

    echo "$pool"
}

# Extract common VM fields from metadata JSON
# Args: vm_json
# Sets global variables: VM_TYPE, VM_STATUS, VM_NODE, VM_NAME, VM_CORES, VM_MEM_MB, VM_DISK_GB
ptm_parse_vm_metadata() {
    local vm_json="$1"

    local parsed
    parsed=$(echo "$vm_json" | jq -r '
        [
            .type // "unknown",
            .status // "unknown",
            .node // "unknown",
            .name // "unknown",
            .maxcpu // 0,
            (.maxmem // 0 | . / 1024 / 1024 | floor),
            (.maxdisk // 0 | . / 1024 / 1024 / 1024 | floor)
        ] | @tsv
    ')

    IFS=$'\t' read -r VM_TYPE VM_STATUS VM_NODE VM_NAME VM_CORES VM_MEM_MB VM_DISK_GB <<< "$parsed"
}

# Stop a VM or container
# Args: vmid, vm_type, node
# Returns: 0 on success, 1 on failure
ptm_stop_vm() {
    local vmid=$1
    local vm_type=$2
    local node=$3

    if [ -z "$vmid" ] || [ -z "$vm_type" ] || [ -z "$node" ]; then
        ptm_log ERROR "ptm_stop_vm: vmid, vm_type, and node required"
        return 1
    fi

    case "$vm_type" in
        qemu)
            if pvesh create "/nodes/${node}/qemu/${vmid}/status/stop" 2>/dev/null; then
                ptm_log INFO "VM $vmid stopped successfully"
                return 0
            fi
            ;;
        lxc)
            if pvesh create "/nodes/${node}/lxc/${vmid}/status/stop" 2>/dev/null; then
                ptm_log INFO "Container $vmid stopped successfully"
                return 0
            fi
            ;;
        *)
            ptm_log ERROR "Unknown VM type: $vm_type"
            return 1
            ;;
    esac

    ptm_log ERROR "Failed to stop $vm_type $vmid"
    return 1
}

# Start a VM or container
# Args: vmid, vm_type, node
# Returns: 0 on success, 1 on failure
ptm_start_vm() {
    local vmid=$1
    local vm_type=$2
    local node=$3

    if [ -z "$vmid" ] || [ -z "$vm_type" ] || [ -z "$node" ]; then
        ptm_log ERROR "ptm_start_vm: vmid, vm_type, and node required"
        return 1
    fi

    case "$vm_type" in
        qemu)
            if pvesh create "/nodes/${node}/qemu/${vmid}/status/start" 2>/dev/null; then
                ptm_log INFO "VM $vmid started successfully"
                return 0
            fi
            ;;
        lxc)
            if pvesh create "/nodes/${node}/lxc/${vmid}/status/start" 2>/dev/null; then
                ptm_log INFO "Container $vmid started successfully"
                return 0
            fi
            ;;
        *)
            ptm_log ERROR "Unknown VM type: $vm_type"
            return 1
            ;;
    esac

    ptm_log ERROR "Failed to start $vm_type $vmid"
    return 1
}

# Disable CPU and RAM hotplug for a VM/container
# Args: vmid, node
# Returns: 0 on success, 1 on failure
ptm_disable_vm_hotplug() {
    local vmid=$1
    local node=$2

    if [ -z "$vmid" ] || [ -z "$node" ]; then
        ptm_log ERROR "ptm_disable_vm_hotplug: vmid and node required"
        return 1
    fi

    local vm_type
    if pvesh get "/nodes/${node}/qemu/${vmid}/status/current" --output-format json &>/dev/null; then
        vm_type="qemu"
    elif pvesh get "/nodes/${node}/lxc/${vmid}/status/current" --output-format json &>/dev/null; then
        vm_type="lxc"
        ptm_log DEBUG "Container $vmid: hotplug not applicable for LXC"
        return 0
    else
        ptm_log ERROR "Cannot determine type for VM/CT $vmid"
        return 1
    fi

    local current_config
    current_config=$(pvesh get "/nodes/${node}/qemu/${vmid}/config" --output-format json 2>/dev/null)

    if [ -z "$current_config" ]; then
        ptm_log ERROR "Failed to get config for VM $vmid"
        return 1
    fi

    local cores=$(echo "$current_config" | jq -r '.cores // 1')
    local memory=$(echo "$current_config" | jq -r '.memory // 512')
    local cpu_type=$(echo "$current_config" | jq -r '.cpu // "host"')

    local cpu_setting="${cpu_type}"
    if [[ ! "$cpu_setting" =~ hotplug ]]; then
        cpu_setting="${cpu_setting},hotplug=0"
    else
        cpu_setting=$(echo "$cpu_setting" | sed 's/hotplug=[0-9]/hotplug=0/')
    fi

    ptm_log INFO "Disabling hotplug for VM $vmid (cores=$cores, memory=$memory MB)"

    if pvesh set "/nodes/${node}/qemu/${vmid}/config" \
        --cpu "$cpu_setting" \
        --cores "$cores" \
        --memory "$memory" 2>&1 | ptm_log DEBUG; then
        ptm_log INFO "Hotplug disabled for VM $vmid"
        return 0
    else
        ptm_log WARN "Failed to disable hotplug for VM $vmid (may not be supported on this Proxmox version)"
        return 1
    fi
}

# Disable hotplug for all VMs in a pool
# Args: pool_id
# Returns: Number of VMs processed
ptm_disable_pool_hotplug() {
    local pool_id=$1

    if [ -z "$pool_id" ]; then
        ptm_log ERROR "ptm_disable_pool_hotplug: pool_id required"
        return 1
    fi

    ptm_log INFO "Disabling hotplug for all VMs in pool: $pool_id"

    local vm_list
    vm_list=$(ptm_get_pool_vm_list "$pool_id")

    if [ -z "$vm_list" ]; then
        ptm_log DEBUG "No VMs found in pool $pool_id"
        return 0
    fi

    local count=0
    local failed=0

    for vmid in $vm_list; do
        local vm_data
        vm_data=$(ptm_get_vm_metadata "$vmid")

        if [ "$vm_data" = "{}" ]; then
            ptm_log WARN "Could not get metadata for VM $vmid"
            ((failed++))
            continue
        fi

        local node
        node=$(echo "$vm_data" | jq -r '.node // ""')

        if [ -z "$node" ]; then
            ptm_log WARN "Could not determine node for VM $vmid"
            ((failed++))
            continue
        fi

        if ptm_disable_vm_hotplug "$vmid" "$node"; then
            ((count++))
        else
            ((failed++))
        fi
    done

    ptm_log INFO "Hotplug disabled for $count VMs in pool $pool_id ($failed failed)"
    return $count
}
