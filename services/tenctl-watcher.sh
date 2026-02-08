#!/bin/bash
# Tenctl Resource Watcher

set -euo pipefail

export LOG_LEVEL="${LOG_LEVEL:-INFO}"

if [ -f "/usr/local/share/tenctl/lib/ptm-loader.sh" ]; then
    CONFIG_FILE="/usr/local/share/tenctl/config/tenant.conf"
    LIB_DIR="/usr/local/share/tenctl/lib"
elif [ -f "/opt/tenctl/lib/ptm-loader.sh" ]; then
    CONFIG_FILE="/opt/tenctl/config/tenant.conf"
    LIB_DIR="/opt/tenctl/lib"
else
    echo "ERROR: Tenant management library not found" >&2
    exit 1
fi

source "$CONFIG_FILE"
source "${LIB_DIR}/ptm-loader.sh"

ptm_load_tenant_management           # Loads core, API, proxmox, tenant modules
ptm_load_module "core/notifications"  # For email alerts on violations

QEMU_DIR="/etc/pve/qemu-server"
LXC_DIR="/etc/pve/lxc"
POLL_INTERVAL=2  # seconds

declare -A SEEN_QEMU
declare -A SEEN_LXC

ptm_log INFO "Proxmox Tenant Watcher starting (polling mode, cluster API detection)..."
ptm_log INFO "Monitoring: $QEMU_DIR, $LXC_DIR (interval: ${POLL_INTERVAL}s)"

# Calculate pool resources using Cluster API
# Args: vm_bridge (vnet name), exclude_vmid (optional, skip this VM)
# Output: "cpu ram storage" (space-separated)
calculate_pool_resources_api() {
    local vm_bridge=$1
    local exclude_vmid=${2:-}

    local total_cpu=0 total_ram=0 total_storage=0

    local all_vms
    all_vms=$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null) || {
        ptm_log WARN "Failed to get cluster resources via API"
        return 1
    }

    while IFS= read -r vm_json; do
        [ -z "$vm_json" ] && continue

        local vmid node vmtype maxcpu maxmem maxdisk
        vmid=$(echo "$vm_json" | jq -r '.vmid')
        node=$(echo "$vm_json" | jq -r '.node')
        vmtype=$(echo "$vm_json" | jq -r '.type')
        maxcpu=$(echo "$vm_json" | jq -r '.maxcpu // 0')
        maxmem=$(echo "$vm_json" | jq -r '.maxmem // 0')
        maxdisk=$(echo "$vm_json" | jq -r '.maxdisk // 0')

        [ "$vmid" = "$exclude_vmid" ] && continue

        local conf_path
        if [ "$vmtype" = "qemu" ]; then
            conf_path="/etc/pve/qemu-server/${vmid}.conf"
        else
            conf_path="/etc/pve/lxc/${vmid}.conf"
        fi

        [ ! -f "$conf_path" ] && continue

        local member_bridge
        member_bridge=$(grep -E '^net[0-9]+:' "$conf_path" 2>/dev/null | grep -oP 'bridge=\K[^,]+' | head -1 || echo "")
        [ "$member_bridge" != "$vm_bridge" ] && continue

        total_cpu=$((total_cpu + maxcpu))
        total_ram=$((total_ram + maxmem / 1024 / 1024))  # bytes -> MB
        total_storage=$((total_storage + maxdisk / 1024 / 1024 / 1024))  # bytes -> GB
    done < <(echo "$all_vms" | jq -c '.[]' 2>/dev/null)

    echo "$total_cpu $total_ram $total_storage"
    return 0
}

