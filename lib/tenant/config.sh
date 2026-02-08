#!/bin/bash
# Tenant configuration management (save, load, delete, list)

# Save tenant configuration to file
# Args: tenant_name, vlan_id, subnet, cpu_limit, ram_limit, storage_limit, [username]
# Returns: 0 on success, 1 on failure
ptm_save_tenant_config() {
    local tenant_name=$1
    local vlan_id=$2
    local subnet=$3
    local cpu_limit=$4
    local ram_limit=$5
    local storage_limit=$6
    local username="${7:-admin}"

    # Create config directory
    if [ ! -d "$TENANT_CONFIG_DIR" ]; then
        mkdir -p "$TENANT_CONFIG_DIR"
        chmod 750 "$TENANT_CONFIG_DIR"
    fi

    local config_file="${TENANT_CONFIG_DIR}/${tenant_name}.conf"

    (umask 027; cat > "${config_file}" <<EOF
TENANT_NAME="$tenant_name"
VLAN_ID=$vlan_id
SUBNET="$subnet"
CPU_LIMIT=$cpu_limit
RAM_LIMIT=$ram_limit
STORAGE_LIMIT=$storage_limit
USERNAME="$username"
POOL_ID="tenant_${tenant_name}"
GROUP_NAME="group_${tenant_name}"
CREATED_DATE="$(date '+%Y-%m-%d %H:%M:%S')"
EOF
)

    if [ ! -f "${config_file}" ]; then
        ptm_log ERROR "Failed to save tenant configuration"
        return 1
    fi

    ptm_log INFO "Tenant configuration saved to ${config_file}"
    return 0
}

# Load tenant configuration from file
# Args: tenant_name
# Returns: 0 on success, 1 on failure
ptm_load_tenant_config() {
    local tenant_name=$1
    local config_file="${TENANT_CONFIG_DIR}/${tenant_name}.conf"

    if [ ! -f "$config_file" ]; then
        ptm_log ERROR "Tenant configuration not found: $config_file"
        return 1
    fi

    # Validate file permissions
    local perms=$(stat -c "%a" "$config_file" 2>/dev/null || echo "777")
    local perms_decimal=$((8#$perms))
    local max_perms_decimal=$((8#640))
    if [ "$perms_decimal" -gt "$max_perms_decimal" ]; then
        ptm_log ERROR "Config file has insecure permissions: $perms (should be 640 or stricter)"
        ptm_log ERROR "Run: chmod 640 $config_file"
        return 1
    fi

    # Check for dangerous shell patterns
    if grep -qE '(\$\(|`|;|&&|\||>|>>|<|eval|exec|rm |mv |cp |chmod |chown |source )' "$config_file"; then
        ptm_log ERROR "Config file contains potentially dangerous shell commands"
        ptm_log ERROR "Config files should only contain variable assignments (VAR=\"value\")"
        local dangerous_line=$(grep -E '(\$\(|`|;|&&|\||>|>>|<|eval|exec|rm |mv |cp |chmod |chown |source )' "$config_file" | head -n1)
        ptm_log ERROR "Found: $dangerous_line"
        return 1
    fi

    # Whitelist validation
    if grep -vE '^[A-Z_]+=(\"[^\"]*\"|[0-9]+)$|^#|^[[:space:]]*$' "$config_file" | grep -q .; then
        ptm_log ERROR "Config file contains lines that are not simple variable assignments"
        local invalid_line=$(grep -vE '^[A-Z_]+=(\"[^\"]*\"|[0-9]+)$|^#|^[[:space:]]*$' "$config_file" | head -n1)
        ptm_log ERROR "Invalid line: $invalid_line"
        return 1
    fi

    if ! ( source "$config_file" ) &>/dev/null; then
        ptm_log ERROR "Config file has syntax errors"
        return 1
    fi

    source "$config_file"
    return 0
}

# Delete tenant configuration file
# Args: tenant_name
# Returns: 0 if deleted, 1 if not found
ptm_delete_tenant_config() {
    local tenant_name=$1
    local config_file="${TENANT_CONFIG_DIR}/${tenant_name}.conf"

    if [ -f "$config_file" ]; then
        rm -f "$config_file"
        ptm_log INFO "Tenant configuration deleted"
        return 0
    fi
    return 1
}

# List all tenants (based on config files)
# Returns: List of tenant names (one per line)
ptm_list_all_tenants() {
    if [ ! -d "$TENANT_CONFIG_DIR" ]; then
        echo "[]"
        return 0
    fi

    shopt -s nullglob
    for config in "$TENANT_CONFIG_DIR"/*.conf; do
        basename "$config" .conf
    done
    shopt -u nullglob
}
