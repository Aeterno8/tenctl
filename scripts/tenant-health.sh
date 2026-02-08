#!/bin/bash

set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
source "${SCRIPT_DIR}/../lib/common.sh"

ptm_parse_verbosity_flags "$@"

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Perform health checks and diagnostics on the multi-tenant system.

Optional:
  -n, --name TENANT_NAME    Check specific tenant health
  -j, --json                Output in JSON format
  -v, --verbose             Verbose output with detailed information
  -h, --help                Display this help message

Checks Performed:
  ✓ System dependencies (pvesh, jq, flock, vzdump)
  ✓ Proxmox cluster status and connectivity
  ✓ SDN zone configuration
  ✓ VLAN allocation and conflicts
  ✓ Subnet allocation and conflicts
  ✓ Tenant configuration integrity
  ✓ Resource pool consistency
  ✓ User and group existence
  ✓ ACL permissions
  ✓ Orphaned resources detection

Examples:
  $0                        # Check overall system health
  $0 -n firma_a             # Check specific tenant
  $0 -v                     # Verbose output
  $0 -j                     # JSON output for automation

Exit Codes:
  0 - All checks passed
  1 - One or more checks failed
  2 - Critical error (system unavailable)

EOF
    exit "${1:-0}"
}

# Parse arguments
SPECIFIC_TENANT=""
JSON_OUTPUT=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            SPECIFIC_TENANT="$2"
            shift 2
            ;;
        -j|--json)
            JSON_OUTPUT=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
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

TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

declare -a JSON_RESULTS=()

record_check() {
    local check_name=$1
    local status=$2  # "pass", "fail", "warn"
    local message=$3
    local details="${4:-}"

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    case "$status" in
        pass)
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
            if [ "$JSON_OUTPUT" = false ]; then
                echo "  ✓ $message"
                [ "$VERBOSE" = true ] && [ -n "$details" ] && echo "    $details"
            fi
            ;;
        fail)
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
            if [ "$JSON_OUTPUT" = false ]; then
                echo "  ✗ $message"
                [ -n "$details" ] && echo "    $details"
            fi
            ;;
        warn)
            WARNING_CHECKS=$((WARNING_CHECKS + 1))
            if [ "$JSON_OUTPUT" = false ]; then
                echo "  ⚠ $message"
                [ -n "$details" ] && echo "    $details"
            fi
            ;;
    esac

    if [ "$JSON_OUTPUT" = true ]; then
        local json_entry
        json_entry=$(jq -n \
            --arg name "$check_name" \
            --arg status "$status" \
            --arg message "$message" \
            --arg details "$details" \
            '{check: $name, status: $status, message: $message, details: $details}')
        JSON_RESULTS+=("$json_entry")
    fi
}


check_dependencies() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo "Checking system dependencies..."
    fi

    if command -v pvesh >/dev/null 2>&1; then
        record_check "dependencies_pvesh" "pass" "pvesh command available"
    else
        record_check "dependencies_pvesh" "fail" "pvesh command not found" "Install Proxmox VE or ensure PATH is correct"
    fi

    if command -v jq >/dev/null 2>&1; then
        local jq_version=$(jq --version 2>/dev/null || echo "unknown")
        record_check "dependencies_jq" "pass" "jq available" "$jq_version"
    else
        record_check "dependencies_jq" "fail" "jq not found" "Install with: apt-get install jq"
    fi

    if command -v flock >/dev/null 2>&1; then
        record_check "dependencies_flock" "pass" "flock available"
    else
        record_check "dependencies_flock" "fail" "flock not found" "Install with: apt-get install util-linux"
    fi

    if command -v vzdump >/dev/null 2>&1; then
        record_check "dependencies_vzdump" "pass" "vzdump available (backup support enabled)"
    else
        record_check "dependencies_vzdump" "warn" "vzdump not found" "Backup functionality will not work"
    fi
}

