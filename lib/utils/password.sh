#!/bin/bash
# Password generation utilities

# Generate random password with strong complexity
# Args: [length] (optional, defaults to PASSWORD_TOTAL_LENGTH)
# Returns: Generated password (printed to stdout)
ptm_generate_password() {
    local length=${1:-$PASSWORD_TOTAL_LENGTH}

    local upper
    local lower
    local digits
    local symbols
    local rest

    upper=$(tr -dc 'A-Z' < /dev/urandom | head -c $PASSWORD_SPECIAL_CHARS)
    lower=$(tr -dc 'a-z' < /dev/urandom | head -c $PASSWORD_SPECIAL_CHARS)
    digits=$(tr -dc '0-9' < /dev/urandom | head -c $PASSWORD_SPECIAL_CHARS)
    symbols=$(tr -dc '!@#$%^&*()-_=+[]{}' < /dev/urandom | head -c $PASSWORD_SPECIAL_CHARS)
    rest=$(tr -dc 'A-Za-z0-9!@#$%^&*()-_=+[]{}' < /dev/urandom | head -c $((length - DEFAULT_PASSWORD_LENGTH)))

    echo "${upper}${lower}${digits}${symbols}${rest}" | fold -w1 | shuf | tr -d '\n'
}
