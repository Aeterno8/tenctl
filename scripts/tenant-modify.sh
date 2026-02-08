#!/bin/bash

set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
source "${SCRIPT_DIR}/../lib/common.sh"

ptm_parse_verbosity_flags "$@"

usage() {
    cat << EOF
Usage: $0 -n TENANT_NAME [OPTIONS]

Modifies tenant resource limits and configuration.

Required:
  -n, --name TENANT_NAME        Name of tenant to modify

Optional Resource Limits:
  -c, --cpu CPU_LIMIT           CPU limit (number of cores)
  -r, --ram RAM_LIMIT           RAM limit in MB
  -s, --storage STORAGE_LIMIT   Storage limit in GB

Optional Configuration:
  --email EMAIL                 Update admin email
  --password PASSWORD           Update admin password (WARNING: see security note below)

Display Options:
  --show-current                Show current configuration before prompting for changes
  --force                       Skip confirmation prompt (for automation)
  --verbose                     Increase verbosity (INFO level, use twice for DEBUG)
  -h, --help                    Display this help message

SECURITY WARNING:
  Do NOT use the --password flag in production environments!
  Passwords passed via command-line arguments are visible in process listings
  (ps aux, /proc, system logs) and may be logged in shell history files.

  For production use:
    - Use interactive password prompt (if implemented)
    - Or retrieve credentials from secure file: /root/tenctl-credentials/

Examples:
  # Increase CPU and RAM for tenant
  $0 -n firma_b -c 32 -r 65536

  # Update storage limit only
  $0 -n firma_b -s 2000

  # Show current configuration
  $0 -n firma_b --show-current

  # Update email
  $0 -n firma_b --email newemail@firma-b.com

EOF
    exit "${1:-0}"
}

TENANT_NAME=""
NEW_CPU_LIMIT=""
NEW_RAM_LIMIT=""
NEW_STORAGE_LIMIT=""
NEW_EMAIL=""
NEW_PASSWORD=""
SHOW_CURRENT=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            TENANT_NAME="$2"
            shift 2
            ;;
        -c|--cpu)
            NEW_CPU_LIMIT="$2"
            shift 2
            ;;
        -r|--ram)
            NEW_RAM_LIMIT="$2"
            shift 2
            ;;
        -s|--storage)
            NEW_STORAGE_LIMIT="$2"
            shift 2
            ;;
        --email)
            NEW_EMAIL="$2"
            shift 2
            ;;
        --password)
            NEW_PASSWORD="$2"
            shift 2
            ;;
        --show-current)
            SHOW_CURRENT=true
            shift
            ;;
        --force)
            FORCE=true
            shift
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

if [ -z "$TENANT_NAME" ]; then
    ptm_log ERROR "Tenant name is required"
    usage 1
fi

ptm_check_root
ptm_check_requirements || exit 1

if ! ptm_tenant_exists "$TENANT_NAME"; then
    ptm_log ERROR "Tenant '$TENANT_NAME' does not exist"
    exit 1
fi

ptm_load_tenant_config "$TENANT_NAME" || exit 1

ORIGINAL_CPU_LIMIT=$CPU_LIMIT
ORIGINAL_RAM_LIMIT=$RAM_LIMIT
ORIGINAL_STORAGE_LIMIT=$STORAGE_LIMIT

if [ "$SHOW_CURRENT" = true ]; then
    ptm_log INFO "Current configuration for: $TENANT_NAME"
    ptm_log INFO "Resource Pool: $POOL_ID"
    ptm_log INFO "User Group:    $GROUP_NAME"
    ptm_log INFO "VLAN ID:       $VLAN_ID"
    ptm_log INFO "Subnet:        $SUBNET"
    ptm_log INFO "Resource Limits:"
    ptm_log INFO "  CPU:      $CPU_LIMIT cores"
    ptm_log INFO "  RAM:      $RAM_LIMIT MB"
    ptm_log INFO "  Storage:  $STORAGE_LIMIT GB"
    ptm_log INFO "Created:       ${CREATED_DATE:-N/A}"
    exit 0
fi

if [ -z "$NEW_CPU_LIMIT" ] && [ -z "$NEW_RAM_LIMIT" ] && [ -z "$NEW_STORAGE_LIMIT" ] && \
   [ -z "$NEW_EMAIL" ] && [ -z "$NEW_PASSWORD" ]; then
    ptm_log ERROR "No modifications specified. Use --help to see available options."
    ptm_log INFO "Hint: Use --show-current to view current configuration"
    exit 1