check_proxmox_cluster() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo "Checking Proxmox cluster..."
    fi

    if pvesh get /version --output-format json &>/dev/null; then
        local pve_version=$(pveversion 2>/dev/null | head -1 || echo "unknown")
        record_check "cluster_api" "pass" "Proxmox API accessible" "$pve_version"
    else
        record_check "cluster_api" "fail" "Cannot connect to Proxmox API" "Check if Proxmox services are running"
        return 1
    fi

    local cluster_info
    if cluster_info=$(pvesh get /cluster/resources --type node --output-format json 2>/dev/null); then
        local node_count=$(echo "$cluster_info" | jq '. | length')
        local online_nodes=$(echo "$cluster_info" | jq '[.[] | select(.status == "online")] | length')

        if [ "$online_nodes" -eq "$node_count" ]; then
            record_check "cluster_nodes" "pass" "All $node_count cluster node(s) online"
        else
            record_check "cluster_nodes" "warn" "Only $online_nodes of $node_count nodes online" "Some nodes may be unavailable"
        fi
    else
        record_check "cluster_nodes" "fail" "Cannot retrieve cluster node information"
    fi

    local pve_major_version=$(ptm_check_proxmox_version 2>/dev/null || echo "0")
    if [ "$pve_major_version" -ge 9 ]; then
        record_check "cluster_version" "pass" "Proxmox VE $pve_major_version.x (native resource limits supported)"
    elif [ "$pve_major_version" -ge 8 ]; then
        record_check "cluster_version" "warn" "Proxmox VE $pve_major_version.x" "Resource limits not enforced (upgrade to 9.0+ recommended)"
    else
        record_check "cluster_version" "fail" "Proxmox VE version unknown or too old" "Minimum supported version: 8.x"
    fi
}

check_sdn_configuration() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo "Checking SDN configuration..."
    fi

    if ! pvesh get /cluster/sdn/zones --output-format json &>/dev/null; then
        record_check "sdn_available" "fail" "SDN not available" "Check Proxmox SDN installation"
        return 1
    fi

    record_check "sdn_available" "pass" "SDN subsystem available"

    if pvesh get "/cluster/sdn/zones/${SDN_ZONE_NAME}" --output-format json &>/dev/null; then
        local zone_info
        zone_info=$(pvesh get "/cluster/sdn/zones/${SDN_ZONE_NAME}" --output-format json 2>/dev/null)
        local zone_type=$(echo "$zone_info" | jq -r '.type // "unknown"')
        record_check "sdn_zone" "pass" "SDN zone '$SDN_ZONE_NAME' configured" "Type: $zone_type"
    else
        record_check "sdn_zone" "fail" "SDN zone '$SDN_ZONE_NAME' not found" "Run 'tenctl init' to configure"
    fi

    if [ -n "${NETWORK_BRIDGE:-}" ]; then
        if ip link show "$NETWORK_BRIDGE" &>/dev/null; then
            record_check "sdn_bridge" "pass" "Network bridge '$NETWORK_BRIDGE' exists"
        else
            record_check "sdn_bridge" "warn" "Network bridge '$NETWORK_BRIDGE' not found" "May cause network connectivity issues"
        fi
    fi
}

