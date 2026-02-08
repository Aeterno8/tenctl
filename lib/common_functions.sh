#!/bin/bash

# Validate default resource limits from config
ptm_validate_numeric_param "DEFAULT_CPU_LIMIT" "$DEFAULT_CPU_LIMIT" 1 256 || exit 1
ptm_validate_numeric_param "DEFAULT_RAM_LIMIT" "$DEFAULT_RAM_LIMIT" 512 524288 || exit 1
ptm_validate_numeric_param "DEFAULT_STORAGE_LIMIT" "$DEFAULT_STORAGE_LIMIT" 1 10000 || exit 1
