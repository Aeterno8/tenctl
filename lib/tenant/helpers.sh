#!/bin/bash

# Check if a tenant exists (based on resource pool)
# Args: tenant_name
# Returns: 0 if exists, 1 if not
ptm_tenant_exists() {
    local tenant_name=$1
    local pool_id="tenant_${tenant_name}"

    # Use --arg to prevent JQ injection vulnerabilities
    pvesh get /pools --output-format json 2>/dev/null | jq -e --arg pid "$pool_id" '.[] | select(.poolid == $pid)' >/dev/null 2>&1
    return $?
}

# Validate and load tenant configuration (common pattern across scripts)
# Args: tenant_name, should_exist (true/false, default true)
# Returns: 0 on success, exits on failure
ptm_validate_and_load_tenant() {
    local tenant_name=$1
    local should_exist="${2:-true}"

    ptm_check_root
    ptm_check_requirements || exit 1

    ptm_validate_tenant_name "$tenant_name" || exit 1

    if [ "$should_exist" = "true" ]; then
        if ! ptm_tenant_exists "$tenant_name"; then
            ptm_log ERROR "Tenant '$tenant_name' does not exist"
            exit 1
        fi

        if ! ptm_load_tenant_config "$tenant_name"; then
            ptm_log ERROR "Failed to load tenant configuration"
            exit 1
        fi
    else
        # For tenant creation (should NOT exist)
        if ptm_tenant_exists "$tenant_name"; then
            ptm_log ERROR "Tenant '$tenant_name' already exists"
            exit 1
        fi
    fi
}

# Update tenant configuration status and other fields
# Args: tenant_name, status, [additional_kv_pairs...]
# Additional args should be in format: "KEY=VALUE"
# Returns: 0 on success, 1 on failure
ptm_update_tenant_status() {
    local tenant_name=$1
    local new_status=$2
    shift 2
    local additional_fields=("$@")

    local tenant_conf="${TENANT_CONFIG_DIR}/${tenant_name}.conf"

    if [ ! -f "$tenant_conf" ]; then
        ptm_log ERROR "Tenant config not found: $tenant_conf"
        return 1
    fi

    cp "$tenant_conf" "${tenant_conf}.backup-$(date +%Y%m%d_%H%M%S)"

    cp "$tenant_conf" "${tenant_conf}.tmp"

    sed -i '/^TENANT_STATUS=/d' "${tenant_conf}.tmp"

    echo "TENANT_STATUS=\"$new_status\"" >> "${tenant_conf}.tmp"

    for field in "${additional_fields[@]}"; do
        local key="${field%%=*}"
        local value="${field#*=}"
        sed -i "/^${key}=/d" "${tenant_conf}.tmp"
        echo "${key}=${value}" >> "${tenant_conf}.tmp"
    done

    mv "${tenant_conf}.tmp" "$tenant_conf"
    chmod 640 "$tenant_conf"
}
