#!/usr/bin/env bash
set -euo pipefail

STOAT_DIR="${STOAT_DIR:-/opt/stoat}"
INFRA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}" )/.." && pwd)"
ENV_FILE="${INFRA_ROOT}/.env"
BASE_TEMPLATE="${INFRA_ROOT}/overrides/Caddyfile.base.template"
OUTPUT_BASE="${STOAT_DIR}/overrides/Caddyfile.base"

# shellcheck source=bin/lib/env.sh disable=SC1091
source "${INFRA_ROOT}/bin/lib/env.sh"
load_root_env "$ENV_FILE"
STOAT_HOSTNAME="$(derive_hostname "${STOAT_FQDN:-}" "${STOAT_SUBDOMAIN:-chat}" "chat")"
ADMIN_EMAIL="$(derive_admin_email)"
INTERNAL_CA="${CADDY_USE_INTERNAL_CA:-0}"

mkdir -p "$(dirname "$OUTPUT_BASE")"

if [[ "$INTERNAL_CA" == "1" ]]; then
    CADDY_ACME=$'    acme_ca https://caddy.localhost.direct/api/acme/local/directory\n    cert_issuer internal'
else
    CADDY_ACME=""
fi
export CADDY_ACME

ADMIN_EMAIL_RENDER="${ADMIN_EMAIL:-admin@example.com}"
export STOAT_HOSTNAME ADMIN_EMAIL="$ADMIN_EMAIL_RENDER"

if command -v envsubst >/dev/null 2>&1; then
    envsubst < "$BASE_TEMPLATE" > "$OUTPUT_BASE"
else
    python3 - "$BASE_TEMPLATE" "$OUTPUT_BASE" <<'PY'
import os
import sys
from string import Template

template_path, output_path = sys.argv[1], sys.argv[2]
with open(template_path) as f:
    content = Template(f.read()).safe_substitute(os.environ)
with open(output_path, 'w') as f:
    f.write(content)
PY
fi

if [[ "$INTERNAL_CA" == "1" ]]; then
    cd "$STOAT_DIR/upstream"
    attempts=10
    ca_tmp=$(mktemp)
    while [[ $attempts -gt 0 ]]; do
        if docker compose -f compose.yml -f "$STOAT_DIR/overrides/docker-compose.override.yml" \
            cp caddy:/data/caddy/pki/authorities/local/root.crt "$ca_tmp" 2>/dev/null; then
            echo "[render_caddy_base] Installing internal CA certificate" >&2
            sudo cp "$ca_tmp" /usr/local/share/ca-certificates/stoat-local-ca.crt
            sudo update-ca-certificates
            break
        fi
        attempts=$((attempts - 1))
        echo "[render_caddy_base] Waiting for caddy internal CA (attempts left: $attempts)" >&2
        sleep 1
    done
    rm -f "$ca_tmp"
    if [[ $attempts -le 0 ]]; then
        echo "[render_caddy_base] Internal CA certificate not available; skipping install" >&2
    fi
fi
