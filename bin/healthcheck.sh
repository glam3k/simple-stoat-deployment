#!/usr/bin/env bash
# healthcheck.sh — Check Stoat service health
# Exit 0 = all healthy, Exit 1 = issues detected
set -euo pipefail

STOAT_DIR="${STOAT_DIR:-/opt/stoat}"
UPSTREAM_DIR="${STOAT_DIR}/upstream"

usage() {
    echo "Usage: $(basename "$0") [--domain <domain>]"
    echo ""
    echo "Checks:"
    echo "  - All expected Docker containers are running"
    echo "  - HTTPS endpoint responds (if --domain given)"
    echo "  - Disk usage below 80%"
    echo "  - Available memory above 256MB"
    exit 0
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
fi

DOMAIN=""
HTTPS_INSECURE="${HEALTHCHECK_INSECURE:-0}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain) DOMAIN="$2"; shift 2 ;;
        *) shift ;;
    esac
done

run_checks() {
    local attempt="$1"
    local ISSUES=0

    echo "=== Stoat Healthcheck (attempt ${attempt}) ==="
    echo ""

    echo "## Container Status"
    if [[ -f "${UPSTREAM_DIR}/compose.yml" ]]; then
        local COMPOSE_OVERRIDE="${STOAT_DIR}/overrides/docker-compose.override.yml"
        if [[ ! -f "${COMPOSE_OVERRIDE}" ]]; then
            echo "  ERROR: Missing compose override at ${COMPOSE_OVERRIDE}"
            ISSUES=$((ISSUES + 1))
        else
            local COMPOSE_FILES=(-f "${UPSTREAM_DIR}/compose.yml" -f "${COMPOSE_OVERRIDE}")
            local COMPOSE_OUTPUT
            COMPOSE_OUTPUT=$(docker compose "${COMPOSE_FILES[@]}" ps --format "table {{.Name}}\t{{.Status}}" 2>/dev/null || true)
            if [[ -z "$COMPOSE_OUTPUT" ]]; then
                echo "  ERROR: Could not query Docker Compose"
                ISSUES=$((ISSUES + 1))
            else
                echo "$COMPOSE_OUTPUT"
                echo ""

                local EXITED
                EXITED=$(docker compose "${COMPOSE_FILES[@]}" ps --format "{{.Name}} {{.Status}}" 2>/dev/null \
                    | grep -v "createbuckets" \
                    | grep -iE "exited|dead|restarting" || true)
                if [[ -n "$EXITED" ]]; then
                    echo "  WARNING: Unhealthy containers detected:"
                    echo "$EXITED" | while read -r line; do echo "    $line"; done
                    ISSUES=$((ISSUES + 1))
                else
                    echo "  OK: All service containers running"
                fi
            fi
        fi
    else
        echo "  SKIP: ${UPSTREAM_DIR}/compose.yml not found"
    fi
    echo ""

    if [[ -n "$DOMAIN" ]]; then
        echo "## HTTPS Endpoint"
        local HTTP_CODE
        local CURL_OPTS=(--max-time 10)
        if [[ "$HTTPS_INSECURE" == "1" ]]; then
            CURL_OPTS+=(-k)
        fi
        HTTP_CODE=$(curl -so /dev/null -w "%{http_code}" "${CURL_OPTS[@]}" "https://${DOMAIN}" 2>/dev/null || echo "000")
        if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 400 ]]; then
            echo "  OK: https://${DOMAIN} returned HTTP ${HTTP_CODE}"
        else
            if [[ "$HTTPS_INSECURE" == "1" ]]; then
                echo "  WARNING: https://${DOMAIN} returned HTTP ${HTTP_CODE} (insecure mode)"
            else
                echo "  WARNING: https://${DOMAIN} returned HTTP ${HTTP_CODE}"
            fi
            ISSUES=$((ISSUES + 1))
        fi
        echo ""
    fi

    echo "## Disk Usage"
    local DISK_PCT
    DISK_PCT=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
    if [[ "$DISK_PCT" -ge 90 ]]; then
        echo "  CRITICAL: Root filesystem at ${DISK_PCT}%"
        ISSUES=$((ISSUES + 1))
    elif [[ "$DISK_PCT" -ge 80 ]]; then
        echo "  WARNING: Root filesystem at ${DISK_PCT}%"
        ISSUES=$((ISSUES + 1))
    else
        echo "  OK: Root filesystem at ${DISK_PCT}%"
    fi
    echo ""

    echo "## Memory"
    if command -v free &>/dev/null; then
        local AVAIL_MB
        AVAIL_MB=$(free -m | awk '/^Mem:/ {print $7}')
        if [[ "$AVAIL_MB" -lt 128 ]]; then
            echo "  CRITICAL: Only ${AVAIL_MB}MB available"
            ISSUES=$((ISSUES + 1))
        elif [[ "$AVAIL_MB" -lt 256 ]]; then
            echo "  WARNING: Only ${AVAIL_MB}MB available"
            ISSUES=$((ISSUES + 1))
        else
            echo "  OK: ${AVAIL_MB}MB available"
        fi
    else
        echo "  SKIP: 'free' command not available (not Linux?)"
    fi
    echo ""

    echo "=== Result ==="
    if [[ "$ISSUES" -eq 0 ]]; then
        echo "All checks passed."
        return 0
    else
        echo "${ISSUES} issue(s) detected."
        return 1
    fi
}

MAX_WAIT=120
SLEEP_INTERVAL=5
DEADLINE=$(( $(date +%s) + MAX_WAIT ))
ATTEMPT=1

while true; do
    if run_checks "$ATTEMPT"; then
        exit 0
    fi

    if (( $(date +%s) >= DEADLINE )); then
        echo "Health check timed out after ${MAX_WAIT}s."
        exit 1
    fi

    ATTEMPT=$((ATTEMPT + 1))
    echo "Retrying in ${SLEEP_INTERVAL}s..."
    sleep "$SLEEP_INTERVAL"
    echo ""
done