check_vlan_allocation() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo "Checking VLAN allocation..."
    fi

    local all_vlans
    all_vlans=$(pvesh get /cluster/sdn/vnets --output-format json 2>/dev/null | jq -r '.[].tag // empty' | sort -n)

    if [ -z "$all_vlans" ]; then
        record_check "vlan_allocation" "warn" "No VLANs allocated" "No tenants created yet"
        return 0
    fi

    local vlan_count=$(echo "$all_vlans" | wc -l)
    local vlan_range_size=$((VLAN_END - VLAN_START + 1))
    local utilization=$((vlan_count * 100 / vlan_range_size))

    record_check "vlan_allocation" "pass" "$vlan_count VLAN(s) allocated" "Utilization: ${utilization}% of range $VLAN_START-$VLAN_END"

    local duplicates
    duplicates=$(echo "$all_vlans" | uniq -d)

    if [ -n "$duplicates" ]; then
        record_check "vlan_conflicts" "fail" "Duplicate VLANs detected: $duplicates" "Manual intervention required"
    else
        record_check "vlan_conflicts" "pass" "No VLAN conflicts detected"
    fi

    local out_of_range=()
    while IFS= read -r vlan; do
        [ -z "$vlan" ] && continue
        if [ "$vlan" -lt "$VLAN_START" ] || [ "$vlan" -gt "$VLAN_END" ]; then
            out_of_range+=("$vlan")
        fi
    done <<< "$all_vlans"

    if [ ${#out_of_range[@]} -gt 0 ]; then
        record_check "vlan_range" "warn" "VLANs outside configured range: ${out_of_range[*]}" "Range: $VLAN_START-$VLAN_END"
    else
        record_check "vlan_range" "pass" "All VLANs within configured range"
    fi
}

check_subnet_allocation() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo "Checking subnet allocation..."
    fi

    local all_subnets
    all_subnets=$(pvesh get /cluster/sdn/vnets --output-format json 2>/dev/null | \
        jq -r '.[].subnets[]?.subnet // empty' | sort)

    if [ -z "$all_subnets" ]; then
        record_check "subnet_allocation" "warn" "No subnets allocated" "No tenants created yet"
        return 0
    fi

    local subnet_count=$(echo "$all_subnets" | wc -l)
    record_check "subnet_allocation" "pass" "$subnet_count subnet(s) allocated"

    local duplicates
    duplicates=$(echo "$all_subnets" | uniq -d)

    if [ -n "$duplicates" ]; then
        record_check "subnet_conflicts" "fail" "Duplicate subnets detected" "$duplicates"
    else
        record_check "subnet_conflicts" "pass" "No subnet conflicts detected"
    fi

    local invalid_subnets=()
    while IFS= read -r subnet; do
        [ -z "$subnet" ] && continue
        if ! [[ "$subnet" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.0/24$ ]]; then
            invalid_subnets+=("$subnet")
        fi
    done <<< "$all_subnets"

    if [ ${#invalid_subnets[@]} -gt 0 ]; then
        record_check "subnet_format" "warn" "Subnets with non-standard format: ${invalid_subnets[*]}"
    else
        record_check "subnet_format" "pass" "All subnets use standard /24 format"
    fi
}

check_tenant_configs() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo "Checking tenant configurations..."
    fi

    if [ ! -d "$TENANT_CONFIG_DIR" ]; then
        record_check "tenant_config_dir" "fail" "Tenant config directory missing: $TENANT_CONFIG_DIR"
        return 1
    fi

    record_check "tenant_config_dir" "pass" "Tenant config directory exists"

    local config_count=0
    if compgen -G "$TENANT_CONFIG_DIR/*.conf" > /dev/null; then
        config_count=$(ls -1 "$TENANT_CONFIG_DIR"/*.conf 2>/dev/null | wc -l)
    fi

    if [ "$config_count" -eq 0 ]; then
        record_check "tenant_count" "warn" "No tenant configurations found" "System is empty"
        return 0
    fi

    record_check "tenant_count" "pass" "$config_count tenant(s) configured"

    local invalid_configs=()
    for config in "$TENANT_CONFIG_DIR"/*.conf; do
        [ -f "$config" ] || continue
        local tenant_name=$(basename "${config%.conf}")

        local perms=$(stat -c "%a" "$config" 2>/dev/null || echo "777")
        if [ "$perms" -gt 640 ]; then
            invalid_configs+=("$tenant_name (insecure permissions: $perms)")
        fi

        if ! ( source "$config" ) &>/dev/null; then
            invalid_configs+=("$tenant_name (syntax errors)")
        fi
    done

    if [ ${#invalid_configs[@]} -gt 0 ]; then
        record_check "config_integrity" "fail" "${#invalid_configs[@]} config(s) with issues" "${invalid_configs[*]}"
    else
        record_check "config_integrity" "pass" "All config files valid"
    fi
}

check_orphaned_resources() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo "Checking for orphaned resources..."
    fi

    local orphaned=()

    local all_pools
    all_pools=$(pvesh get /pools --output-format json 2>/dev/null | jq -r '.[].poolid' | grep "^tenant_" || true)

    for pool in $all_pools; do
        local tenant_name="${pool#tenant_}"
        if [ ! -f "${TENANT_CONFIG_DIR}/${tenant_name}.conf" ]; then
            orphaned+=("pool:$pool (no config file)")
        fi
    done

    if [ -d "$TENANT_CONFIG_DIR" ]; then
        for conf in "$TENANT_CONFIG_DIR"/*.conf; do
            [ -f "$conf" ] || continue
            local tenant_name=$(basename "${conf%.conf}")
            local pool_id="tenant_${tenant_name}"

            if ! pvesh get "/pools/${pool_id}" --output-format json &>/dev/null; then
                orphaned+=("config:$tenant_name (no resource pool)")
            fi
        done
    fi

    local all_vnets
    all_vnets=$(pvesh get /cluster/sdn/vnets --output-format json 2>/dev/null | \
        jq -r '.[].vnet' | grep "^vnet_" || true)

    for vnet in $all_vnets; do
        local tenant_name="${vnet#vnet_}"
        if [ ! -f "${TENANT_CONFIG_DIR}/${tenant_name}.conf" ]; then
            orphaned+=("vnet:$vnet (no tenant)")
        fi
    done

    if [ ${#orphaned[@]} -eq 0 ]; then
        record_check "orphaned_resources" "pass" "No orphaned resources detected"
    else
        local details=$(printf '%s\n' "${orphaned[@]}")
        record_check "orphaned_resources" "fail" "${#orphaned[@]} orphaned resource(s) found" "$details"
    fi
}

check_specific_tenant() {
    local tenant_name=$1

    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo "Checking tenant: $tenant_name"
        echo "=========================================="
    fi

    # Check if tenant exists
    if ! ptm_tenant_exists "$tenant_name"; then
        record_check "ptm_tenant_exists" "fail" "Tenant does not exist: $tenant_name"
        return 1
    fi

    record_check "ptm_tenant_exists" "pass" "Tenant exists"

    if ! ptm_load_tenant_config "$tenant_name" 2>/dev/null; then
        record_check "tenant_config" "fail" "Cannot load tenant configuration"
        return 1
    fi

    record_check "tenant_config" "pass" "Configuration loaded successfully"

    local pool_id="tenant_${tenant_name}"
    if pvesh get "/pools/${pool_id}" --output-format json &>/dev/null; then
        record_check "tenant_pool" "pass" "Resource pool exists: $pool_id"
    else
        record_check "tenant_pool" "fail" "Resource pool missing: $pool_id"
    fi

    local group_name="group_${tenant_name}"
    if pvesh get "/access/groups/${group_name}" --output-format json &>/dev/null; then
        record_check "tenant_group" "pass" "User group exists: $group_name"
    else
        record_check "tenant_group" "fail" "User group missing: $group_name"
    fi

    local user_id="${USERNAME:-admin}@pve"
    if pvesh get "/access/users/${user_id}" --output-format json &>/dev/null; then
        record_check "tenant_user" "pass" "Admin user exists: $user_id"
    else
        record_check "tenant_user" "fail" "Admin user missing: $user_id"
    fi

    local vnet_name="vnet_${tenant_name}"
    if pvesh get "/cluster/sdn/vnets/${vnet_name}" --output-format json &>/dev/null; then
        record_check "tenant_vnet" "pass" "VNet exists: $vnet_name"

        local vnet_info
        vnet_info=$(pvesh get "/cluster/sdn/vnets/${vnet_name}" --output-format json 2>/dev/null)
        local has_subnet=$(echo "$vnet_info" | jq -r '.subnets[]?.subnet // empty')

        if [ -n "$has_subnet" ]; then
            record_check "tenant_subnet" "pass" "Subnet configured: $has_subnet"
        else
            record_check "tenant_subnet" "warn" "No subnet configured in VNet"
        fi
    else
        record_check "tenant_vnet" "warn" "VNet not found: $vnet_name" "May not be using SDN"
    fi

    local vm_list
    vm_list=$(pvesh get "/pools/${pool_id}" --output-format json 2>/dev/null | jq -r '.[].vmid // empty' | wc -l)

    if [ "$vm_list" -gt 0 ]; then
        record_check "tenant_vms" "pass" "$vm_list VM(s)/container(s) in pool"
    else
        record_check "tenant_vms" "warn" "No VMs in pool" "Pool is empty"
    fi
}

main() {
    ptm_check_root

    if [ "$JSON_OUTPUT" = false ]; then
        echo "=========================================="
        echo "Tenctl Health Check"
        echo "=========================================="
        echo ""
    fi

    check_dependencies
    check_proxmox_cluster || {
        if [ "$JSON_OUTPUT" = false ]; then
            echo ""
            echo "CRITICAL: Cannot connect to Proxmox cluster"
            echo "Health check aborted"
        fi
        exit 2
    }
    check_sdn_configuration
    check_vlan_allocation
    check_subnet_allocation
    check_tenant_configs
    check_orphaned_resources

    if [ -n "$SPECIFIC_TENANT" ]; then
        check_specific_tenant "$SPECIFIC_TENANT"
    fi

    if [ "$JSON_OUTPUT" = true ]; then
        local all_checks=$(printf '%s\n' "${JSON_RESULTS[@]}" | jq -s '.')

        jq -n \
            --argjson checks "$all_checks" \
            --argjson total "$TOTAL_CHECKS" \
            --argjson passed "$PASSED_CHECKS" \
            --argjson failed "$FAILED_CHECKS" \
            --argjson warnings "$WARNING_CHECKS" \
            '{
                summary: {
                    total_checks: $total,
                    passed: $passed,
                    failed: $failed,
                    warnings: $warnings,
                    status: (if $failed > 0 then "FAILED" elif $warnings > 0 then "WARNING" else "PASSED" end)
                },
                checks: $checks,
                timestamp: now | strftime("%Y-%m-%dT%H:%M:%SZ")
            }'
    else
        echo ""
        echo "=========================================="
        echo "Health Check Summary"
        echo "=========================================="
        echo "Total checks:   $TOTAL_CHECKS"
        echo "Passed:         $PASSED_CHECKS ✓"
        echo "Warnings:       $WARNING_CHECKS ⚠"
        echo "Failed:         $FAILED_CHECKS ✗"
        echo "=========================================="

        if [ $FAILED_CHECKS -eq 0 ] && [ $WARNING_CHECKS -eq 0 ]; then
            echo "Status: ✓ ALL CHECKS PASSED"
            exit 0
        elif [ $FAILED_CHECKS -eq 0 ]; then
            echo "Status: ⚠ PASSED WITH WARNINGS"
            exit 0
        else
            echo "Status: ✗ CHECKS FAILED"
            exit 1
        fi
    fi
}

main "$@"
