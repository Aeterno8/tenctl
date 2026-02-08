#!/bin/bash

set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
source "${SCRIPT_DIR}/../lib/common.sh"

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Generate audit reports from tenant management logs.

Optional:
  -n, --name TENANT_NAME      Filter logs for specific tenant
  -l, --level LEVEL           Filter by ptm_log level (INFO, WARN, ERROR)
  -d, --days DAYS             Show logs from last N days (default: 7)
  -s, --since DATE            Show logs since date (YYYY-MM-DD)
  -u, --until DATE            Show logs until date (YYYY-MM-DD)
  --json                      Output in JSON format
  --operations-only           Show only tenant operations (add/modify/remove)
  --errors-only               Show only ERROR level logs
  -h, --help                  Show this help

Examples:
  $0                          # Last 7 days, all logs
  $0 -n firma_a               # Last 7 days for firma_a
  $0 --days 30                # Last 30 days
  $0 --since 2024-01-01       # Since specific date
  $0 --errors-only            # Only errors
  $0 --operations-only --json # Operations in JSON format

EOF
    exit 1
}

TENANT_NAME=""
FILTER_LEVEL=""
DAYS=7
SINCE_DATE=""
UNTIL_DATE=""
JSON_OUTPUT=false
OPERATIONS_ONLY=false
ERRORS_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            TENANT_NAME="$2"
            shift 2
            ;;
        -l|--level)
            FILTER_LEVEL="$2"
            shift 2
            ;;
        -d|--days)
            DAYS="$2"
            shift 2
            ;;
        -s|--since)
            SINCE_DATE="$2"
            shift 2
            ;;
        -u|--until)
            UNTIL_DATE="$2"
            shift 2
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --operations-only)
            OPERATIONS_ONLY=true
            shift
            ;;
        --errors-only)
            ERRORS_ONLY=true
            FILTER_LEVEL="ERROR"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

ptm_check_root
ptm_check_requirements || exit 1

if [ -n "$TENANT_NAME" ]; then
    ptm_validate_tenant_name "$TENANT_NAME" || exit 1
    if ! ptm_tenant_exists "$TENANT_NAME"; then
        ptm_log WARN "Tenant '$TENANT_NAME' does not exist (showing historical logs if any)"
    fi
fi

LOG_FILE="/var/ptm_log/tenctl/tenant-management.ptm_log"

if [ ! -f "$LOG_FILE" ]; then
    ptm_log ERROR "Log file not found: $LOG_FILE"
    ptm_log INFO "No audit data available. Logs are created when tenant operations are performed."
    exit 1
fi

if [ -n "$SINCE_DATE" ]; then
    START_TIMESTAMP=$(date -d "$SINCE_DATE" +%s 2>/dev/null || echo "0")
else
    START_TIMESTAMP=$(date -d "$DAYS days ago" +%s 2>/dev/null || echo "0")
fi

if [ -n "$UNTIL_DATE" ]; then
    END_TIMESTAMP=$(date -d "$UNTIL_DATE 23:59:59" +%s 2>/dev/null || echo "9999999999")
else
    END_TIMESTAMP=$(date +%s)
fi

declare -a LOG_ENTRIES

while IFS= read -r line; do
    # Log format: [YYYY-MM-DD HH:MM:SS] [LEVEL] Message
    if [[ "$line" =~ ^\[([0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2})\]\ \[([A-Z]+)\]\ (.+)$ ]]; then
        log_timestamp="${BASH_REMATCH[1]}"
        log_level="${BASH_REMATCH[2]}"
        log_message="${BASH_REMATCH[3]}"

        # Convert timestamp to epoch
        log_epoch=$(date -d "$log_timestamp" +%s 2>/dev/null || echo "0")

        if [ "$log_epoch" -lt "$START_TIMESTAMP" ] || [ "$log_epoch" -gt "$END_TIMESTAMP" ]; then
            continue
        fi

        if [ -n "$TENANT_NAME" ]; then
            if ! echo "$log_message" | grep -qi "$TENANT_NAME"; then
                continue
            fi
        fi

        if [ -n "$FILTER_LEVEL" ]; then
            if [ "$log_level" != "$FILTER_LEVEL" ]; then
                continue
            fi
        fi

        if [ "$OPERATIONS_ONLY" = true ]; then
            if ! echo "$log_message" | grep -qiE "(tenant.*created|tenant.*modified|tenant.*removed|tenant.*deleted|pool.*created|user.*created|vnet.*created)"; then
                continue
            fi
        fi

        LOG_ENTRIES+=("$log_timestamp|$log_level|$log_message")
    fi
