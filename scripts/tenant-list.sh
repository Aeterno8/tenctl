#!/bin/bash

set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
source "${SCRIPT_DIR}/../lib/common.sh"

ptm_parse_verbosity_flags "$@"

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Lists all tenants and their resources.

Optional:
  -j, --json               Output u JSON formatu
  -d, --detailed           Detaljni prikaz sa VM-ovima
  -n, --name TENANT_NAME   Show only specific tenant
  --verbose                Increase verbosity (INFO level, use twice for DEBUG)
  -h, --help               Show this help message

Example:
  $0
  $0 --detailed
  $0 --json
  $0 -n firma_b -d

EOF
    exit "${1:-0}"
}

JSON_OUTPUT=false
DETAILED=false
SPECIFIC_TENANT=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -j|--json)
            JSON_OUTPUT=true
            shift
            ;;
        -d|--detailed)
            DETAILED=true
            shift
            ;;
        -n|--name)
            SPECIFIC_TENANT="$2"
            shift 2
            ;;
        --verbose)
            # Handled by ptm_parse_verbosity_flags
            shift
            ;;
        -h|--help)
            usage 0
            ;;
        *)
            echo "Unknown option: $1"
            usage 1
            ;;
    esac
done

ptm_check_requirements || exit 1
ptm_check_root

declare -A VM_CACHE
declare -A POOL_VM_CACHE

init_vm_cache() {
    local all_vms_json
    all_vms_json=$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null)

    while IFS= read -r vm_json; do
        local vmid=$(echo "$vm_json" | jq -r '.vmid')
        VM_CACHE[$vmid]="$vm_json"
    done < <(echo "$all_vms_json" | jq -c '.[]')
}

get_pool_vms() {
    local pool_id=$1

    if [ -n "${POOL_VM_CACHE[$pool_id]:-}" ]; then
        echo "${POOL_VM_CACHE[$pool_id]}"
        return 0
    fi

    local vm_list=""
    if pvesh get "/pools/${pool_id}" --output-format json &>/dev/null; then
        local pool_data
        pool_data=$(pvesh get "/pools/${pool_id}" --output-format json 2>/dev/null)

        if echo "$pool_data" | jq -e '. | type == "array"' >/dev/null 2>&1; then
            vm_list=$(echo "$pool_data" | jq -r '.[] | select(.vmid != null) | .vmid' 2>/dev/null || echo "")
        fi

        POOL_VM_CACHE[$pool_id]="$vm_list"
    fi

    echo "$vm_list"
}

get_cached_vm_details() {
    local vmid=$1

    if [ -n "${VM_CACHE[$vmid]}" ]; then
        local vm_json="${VM_CACHE[$vmid]}"
        local vm_name=$(echo "$vm_json" | jq -r '.name // "unknown"')
        local vm_type=$(echo "$vm_json" | jq -r '.type // "unknown"')
        local vm_status=$(echo "$vm_json" | jq -r '.status // "unknown"')
        local vm_node=$(echo "$vm_json" | jq -r '.node // "unknown"')
        local vm_cpu=$(echo "$vm_json" | jq -r '.maxcpu // 0')
        local vm_mem=$(echo "$vm_json" | jq -r '.maxmem // 0')

        echo "$vmid|$vm_name|$vm_type|$vm_status|$vm_node|$vm_cpu|$vm_mem"
        return 0
    fi

    get_vm_details "$vmid"
}

get_vm_details() {
    local vmid=$1

    if ! [[ "$vmid" =~ ^[0-9]+$ ]]; then
        ptm_log ERROR "Invalid VMID format: $vmid"
        echo "$vmid|invalid|invalid|invalid|invalid|0|0"
        return 1
    fi

    local vm_info
    vm_info=$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null | jq --argjson id "$vmid" '.[] | select(.vmid == $id)')

    local vm_name
    local vm_type
    local vm_status
    local vm_node
    local vm_cpu
    local vm_mem

    vm_name=$(echo "$vm_info" | jq -r '.name // "unknown"')
    vm_type=$(echo "$vm_info" | jq -r '.type // "unknown"')
    vm_status=$(echo "$vm_info" | jq -r '.status // "unknown"')
    vm_node=$(echo "$vm_info" | jq -r '.node // "unknown"')
    vm_cpu=$(echo "$vm_info" | jq -r '.maxcpu // 0')
    vm_mem=$(echo "$vm_info" | jq -r '.maxmem // 0')

    vm_mem=$((vm_mem / 1024 / 1024))

    echo "$vmid|$vm_name|$vm_type|$vm_status|$vm_node|$vm_cpu|$vm_mem"
}

