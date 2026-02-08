#!/bin/bash

set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
source "${SCRIPT_DIR}/../lib/common.sh"

ptm_parse_verbosity_flags "$@"

wait_for_vm_stop() {
    local node=$1
    local vmid=$2
    local vm_type=$3
    local max_wait=$VM_STOP_TIMEOUT_SECONDS
    local waited=0

    if ! [[ "$vmid" =~ ^[0-9]+$ ]]; then
        ptm_log ERROR "Invalid VMID format: $vmid"
        return 1
    fi

    while [ $waited -lt $max_wait ]; do
        local status
        status=$(pvesh get "/nodes/${node}/${vm_type}/${vmid}/status/current" --output-format json 2>/dev/null | jq -r '.status // "unknown"')

        if [ "$status" = "stopped" ]; then
            return 0
        fi

        sleep 1
        waited=$((waited + 1))
    done

    ptm_log WARN "VM $vmid did not stop within ${max_wait}s, forcing deletion"
    return 1
}

usage() {
    cat << EOF
Usage: $0 -n TENANT_NAME [OPTIONS]

Removes a tenant from Proxmox multi-tenant environment.

Required:
  -n, --name TENANT_NAME    Ime tenanta za uklanjanje

Optional:
  -f, --force              Force removal without confirmation
  -b, --backup             Create VM backups before deletion (vzdump to default storage)
  --verbose                Increase verbosity (INFO level, use twice for DEBUG)
  -h, --help               Display this help message

Examples:
  $0 -n firma_b
  $0 -n firma_b --force
  $0 -n firma_b --backup --force

EOF
    exit "${1:-0}"
}

TENANT_NAME=""
FORCE=false
BACKUP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            TENANT_NAME="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -b|--backup)
            BACKUP=true
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

TENANT_EMAIL=""
CREDENTIALS_DIR="/root/tenctl-credentials"
if [ -d "$CREDENTIALS_DIR" ]; then
    CRED_FILE=$(ls -t "$CREDENTIALS_DIR"/tenant_"${TENANT_NAME}"_*.json 2>/dev/null | head -1)
    if [ -n "$CRED_FILE" ] && [ -f "$CRED_FILE" ]; then
        TENANT_EMAIL=$(jq -r '.email // ""' "$CRED_FILE" 2>/dev/null)
    fi
fi

ptm_log INFO "Tenant removal details"
ptm_log INFO "Tenant Name: $TENANT_NAME"
ptm_log INFO "Resource Pool: $POOL_ID"
ptm_log INFO "User Group: $GROUP_NAME"
ptm_log INFO "VLAN ID: $VLAN_ID"
ptm_log INFO "Subnet: $SUBNET"

pool_data=$(pvesh get "/pools/${POOL_ID}" --output-format json 2>/dev/null)
if echo "$pool_data" | jq -e '. | type == "array"' >/dev/null 2>&1; then
    mapfile -t vm_list < <(echo "$pool_data" | jq -r '.[] | select(.vmid != null) | .vmid' 2>/dev/null)
else
    vm_list=()
