#!/bin/bash

# Tenant naming constraints
readonly POOL_ID_PREFIX="tenant_"
readonly POOL_ID_MAX_LENGTH=32
readonly TENANT_NAME_MAX_LENGTH=$((POOL_ID_MAX_LENGTH - ${#POOL_ID_PREFIX}))  # 25 chars

# Password generation
readonly DEFAULT_PASSWORD_LENGTH=16
readonly PASSWORD_SPECIAL_CHARS=4
readonly PASSWORD_TOTAL_LENGTH=$((DEFAULT_PASSWORD_LENGTH + PASSWORD_SPECIAL_CHARS))  # 20 chars

# Timeouts and retries
readonly VM_STOP_TIMEOUT_SECONDS=30
readonly API_RETRY_COUNT=3
readonly API_RETRY_DELAY_SECONDS=2

# Resource limits and validation
readonly CLUSTER_MAX_UTILIZATION_PERCENT=80
readonly MIN_RAM_MB=512
readonly MIN_CPU_CORES=1
readonly MIN_STORAGE_GB=1

# Network validation ranges
readonly VLAN_MIN=1
readonly VLAN_MAX=4094
readonly VLAN_RESERVED=4095

# Testing VLAN
readonly TEST_VLAN_ID=4094

# File permissions (octal values)
readonly LOG_DIR_PERMS=750
readonly CONFIG_FILE_PERMS=640
readonly CREDENTIALS_FILE_PERMS=600
readonly CONFIG_DIR_PERMS=750

# Path management
readonly PMTM_LOG_FILE="${LOG_DIR}/tenant-management.ptm_log"
readonly PMTM_CREDENTIALS_DIR="/root/tenctl-credentials"
readonly PMTM_LOCK_DIR="/var/lock/tenctl"
readonly PMTM_VLAN_LOCK="${PMTM_LOCK_DIR}/vlan.lock"
readonly PMTM_SUBNET_LOCK="${PMTM_LOCK_DIR}/subnet.lock"
readonly PMTM_BACKUP_DIR="/var/backups/tenctl"

ptm_init_directories() {
    mkdir -p "$LOG_DIR" && chmod $LOG_DIR_PERMS "$LOG_DIR" 2>/dev/null || true
    mkdir -p "$TENANT_CONFIG_DIR" && chmod $CONFIG_DIR_PERMS "$TENANT_CONFIG_DIR" 2>/dev/null || true
    mkdir -p "$PMTM_LOCK_DIR" && chmod 755 "$PMTM_LOCK_DIR" 2>/dev/null || true
    mkdir -p "$PMTM_CREDENTIALS_DIR" && chmod 700 "$PMTM_CREDENTIALS_DIR" 2>/dev/null || true
}