display_tenant() {
    local tenant_name=$1

    if ! ptm_load_tenant_config "$tenant_name" 2>/dev/null; then
        return 1
    fi

    local vm_list=$(get_pool_vms "$POOL_ID")
    local vm_count=0
    if [ -n "$vm_list" ]; then
        vm_count=$(echo "$vm_list" | wc -w)
    fi

    if [ "$JSON_OUTPUT" = true ]; then
        local vms_json="[]"
        if [ "$DETAILED" = true ] && [ -n "$vm_list" ]; then
            local -a vm_json_array=()
            for vmid in $vm_list; do
                local details=$(get_cached_vm_details "$vmid")
                IFS='|' read -r vid vname vtype vstatus vnode vcpu vmem <<< "$details"

                local vm_json=$(jq -n \
                    --arg vmid "$vid" \
                    --arg name "$vname" \
                    --arg type "$vtype" \
                    --arg status "$vstatus" \
                    --arg node "$vnode" \
                    --arg cpu "$vcpu" \
                    --arg mem "$vmem" \
                    '{vmid: ($vmid | tonumber), name: $name, type: $type, status: $status, node: $node, cpu: ($cpu | tonumber), mem: ($mem | tonumber)}')
                vm_json_array+=("$vm_json")
            done

            if [ ${#vm_json_array[@]} -gt 0 ]; then
                vms_json=$(printf '%s\n' "${vm_json_array[@]}" | jq -s '.')
            else
                vms_json="[]"
            fi
        fi

        cat <<EOF
{
  "tenant_name": "$TENANT_NAME",
  "pool_id": "$POOL_ID",
  "group_name": "$GROUP_NAME",
  "vlan_id": $VLAN_ID,
  "subnet": "$SUBNET",
  "cpu_limit": $CPU_LIMIT,
  "ram_limit": $RAM_LIMIT,
  "storage_limit": $STORAGE_LIMIT,
  "vm_count": $vm_count,
  "created_date": "$CREATED_DATE",
  "vms": $vms_json
}
EOF
    else
        echo "=========================================="
        echo "Tenant: $TENANT_NAME"
        echo "=========================================="
        echo "Resource Pool: $POOL_ID"
        echo "User Group:    $GROUP_NAME"
        echo "VLAN ID:       $VLAN_ID"
        echo "Subnet:        $SUBNET"
        echo "Created:       ${CREATED_DATE:-N/A}"
        echo ""
        echo "Resource Limits:"
        echo "  CPU:      $CPU_LIMIT cores"
        echo "  RAM:      $RAM_LIMIT MB"
        echo "  Storage:  $STORAGE_LIMIT GB"
        echo ""
        echo "VM/Container Count: $vm_count"

        if [ "$DETAILED" = true ] && [ -n "$vm_list" ]; then
            echo ""
            echo "VMs/Containers:"
            printf "  %-8s %-20s %-10s %-10s %-10s %8s %10s\n" "VMID" "Name" "Type" "Status" "Node" "CPU" "RAM(MB)"
            echo "  --------------------------------------------------------------------------------"

            for vmid in $vm_list; do
                local details=$(get_cached_vm_details "$vmid")
                IFS='|' read -r vid vname vtype vstatus vnode vcpu vmem <<< "$details"
                printf "  %-8s %-20s %-10s %-10s %-10s %8s %10s\n" "$vid" "$vname" "$vtype" "$vstatus" "$vnode" "$vcpu" "$vmem"
            done
        fi

        echo "=========================================="
        echo ""
    fi
}

init_vm_cache

if [ -n "$SPECIFIC_TENANT" ]; then
    if ! ptm_tenant_exists "$SPECIFIC_TENANT"; then
        ptm_log ERROR "Tenant '$SPECIFIC_TENANT' does not exist"
        exit 1
    fi

    display_tenant "$SPECIFIC_TENANT"
else
    tenants=$(ptm_list_all_tenants)

    if [ -z "$tenants" ]; then
        if [ "$JSON_OUTPUT" = true ]; then
            echo "[]"
        else
            ptm_log INFO "No tenants found"
        fi
        exit 0
    fi

    if [ "$JSON_OUTPUT" = true ]; then
        echo "["
        first=true
        for tenant in $tenants; do
            if [ "$first" = true ]; then
                first=false
            else
                echo ","
            fi
            display_tenant "$tenant"
        done
        echo "]"
    else
        echo ""
        echo "Tenctl Overview"
        echo "=============================="
        echo ""
        printf "%-20s %-15s %-20s %-8s %-12s %-8s %-10s %-8s\n" \
            "Tenant" "Pool ID" "Subnet" "VLAN" "CPU Limit" "RAM(MB)" "Storage(GB)" "VM Count"
        echo "--------------------------------------------------------------------------------------------------------"

        for tenant in $tenants; do
            if ptm_load_tenant_config "$tenant" 2>/dev/null; then
                tenant_vm_list=$(get_pool_vms "$POOL_ID")
                tenant_vm_count=0
                if [ -n "$tenant_vm_list" ]; then
                    tenant_vm_count=$(echo "$tenant_vm_list" | wc -w)
                fi
                printf "%-20s %-15s %-20s %-8s %-12s %-8s %-10s %-8s\n" \
                    "$TENANT_NAME" "$POOL_ID" "$SUBNET" "$VLAN_ID" \
                    "$CPU_LIMIT" "$RAM_LIMIT" "$STORAGE_LIMIT" "$tenant_vm_count"
            fi
        done

        echo "--------------------------------------------------------------------------------------------------------"
        echo ""

        if [ "$DETAILED" = true ]; then
            echo ""
            echo "Detailed Information:"
            echo ""
            for tenant in $tenants; do
                display_tenant "$tenant"
            done
        fi
    fi
fi

exit 0
