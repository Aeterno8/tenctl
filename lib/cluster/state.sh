#!/bin/bash

# Cluster state file (shared via pmxcfs)
CLUSTER_STATE_FILE="/etc/pve/tenctl-cluster.json"

ptm_get_cluster_nodes() {
    if ! command -v pvesh &>/dev/null; then
        echo "$(hostname)"
        return 0
    fi

    pvesh get /nodes --output-format json 2>/dev/null | \
        jq -r '.[].node' 2>/dev/null || echo "$(hostname)"
}

ptm_get_online_nodes() {
    if ! command -v pvesh &>/dev/null; then
        echo "$(hostname)"
        return 0
    fi

    pvesh get /nodes --output-format json 2>/dev/null | \
        jq -r '.[] | select(.status == "online") | .node' 2>/dev/null || echo "$(hostname)"
}

ptm_init_cluster_state() {
    local version="${1:-unknown}"
    local current_node="$(hostname)"

    if [ ! -d "/etc/pve" ]; then
        mkdir -p "/etc/pve" 2>/dev/null || true
    fi

    # Create initial state
    cat > "$CLUSTER_STATE_FILE" <<EOF
{
  "version": "$version",
  "updated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "updated_by": "$current_node",
  "nodes": {
    "$current_node": {
      "version": "$version",
      "status": "ok",
      "updated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    }
  }
}
EOF
}

ptm_get_cluster_version() {
    if [ ! -f "$CLUSTER_STATE_FILE" ]; then
        echo "unknown"
        return 0
    fi

    jq -r '.version // "unknown"' "$CLUSTER_STATE_FILE" 2>/dev/null || echo "unknown"
}

ptm_get_node_version() {
    local node="$1"

    if [ ! -f "$CLUSTER_STATE_FILE" ]; then
        echo "unknown"
        return 0
    fi

    jq -r ".nodes.\"$node\".version // \"unknown\"" "$CLUSTER_STATE_FILE" 2>/dev/null || echo "unknown"
}

ptm_get_node_status() {
    local node="$1"

    if [ ! -f "$CLUSTER_STATE_FILE" ]; then
        echo "unknown"
        return 0
    fi

    jq -r ".nodes.\"$node\".status // \"unknown\"" "$CLUSTER_STATE_FILE" 2>/dev/null || echo "unknown"
}

ptm_set_cluster_version() {
    local version="$1"
    local current_node="$(hostname)"

    if [ ! -f "$CLUSTER_STATE_FILE" ]; then
        ptm_init_cluster_state "$version"
        return 0
    fi

    local temp_file=$(mktemp)
    jq --arg version "$version" \
       --arg updated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       --arg updated_by "$current_node" \
       '.version = $version | .updated_at = $updated_at | .updated_by = $updated_by' \
       "$CLUSTER_STATE_FILE" > "$temp_file" 2>/dev/null

    if [ $? -eq 0 ]; then
        # Use cat instead of mv to avoid pmxcfs permission issues
        cat "$temp_file" > "$CLUSTER_STATE_FILE" && rm -f "$temp_file"
    else
        rm -f "$temp_file"
        return 1
    fi
}

ptm_set_node_version() {
    local node="$1"
    local version="$2"
    local status="${3:-ok}"

    if [ ! -f "$CLUSTER_STATE_FILE" ]; then
        ptm_init_cluster_state "$version"
        return 0
    fi

    local temp_file=$(mktemp)
    jq --arg node "$node" \
       --arg version "$version" \
       --arg status "$status" \
       --arg updated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.nodes[$node] = {
           "version": $version,
           "status": $status,
           "updated_at": $updated_at
       }' \
       "$CLUSTER_STATE_FILE" > "$temp_file" 2>/dev/null

    if [ $? -eq 0 ]; then
        # Use cat instead of mv to avoid pmxcfs permission issues
        cat "$temp_file" > "$CLUSTER_STATE_FILE" && rm -f "$temp_file"
    else
        rm -f "$temp_file"
        return 1
    fi
}

ptm_version_lt() {
    local v1="$1"
    local v2="$2"

    if [ "$v1" = "unknown" ] || [ "$v2" = "unknown" ]; then
        return 1
    fi

    if [ "$v1" = "$v2" ]; then
        return 1
    fi

    local sorted=$(printf "%s\n%s" "$v1" "$v2" | sort -V | head -n1)
    [ "$sorted" = "$v1" ]
}

# Check version consistency between local and cluster
# Returns: 0 = consistent, 1 = local behind, 2 = local ahead, 3 = error
ptm_check_version_consistency() {
    local local_version="$1"
    local cluster_version=$(ptm_get_cluster_version)

    if [ "$cluster_version" = "unknown" ]; then
        return 0
    fi

    if [ "$local_version" = "$cluster_version" ]; then
        return 0
    fi

    if ptm_version_lt "$local_version" "$cluster_version"; then
        return 1  # Local behind
    else
        return 2  # Local ahead
    fi
}

# Display warning if version is inconsistent
ptm_warn_version_mismatch() {
    local local_version="$1"
    local cluster_version=$(ptm_get_cluster_version)
    local current_node="$(hostname)"

    if [ "$cluster_version" = "unknown" ]; then
        return 0
    fi

    ptm_check_version_consistency "$local_version"
    local status=$?

    case $status in
        0)
            # Consistent, no warning
            return 0
            ;;
        1)
            # Local behind
            echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
            echo -e "${YELLOW}⚠  VERSION MISMATCH WARNING${NC}" >&2
            echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
            echo -e "${YELLOW}This node ($current_node) is running version ${local_version}${NC}" >&2
            echo -e "${YELLOW}Cluster expects version ${cluster_version}${NC}" >&2
            echo "" >&2
            echo -e "${YELLOW}Run: ${NC}${GREEN}tenctl update-cli${NC}${YELLOW} to update this node${NC}" >&2
            echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
            echo "" >&2
            return 0
            ;;
        2)
            ptm_set_cluster_version "$local_version"
            ptm_set_node_version "$current_node" "$local_version" "ok"
            return 0
            ;;
        *)
            return 0
            ;;
    esac
}