# Calculate pool resources by scanning local config files (fallback)
# Used when cluster API is unavailable
# Args: vm_bridge (vnet name), exclude_vmid (optional, skip this VM)
# Output: "cpu ram storage" (space-separated)
calculate_pool_resources_local() {
    local vm_bridge=$1
    local exclude_vmid=${2:-}

    local pool_cpu=0 pool_ram=0 pool_storage=0

    for conf_path in /etc/pve/qemu-server/*.conf; do
        [ -f "$conf_path" ] || continue
        local member_vmid=$(basename "$conf_path" .conf)
        [ "$member_vmid" = "$exclude_vmid" ] && continue

        local member_bridge
        member_bridge=$(grep -E '^net[0-9]+:' "$conf_path" 2>/dev/null | grep -oP 'bridge=\K[^,]+' | head -1 || echo "")
        [ "$member_bridge" != "$vm_bridge" ] && continue

        local m_cpu=$(grep -E '^cores:' "$conf_path" 2>/dev/null | awk '{print $2}' || echo "0")
        local m_ram=$(grep -E '^memory:' "$conf_path" 2>/dev/null | awk '{print $2}' || echo "0")
        local m_storage=0
        while IFS= read -r disk_line; do
            local sz=$(echo "$disk_line" | grep -oP 'size=\K[0-9]+(?=G)' || echo "0")
            m_storage=$((m_storage + sz))
        done < <(grep -E '^(scsi|virtio|sata|ide)[0-9]+:' "$conf_path" 2>/dev/null || true)

        pool_cpu=$((pool_cpu + m_cpu))
        pool_ram=$((pool_ram + m_ram))
        pool_storage=$((pool_storage + m_storage))
    done

    for conf_path in /etc/pve/lxc/*.conf; do
        [ -f "$conf_path" ] || continue
        local member_vmid=$(basename "$conf_path" .conf)
        [ "$member_vmid" = "$exclude_vmid" ] && continue

        local member_bridge
        member_bridge=$(grep -E '^net[0-9]+:' "$conf_path" 2>/dev/null | grep -oP 'bridge=\K[^,]+' | head -1 || echo "")
        [ "$member_bridge" != "$vm_bridge" ] && continue

        local m_cpu=$(grep -E '^cores:' "$conf_path" 2>/dev/null | awk '{print $2}' || echo "0")
        local m_ram=$(grep -E '^memory:' "$conf_path" 2>/dev/null | awk '{print $2}' || echo "0")
        local m_storage=$(grep -E '^rootfs:' "$conf_path" 2>/dev/null | grep -oP 'size=\K[0-9]+(?=G)' || echo "0")

        pool_cpu=$((pool_cpu + m_cpu))
        pool_ram=$((pool_ram + m_ram))
        pool_storage=$((pool_storage + m_storage))
    done

    echo "$pool_cpu $pool_ram $pool_storage"
}

# Validate a newly created VM/CT config
# Args: config_file_path, vmtype
# Returns: 0 if valid, 1 if should be deleted
validate_new_vm_config() {
    local config_path=$1
    local vmtype=$2  # "qemu" or "lxc"

    local vmid
    vmid=$(basename "$config_path" .conf)

    if ! [[ "$vmid" =~ ^[0-9]+$ ]]; then
        ptm_log WARN "Invalid VMID extracted from $config_path: $vmid"
        return 0
    fi

    ptm_log DEBUG "New VM/CT detected: VMID=$vmid, Type=$vmtype"

    sleep 0.2

    if [ ! -f "$config_path" ]; then
        ptm_log DEBUG "Config file $config_path no longer exists, skipping"
        return 0
    fi

    local vm_cpu vm_ram vm_storage

    if [ "$vmtype" = "qemu" ]; then
        vm_cpu=$(grep -E '^cores:' "$config_path" 2>/dev/null | awk '{print $2}' || echo "1")
        vm_ram=$(grep -E '^memory:' "$config_path" 2>/dev/null | awk '{print $2}' || echo "512")
        vm_storage=0
        while IFS= read -r disk_line; do
            local size=$(echo "$disk_line" | grep -oP 'size=\K[0-9]+(?=G)' || echo "0")
            vm_storage=$((vm_storage + size))
        done < <(grep -E '^(scsi|virtio|sata|ide)[0-9]+:' "$config_path" 2>/dev/null || true)
    else
        vm_cpu=$(grep -E '^cores:' "$config_path" 2>/dev/null | awk '{print $2}' || echo "1")
        vm_ram=$(grep -E '^memory:' "$config_path" 2>/dev/null | awk '{print $2}' || echo "512")
        vm_storage=$(grep -E '^rootfs:' "$config_path" 2>/dev/null | grep -oP 'size=\K[0-9]+(?=G)' || echo "0")
    fi

    local vm_bridge
    vm_bridge=$(grep -E '^net[0-9]+:' "$config_path" 2>/dev/null | grep -oP 'bridge=\K[^,]+' | head -1 || echo "")

    if [[ ! "$vm_bridge" =~ ^vn[0-9]+$ ]]; then
        ptm_log DEBUG "VM $vmid not on tenant vnet (bridge=$vm_bridge), skipping"
        return 0
    fi

    local vlan_id="${vm_bridge#vn}"

    local tenant_name=""
    for conf in /etc/pve/tenants/*.conf; do
        [ -f "$conf" ] || continue
        if grep -q "^VLAN_ID=${vlan_id}$" "$conf" 2>/dev/null; then
            tenant_name=$(grep "^TENANT_NAME=" "$conf" | cut -d'"' -f2)
            break
        fi
    done

    if [ -z "$tenant_name" ]; then
        ptm_log DEBUG "No tenant found for VLAN $vlan_id, skipping"
        return 0
    fi

    local vm_pool="tenant_${tenant_name}"
    ptm_log INFO "VM $vmid on vnet $vm_bridge (tenant: $tenant_name)"

    if ! ptm_load_tenant_config "$tenant_name" 2>/dev/null; then
        ptm_log WARN "No tenant config for $tenant_name, allowing"
        return 0
    fi

    local pool_resources pool_cpu pool_ram pool_storage

    if pool_resources=$(calculate_pool_resources_api "$vm_bridge" "$vmid"); then
        read -r pool_cpu pool_ram pool_storage <<< "$pool_resources"
        ptm_log DEBUG "Pool resources from cluster API: CPU=$pool_cpu, RAM=$pool_ram MB, Storage=$pool_storage GB"
    else
        ptm_log WARN "Cluster API unavailable, falling back to local file scanning"
        pool_resources=$(calculate_pool_resources_local "$vm_bridge" "$vmid")
        read -r pool_cpu pool_ram pool_storage <<< "$pool_resources"
        ptm_log DEBUG "Pool resources from local scan: CPU=$pool_cpu, RAM=$pool_ram MB, Storage=$pool_storage GB"
    fi

    local new_cpu=$((pool_cpu + vm_cpu))
    local new_ram=$((pool_ram + vm_ram))
    local new_storage=$((pool_storage + vm_storage))

    ptm_log DEBUG "Pool $vm_pool current: CPU=$pool_cpu, RAM=$pool_ram MB, Storage=$pool_storage GB"
    ptm_log DEBUG "Pool $vm_pool new totals: CPU=$new_cpu, RAM=$new_ram MB, Storage=$new_storage GB"
    ptm_log DEBUG "Tenant $tenant_name limits: CPU=$CPU_LIMIT, RAM=$RAM_LIMIT MB, Storage=$STORAGE_LIMIT GB"

    local violations=()
    local should_delete=false

    if [ "$new_cpu" -gt "$CPU_LIMIT" ]; then
        violations+=("CPU: $new_cpu > $CPU_LIMIT cores")
        should_delete=true
    fi

    if [ "$new_ram" -gt "$RAM_LIMIT" ]; then
        violations+=("RAM: $new_ram > $RAM_LIMIT MB")
        should_delete=true
    fi

    if [ "$new_storage" -gt "$STORAGE_LIMIT" ]; then
        violations+=("Storage: $new_storage > $STORAGE_LIMIT GB")
        should_delete=true
    fi

    if [ "$should_delete" = true ]; then
        local violations_str=$(IFS=", "; echo "${violations[*]}")
        ptm_log ERROR "BLOCKED VM CREATION: $vmtype $vmid in tenant $tenant_name would exceed limits: $violations_str"

        local violation_details="Tenant: $tenant_name
Pool: $vm_pool

Violations Detected:
$(for v in "${violations[@]}"; do echo "  - $v"; done)

Current Pool Total (including this VM):
  CPU:     $new_cpu / $CPU_LIMIT cores
  RAM:     $new_ram / $RAM_LIMIT MB
  Storage: $new_storage / $STORAGE_LIMIT GB

This VM's Allocated Resources:
  CPU:     $vm_cpu cores
  RAM:     $vm_ram MB
  Storage: $vm_storage GB"

        local tenant_email=""
        local cred_dir="/root/tenctl-credentials"
        if [ -d "$cred_dir" ]; then
            local cred_file
            cred_file=$(ls -t "$cred_dir"/tenant_"${tenant_name}"_*.json 2>/dev/null | head -1)
            if [ -n "$cred_file" ] && [ -f "$cred_file" ]; then
                tenant_email=$(jq -r '.email // ""' "$cred_file" 2>/dev/null)
            fi
        fi

        if [ -n "$tenant_email" ]; then
            (ptm_send_vm_blocked_email "$tenant_name" "$tenant_email" "$vmid" "$vmtype" "$violation_details" &) 2>/dev/null
        fi

        delete_vm_config "$config_path" "$vmid" "$vmtype" "Resource limits exceeded" "$violation_details"

        return 1
    else
        ptm_log INFO "VM creation allowed: $vmtype $vmid in tenant $tenant_name (within limits)"
        return 0
    fi
}

# Create a Proxmox task log entry (visible in GUI Task History)
# Args: vmid, vmtype, error_message, [optional_user]
create_task_error() {
    local vmid=$1
    local vmtype=$2
    local error_msg=$3
    local user="${4:-root@pam}"

    local node=$(hostname)
    local pid=$$
    local pstart=$(printf '%08X' $pid)
    local starttime=$(date +%s)
    local starttime_hex=$(printf '%08X' $starttime)

    local tasktype
    if [ "$vmtype" = "qemu" ]; then
        tasktype="qmcreate"
    else
        tasktype="vzcreate"
    fi

    local upid="UPID:${node}:${pstart}:${pstart}:${starttime_hex}:${tasktype}:${vmid}:${user}:"

    local dir_index=$(printf '%X' $((starttime % 16)))
    local task_dir="/var/log/pve/tasks/${dir_index}"
    mkdir -p "$task_dir" 2>/dev/null || true

    local task_file="${task_dir}/${upid}"
    local active_file="/var/log/pve/tasks/active"
    local index_file="/var/log/pve/tasks/index"

    flock /var/lock/pve-tasks.lck bash -c "
        echo 'TASK RUNNING' > '${task_file}'
        echo '${upid} 1 ${starttime_hex} running' >> '${active_file}'
    " 2>/dev/null || true

    sleep 0.1

    cat > "$task_file" <<EOF
TASK ERROR: ${error_msg}
EOF

    flock /var/lock/pve-tasks.lck bash -c "
        sed -i 's#${upid} 1 ${starttime_hex} running#${upid} 1 ${starttime_hex} ERROR#' '${active_file}'
    " 2>/dev/null || true

    echo "${upid} ${starttime_hex} ERROR" >> "$index_file" 2>/dev/null || true

    ptm_log INFO "Created task error entry: $upid"
}

# Get the user who created a VM by checking recent task history
# Args: vmid, vmtype
# Output: username (e.g., admin_tenant@pve) or "root@pam" as fallback
get_vm_creator() {
    local vmid=$1
    local vmtype=$2

    local tasktype
    if [ "$vmtype" = "qemu" ]; then
        tasktype="qmcreate"
    else
        tasktype="vzcreate"
    fi

    local creator
    creator=$(grep ":${tasktype}:${vmid}:" /var/log/pve/tasks/index 2>/dev/null | tail -1 | grep -oP ":${vmid}:\K[^:]+(?=:)" || echo "root@pam")

    echo "$creator"
}

# Delete a VM/CT config file with detailed logging
# Args: config_file_path, vmid, vmtype, reason, violation_details
delete_vm_config() {
    local config_path=$1
    local vmid=$2
    local vmtype=$3
    local reason=$4
    local violation_details=$5
    local start_time=$(date +%s.%N)

    ptm_log ERROR "Deleting $vmtype config: $config_path (VMID=$vmid)"
    ptm_log ERROR "Reason: $reason"
    local t1=$(date +%s.%N)
    local creator
    creator=$(get_vm_creator "$vmid" "$vmtype")
    local t2=$(date +%s.%N)
    ptm_log INFO "VM creator: $creator (lookup: $(echo "$t2 - $t1" | bc -l | cut -c1-5)s)"

    local user_message="VM/Container ${vmid} creation BLOCKED - exceeds tenant resource limits

${violation_details}

Action: The VM/CT configuration was automatically deleted because it would exceed your tenant's allocated resources. Please reduce the resource allocation or contact your administrator to increase your limits."

    local t3=$(date +%s.%N)
    create_task_error "$vmid" "$vmtype" "$user_message" "$creator"
    local t4=$(date +%s.%N)
    ptm_log INFO "Task error created (took $(echo "$t4 - $t3" | bc -l | cut -c1-5)s)"

    local t5=$(date +%s.%N)
    if rm -f "$config_path" 2>/dev/null; then
        local t6=$(date +%s.%N)
        ptm_log INFO "Config deleted (took $(echo "$t6 - $t5" | bc -l | cut -c1-5)s)"

        if [ "$vmtype" = "qemu" ]; then
            (
                sleep 1
                local disk_pattern="vm-${vmid}-disk-*"

                lvs --noheadings -o lv_name 2>/dev/null | grep -E "vm-${vmid}-disk-" | while read -r lv_name; do
                    lvremove -f "/dev/pve/${lv_name}" 2>&1 >/dev/null || true
                done
            ) &
        fi
    else
        ptm_log ERROR "Failed to delete $vmtype $vmid config file: $config_path"
    fi

    local end_time=$(date +%s.%N)
    ptm_log INFO "Total deletion time: $(echo "$end_time - $start_time" | bc -l | cut -c1-5)s"
}

# Get file signature (mtime:size) for change detection
# Args: filepath
# Output: "mtime:size" string
get_file_signature() {
    local filepath=$1
    stat -c "%Y:%s" "$filepath" 2>/dev/null || echo ""
}

# Poll directory for new/changed .conf files
# Args: directory, vmtype, seen_array_name
poll_directory() {
    local dir=$1
    local vmtype=$2
    local -n seen=$3

    shopt -s nullglob
    for conf_file in "$dir"/*.conf; do
        [ -f "$conf_file" ] || continue

        local vmid=$(basename "$conf_file" .conf)

        local sig=$(get_file_signature "$conf_file")
        [ -z "$sig" ] && continue

        if [ -z "${seen[$vmid]:-}" ] || [ "${seen[$vmid]}" != "$sig" ]; then
            ptm_log DEBUG "Detected new/modified config: $conf_file"

            seen[$vmid]="$sig"

            if ! validate_new_vm_config "$conf_file" "$vmtype"; then
                unset seen[$vmid]
            fi
        fi
    done
    shopt -u nullglob 
}

bootstrap_seen_files() {
    local dir=$1
    local -n seen_arr=$2

    shopt -s nullglob
    local count=0
    for conf_file in "$dir"/*.conf; do
        [ -f "$conf_file" ] || continue
        local vmid=$(basename "$conf_file" .conf)
        local sig=$(get_file_signature "$conf_file")
        if [ -n "$sig" ]; then
            seen_arr[$vmid]="$sig"
            count=$((count + 1))
        fi
    done
    shopt -u nullglob

    ptm_log INFO "Bootstrap: marked $count existing configs in $dir as seen"
}

poll_loop() {
    ptm_log INFO "Bootstrapping - marking existing VM/CT configs..."
    bootstrap_seen_files "$QEMU_DIR" SEEN_QEMU
    bootstrap_seen_files "$LXC_DIR" SEEN_LXC

    ptm_log INFO "Starting polling loop (interval: ${POLL_INTERVAL}s)"

    while true; do
        poll_directory "$QEMU_DIR" "qemu" SEEN_QEMU

        poll_directory "$LXC_DIR" "lxc" SEEN_LXC

        sleep "$POLL_INTERVAL"
    done
}

cleanup() {
    ptm_log INFO "Proxmox Tenant Watcher shutting down..."
    exit 0
}

trap cleanup SIGTERM SIGINT

poll_loop
