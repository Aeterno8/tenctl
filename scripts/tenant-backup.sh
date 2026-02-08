#!/bin/bash

set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
source "${SCRIPT_DIR}/../lib/common.sh"

ptm_parse_verbosity_flags "$@"

usage() {
    cat << EOF
Usage: $0 -n TENANT_NAME [OPTIONS]

Backup tenant configuration and VM inventory metadata.

IMPORTANT: This backs up tenant CONFIG only, not VM disk images.
For full VM backup, use Proxmox Backup Server or vzdump separately.

Required:
  -n, --name TENANT_NAME      Name of the tenant to backup

Optional:
  -o, --output DIR            Output directory (default: /var/backups/tenctl)
  --verbose                   Increase verbosity (INFO level, use twice for DEBUG)
  -h, --help                  Show this help

Examples:
  $0 -n firma_a
  $0 -n firma_a --output /mnt/backups

Backup Contents:
  - Tenant configuration file
  - VM/Container inventory (IDs, names, resources)
  - Resource pool metadata
  - User and group information
  - Network (VLAN, subnet) configuration
  - Timestamp and checksums

NOT Included (use Proxmox Backup Server):
  - VM disk images
  - VM snapshots
  - Container filesystems

EOF
    exit 1
}

TENANT_NAME=""
BACKUP_DIR="/var/backups/tenctl"

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            TENANT_NAME="$2"
            shift 2
            ;;
        -o|--output)
            BACKUP_DIR="$2"
            shift 2
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
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_SUBDIR="${BACKUP_DIR}/${TENANT_NAME}/${TIMESTAMP}"

mkdir -p "$BACKUP_SUBDIR"
chmod 700 "$BACKUP_SUBDIR"

ptm_log INFO "Tenant Backup"
ptm_log INFO "Tenant: $TENANT_NAME"
ptm_log INFO "Backup location: $BACKUP_SUBDIR"

ptm_log INFO "Backing up tenant configuration..."
TENANT_CONF="${TENANT_CONFIG_DIR}/${TENANT_NAME}.conf"

if [ -f "$TENANT_CONF" ]; then
    cp "$TENANT_CONF" "${BACKUP_SUBDIR}/tenant.conf"
    ptm_log INFO "✓ Tenant config backed up"
else
    ptm_log ERROR "Tenant config file not found: $TENANT_CONF"
    exit 1
fi

ptm_log INFO "Backing up VM inventory..."

VM_LIST=$(ptm_get_pool_vm_list "$POOL_ID")
VM_COUNT=0

VM_INVENTORY="["

for vmid in $VM_LIST; do
    VM_DATA=$(ptm_get_vm_metadata "$vmid")

    if [ "$VM_DATA" = "{}" ]; then
        continue
    fi

    [ $VM_COUNT -gt 0 ] && VM_INVENTORY+=","
    VM_INVENTORY+="$VM_DATA"
    VM_COUNT=$((VM_COUNT + 1))
done

VM_INVENTORY+="]"

echo "$VM_INVENTORY" | jq '.' > "${BACKUP_SUBDIR}/vm-inventory.json"
ptm_log INFO "✓ VM inventory backed up ($VM_COUNT VMs)"

ptm_log INFO "Backing up resource pool metadata..."

POOL_DATA=$(pvesh get "/pools/${POOL_ID}" --output-format json 2>/dev/null || echo "{}")
echo "$POOL_DATA" | jq '.' > "${BACKUP_SUBDIR}/pool-metadata.json"
ptm_log INFO "✓ Pool metadata backed up"

ptm_log INFO "Backing up user and group information..."

USER_DATA=$(pvesh get "/access/users/${USERNAME}@pve" --output-format json 2>/dev/null || echo "{}")
echo "$USER_DATA" | jq '.' > "${BACKUP_SUBDIR}/user-info.json"

GROUP_DATA=$(pvesh get "/access/groups/${GROUP_NAME}" --output-format json 2>/dev/null || echo "{}")
echo "$GROUP_DATA" | jq '.' > "${BACKUP_SUBDIR}/group-info.json"

ptm_log INFO "✓ User/group info backed up"

ptm_log INFO "Backing up network configuration..."

if [ -n "${VNET_NAME:-}" ]; then
    VNET_DATA=$(pvesh get "/cluster/sdn/vnets/${VNET_NAME}" --output-format json 2>/dev/null || echo "{}")
    echo "$VNET_DATA" | jq '.' > "${BACKUP_SUBDIR}/vnet-config.json"
    ptm_log INFO "✓ VNet config backed up"
fi

ptm_log INFO "Creating backup manifest..."

cat > "${BACKUP_SUBDIR}/manifest.json" <<EOF
{
  "tenant_name": "$TENANT_NAME",
  "backup_timestamp": "$(date -Iseconds)",
  "backup_version": "1.0",
  "tenant_status": "${TENANT_STATUS:-ACTIVE}",
  "vm_count": $VM_COUNT,
  "pool_id": "$POOL_ID",
  "vlan_id": ${VLAN_ID:-null},
  "subnet": "${SUBNET:-null}",
  "vnet_name": "${VNET_NAME:-null}",
  "user": "${USERNAME}@pve",
  "group": "$GROUP_NAME",
  "cpu_limit": $CPU_LIMIT,
  "ram_limit": $RAM_LIMIT,
  "storage_limit": $STORAGE_LIMIT
}
EOF

ptm_log INFO "✓ Manifest created"

ptm_log INFO "Generating checksums..."
(cd "$BACKUP_SUBDIR" && sha256sum * > checksums.txt)
ptm_log INFO "✓ Checksums generated"

ptm_log INFO "Creating compressed archive..."
ARCHIVE_NAME="${TENANT_NAME}_${TIMESTAMP}.tar.gz"
ARCHIVE_PATH="${BACKUP_DIR}/${ARCHIVE_NAME}"

tar -czf "$ARCHIVE_PATH" -C "${BACKUP_DIR}/${TENANT_NAME}" "$TIMESTAMP"
ARCHIVE_SIZE=$(du -h "$ARCHIVE_PATH" | cut -f1)

ptm_log INFO "✓ Archive created: $ARCHIVE_PATH ($ARCHIVE_SIZE)"

ptm_log INFO "Backup Complete!"
ptm_log INFO "Tenant: $TENANT_NAME"
ptm_log INFO "VMs backed up: $VM_COUNT"
ptm_log INFO "Archive: $ARCHIVE_PATH"
ptm_log INFO "Size: $ARCHIVE_SIZE"
ptm_log INFO "Backup Contents:"
ptm_log INFO "  ✓ Tenant configuration"
ptm_log INFO "  ✓ VM inventory metadata"
ptm_log INFO "  ✓ Resource pool metadata"
ptm_log INFO "  ✓ User/group information"
ptm_log INFO "  ✓ Network configuration"
ptm_log WARN "NOTE: VM disk images are NOT included in this backup"
ptm_log INFO "For full VM backup, use:"
ptm_log INFO "  vzdump <vmid> --storage <backup-storage>"
ptm_log INFO "  or Proxmox Backup Server"
ptm_log INFO "To restore this backup:"
ptm_log INFO "  tenctl restore --file $ARCHIVE_PATH"

exit 0
