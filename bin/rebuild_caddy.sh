#!/usr/bin/env bash
# rebuild_caddy.sh — Assemble Caddyfile from base + fragments and restart Caddy
set -euo pipefail

STOAT_DIR="${STOAT_DIR:-/opt/stoat}"
UPSTREAM_DIR="${STOAT_DIR}/upstream"
BASE="${STOAT_DIR}/overrides/Caddyfile.base"
FRAGMENTS_DIR="${STOAT_DIR}/overrides/Caddyfile.d"
OUTPUT="${UPSTREAM_DIR}/Caddyfile"

echo "[rebuild_caddy] Using STOAT_DIR=${STOAT_DIR}" >&2

if [[ ! -d "$UPSTREAM_DIR" ]]; then
    echo "ERROR: Upstream directory missing at $UPSTREAM_DIR" >&2
    exit 1
fi

if [[ ! -f "$BASE" ]]; then
    echo "ERROR: Base Caddyfile not found at $BASE" >&2
    exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"
cp "$BASE" "$OUTPUT"

if [[ -d "$FRAGMENTS_DIR" ]]; then
    appended=0
    for f in "$FRAGMENTS_DIR"/*.caddy; do
        [[ -f "$f" ]] || continue
        appended=1
        echo "" >> "$OUTPUT"
        cat "$f" >> "$OUTPUT"
    done
    if [[ $appended -eq 0 ]]; then
        echo "[rebuild_caddy] No Caddy fragments found under $FRAGMENTS_DIR" >&2
    fi
else
    echo "[rebuild_caddy] Fragment directory $FRAGMENTS_DIR does not exist" >&2
fi

COMPOSE_OVERRIDE="${STOAT_DIR}/overrides/docker-compose.override.yml"
COMPOSE_FILES=(-f "${UPSTREAM_DIR}/compose.yml")
if [[ -f "$COMPOSE_OVERRIDE" ]]; then
    COMPOSE_FILES+=(-f "$COMPOSE_OVERRIDE")
fi

cd "$UPSTREAM_DIR"
echo "[rebuild_caddy] Reloading Caddy" >&2
if docker compose "${COMPOSE_FILES[@]}" exec -T caddy caddy reload --config /etc/caddy/Caddyfile; then
    echo "[rebuild_caddy] Caddy reload succeeded" >&2
else
    echo "[rebuild_caddy] Reload failed; restarting caddy" >&2
    if ! docker compose "${COMPOSE_FILES[@]}" restart caddy; then
        echo "ERROR: Failed to reload or restart Caddy" >&2
        exit 1
    fi
    echo "[rebuild_caddy] Caddy restarted" >&2
fi

TMP_CONTAINER_FILE=$(mktemp)
if docker compose "${COMPOSE_FILES[@]}" exec -T caddy cat /etc/caddy/Caddyfile >"$TMP_CONTAINER_FILE"; then
    if ! cmp -s "$OUTPUT" "$TMP_CONTAINER_FILE"; then
        echo "[rebuild_caddy] Container Caddyfile differs from host; forcing restart" >&2
        if ! docker compose "${COMPOSE_FILES[@]}" restart caddy; then
            echo "ERROR: Failed to restart caddy after mismatch" >&2
            rm -f "$TMP_CONTAINER_FILE"
            exit 1
        fi
        if ! docker compose "${COMPOSE_FILES[@]}" exec -T caddy cat /etc/caddy/Caddyfile >"$TMP_CONTAINER_FILE" || \
           ! cmp -s "$OUTPUT" "$TMP_CONTAINER_FILE"; then
            echo "ERROR: Container Caddyfile still mismatched after restart" >&2
            rm -f "$TMP_CONTAINER_FILE"
            exit 1
        fi
    fi
else
    echo "[rebuild_caddy] Unable to read container Caddyfile" >&2
fi
rm -f "$TMP_CONTAINER_FILE"
