#!/bin/bash

# Create user group
# Args: group_name, comment
# Returns: 0 on success, 1 on failure
ptm_create_user_group() {
    local group_name=$1
    local comment=$2

    ptm_log INFO "Creating user group: $group_name"

    local output
    output=$(pvesh create /access/groups --groupid "${group_name}" --comment "${comment}" 2>&1)
    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        ptm_log INFO "User group created successfully"
        return 0
    elif echo "$output" | grep -q "already exists"; then
        ptm_log INFO "User group already exists, continuing"
        return 0
    else
        ptm_log ERROR "Failed to create user group: $output"
        return 1
    fi
}

# Create user
# Args: username, password, groups, email
# Returns: 0 on success, 1 on failure
ptm_create_user() {
    local username=$1
    local password=$2
    local groups=$3
    local email=$4

    ptm_log INFO "Creating user: ${username}@pve"
    ptm_log DEBUG "User groups: $groups, Email: $email"

    if pvesh create /access/users --userid "${username}@pve" --password "${password}" --groups "${groups}" --email "${email}" 2>/dev/null; then
        ptm_log INFO "User created successfully"
        return 0
    else
        ptm_log ERROR "Failed to create user"
        return 1
    fi
}
