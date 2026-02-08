#!/bin/bash

# Parse disk parameters from arguments and return total storage in GB
# Args: command_type ("qm" or "pct"), argument_array
# Returns: Total storage in GB (printed to stdout)
ptm_parse_disk_parameters() {
    local cmd_type=$1
    shift
    local args=("$@")
    local total_storage=0

    local i=0
    while [ $i -lt ${#args[@]} ]; do
        local arg="${args[$i]}"

        if [ "$cmd_type" = "qm" ]; then
            # VM disk parameters: --scsi0-30, --virtio0-15, --ide0-3, --sata0-5
            if [[ "$arg" =~ ^--(scsi|virtio|ide|sata)[0-9]+$ ]]; then
                i=$((i + 1))
                local disk_spec="${args[$i]}"

                if [[ "$disk_spec" =~ :([0-9]+) ]]; then
                    local size="${BASH_REMATCH[1]}"
                    total_storage=$((total_storage + size))
                    ptm_log DEBUG "Parsed disk parameter: $arg $disk_spec → ${size}GB"
                fi
            fi
        elif [ "$cmd_type" = "pct" ]; then
            # Container disk parameters: --rootfs, --mp0-255
            if [[ "$arg" =~ ^--(rootfs|mp[0-9]+)$ ]]; then
                i=$((i + 1))
                local disk_spec="${args[$i]}"

                if [[ "$disk_spec" =~ :([0-9]+) ]]; then
                    local size="${BASH_REMATCH[1]}"
                    total_storage=$((total_storage + size))
                    ptm_log DEBUG "Parsed disk parameter: $arg $disk_spec → ${size}GB"
                elif [[ "$disk_spec" =~ size=([0-9]+)G ]]; then
                    local size="${BASH_REMATCH[1]}"
                    total_storage=$((total_storage + size))
                    ptm_log DEBUG "Parsed disk parameter: $arg $disk_spec → ${size}GB"
                fi
            fi
        fi

        i=$((i + 1))
    done

    echo "$total_storage"
}

# Args: argument_array
# Sets global variables: PARSED_CPU, PARSED_RAM
ptm_parse_cpu_ram_from_args() {
    local args=("$@")
    PARSED_CPU=0
    PARSED_RAM=0

    local i=0
    while [ $i -lt ${#args[@]} ]; do
        local arg="${args[$i]}"

        case "$arg" in
            --cores)
                i=$((i + 1))
                PARSED_CPU="${args[$i]}"
                ptm_log DEBUG "Parsed CPU: ${PARSED_CPU} cores"
                ;;
            --memory)
                i=$((i + 1))
                PARSED_RAM="${args[$i]}"
                ptm_log DEBUG "Parsed RAM: ${PARSED_RAM} MB"
                ;;
            --sockets)
                i=$((i + 1))
                local sockets="${args[$i]}"
                if [ "$PARSED_CPU" -gt 0 ]; then
                    PARSED_CPU=$((PARSED_CPU * sockets))
                    ptm_log DEBUG "Adjusted CPU for sockets: ${PARSED_CPU} cores (${sockets} sockets)"
                fi
                ;;
        esac

        i=$((i + 1))
    done
}

# Args: vmid
# Returns: JSON string with cpu, ram_mb, storage_gb
ptm_get_current_vm_resources() {
    local vmid=$1

    if [ -z "$vmid" ]; then
        echo "{\"cpu\":0,\"ram_mb\":0,\"storage_gb\":0}"
        return 1
    fi

    local vm_data
    vm_data=$(ptm_get_vm_metadata "$vmid")

    if [ "$vm_data" = "{}" ]; then
        echo "{\"cpu\":0,\"ram_mb\":0,\"storage_gb\":0}"
        return 1
    fi

    local cpu ram_bytes storage_bytes
    cpu=$(echo "$vm_data" | jq -r '.maxcpu // 0')
    ram_bytes=$(echo "$vm_data" | jq -r '.maxmem // 0')
    storage_bytes=$(echo "$vm_data" | jq -r '.maxdisk // 0')

    local ram_mb=$((ram_bytes / 1024 / 1024))
    local storage_gb=$((storage_bytes / 1024 / 1024 / 1024))

    echo "{\"cpu\":${cpu},\"ram_mb\":${ram_mb},\"storage_gb\":${storage_gb}}"
}

# Args: pool_id
# Returns: JSON string with total_cpu, total_ram_mb, total_storage_gb
ptm_calculate_pool_resources() {
    local pool_id=$1

    if [ -z "$pool_id" ]; then
        echo "{\"total_cpu\":0,\"total_ram_mb\":0,\"total_storage_gb\":0}"
        return 1
    fi

    local total_cpu=0
    local total_ram=0
    local total_storage=0

    # all VMs in pool 
    local vm_list
    vm_list=$(ptm_get_pool_vm_list "$pool_id")

    if [ -n "$vm_list" ]; then
        for vmid in $vm_list; do
            local vm_resources
            vm_resources=$(ptm_get_current_vm_resources "$vmid")

            local vm_cpu vm_ram vm_storage
            vm_cpu=$(echo "$vm_resources" | jq -r '.cpu // 0')
            vm_ram=$(echo "$vm_resources" | jq -r '.ram_mb // 0')
            vm_storage=$(echo "$vm_resources" | jq -r '.storage_gb // 0')

            total_cpu=$((total_cpu + vm_cpu))
            total_ram=$((total_ram + vm_ram))
            total_storage=$((total_storage + vm_storage))
        done
    fi

    ptm_log DEBUG "Pool $pool_id resources: CPU=${total_cpu}, RAM=${total_ram}MB, Storage=${total_storage}GB"

    echo "{\"total_cpu\":${total_cpu},\"total_ram_mb\":${total_ram},\"total_storage_gb\":${total_storage}}"
}

# Validate resources against tenant limits
# Args: pool_id, new_total_cpu, new_total_ram, new_total_storage, operation_description
# Returns: 0 if within limits, 1 if exceeded (exits with error message)
ptm_validate_resource_limits() {
    local pool_id=$1
    local new_cpu=$2
    local new_ram=$3
    local new_storage=$4
    local operation_desc="${5:-operation}"

    if [[ ! "$pool_id" =~ ^tenant_(.+)$ ]]; then
        ptm_log ERROR "Invalid pool ID format: $pool_id"
        return 1
    fi

    local tenant_name="${BASH_REMATCH[1]}"

    if ! ptm_load_tenant_config "$tenant_name" 2>/dev/null; then
        ptm_log ERROR "Failed to load tenant configuration: $tenant_name"
        return 1
    fi

    local exceeded=""
    local exceeded_type=""

    if [ "$new_cpu" -gt "$CPU_LIMIT" ]; then
        exceeded="CPU"
        exceeded_type="CPU"
    elif [ "$new_ram" -gt "$RAM_LIMIT" ]; then
        exceeded="RAM"
        exceeded_type="RAM"
    elif [ "$new_storage" -gt "$STORAGE_LIMIT" ]; then
        exceeded="Storage"
        exceeded_type="Storage"
    fi

    if [ -n "$exceeded" ]; then
        local pool_resources
        pool_resources=$(ptm_calculate_pool_resources "$pool_id")
        local current_cpu current_ram current_storage
        current_cpu=$(echo "$pool_resources" | jq -r '.total_cpu')
        current_ram=$(echo "$pool_resources" | jq -r '.total_ram_mb')
        current_storage=$(echo "$pool_resources" | jq -r '.total_storage_gb')

        cat >&2 <<EOF
ERROR: Operation blocked - would exceed tenant resource limits

Tenant: $tenant_name
Pool: $pool_id
Operation: $operation_desc
Resource Exceeded: $exceeded_type

Current Pool Allocation:
  CPU:     ${current_cpu} / ${CPU_LIMIT} cores
  RAM:     ${current_ram} / ${RAM_LIMIT} MB
  Storage: ${current_storage} / ${STORAGE_LIMIT} GB

New Total Would Be:
  CPU:     ${new_cpu} cores (limit: ${CPU_LIMIT})
  RAM:     ${new_ram} MB (limit: ${RAM_LIMIT})
  Storage: ${new_storage} GB (limit: ${STORAGE_LIMIT})

Contact your administrator to increase resource limits.
EOF
        return 1
    fi

    ptm_log DEBUG "Resource validation passed: CPU=${new_cpu}/${CPU_LIMIT}, RAM=${new_ram}/${RAM_LIMIT}, Storage=${new_storage}/${STORAGE_LIMIT}"
    return 0
}

# Args: vmid, disk_id (e.g., "scsi0")
# Returns: Disk size in GB
ptm_get_vm_disk_size() {
    local vmid=$1
    local disk_id=$2

    if [ -z "$vmid" ] || [ -z "$disk_id" ]; then
        echo "0"
        return 1
    fi

    local vm_config
    vm_config=$(pvesh get "/nodes/$(hostname)/qemu/${vmid}/config" --output-format json 2>/dev/null || echo "{}")

    if [ "$vm_config" = "{}" ]; then
        vm_config=$(pvesh get "/nodes/$(hostname)/lxc/${vmid}/config" --output-format json 2>/dev/null || echo "{}")
    fi

    local disk_config
    disk_config=$(echo "$vm_config" | jq -r ".${disk_id} // \"\"")

    if [[ "$disk_config" =~ size=([0-9]+)G ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$disk_config" =~ :([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "0"
    fi
}

# Args: backup_file
# Returns: JSON string with cpu, ram_mb, storage_gb
ptm_extract_backup_metadata() {
    local backup_file=$1

    if [ ! -f "$backup_file" ]; then
        ptm_log WARN "Backup file not found: $backup_file"
        echo "{}"
        return 1
    fi

    if [[ "$backup_file" =~ \.vma(\.zst)?$ ]]; then
        ptm_log WARN "VMA backup format - metadata extraction not implemented"
        echo "{}"
        return 1
    fi

    # For .tar.zst or .tar.gz files
    if [[ "$backup_file" =~ \.tar\.(zst|gz|bz2)$ ]]; then
        local config_file
        if tar -tzf "$backup_file" 2>/dev/null | grep -q "qemu-server\.conf"; then
            config_file=$(tar -xzf "$backup_file" --to-stdout "*/qemu-server.conf" 2>/dev/null)
        elif tar -tzf "$backup_file" 2>/dev/null | grep -q "pct\.conf"; then
            config_file=$(tar -xzf "$backup_file" --to-stdout "*/pct.conf" 2>/dev/null)
        fi

        if [ -n "$config_file" ]; then
            local cpu ram storage
            cpu=$(echo "$config_file" | grep "^cores:" | cut -d: -f2 | tr -d ' ')
            ram=$(echo "$config_file" | grep "^memory:" | cut -d: -f2 | tr -d ' ')

            storage=0

            : ${cpu:=0}
            : ${ram:=0}

            echo "{\"cpu\":${cpu},\"ram_mb\":${ram},\"storage_gb\":${storage}}"
            return 0
        fi
    fi

    ptm_log WARN "Could not extract backup metadata from: $backup_file"
    echo "{}"
    return 1
}

# Args: argument_array
# Returns: Pool name (or empty)
ptm_extract_pool_from_args() {
    local args=("$@")
    local pool=""

    local i=0
    while [ $i -lt ${#args[@]} ]; do
        if [ "${args[$i]}" = "--pool" ]; then
            i=$((i + 1))
            pool="${args[$i]}"
            break
        fi
        i=$((i + 1))
    done

    echo "$pool"
}

# Args: argument_array
# Returns: VMID (or empty)
ptm_extract_vmid_from_args() {
    local args=("$@")

    for arg in "${args[@]}"; do
        if [[ "$arg" =~ ^[0-9]+$ ]]; then
            echo "$arg"
            return 0
        fi
    done

    echo ""
}

# Check if operation is resource reduction
# Args: current_cpu, new_cpu, current_ram, new_ram, current_storage, new_storage
# Returns: 0 if reduction, 1 if increase
ptm_is_resource_reduction() {
    local curr_cpu=$1
    local new_cpu=$2
    local curr_ram=$3
    local new_ram=$4
    local curr_storage=$5
    local new_storage=$6

    if [ "$new_cpu" -gt "$curr_cpu" ] || [ "$new_ram" -gt "$curr_ram" ] || [ "$new_storage" -gt "$curr_storage" ]; then
        return 1
    fi

    return 0
}

# Args: command_type ("qm" or "pct"), remaining_arguments
# Returns: 0 if valid, exits with error if invalid
ptm_validate_create_operation() {
    local cmd_type=$1
    shift
    local args=("$@")

    ptm_log DEBUG "Validating $cmd_type create operation"

    local pool
    pool=$(ptm_extract_pool_from_args "${args[@]}")

    if [ -z "$pool" ] || [[ ! "$pool" =~ ^tenant_ ]]; then
        ptm_log DEBUG "Non-tenant pool or no pool specified, allowing operation"
        return 0
    fi

    ptm_parse_cpu_ram_from_args "${args[@]}"
    local requested_cpu=$PARSED_CPU
    local requested_ram=$PARSED_RAM
    local requested_storage
    requested_storage=$(ptm_parse_disk_parameters "$cmd_type" "${args[@]}")

    ptm_log DEBUG "Create operation requests: CPU=${requested_cpu}, RAM=${requested_ram}MB, Storage=${requested_storage}GB"

    if [ "$requested_cpu" -eq 0 ] && [ "$requested_ram" -eq 0 ] && [ "$requested_storage" -eq 0 ]; then
        ptm_log DEBUG "No resources specified in create, allowing"
        return 0
    fi

    local pool_resources
    pool_resources=$(ptm_calculate_pool_resources "$pool")
    local current_cpu current_ram current_storage
    current_cpu=$(echo "$pool_resources" | jq -r '.total_cpu')
    current_ram=$(echo "$pool_resources" | jq -r '.total_ram_mb')
    current_storage=$(echo "$pool_resources" | jq -r '.total_storage_gb')

    local new_cpu=$((current_cpu + requested_cpu))
    local new_ram=$((current_ram + requested_ram))
    local new_storage=$((current_storage + requested_storage))

    ptm_validate_resource_limits "$pool" "$new_cpu" "$new_ram" "$new_storage" "$cmd_type create"
}

# Args: command_type ("qm" or "pct"), remaining_arguments
# Returns: 0 if valid, exits with error if invalid
ptm_validate_set_operation() {
    local cmd_type=$1
    shift
    local args=("$@")

    ptm_log DEBUG "Validating $cmd_type set operation"

    local vmid
    vmid=$(ptm_extract_vmid_from_args "${args[@]}")

    if [ -z "$vmid" ]; then
        ptm_log WARN "Could not extract VMID from set operation, allowing"
        return 0
    fi

    local vm_pool
    vm_pool=$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null | \
        jq -r --argjson id "$vmid" '.[] | select(.vmid == $id) | .pool // ""')

    if [ -z "$vm_pool" ] || [[ ! "$vm_pool" =~ ^tenant_ ]]; then
        ptm_log DEBUG "VM not in tenant pool, allowing operation"
        return 0
    fi

    local current_vm_resources
    current_vm_resources=$(ptm_get_current_vm_resources "$vmid")
    local curr_cpu curr_ram curr_storage
    curr_cpu=$(echo "$current_vm_resources" | jq -r '.cpu')
    curr_ram=$(echo "$current_vm_resources" | jq -r '.ram_mb')
    curr_storage=$(echo "$current_vm_resources" | jq -r '.storage_gb')

    ptm_log DEBUG "Current VM resources: CPU=${curr_cpu}, RAM=${curr_ram}MB, Storage=${curr_storage}GB"

    ptm_parse_cpu_ram_from_args "${args[@]}"
    local new_cpu_raw=$PARSED_CPU
    local new_ram_raw=$PARSED_RAM
    local new_storage_raw
    new_storage_raw=$(ptm_parse_disk_parameters "$cmd_type" "${args[@]}")

    local new_cpu=${new_cpu_raw:-$curr_cpu}
    local new_ram=${new_ram_raw:-$curr_ram}
    local new_storage=$((curr_storage + new_storage_raw))  # Add new disks to current

    if [ "$new_cpu_raw" -eq 0 ]; then
        new_cpu=$curr_cpu
    fi
    if [ "$new_ram_raw" -eq 0 ]; then
        new_ram=$curr_ram
    fi

    ptm_log DEBUG "New VM resources: CPU=${new_cpu}, RAM=${new_ram}MB, Storage=${new_storage}GB"

    if ptm_is_resource_reduction "$curr_cpu" "$new_cpu" "$curr_ram" "$new_ram" "$curr_storage" "$new_storage"; then
        ptm_log DEBUG "Resource reduction detected, allowing"
        return 0
    fi

    local pool_resources
    pool_resources=$(ptm_calculate_pool_resources "$vm_pool")
    local pool_cpu pool_ram pool_storage
    pool_cpu=$(echo "$pool_resources" | jq -r '.total_cpu')
    pool_ram=$(echo "$pool_resources" | jq -r '.total_ram_mb')
    pool_storage=$(echo "$pool_resources" | jq -r '.total_storage_gb')

    local new_pool_cpu=$((pool_cpu - curr_cpu + new_cpu))
    local new_pool_ram=$((pool_ram - curr_ram + new_ram))
    local new_pool_storage=$((pool_storage - curr_storage + new_storage))

    ptm_log DEBUG "New pool totals: CPU=${new_pool_cpu}, RAM=${new_pool_ram}MB, Storage=${new_pool_storage}GB"

    ptm_validate_resource_limits "$vm_pool" "$new_pool_cpu" "$new_pool_ram" "$new_pool_storage" "$cmd_type set VMID=$vmid"
}

# Args: command_type ("qm" or "pct"), remaining_arguments
# Returns: 0 if valid, exits with error if invalid
ptm_validate_resize_operation() {
    local cmd_type=$1
    shift
    local args=("$@")

    ptm_log DEBUG "Validating $cmd_type resize operation"

    local vmid="${args[0]}"
    local disk="${args[1]}"
    local size="${args[2]}"

    if [ -z "$vmid" ] || [ -z "$disk" ] || [ -z "$size" ]; then
        ptm_log WARN "Could not parse resize parameters, allowing"
        return 0
    fi

    local vm_pool
    vm_pool=$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null | \
        jq -r --argjson id "$vmid" '.[] | select(.vmid == $id) | .pool // ""')

    if [ -z "$vm_pool" ] || [[ ! "$vm_pool" =~ ^tenant_ ]]; then
        ptm_log DEBUG "VM not in tenant pool, allowing resize"
        return 0
    fi

    local current_disk_size
    current_disk_size=$(ptm_get_vm_disk_size "$vmid" "$disk")

    ptm_log DEBUG "Current disk $disk size: ${current_disk_size}GB"

    local size_increase=0

    if [[ "$size" =~ ^\+([0-9]+)G?$ ]]; then
        size_increase="${BASH_REMATCH[1]}"
        ptm_log DEBUG "Relative resize: +${size_increase}GB"
    elif [[ "$size" =~ ^([0-9]+)G?$ ]]; then
        local new_size="${BASH_REMATCH[1]}"
        size_increase=$((new_size - current_disk_size))
        ptm_log DEBUG "Absolute resize: ${new_size}GB (increase: ${size_increase}GB)"
    else
        ptm_log WARN "Could not parse resize size: $size, allowing"
        return 0
    fi

    if [ "$size_increase" -le 0 ]; then
        ptm_log DEBUG "Disk shrinking or no change, allowing"
        return 0
    fi

    local pool_resources
    pool_resources=$(ptm_calculate_pool_resources "$vm_pool")
    local pool_storage
    pool_storage=$(echo "$pool_resources" | jq -r '.total_storage_gb')

    local new_pool_storage=$((pool_storage + size_increase))

    ptm_log DEBUG "Pool storage after resize: ${new_pool_storage}GB"

    local pool_cpu pool_ram
    pool_cpu=$(echo "$pool_resources" | jq -r '.total_cpu')
    pool_ram=$(echo "$pool_resources" | jq -r '.total_ram_mb')

    # Validate against limits
    ptm_validate_resource_limits "$vm_pool" "$pool_cpu" "$pool_ram" "$new_pool_storage" "$cmd_type resize VMID=$vmid disk=$disk +${size_increase}GB"
}

# Args: command_type ("qm" or "pct"), remaining_arguments
# Returns: 0 if valid, exits with error if invalid
ptm_validate_clone_operation() {
    local cmd_type=$1
    shift
    local args=("$@")

    ptm_log DEBUG "Validating $cmd_type clone operation"

    local source_vmid="${args[0]}"
    local target_vmid="${args[1]}"

    if [ -z "$source_vmid" ] || [ -z "$target_vmid" ]; then
        ptm_log WARN "Could not parse clone parameters, allowing"
        return 0
    fi

    local target_pool
    target_pool=$(ptm_extract_pool_from_args "${args[@]}")

    if [ -z "$target_pool" ]; then
        target_pool=$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null | \
            jq -r --argjson id "$source_vmid" '.[] | select(.vmid == $id) | .pool // ""')
    fi

    if [ -z "$target_pool" ] || [[ ! "$target_pool" =~ ^tenant_ ]]; then
        ptm_log DEBUG "Target pool is not tenant pool, allowing clone"
        return 0
    fi

    local source_resources
    source_resources=$(ptm_get_current_vm_resources "$source_vmid")
    local clone_cpu clone_ram clone_storage
    clone_cpu=$(echo "$source_resources" | jq -r '.cpu')
    clone_ram=$(echo "$source_resources" | jq -r '.ram_mb')
    clone_storage=$(echo "$source_resources" | jq -r '.storage_gb')

    ptm_log DEBUG "Source VM resources: CPU=${clone_cpu}, RAM=${clone_ram}MB, Storage=${clone_storage}GB"

    local full_clone=false
    for arg in "${args[@]}"; do
        if [ "$arg" = "--full" ]; then
            full_clone=true
            break
        fi
    done

    if [ "$full_clone" = true ]; then
        ptm_log DEBUG "Full clone detected - validating full storage"
    else
        clone_storage=1
        ptm_log DEBUG "Linked clone detected - validating minimal storage: ${clone_storage}GB"
    fi

    ptm_parse_cpu_ram_from_args "${args[@]}"
    if [ "$PARSED_CPU" -gt 0 ]; then
        clone_cpu=$PARSED_CPU
        ptm_log DEBUG "Clone CPU overridden: ${clone_cpu}"
    fi
    if [ "$PARSED_RAM" -gt 0 ]; then
        clone_ram=$PARSED_RAM
        ptm_log DEBUG "Clone RAM overridden: ${clone_ram}"
    fi

    local pool_resources
    pool_resources=$(ptm_calculate_pool_resources "$target_pool")
    local pool_cpu pool_ram pool_storage
    pool_cpu=$(echo "$pool_resources" | jq -r '.total_cpu')
    pool_ram=$(echo "$pool_resources" | jq -r '.total_ram_mb')
    pool_storage=$(echo "$pool_resources" | jq -r '.total_storage_gb')

    local new_pool_cpu=$((pool_cpu + clone_cpu))
    local new_pool_ram=$((pool_ram + clone_ram))
    local new_pool_storage=$((pool_storage + clone_storage))

    ptm_log DEBUG "New pool totals after clone: CPU=${new_pool_cpu}, RAM=${new_pool_ram}MB, Storage=${new_pool_storage}GB"

    ptm_validate_resource_limits "$target_pool" "$new_pool_cpu" "$new_pool_ram" "$new_pool_storage" "$cmd_type clone $source_vmid -> $target_vmid"
}

# Args: command_type ("qm" or "pct"), remaining_arguments
# Returns: 0 if valid, exits with error if invalid
ptm_validate_restore_operation() {
    local cmd_type=$1
    shift
    local args=("$@")

    ptm_log DEBUG "Validating $cmd_type restore operation"

    local backup_file="${args[0]}"
    local target_vmid="${args[1]}"

    if [ -z "$backup_file" ] || [ -z "$target_vmid" ]; then
        ptm_log WARN "Could not parse restore parameters, allowing"
        return 0
    fi

    local pool
    pool=$(ptm_extract_pool_from_args "${args[@]}")

    if [ -z "$pool" ] || [[ ! "$pool" =~ ^tenant_ ]]; then
        ptm_log DEBUG "Non-tenant pool, allowing restore"
        return 0
    fi

    local backup_metadata
    backup_metadata=$(ptm_extract_backup_metadata "$backup_file")

    local restore_cpu restore_ram restore_storage

    if [ "$backup_metadata" = "{}" ] || [ -z "$backup_metadata" ]; then
        cat >&2 <<EOF
ERROR: Cannot restore - backup metadata unavailable

Backup file: $backup_file
Reason: Unable to read resource specifications from backup archive

To restore this VM, please:
1. Verify backup file integrity
2. Extract metadata manually and specify resources explicitly:
   qmrestore $backup_file $target_vmid --pool $pool --cores N --memory M

This check prevents accidental resource limit violations.
EOF
        exit 1
    fi

    restore_cpu=$(echo "$backup_metadata" | jq -r '.cpu // 0')
    restore_ram=$(echo "$backup_metadata" | jq -r '.ram_mb // 0')
    restore_storage=$(echo "$backup_metadata" | jq -r '.storage_gb // 0')

    ptm_log DEBUG "Backup resources: CPU=${restore_cpu}, RAM=${restore_ram}MB, Storage=${restore_storage}GB"

    ptm_parse_cpu_ram_from_args "${args[@]}"
    if [ "$PARSED_CPU" -gt 0 ]; then
        restore_cpu=$PARSED_CPU
        ptm_log DEBUG "Restore CPU overridden: ${restore_cpu}"
    fi
    if [ "$PARSED_RAM" -gt 0 ]; then
        restore_ram=$PARSED_RAM
        ptm_log DEBUG "Restore RAM overridden: ${restore_ram}"
    fi

    local pool_resources
    pool_resources=$(ptm_calculate_pool_resources "$pool")
    local pool_cpu pool_ram pool_storage
    pool_cpu=$(echo "$pool_resources" | jq -r '.total_cpu')
    pool_ram=$(echo "$pool_resources" | jq -r '.total_ram_mb')
    pool_storage=$(echo "$pool_resources" | jq -r '.total_storage_gb')

    local new_pool_cpu=$((pool_cpu + restore_cpu))
    local new_pool_ram=$((pool_ram + restore_ram))
    local new_pool_storage=$((pool_storage + restore_storage))

    ptm_log DEBUG "New pool totals after restore: CPU=${new_pool_cpu}, RAM=${new_pool_ram}MB, Storage=${new_pool_storage}GB"

    ptm_validate_resource_limits "$pool" "$new_pool_cpu" "$new_pool_ram" "$new_pool_storage" "$cmd_type restore from $backup_file"
}
