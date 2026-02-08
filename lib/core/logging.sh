#!/bin/bash

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global log level (default: INFO)
: ${LOG_LEVEL:="INFO"}

declare -A LOG_LEVELS=(
    ["ERROR"]=0
    ["WARN"]=1
    ["INFO"]=2
    ["DEBUG"]=3
)

__ptm_should_log() {
    local level=$1
    local current_level="${LOG_LEVEL:-INFO}"

    local current_level_value=2
    case "$current_level" in
        ERROR) current_level_value=0 ;;
        WARN)  current_level_value=1 ;;
        INFO)  current_level_value=2 ;;
        DEBUG) current_level_value=3 ;;
    esac

    local message_level_value=0
    case "$level" in
        ERROR) message_level_value=0 ;;
        WARN)  message_level_value=1 ;;
        INFO)  message_level_value=2 ;;
        DEBUG) message_level_value=3 ;;
    esac

    # Display message if its priority is higher or equal to current log level
    [[ $message_level_value -le $current_level_value ]]
}

ptm_log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if ! __ptm_should_log "$level"; then
        return 0
    fi

    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR"
        chmod 750 "$LOG_DIR"
    fi

    echo "[$timestamp] [$level] $message" >> "$LOG_DIR/tenant-management.log"

    case $level in
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message" >&2
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        INFO)
            echo -e "${GREEN}[INFO]${NC} $message"
            ;;
        DEBUG)
            echo -e "${BLUE}[DEBUG]${NC} $message"
            ;;
    esac
}

ptm_log_console() {
    local message="$@"
    echo -e "$message"
}
