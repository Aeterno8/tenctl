#!/bin/bash

ptm_check_root() {
    if [ "$EUID" -ne 0 ]; then
        ptm_log ERROR "This script must be run as root"
        exit 1
    fi
}

ptm_check_pvesh() {
    if ! command -v pvesh &> /dev/null; then
        ptm_log ERROR "pvesh command not found. Are you running this on a Proxmox node?"
        exit 1
    fi
}

ptm_check_requirements() {
    local missing_deps=()

    command -v pvesh >/dev/null 2>&1 || missing_deps+=("pvesh")
    command -v jq >/dev/null 2>&1 || missing_deps+=("jq")
    command -v flock >/dev/null 2>&1 || missing_deps+=("flock")

    if [ ${#missing_deps[@]} -gt 0 ]; then
        ptm_log ERROR "Missing required dependencies: ${missing_deps[*]}"
        ptm_log ERROR "Install with: apt-get install ${missing_deps[*]}"
        return 1
    fi

    return 0
}
