#!/bin/bash

# Check if VyOS is configured and reachable
ptm_check_vyos_configured() {
    if [ -z "${VYOS_ENABLED:-}" ] || [ "$VYOS_ENABLED" != "true" ]; then
        return 1
    fi
    
    if [ -z "${VYOS_NODE:-}" ] || [ -z "${VYOS_VMID:-}" ] || [ -z "${VYOS_SSH_USER:-}" ]; then
        ptm_log ERROR "VyOS configuration incomplete. Required: VYOS_NODE, VYOS_VMID, VYOS_SSH_USER"
        return 1
    fi
    
    return 0
}

ptm_get_vyos_ip() {
    local node="$1"
    local vmid="$2"
    
    # Try to get IP from QEMU guest agent
    local ip
    ip=$(ssh "root@${node}.lan" "qm guest cmd $vmid network-get-interfaces 2>/dev/null | jq -r '.[] | select(.name==\"eth0\") | .[\"ip-addresses\"][] | select(.\"ip-address-type\"==\"ipv4\") | .\"ip-address\"' 2>/dev/null | head -1")
    
    if [ -z "$ip" ]; then
        # Fallback
        ip="${VYOS_IP:-}"
    fi
    
    echo "$ip"
}

# Execute VyOS command via SSH
ptm_vyos_exec() {
    local cmd="$1"
    local node="${VYOS_NODE}"
    local vmid="${VYOS_VMID}"
    local user="${VYOS_SSH_USER}"
    local ip
    
    ip=$(ptm_get_vyos_ip "$node" "$vmid")
    
    if [ -z "$ip" ]; then
        ptm_log ERROR "Cannot determine VyOS IP address"
        return 1
    fi
    
    # Create a VyOS script that sources the proper environment
    local tmpfile="/tmp/vyos-cmd-$$.sh"
    cat > "$tmpfile" << 'EOFVYOS'
#!/bin/vbash
source /opt/vyatta/etc/functions/script-template
EOFVYOS
    echo "$cmd" >> "$tmpfile"
    
    scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$tmpfile" "${user}@${ip}:/tmp/vyos-exec-$$.sh" 2>/dev/null
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${user}@${ip}" "sudo chmod +x /tmp/vyos-exec-$$.sh && sudo /tmp/vyos-exec-$$.sh && rm -f /tmp/vyos-exec-$$.sh" 2>&1
    local result=$?
    
    rm -f "$tmpfile"
    return $result
}

# Configure VyOS for new tenant
ptm_configure_vyos_tenant() {
    local tenant_name="$1"
    local vlan_id="$2"
    local subnet="$3"
    local gateway="$4"
    
    if ! ptm_check_vyos_configured; then
        ptm_log WARN "VyOS not configured, skipping router configuration"
        return 0
    fi
    
    ptm_log INFO "Configuring VyOS router for tenant $tenant_name (VLAN $vlan_id, subnet $subnet)"
    
    local interface="${VYOS_LAN_INTERFACE:-eth1}"
    local vlan_interface="${interface}.${vlan_id}"
    
    local config_commands="
configure
set interfaces ethernet ${interface} vif ${vlan_id} description 'Tenant ${tenant_name}'
set interfaces ethernet ${interface} vif ${vlan_id} address '${gateway}/24'
set nat source rule $((vlan_id * 10)) outbound-interface name '${VYOS_WAN_INTERFACE:-eth0}'
set nat source rule $((vlan_id * 10)) source address '${subnet}.0/24'
set nat source rule $((vlan_id * 10)) translation address masquerade
commit
save
exit
"
    
    if ptm_vyos_exec "$config_commands"; then
        ptm_log INFO "VyOS configuration successful for tenant $tenant_name"
        return 0
    else
        ptm_log ERROR "Failed to configure VyOS for tenant $tenant_name"
        return 1
    fi
}

# Remove VyOS configuration for tenant
ptm_remove_vyos_tenant() {
    local tenant_name="$1"
    local vlan_id="$2"
    
    if ! ptm_check_vyos_configured; then
        ptm_log WARN "VyOS not configured, skipping router cleanup"
        return 0
    fi
    
    ptm_log INFO "Removing VyOS configuration for tenant $tenant_name (VLAN $vlan_id)"
    
    local interface="${VYOS_LAN_INTERFACE:-eth1}"
    
    local cleanup_commands="
configure
delete interfaces ethernet ${interface} vif ${vlan_id}
delete nat source rule $((vlan_id * 10))
commit
save
exit
"
    
    if ptm_vyos_exec "$cleanup_commands"; then
        ptm_log INFO "VyOS cleanup successful for tenant $tenant_name"
        return 0
    else
        ptm_log WARN "Failed to remove VyOS configuration for tenant $tenant_name"
        return 1
    fi
}

# Initialize VyOS router with base configuration
ptm_initialize_vyos() {
    local node="${VYOS_NODE}"
    local vmid="${VYOS_VMID}"
    local wan_interface="${VYOS_WAN_INTERFACE:-eth0}"
    local lan_interface="${VYOS_LAN_INTERFACE:-eth1}"
    local wan_ip="${VYOS_WAN_IP}"
    local wan_gateway="${VYOS_WAN_GATEWAY}"
    
    if ! ptm_check_vyos_configured; then
        ptm_log ERROR "VyOS configuration incomplete"
        return 1
    fi
    
    ptm_log INFO "Initializing VyOS router on node $node (VM $vmid)"
    
    local init_commands="
configure
set interfaces ethernet ${wan_interface} address '${wan_ip}/24'
set protocols static route 0.0.0.0/0 next-hop '${wan_gateway}'
set system name-server '8.8.8.8'
set system name-server '8.8.4.4'
set interfaces ethernet ${lan_interface} description 'Tenant Networks'
set nat source rule 1 outbound-interface name '${wan_interface}'
set nat source rule 1 source address '${BASE_SUBNET}.0.0/16'
set nat source rule 1 translation address masquerade
commit
save
exit
"
    
    if ptm_vyos_exec "$init_commands"; then
        ptm_log INFO "VyOS initialization successful"
        return 0
    else
        ptm_log ERROR "Failed to initialize VyOS"
        return 1
    fi
}

# Test VyOS connectivity
ptm_test_vyos_connection() {
    if ! ptm_check_vyos_configured; then
        echo "VyOS not configured"
        return 1
    fi
    
    local node="${VYOS_NODE}"
    local vmid="${VYOS_VMID}"
    local ip
    
    ip=$(ptm_get_vyos_ip "$node" "$vmid")
    
    if [ -z "$ip" ]; then
        echo "Cannot determine VyOS IP"
        return 1
    fi
    
    echo "VyOS IP: $ip"
    
    if ptm_vyos_exec "show version" >/dev/null 2>&1; then
        echo "VyOS connection successful"
        return 0
    else
        echo "Cannot connect to VyOS"
        return 1
    fi
}