ptm_get_cluster_status() {
    if [ ! -f "$CLUSTER_STATE_FILE" ]; then
        echo "No cluster state file found"
        return 1
    fi

    local cluster_version=$(jq -r '.version' "$CLUSTER_STATE_FILE" 2>/dev/null)
    local updated_at=$(jq -r '.updated_at' "$CLUSTER_STATE_FILE" 2>/dev/null)
    local updated_by=$(jq -r '.updated_by' "$CLUSTER_STATE_FILE" 2>/dev/null)

    echo "Cluster Version: $cluster_version"
    echo "Last Updated: $updated_at by $updated_by"
    echo ""
    echo "Node Status:"

    local nodes=$(jq -r '.nodes | keys[]' "$CLUSTER_STATE_FILE" 2>/dev/null)

    for node in $nodes; do
        local node_version=$(jq -r ".nodes.\"$node\".version" "$CLUSTER_STATE_FILE" 2>/dev/null)
        local node_status=$(jq -r ".nodes.\"$node\".status" "$CLUSTER_STATE_FILE" 2>/dev/null)
        local node_updated=$(jq -r ".nodes.\"$node\".updated_at" "$CLUSTER_STATE_FILE" 2>/dev/null)

        local indicator="?"
        local color="$NC"
        case "$node_status" in
            ok)
                if [ "$node_version" = "$cluster_version" ]; then
                    indicator="✓"
                    color="$GREEN"
                else
                    indicator="⚠"
                    color="$YELLOW"
                fi
                ;;
            pending)
                indicator="⏳"
                color="$YELLOW"
                ;;
            failed)
                indicator="✗"
                color="$RED"
                ;;
            *)
                indicator="?"
                color="$YELLOW"
                ;;
        esac

        printf "  %-10s : %s %-8s %s(%s)%s - %s\n" \
            "$node" \
            "$color" \
            "$node_version" \
            "$indicator" \
            "$node_status" \
            "$NC" \
            "$node_updated"
    done
}
