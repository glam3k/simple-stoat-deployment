#!/usr/bin/env bash
# Shared helpers for loading the root .env file and deriving hostnames.

load_root_env() {
    local env_file="$1"
    if [[ ! -f "$env_file" ]]; then
        echo "ERROR: Root env file not found at $env_file" >&2
        echo "       Copy .env.example to .env and fill in the hostnames." >&2
        exit 1
    fi
    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a
}

derive_hostname() {
    local override="$1"
    local subdomain="$2"
    local default_subdomain="$3"
    if [[ -n "$override" ]]; then
        echo "$override"
        return
    fi
    local base="${BASE_DOMAIN:-}"
    if [[ -z "$base" ]]; then
        echo "ERROR: BASE_DOMAIN is not set in the root .env file." >&2
        exit 1
    fi
    local effective_sub="$subdomain"
    if [[ -z "$effective_sub" ]]; then
        effective_sub="$default_subdomain"
    fi
    if [[ -z "$effective_sub" ]]; then
        echo "$base"
    else
        echo "${effective_sub}.${base}"
    fi
}

derive_admin_email() {
    local base="${BASE_DOMAIN:-}"
    if [[ -z "$base" ]]; then
        echo "ERROR: BASE_DOMAIN is not set in the root .env file." >&2
        exit 1
    fi
    echo "admin@${base}"
}

set_env_value() {
    local file="$1"
    local key="$2"
    local value="$3"
    local tmp
    tmp=$(mktemp)
    if [[ -f "$file" ]]; then
        awk -v key="$key" -v value="$value" '
            BEGIN { updated = 0 }
            {
                if ($0 ~ "^" key "=") {
                    print key "=" value
                    updated = 1
                } else {
                    print $0
                }
            }
            END {
                if (!updated) {
                    print key "=" value
                }
            }
        ' "$file" >"$tmp"
    else
        printf '%s=%s\n' "$key" "$value" >"$tmp"
    fi
    mv "$tmp" "$file"
}