fi
VM_COUNT=${#vm_list[@]}

if [ "$VM_COUNT" -gt 0 ]; then
    ptm_log WARN "Pool contains $VM_COUNT VM(s)/Container(s)"

    ptm_log INFO "VMs/Containers in pool:"
    for vmid in "${vm_list[@]}"; do
        if ! [[ "$vmid" =~ ^[0-9]+$ ]]; then
            ptm_log ERROR "Invalid VMID format: $vmid"
            continue
        fi
        vm_info=$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null | jq --argjson id "$vmid" '.[] | select(.vmid == $id)')
        vm_name=$(echo "$vm_info" | jq -r '.name // "unknown"')
        ptm_log INFO "  - VMID: $vmid, Name: $vm_name"
    done

    if [ "$FORCE" = false ]; then
        echo ""
        read -p "WARNING: This will delete all VMs/Containers in this pool. Continue? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            ptm_log INFO "Removal cancelled"
            exit 0
        fi
    fi

    if [ "$BACKUP" = true ]; then
        ptm_log INFO "Creating backups before deletion..."
        declare -a BACKUP_FAILED=()

        for vmid in "${vm_list[@]}"; do
            if ! [[ "$vmid" =~ ^[0-9]+$ ]]; then
                ptm_log ERROR "Invalid VMID format for backup: $vmid"
                BACKUP_FAILED+=("$vmid (invalid format)")
                continue
            fi

            vm_info=$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null | jq --argjson id "$vmid" '.[] | select(.vmid == $id)')
            vm_type=$(echo "$vm_info" | jq -r '.type')
            vm_name=$(echo "$vm_info" | jq -r '.name // "unknown"')
            node=$(echo "$vm_info" | jq -r '.node')

            if [ "$vm_type" = "qemu" ]; then
                ptm_log INFO "Backing up VM ${vmid} (${vm_name}) on ${node}..."

                if vzdump "$vmid" --node "$node" --mode snapshot --compress zstd --remove 0 2>/dev/null; then
                    ptm_log INFO "Backup created successfully for VM ${vmid}"
                else
                    ptm_log WARN "Failed to create backup for VM ${vmid}"
                    BACKUP_FAILED+=("${vm_type}:${vmid}")
                fi
            else
                ptm_log INFO "Skipping backup for ${vm_type} ${vmid} (containers not supported)"
            fi
        done

        if [ ${#BACKUP_FAILED[@]} -gt 0 ]; then
            ptm_log WARN "Failed to backup ${#BACKUP_FAILED[@]} VM(s): ${BACKUP_FAILED[*]}"
            echo ""
            read -p "Some backups failed. Continue with deletion? (yes/no): " confirm_after_backup
            if [ "$confirm_after_backup" != "yes" ]; then
                ptm_log INFO "Removal cancelled"
                exit 0
            fi
        else
            ptm_log INFO "All VM backups completed successfully"
        fi
    fi

    ptm_log INFO "Stopping and removing VMs/Containers..."
    declare -a FAILED_DELETIONS=()

    for vmid in "${vm_list[@]}"; do
        if ! [[ "$vmid" =~ ^[0-9]+$ ]]; then
            ptm_log ERROR "Invalid VMID format: $vmid"
            FAILED_DELETIONS+=("$vmid (invalid format)")
            continue
        fi
        vm_info=$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null | jq --argjson id "$vmid" '.[] | select(.vmid == $id)')
        vm_type=$(echo "$vm_info" | jq -r '.type')
        node=$(echo "$vm_info" | jq -r '.node')

        ptm_log INFO "Stopping ${vm_type} ${vmid} on ${node}..."
        pvesh create "/nodes/${node}/${vm_type}/${vmid}/status/stop" 2>/dev/null || true

        wait_for_vm_stop "$node" "$vmid" "$vm_type"

        ptm_log INFO "Deleting ${vm_type} ${vmid}..."
        if ! pvesh delete "/nodes/${node}/${vm_type}/${vmid}" 2>/dev/null; then
            FAILED_DELETIONS+=("${vm_type}:${vmid}")
            ptm_log ERROR "Failed to delete ${vm_type} ${vmid}"
        fi
    done

    if [ ${#FAILED_DELETIONS[@]} -gt 0 ]; then
        ptm_log ERROR "Failed to delete ${#FAILED_DELETIONS[@]} VM(s)/container(s)"
        ptm_log ERROR "Manual cleanup required for: ${FAILED_DELETIONS[*]}"
        exit 1
    fi
else
    ptm_log INFO "Pool is empty, no VMs/Containers to remove"
fi

if [ "$FORCE" = false ] && [ "$VM_COUNT" -eq 0 ]; then
    echo ""
    read -p "Remove tenant '$TENANT_NAME'? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        ptm_log INFO "Removal cancelled"
        exit 0
    fi
fi

if ptm_check_vyos_configured 2>/dev/null; then
    ptm_log INFO "Removing VyOS configuration for tenant $TENANT_NAME..."
    if ptm_remove_vyos_tenant "$TENANT_NAME" "$VLAN_ID"; then
        ptm_log INFO "VyOS configuration removed successfully"
    else
        ptm_log WARN "Failed to remove VyOS configuration (non-fatal)"
    fi
else
    ptm_log INFO "VyOS not enabled, skipping router cleanup"
fi

VNET_NAME="vn${VLAN_ID}"  # Format: vn<VLAN_ID> (e.g., vn100)

if pvesh get "/cluster/sdn/vnets/${VNET_NAME}" --output-format json &>/dev/null; then
    ptm_log INFO "Removing SDN VNet: $VNET_NAME"

    if [ -n "$SUBNET" ]; then
        subnet_id="${SDN_ZONE_NAME}-$(echo "$SUBNET" | tr '/' '-')"

        ptm_log INFO "Removing SDN subnet: $subnet_id"
        if pvesh delete "/cluster/sdn/vnets/${VNET_NAME}/subnets/${subnet_id}" 2>&1; then
            ptm_log INFO "Subnet deleted successfully"
        else
            ptm_log WARN "Failed to delete subnet (may not exist or already removed)"
        fi
    fi

    pvesh set /cluster/sdn 2>/dev/null || true

    if pvesh delete "/cluster/sdn/vnets/${VNET_NAME}" 2>&1; then
        ptm_log INFO "VNet deleted successfully"
    else
        ptm_log ERROR "Failed to delete VNet (may require manual cleanup)"
    fi

    if pvesh set /cluster/sdn 2>/dev/null; then
        ptm_log INFO "SDN configuration updated"
    else
        ptm_log WARN "Failed to apply SDN config (may need manual reload)"
    fi
else
    ptm_log INFO "VNet $VNET_NAME not found (already deleted or never created)"
fi

USER_ID="${USERNAME:-admin}@pve"
ptm_log INFO "Removing ACL permissions for $USER_ID"

pvesh set /access/acl --delete 1 --path "/pool/${POOL_ID}" --roles "${TENANT_ADMIN_ROLE}" --users "${USER_ID}" 2>/dev/null || ptm_log WARN "Failed to remove pool ACL (may not exist)"
pvesh set /access/acl --delete 1 --path "/pool/${POOL_ID}" --roles "PVEVMAdmin" --users "${USER_ID}" 2>/dev/null || ptm_log WARN "Failed to remove VM admin ACL (may not exist)"

for storage in "local" "local-lvm" "local-zfs"; do
    pvesh set /access/acl --delete 1 --path "/storage/$storage" --roles "PVEDatastoreUser" --users "${USER_ID}" 2>/dev/null || true
done

if [ -n "${VNET_NAME:-}" ]; then
    pvesh set /access/acl --delete 1 --path "/sdn/zones/${SDN_ZONE_NAME}/${VNET_NAME}" --roles "PVESDNUser" --users "${USER_ID}" 2>/dev/null || true
fi

ptm_log INFO "Deleting user: $USER_ID"
pvesh delete "/access/users/${USER_ID}" 2>/dev/null || ptm_log WARN "Failed to delete user"

ptm_log INFO "Deleting user group: $GROUP_NAME"
pvesh delete "/access/groups/${GROUP_NAME}" 2>/dev/null || ptm_log WARN "Failed to delete group"

ptm_log INFO "Deleting resource pool: $POOL_ID"
if pvesh delete "/pools/${POOL_ID}" 2>/dev/null; then
    ptm_log INFO "Resource pool deleted successfully"
else
    ptm_log WARN "Failed to delete resource pool"
fi

ptm_delete_tenant_config "$TENANT_NAME"

if [ -f "/tmp/tenant_${TENANT_NAME}_credentials.json" ]; then
    rm -f "/tmp/tenant_${TENANT_NAME}_credentials.json"
    ptm_log INFO "Deleted old credentials file from /tmp"
fi

CREDENTIALS_DIR="/root/tenctl-credentials"
if [ -d "$CREDENTIALS_DIR" ] && [ -n "$TENANT_NAME" ]; then
    shopt -s nullglob
    found_files=0
    for file in "$CREDENTIALS_DIR"/tenant_"${TENANT_NAME}"_*.json; do
        if [ -f "$file" ]; then
            rm -f "$file"
            ptm_log INFO "Deleted credentials file: $(basename "$file")"
            found_files=$((found_files + 1))
        fi
    done
    shopt -u nullglob

    if [ $found_files -eq 0 ]; then
        ptm_log WARN "No credentials files found for tenant $TENANT_NAME"
    else
        ptm_log INFO "Deleted $found_files credentials file(s) from secure location"
    fi
fi

if [ -n "$TENANT_EMAIL" ]; then
    ptm_send_tenant_removal_email "$TENANT_NAME" "$TENANT_EMAIL" || \
        ptm_log WARN "Failed to send removal email to $TENANT_EMAIL (non-fatal)"
fi

ptm_log INFO "Tenant '$TENANT_NAME' removed successfully!"

exit 0
