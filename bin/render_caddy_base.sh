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
    CADDY_ACME=$(cat <<ACME
    acme_ca https://caddy.localhost.direct/api/acme/local/directory
    cert_issuer internal
ACME
)
else
    CADDY_ACME=""
fi
export CADDY_ACME

export STOAT_HOSTNAME ADMIN_EMAIL

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
    CA_CERT="${STOAT_DIR}/upstream/data/caddy/pki/authorities/local/root.crt"
    if [[ -f "$CA_CERT" ]]; then
        sudo cp "$CA_CERT" /usr/local/share/ca-certificates/stoat-local-ca.crt
        sudo update-ca-certificates
    fi
fi
