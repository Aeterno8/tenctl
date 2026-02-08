#!/bin/bash

ptm_validate_numeric_param() {
    local param_name=$1
    local param_value=$2
    local min=${3:-1}
    local max=${4:-999999}

    if ! [[ "$param_value" =~ ^[0-9]+$ ]]; then
        ptm_log ERROR "$param_name must be a positive integer: got '$param_value'"
        return 1
    fi

    if [ "$param_value" -lt "$min" ] || [ "$param_value" -gt "$max" ]; then
        ptm_log ERROR "$param_name out of range [$min-$max]: got '$param_value'"
        return 1
    fi

    return 0
}

ptm_validate_tenant_name() {
    local name=$1

    ptm_log DEBUG "Validating tenant name: $name"

    if [ ${#name} -eq 0 ] || [ ${#name} -gt $TENANT_NAME_MAX_LENGTH ]; then
        ptm_log ERROR "Tenant name length must be 1-$TENANT_NAME_MAX_LENGTH characters"
        return 1
    fi

    if [[ ! "$name" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
        ptm_log ERROR "Tenant name must start with letter, contain only alphanumeric/underscore"
        return 1
    fi

    local reserved=("root" "admin" "system" "test" "tmp" "default" "pool" "user" "group")
    for keyword in "${reserved[@]}"; do
        if [[ "${name,,}" == "${keyword}" ]]; then
            ptm_log ERROR "Tenant name '$name' is reserved"
            return 1
        fi
    done

    return 0
}

ptm_validate_username() {
    local username=$1

    if [ -z "$username" ]; then
        ptm_log ERROR "Username cannot be empty"
        return 1
    fi

    if [ ${#username} -lt 2 ] || [ ${#username} -gt 25 ]; then
        ptm_log ERROR "Username length must be 2-25 characters"
        return 1
    fi

    if [[ ! "$username" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
        ptm_log ERROR "Username must start with alphanumeric, contain only alphanumeric, underscore, hyphen, or dot"
        return 1
    fi

    local reserved=("root" "pam" "backup")
    for keyword in "${reserved[@]}"; do
        if [[ "${username,,}" == "${keyword}" ]]; then
            ptm_log ERROR "Username '$username' is reserved"
            return 1
        fi
    done

    return 0
}

ptm_validate_email() {
    local email=$1
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        ptm_log ERROR "Invalid email address format: $email"
        return 1
    fi
    return 0
}

ptm_validate_vlan_id() {
    local vlan=$1

    ptm_log DEBUG "Validating VLAN ID: $vlan"

    if ! [[ "$vlan" =~ ^[0-9]+$ ]]; then
        ptm_log ERROR "VLAN ID must be numeric: $vlan"
        return 1
    fi

    if [ "$vlan" -lt 1 ] || [ "$vlan" -gt 4094 ] || [ "$vlan" -eq 4095 ]; then
        ptm_log ERROR "VLAN ID must be in range 1-4094 (excluding 4095): $vlan"
        return 1
    fi

    local lockfile="$PMTM_VLAN_LOCK"
    mkdir -p "$(dirname "$lockfile")"

    (
        flock -x 200
        local used_vlans
        used_vlans=$(pvesh get /cluster/sdn/vnets --output-format json 2>/dev/null | jq -r '.[].tag // empty' | sort -n)

        if echo "$used_vlans" | grep -q "^${vlan}$"; then
            ptm_log ERROR "VLAN ID already in use: $vlan"
            return 1
        fi

        return 0
    ) 200>"$lockfile"

    return $?
}

ptm_validate_subnet() {
    local subnet=$1

    ptm_log DEBUG "Validating subnet: $subnet"

    if ! [[ "$subnet" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.0/24$ ]]; then
        ptm_log ERROR "Subnet must be in format X.Y.Z.0/24: $subnet"
        return 1
    fi

    local oct1="${BASH_REMATCH[1]}"
    local oct2="${BASH_REMATCH[2]}"
    local oct3="${BASH_REMATCH[3]}"

    if [ "$oct1" -gt 255 ] || [ "$oct2" -gt 255 ] || [ "$oct3" -gt 255 ]; then
        ptm_log ERROR "Invalid IP octets in subnet (must be 0-255): $subnet"
        return 1
    fi

    local lockfile="$PMTM_SUBNET_LOCK"
    mkdir -p "$(dirname "$lockfile")"

    (
        flock -x 200
        local used_subnets
        used_subnets=$(pvesh get /cluster/sdn/vnets --output-format json 2>/dev/null | \
            jq -r '.[].subnets[]?.subnet // empty' | sort)

        if echo "$used_subnets" | grep -q "^${subnet}$"; then
            ptm_log ERROR "Subnet already in use: $subnet"
            return 1
        fi

        return 0
    ) 200>"$lockfile"

    return $?
}