done < "$LOG_FILE"

TOTAL_ENTRIES="${LOG_ENTRIES[@]+"${#LOG_ENTRIES[@]}"}"
: ${TOTAL_ENTRIES:=0}

if [ "$TOTAL_ENTRIES" -eq 0 ]; then
    if [ "$JSON_OUTPUT" = true ]; then
        echo '{"total": 0, "entries": []}'
    else
        ptm_log INFO "Tenant Audit Report"
        ptm_log INFO "No ptm_log entries found for the specified criteria"
        [ -n "$TENANT_NAME" ] && ptm_log INFO "Tenant filter: $TENANT_NAME"
        [ -n "$FILTER_LEVEL" ] && ptm_log INFO "Level filter: $FILTER_LEVEL"
        ptm_log INFO "Date range: $(date -d "@$START_TIMESTAMP" "+%Y-%m-%d") to $(date -d "@$END_TIMESTAMP" "+%Y-%m-%d")"
    fi
    exit 0
fi

if [ "$JSON_OUTPUT" = true ]; then
    echo "{"
    echo "  \"total\": $TOTAL_ENTRIES,"
    [ -n "$TENANT_NAME" ] && echo "  \"tenant_filter\": \"$TENANT_NAME\","
    [ -n "$FILTER_LEVEL" ] && echo "  \"level_filter\": \"$FILTER_LEVEL\","
    echo "  \"date_range\": {"
    echo "    \"from\": \"$(date -d "@$START_TIMESTAMP" "+%Y-%m-%d %H:%M:%S")\","
    echo "    \"to\": \"$(date -d "@$END_TIMESTAMP" "+%Y-%m-%d %H:%M:%S")\""
    echo "  },"
    echo "  \"entries\": ["

    for i in "${!LOG_ENTRIES[@]}"; do
        IFS='|' read -r timestamp level message <<< "${LOG_ENTRIES[$i]}"
        message_escaped=$(echo "$message" | sed 's/"/\\"/g')

        [ $i -gt 0 ] && echo ","
        echo -n "    {\"timestamp\": \"$timestamp\", \"level\": \"$level\", \"message\": \"$message_escaped\"}"
    done

    echo ""
    echo "  ]"
    echo "}"
else
    ptm_log INFO "Tenant Audit Report"
    ptm_log INFO "Total entries: $TOTAL_ENTRIES"
    [ -n "$TENANT_NAME" ] && ptm_log INFO "Tenant filter: $TENANT_NAME"
    [ -n "$FILTER_LEVEL" ] && ptm_log INFO "Level filter: $FILTER_LEVEL"
    ptm_log INFO "Date range: $(date -d "@$START_TIMESTAMP" "+%Y-%m-%d") to $(date -d "@$END_TIMESTAMP" "+%Y-%m-%d")"

    ERROR_COUNT=0
    WARN_COUNT=0
    INFO_COUNT=0

    for entry in "${LOG_ENTRIES[@]}"; do
        IFS='|' read -r timestamp level message <<< "$entry"
        case "$level" in
            ERROR) ERROR_COUNT=$((ERROR_COUNT + 1)) ;;
            WARN) WARN_COUNT=$((WARN_COUNT + 1)) ;;
            INFO) INFO_COUNT=$((INFO_COUNT + 1)) ;;
        esac
    done

    ptm_log INFO "Summary by Level:"
    ptm_log INFO "  INFO:  $INFO_COUNT"
    ptm_log INFO "  WARN:  $WARN_COUNT"
    ptm_log INFO "  ERROR: $ERROR_COUNT"
    ptm_log INFO "Log Entries (newest first)"

    for (( i=${#LOG_ENTRIES[@]}-1; i>=0; i-- )); do
        IFS='|' read -r timestamp level message <<< "${LOG_ENTRIES[$i]}"

        case "$level" in
            ERROR)
                echo -e "${RED}[$timestamp] [$level] $message${NC}"
                ;;
            WARN)
                echo -e "${YELLOW}[$timestamp] [$level] $message${NC}"
                ;;
            *)
                echo -e "${GREEN}[$timestamp] [$level]${NC} $message"
                ;;
        esac
    done

fi

exit 0
