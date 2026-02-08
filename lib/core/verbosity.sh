#!/bin/bash

ptm_parse_verbosity_flags() {
    local verbose_count=0

    for arg in "$@"; do
        case "$arg" in
            --verbose)
                verbose_count=$((verbose_count + 1))
                ;;
        esac
    done

    case $verbose_count in
        0)
            LOG_LEVEL="ERROR"
            ;;
        1)
            LOG_LEVEL="INFO"
            ;;
        *)
            LOG_LEVEL="DEBUG"
            ;;
    esac

    export LOG_LEVEL
}