fi

CPU_LIMIT=${NEW_CPU_LIMIT:-$ORIGINAL_CPU_LIMIT}
RAM_LIMIT=${NEW_RAM_LIMIT:-$ORIGINAL_RAM_LIMIT}
STORAGE_LIMIT=${NEW_STORAGE_LIMIT:-$ORIGINAL_STORAGE_LIMIT}

if [ -n "$NEW_CPU_LIMIT" ]; then
    if ! [[ "$NEW_CPU_LIMIT" =~ ^[0-9]+$ ]] || [ "$NEW_CPU_LIMIT" -lt $MIN_CPU_CORES ]; then
        ptm_log ERROR "Invalid CPU limit: $NEW_CPU_LIMIT (must be >= $MIN_CPU_CORES)"
        exit 1
    fi
fi

if [ -n "$NEW_RAM_LIMIT" ]; then
    if ! [[ "$NEW_RAM_LIMIT" =~ ^[0-9]+$ ]] || [ "$NEW_RAM_LIMIT" -lt $MIN_RAM_MB ]; then
        ptm_log ERROR "Invalid RAM limit: $NEW_RAM_LIMIT (must be >= $MIN_RAM_MB MB)"
        exit 1
    fi
fi

if [ -n "$NEW_STORAGE_LIMIT" ]; then
    if ! [[ "$NEW_STORAGE_LIMIT" =~ ^[0-9]+$ ]] || [ "$NEW_STORAGE_LIMIT" -lt $MIN_STORAGE_GB ]; then
        ptm_log ERROR "Invalid storage limit: $NEW_STORAGE_LIMIT (must be >= $MIN_STORAGE_GB GB)"
        exit 1
    fi
fi

if [ -n "$NEW_EMAIL" ]; then
    ptm_validate_email "$NEW_EMAIL" || exit 1
fi

ADDITIONAL_CPU=$((CPU_LIMIT - ORIGINAL_CPU_LIMIT))
ADDITIONAL_RAM=$((RAM_LIMIT - ORIGINAL_RAM_LIMIT))
ADDITIONAL_STORAGE=$((STORAGE_LIMIT - ORIGINAL_STORAGE_LIMIT))

if [ $ADDITIONAL_CPU -gt 0 ] || [ $ADDITIONAL_RAM -gt 0 ] || [ $ADDITIONAL_STORAGE -gt 0 ]; then
    ptm_log INFO "Validating cluster capacity for resource increase..."

    if ! ptm_validate_cluster_resources "$CPU_LIMIT" "$RAM_LIMIT" "$STORAGE_LIMIT" "$TENANT_NAME"; then
        ptm_log ERROR "Cannot modify tenant: insufficient cluster resources"
        ptm_log ERROR "Requested total: ${CPU_LIMIT} CPU, ${RAM_LIMIT} MB RAM, ${STORAGE_LIMIT} GB storage"
        ptm_log ERROR "Current allocation: ${ORIGINAL_CPU_LIMIT} CPU, ${ORIGINAL_RAM_LIMIT} MB RAM, ${ORIGINAL_STORAGE_LIMIT} GB storage"
        ptm_log ERROR "Increase: ${ADDITIONAL_CPU} CPU, ${ADDITIONAL_RAM} MB RAM, ${ADDITIONAL_STORAGE} GB storage"
        exit 1
    fi
fi

ptm_log INFO "Tenant modification summary"
ptm_log INFO "Tenant Name: $TENANT_NAME"

if [ -n "$NEW_CPU_LIMIT" ]; then
    ptm_log INFO "CPU Limit:      $ORIGINAL_CPU_LIMIT cores → $CPU_LIMIT cores"
else
    ptm_log INFO "CPU Limit:      $CPU_LIMIT cores (unchanged)"
fi

if [ -n "$NEW_RAM_LIMIT" ]; then
    ptm_log INFO "RAM Limit:      $ORIGINAL_RAM_LIMIT MB → $RAM_LIMIT MB"
else
    ptm_log INFO "RAM Limit:      $RAM_LIMIT MB (unchanged)"
fi

if [ -n "$NEW_STORAGE_LIMIT" ]; then
    ptm_log INFO "Storage Limit:  $ORIGINAL_STORAGE_LIMIT GB → $STORAGE_LIMIT GB"
else
    ptm_log INFO "Storage Limit:  $STORAGE_LIMIT GB (unchanged)"
fi

if [ -n "$NEW_EMAIL" ]; then
    ptm_log INFO "Email:          updating to $NEW_EMAIL"
