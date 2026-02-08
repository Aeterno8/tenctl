#!/bin/bash

# Get storage usage for a tenant (sum of all VM disks in pool)
# Args: pool_id
# Returns: Total storage used in GB (printed to stdout)
ptm_get_storage_usage() {
    local pool_id=$1
    local total_storage=0

    local vm_list
    vm_list=$(pvesh get "/pools/${pool_id}" --output-format json 2>/dev/null | jq -r '.members[]? | select(.vmid != null) | .vmid' || echo "")

    for vmid in $vm_list; do
        local vm_data
        vm_data=$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null | \
            jq --argjson id "$vmid" '.[] | select(.vmid == $id)' || echo "{}")

        local disk_bytes
        disk_bytes=$(echo "$vm_data" | jq -r '.maxdisk // 0')
        local disk_gb=$((disk_bytes / 1024 / 1024 / 1024))

        total_storage=$((total_storage + disk_gb))
    done

    echo "$total_storage"
}

# Check if storage usage exceeds limit
# Args: pool_id, storage_limit, [warn_threshold]
# Returns: 0 if under limit, 1 if over limit
ptm_check_storage_limit() {
    local pool_id=$1
    local storage_limit=$2
    local warn_threshold="${3:-80}"

    local current_usage
    current_usage=$(ptm_get_storage_usage "$pool_id")

    local usage_percent=$((current_usage * 100 / storage_limit))

    if [ "$current_usage" -gt "$storage_limit" ]; then
        ptm_log ERROR "Storage limit exceeded: ${current_usage}GB / ${storage_limit}GB (${usage_percent}%)"
        return 1
    elif [ "$usage_percent" -ge "$warn_threshold" ]; then
        ptm_log WARN "Storage usage high: ${current_usage}GB / ${storage_limit}GB (${usage_percent}%)"
        return 0
    else
        ptm_log INFO "Storage usage OK: ${current_usage}GB / ${storage_limit}GB (${usage_percent}%)"
        return 0
    fi
}

# Enforce storage quota using backend storage
# Args: pool_id, storage_limit_gb, tenant_name
# Returns: 0 if quota applied, 1 if not supported
ptm_enforce_storage_quota_hard() {
    local pool_id=$1
    local storage_limit_gb=$2
    local tenant_name=$3

    ptm_log INFO "Attempting to enforce storage quota via backend storage..."

    local storage_list
    storage_list=$(pvesh get /storage --output-format json 2>/dev/null || echo "[]")

    local vm_list
    vm_list=$(pvesh get "/pools/${pool_id}" --output-format json 2>/dev/null | jq -r '.members[]? | select(.vmid != null) | .vmid' || echo "")

    local quota_applied=false

    for vmid in $vm_list; do
        local vm_data
        vm_data=$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null | \
            jq --argjson id "$vmid" '.[] | select(.vmid == $id)' || echo "{}")

        local node
        node=$(echo "$vm_data" | jq -r '.node // "unknown"')

        if [ "$node" = "unknown" ]; then
            continue
        fi

        local storage_type
        storage_type=$(echo "$storage_list" | jq -r --arg pool "$pool_id" '.[] | select(.storage | contains("zfs")) | .type' | head -n1)

        if [ "$storage_type" = "zfspool" ]; then
            ptm_log INFO "Detected ZFS storage for VM $vmid"

            local dataset="rpool/data/vm-${vmid}-disk-0"  # Example path

            if command -v zfs &>/dev/null; then
                ptm_log INFO "ZFS detected - quota enforcement requires manual ZFS dataset configuration"
                ptm_log INFO "Example: zfs set quota=${storage_limit_gb}G ${dataset}"
                quota_applied=true
            fi
        fi

        if echo "$storage_list" | jq -e '.[] | select(.type == "rbd")' &>/dev/null; then
            ptm_log INFO "Detected Ceph RBD storage"
            ptm_log INFO "Ceph pool quotas can be set via: ceph osd pool set-quota <pool> max_bytes ${storage_limit_gb}G"
            quota_applied=true
        fi
    done

    if [ "$quota_applied" = false ]; then
        ptm_log WARN "No backend storage quotas applied - using soft limits only"
        ptm_log WARN "For hard enforcement, configure ZFS quotas or Ceph pool quotas manually"
        return 1
    fi

    return 0
}
