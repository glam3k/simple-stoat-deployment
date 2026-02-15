#!/usr/bin/env bash
# rebuild_caddy.sh — Assemble Caddyfile from base + fragments and restart Caddy
set -euo pipefail

STOAT_DIR="${STOAT_DIR:-/opt/stoat}"
UPSTREAM_DIR="${STOAT_DIR}/upstream"
BASE="${STOAT_DIR}/overrides/Caddyfile.base"
FRAGMENTS_DIR="${STOAT_DIR}/overrides/Caddyfile.d"
OUTPUT="${UPSTREAM_DIR}/Caddyfile"

# Start from base (contains global block, site block, headers — everything)
cp "$BASE" "$OUTPUT"

# Append each fragment
if [[ -d "$FRAGMENTS_DIR" ]]; then
    for f in "$FRAGMENTS_DIR"/*.caddy; do
        [[ -f "$f" ]] || continue
        echo "" >> "$OUTPUT"
        cat "$f" >> "$OUTPUT"
    done
fi

# Restart caddy
COMPOSE_OVERRIDE="${STOAT_DIR}/overrides/docker-compose.override.yml"
COMPOSE_FILES=(-f "${UPSTREAM_DIR}/compose.yml")
[[ -f "$COMPOSE_OVERRIDE" ]] && COMPOSE_FILES+=(-f "$COMPOSE_OVERRIDE")
cd "$UPSTREAM_DIR"
docker compose "${COMPOSE_FILES[@]}" exec caddy caddy reload --config /etc/caddy/Caddyfile 2>/dev/null \
    || docker compose "${COMPOSE_FILES[@]}" restart caddy
