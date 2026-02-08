#!/bin/bash
set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
source "${SCRIPT_DIR}/../lib/common.sh"

ptm_parse_verbosity_flags "$@"

usage() {
    cat << EOF
Usage: $0 -n TENANT_NAME [OPTIONS]

Resume a suspended tenant (re-enable access, optionally start VMs).

Required:
  -n, --name TENANT_NAME      Name of the tenant to resume

Optional:
  --start-vms                 Start all stopped VMs (default: leave stopped)
  -f, --force                 Skip confirmation prompt
  --verbose                   Increase verbosity (INFO level, use twice for DEBUG)
  -h, --help                  Show this help

Examples:
  $0 -n firma_a                    # Resume tenant, VMs stay stopped
  $0 -n firma_a --start-vms        # Resume and start all VMs

What happens during resume:
  1. Tenant user account is re-enabled (can login again)
  2. Optionally: All VMs/containers are started
  3. Tenant config is marked as ACTIVE
  4. Action is logged

EOF
    exit 1
}

TENANT_NAME=""
START_VMS=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            TENANT_NAME="$2"
            shift 2
            ;;
        --start-vms)
            START_VMS=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        --verbose)
            # Handled by ptm_parse_verbosity_flags
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

if [ -z "$TENANT_NAME" ]; then
    echo "ERROR: Tenant name is required"
    usage
fi

ptm_check_root
ptm_check_requirements || exit 1

ptm_validate_tenant_name "$TENANT_NAME" || exit 1

if ! ptm_tenant_exists "$TENANT_NAME"; then
    ptm_log ERROR "Tenant '$TENANT_NAME' does not exist"
    exit 1
fi

if ! ptm_load_tenant_config "$TENANT_NAME"; then
    ptm_log ERROR "Failed to load tenant configuration"
    exit 1
fi

POOL_ID="tenant_${TENANT_NAME}"
USER_ID="${USERNAME}@pve"

if [ "${TENANT_STATUS:-ACTIVE}" != "SUSPENDED" ]; then
    ptm_log WARN "Tenant '$TENANT_NAME' is not suspended (current status: ${TENANT_STATUS:-ACTIVE})"
    ptm_log INFO "Nothing to resume"
    exit 0
fi

SUSPEND_REASON="${SUSPEND_REASON:-Unknown}"
SUSPEND_DATE="${SUSPEND_DATE:-Unknown}"

ptm_log INFO "Tenant Resume Plan"
ptm_log INFO "Tenant: $TENANT_NAME"
ptm_log INFO "User: $USER_ID"
ptm_log INFO "Pool: $POOL_ID"
ptm_log INFO "Suspension Info:"
ptm_log INFO "  Reason: $SUSPEND_REASON"
ptm_log INFO "  Suspended on: $SUSPEND_DATE"
ptm_log INFO "Actions:"
ptm_log INFO "  1. Re-enable user account ($USER_ID)"
if [ "$START_VMS" = true ]; then
    VM_COUNT=$(ptm_get_pool_vm_list "$POOL_ID" | wc -w)
    ptm_log INFO "  2. Start all VMs/containers ($VM_COUNT total)"
    ptm_log INFO "  3. Mark tenant as ACTIVE in config"
else
    ptm_log INFO "  2. Mark tenant as ACTIVE in config"
    ptm_log INFO "  3. VMs will remain stopped (use --start-vms to start)"
fi

if [ "$FORCE" = false ]; then
    read -p "Continue with resume? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        ptm_log INFO "Resume cancelled"
        exit 0
    fi
fi

ptm_log INFO "Starting tenant resume..."

ptm_log INFO "Re-enabling user account: $USER_ID"
if pvesh set "/access/users/${USER_ID}" --enable 1 2>/dev/null; then
    ptm_log INFO "User account re-enabled successfully"
else
    ptm_log ERROR "Failed to re-enable user account"
    ptm_log WARN "Continuing with resume..."
fi

if [ "$START_VMS" = true ]; then
    ptm_log INFO "Starting all VMs/containers..."

    VM_LIST=$(ptm_get_pool_vm_list "$POOL_ID")

    STARTED_COUNT=0
    FAILED_COUNT=0

    for vmid in $VM_LIST; do
        VM_DATA=$(ptm_get_vm_metadata "$vmid")

        if [ "$VM_DATA" = "{}" ]; then
            continue
        fi

        ptm_parse_vm_metadata "$VM_DATA"

        if [ "$VM_STATUS" = "running" ]; then
            ptm_log INFO "  VM $vmid already running"
            continue
        fi

        ptm_log INFO "  Starting VM $vmid (type: $VM_TYPE, node: $VM_NODE)..."

        if ptm_start_vm "$vmid" "$VM_TYPE" "$VM_NODE"; then
            STARTED_COUNT=$((STARTED_COUNT + 1))
        else
            FAILED_COUNT=$((FAILED_COUNT + 1))
        fi
    done

    ptm_log INFO "VM start summary: $STARTED_COUNT started, $FAILED_COUNT failed"
fi

TENANT_CONF="${TENANT_CONFIG_DIR}/${TENANT_NAME}.conf"
cp "$TENANT_CONF" "${TENANT_CONF}.backup-$(date +%Y%m%d_%H%M%S)"
sed -i '/^SUSPEND_REASON=/d; /^SUSPEND_DATE=/d' "$TENANT_CONF"

ptm_update_tenant_status "$TENANT_NAME" "ACTIVE" \
    "RESUME_DATE=\"$(date "+%Y-%m-%d %H:%M:%S")\""

ptm_log INFO "Tenant config updated with ACTIVE status"

ptm_log INFO "Tenant Resume Complete!"
ptm_log INFO "Tenant: $TENANT_NAME"
ptm_log INFO "Status: ACTIVE"
if [ "$START_VMS" = true ]; then
    ptm_log INFO "VMs started: $STARTED_COUNT"
    [ "$FAILED_COUNT" -gt 0 ] && ptm_log WARN "VMs failed to start: $FAILED_COUNT"
fi
ptm_log INFO "Tenant '$TENANT_NAME' is now active"
ptm_log INFO "User $USER_ID can login again"

exit 0
