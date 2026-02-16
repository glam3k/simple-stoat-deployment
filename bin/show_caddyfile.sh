#!/usr/bin/env bash
# Print the host and in-container Caddyfile contents for debugging.
set -euo pipefail

STOAT_DIR="${STOAT_DIR:-/opt/stoat}"
UPSTREAM_DIR="${STOAT_DIR}/upstream"
HOST_FILE="${UPSTREAM_DIR}/Caddyfile"
COMPOSE_OVERRIDE="${STOAT_DIR}/overrides/docker-compose.override.yml"
COMPOSE_FILES=(-f "${UPSTREAM_DIR}/compose.yml")
if [[ -f "$COMPOSE_OVERRIDE" ]]; then
    COMPOSE_FILES+=(-f "$COMPOSE_OVERRIDE")
fi

echo "[show_caddyfile] Host file: ${HOST_FILE}" >&2
if [[ -f "$HOST_FILE" ]]; then
    echo "---- host Caddyfile ----"
    cat "$HOST_FILE"
else
    echo "[show_caddyfile] Host Caddyfile missing" >&2
fi

if [[ -d "$UPSTREAM_DIR" ]]; then
    cd "$UPSTREAM_DIR"
    echo "---- container /etc/caddy/Caddyfile ----"
    if ! docker compose "${COMPOSE_FILES[@]}" ps caddy >/dev/null 2>&1; then
        echo "[show_caddyfile] Skipping container dump; caddy service not running" >&2
    elif ! docker compose "${COMPOSE_FILES[@]}" exec caddy cat /etc/caddy/Caddyfile; then
        echo "[show_caddyfile] Failed to read Caddyfile from container" >&2
    fi
else
    echo "[show_caddyfile] Upstream directory missing at ${UPSTREAM_DIR}" >&2
fi