fi

if [ -n "$NEW_PASSWORD" ]; then
    ptm_log INFO "Password:       will be updated (not displayed)"
fi

echo ""
if [ "$FORCE" = false ]; then
    read -p "Apply these changes? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        ptm_log INFO "Modification cancelled"
        exit 0
    fi
else
    ptm_log INFO "Skipping confirmation (--force flag set)"
fi

if [ -n "$NEW_CPU_LIMIT" ] || [ -n "$NEW_RAM_LIMIT" ] || [ -n "$NEW_STORAGE_LIMIT" ]; then
    ptm_log DEBUG "Updating resource pool limits tracking..."
    ptm_set_pool_limits "$POOL_ID" "$CPU_LIMIT" "$RAM_LIMIT" "$STORAGE_LIMIT"
    ptm_log INFO "Resource limits updated in tenant configuration"
fi

if [ -n "$NEW_EMAIL" ]; then
    USER_ID="${USERNAME:-admin}@pve"
    ptm_log INFO "Updating user email for $USER_ID..."
    if pvesh set "/access/users/${USER_ID}" --email "$NEW_EMAIL" 2>/dev/null; then
        ptm_log INFO "User email updated successfully"
    else
        ptm_log ERROR "Failed to update user email"
        exit 1
    fi
fi

if [ -n "$NEW_PASSWORD" ]; then
    USER_ID="${USERNAME:-admin}@pve"
    ptm_log INFO "Updating user password for $USER_ID..."
    if pvesh set "/access/users/${USER_ID}" --password "$NEW_PASSWORD" 2>/dev/null; then
        ptm_log INFO "User password updated successfully"

        CREDENTIALS_DIR="/root/tenctl-credentials"
        if [ -d "$CREDENTIALS_DIR" ]; then
            CREDENTIALS_FILE="${CREDENTIALS_DIR}/tenant_${TENANT_NAME}_$(date +%Y%m%d_%H%M%S)_$$.json"

            (umask 077; jq -n \
              --arg tenant "$TENANT_NAME" \
              --arg user "$USER_ID" \
              --arg pass "$NEW_PASSWORD" \
              --arg email "${NEW_EMAIL:-${EMAIL:-}}" \
              --arg vlan "$VLAN_ID" \
              --arg subnet "$SUBNET" \
              --argjson cpu "$CPU_LIMIT" \
              --argjson ram "$RAM_LIMIT" \
              --argjson storage "$STORAGE_LIMIT" \
              --arg pool "$POOL_ID" \
              --arg group "$GROUP_NAME" \
              --arg vnet "vnet_${TENANT_NAME}" \
              --arg modified "$(date -Iseconds)" \
              '{
                tenant_name: $tenant,
                username: $user,
                password: $pass,
                email: $email,
                vlan_id: $vlan,
                subnet: $subnet,
                cpu_limit: $cpu,
                ram_limit: $ram,
                storage_limit: $storage,
                pool_id: $pool,
                group_name: $group,
                vnet_name: $vnet,
                modified_date: $modified
              }' > "$CREDENTIALS_FILE") || {
                ptm_log ERROR "Failed to save updated credentials file"
                exit 1
            }

            ptm_log INFO "Updated credentials saved: $CREDENTIALS_FILE (mode 600)"
        fi
    else
        ptm_log ERROR "Failed to update user password"
        exit 1
    fi
fi

ptm_log INFO "Updating tenant configuration..."
ptm_save_tenant_config "$TENANT_NAME" "$VLAN_ID" "$SUBNET" "$CPU_LIMIT" "$RAM_LIMIT" "$STORAGE_LIMIT" "$USERNAME" || {
    ptm_log ERROR "Failed to update tenant configuration"
    exit 1
}

ptm_log INFO "Tenant '$TENANT_NAME' modified successfully!"
ptm_log INFO "Updated configuration:"
ptm_log INFO "  CPU:      $CPU_LIMIT cores"
ptm_log INFO "  RAM:      $RAM_LIMIT MB"
ptm_log INFO "  Storage:  $STORAGE_LIMIT GB"

if [ -n "$NEW_EMAIL" ]; then
    ptm_log INFO "  Email:    $NEW_EMAIL"
fi

if [ -n "$NEW_PASSWORD" ]; then
    ptm_log INFO "  Password: *** (updated, see credentials file)"
fi

ptm_log INFO "Note: Existing VMs in pool '$POOL_ID' are not affected."
ptm_log INFO "New resource limits apply to future VM allocations."

exit 0
