#!/bin/bash

# Save tenant credentials to secure JSON file
# Args: tenant_name, username, password, additional_json (optional)
# Returns: path to created credentials file
ptm_save_tenant_credentials() {
    local tenant_name=$1
    local username=$2
    local password=$3
    local additional_json="${4:-{}}"

    local cred_dir="/root/tenctl-credentials"
    mkdir -p "$cred_dir"
    chmod 700 "$cred_dir"

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local cred_file="${cred_dir}/tenant_${tenant_name}_${timestamp}.json"

    # Build base JSON
    local base_json
    base_json=$(jq -n \
        --arg tenant "$tenant_name" \
        --arg user "$username" \
        --arg pass "$password" \
        --arg created "$(date -Iseconds)" \
        '{
            tenant_name: $tenant,
            username: $user,
            password: $pass,
            created_date: $created
        }')

    # Merge with additional fields if provided
    if [ "$additional_json" != "{}" ]; then
        echo "$base_json" | jq ". + $additional_json" > "$cred_file"
    else
        echo "$base_json" > "$cred_file"
    fi

    chmod 600 "$cred_file"

    echo "$cred_file"
}
