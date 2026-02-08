#!/bin/bash

ptm_get_next_vlan() {
    local lockfile="$PMTM_VLAN_LOCK"
    mkdir -p "$(dirname "$lockfile")"

    ptm_log DEBUG "Acquiring VLAN allocation lock"

    (
        # exclusive lock
        flock -x 200
        ptm_log DEBUG "VLAN lock acquired, scanning for available VLAN in range $VLAN_START-$VLAN_END"

        declare -A used_vlans
        while IFS= read -r vlan; do
            [ -n "$vlan" ] && used_vlans[$vlan]=1
        done < <(pvesh get /cluster/sdn/vnets --output-format json 2>/dev/null | jq -r '.[].tag // empty')

        for vlan in $(seq "$VLAN_START" "$VLAN_END"); do
            if [ -z "${used_vlans[$vlan]:-}" ]; then
                ptm_log DEBUG "Allocated VLAN: $vlan"
                echo "$vlan"
                return 0
            fi
        done

        ptm_log ERROR "No available VLAN IDs in range $VLAN_START-$VLAN_END"
        return 1
    ) 200>"$lockfile"
}

ptm_get_next_subnet() {
    local lockfile="$PMTM_SUBNET_LOCK"
    mkdir -p "$(dirname "$lockfile")"

    ptm_log DEBUG "Acquiring subnet allocation lock"

    (
        # exclusive lock
        flock -x 200
        ptm_log DEBUG "Subnet lock acquired, scanning for available subnet in ${BASE_SUBNET}.0.0/16"

        declare -A used_octets

        while IFS= read -r subnet; do
            if [[ "$subnet" =~ ^${BASE_SUBNET}\.([0-9]+)\.0/24$ ]]; then
                used_octets[${BASH_REMATCH[1]}]=1
            fi
        done < <(pvesh get /cluster/sdn/vnets --output-format json 2>/dev/null | jq -r '.[].subnets[]?.subnet // empty')


        if [ -f /etc/pve/sdn/subnets.cfg ]; then
            while IFS= read -r line; do
                # Match lines like: tenants-10.100.1.0-24
                if [[ "$line" =~ ^subnet:[[:space:]]+${SDN_ZONE_NAME}-${BASE_SUBNET//./\\.}\.([0-9]+)\.0-24 ]]; then
                    used_octets[${BASH_REMATCH[1]}]=1
                fi
            done < /etc/pve/sdn/subnets.cfg
        fi

        if [ -d "$TENANT_CONFIG_DIR" ]; then
            while IFS= read -r subnet; do
                if [[ "$subnet" =~ ^${BASE_SUBNET}\.([0-9]+)\.0/24$ ]]; then
                    used_octets[${BASH_REMATCH[1]}]=1
                fi
            done < <(grep -h "^SUBNET=" "$TENANT_CONFIG_DIR"/*.conf 2>/dev/null | cut -d'"' -f2)
        fi

        # Find first available subnet
        for subnet_third_octet in $(seq 0 255); do
            if [ -z "${used_octets[$subnet_third_octet]:-}" ]; then
                local allocated_subnet="${BASE_SUBNET}.${subnet_third_octet}.0/24"
                ptm_log DEBUG "Allocated subnet: $allocated_subnet"
                echo "$allocated_subnet"
                return 0
            fi
        done

        ptm_log ERROR "No available subnets in range ${BASE_SUBNET}.0.0/16"
        return 1
    ) 200>"$lockfile"
}

# Atomically allocate VLAN and create VNet
# Returns: "VLAN_ID:VNET_NAME" on success, exits with error on failure
ptm_allocate_and_create_vnet() {
    local tenant_name=$1
    local zone=$2
    local lockfile="$PMTM_VLAN_LOCK"
    mkdir -p "$(dirname "$lockfile")"

    (
        flock -x 200

        declare -A used_vlans
        while IFS= read -r vlan; do
            [ -n "$vlan" ] && used_vlans[$vlan]=1
        done < <(pvesh get /cluster/sdn/vnets --output-format json 2>/dev/null | jq -r '.[].tag // empty')

        local vlan_id=""
        for vlan in $(seq "$VLAN_START" "$VLAN_END"); do
            if [ -z "${used_vlans[$vlan]:-}" ]; then
                vlan_id=$vlan
                break
            fi
        done

        if [ -z "$vlan_id" ]; then
            ptm_log ERROR "No available VLAN IDs in range $VLAN_START-$VLAN_END"
            return 1
        fi

        local vnet_name="vn${vlan_id}"

        if pvesh create /cluster/sdn/vnets \
            --vnet "$vnet_name" \
            --zone "$zone" \
            --tag "$vlan_id" \
            --alias "Network for ${tenant_name}" 2>/dev/null; then
            echo "${vlan_id}:${vnet_name}"
            return 0
        else
            ptm_log ERROR "Failed to create VNet: $vnet_name with VLAN $vlan_id"
            return 1
        fi
    ) 200>"$lockfile"
}

# Atomically allocate subnet and create it in VNet
# Returns: SUBNET on success, exits with error on failure
ptm_allocate_and_create_subnet() {
    local vnet_name=$1
    local lockfile="$PMTM_SUBNET_LOCK"
    mkdir -p "$(dirname "$lockfile")"

    (
        flock -x 200

        declare -A used_octets

        while IFS= read -r subnet; do
            if [[ "$subnet" =~ ^${BASE_SUBNET}\.([0-9]+)\.0/24$ ]]; then
                used_octets[${BASH_REMATCH[1]}]=1
            fi
        done < <(pvesh get /cluster/sdn/vnets --output-format json 2>/dev/null | jq -r '.[].subnets[]?.subnet // empty')

        if [ -f /etc/pve/sdn/subnets.cfg ]; then
            while IFS= read -r line; do
                if [[ "$line" =~ ^subnet:[[:space:]]+${SDN_ZONE_NAME}-${BASE_SUBNET//./\\.}\.([0-9]+)\.0-24 ]]; then
                    used_octets[${BASH_REMATCH[1]}]=1
                fi
            done < /etc/pve/sdn/subnets.cfg
        fi

        if [ -d "$TENANT_CONFIG_DIR" ]; then
            while IFS= read -r subnet; do
                if [[ "$subnet" =~ ^${BASE_SUBNET}\.([0-9]+)\.0/24$ ]]; then
                    used_octets[${BASH_REMATCH[1]}]=1
                fi
            done < <(grep -h "^SUBNET=" "$TENANT_CONFIG_DIR"/*.conf 2>/dev/null | cut -d'"' -f2)
        fi

        local subnet=""
        for subnet_third_octet in $(seq 0 255); do
            if [ -z "${used_octets[$subnet_third_octet]:-}" ]; then
                subnet="${BASE_SUBNET}.${subnet_third_octet}.0/24"
                break
            fi
        done

        if [ -z "$subnet" ]; then
            ptm_log ERROR "No available subnets in range ${BASE_SUBNET}.0.0/16"
            return 1
        fi

        if pvesh create "/cluster/sdn/vnets/${vnet_name}/subnets" \
            --subnet "$subnet" \
            --type subnet 2>&1; then
            echo "$subnet"
            return 0
        else
            ptm_log ERROR "Failed to create subnet: $subnet in VNet $vnet_name"
            return 1
        fi
    ) 200>"$lockfile"
}
