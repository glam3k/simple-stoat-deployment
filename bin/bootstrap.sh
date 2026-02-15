#!/usr/bin/env bash
# bootstrap.sh — Create initial system accounts for Stoat
# Run after services are healthy, or standalone.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
STOAT_DIR="${STOAT_DIR:-/opt/stoat}"
UPSTREAM_DIR="${STOAT_DIR}/upstream"
ENV_FILE="${INFRA_ROOT}/.env"

# shellcheck source=bin/lib/env.sh disable=SC1091
source "${INFRA_ROOT}/bin/lib/env.sh"
load_root_env "$ENV_FILE"
DEFAULT_ADMIN_EMAIL="$(derive_admin_email)"

usage() {
    echo "Usage: $(basename "$0") --domain <domain> [--admin-email <email>]"
    echo ""
    echo "Creates initial system accounts so the admin panel works on first login."
    echo ""
    echo "Arguments:"
    echo "  --domain        The Stoat domain (e.g., chat.example.com)"
    echo "  --admin-email   Authentik login email (defaults to admin@BASE_DOMAIN)"
    echo "  --admin-name    Display name for admin person (default: admin)"
    echo ""
    echo "Environment:"
    echo "  STOAT_DIR              Installation directory (default: /opt/stoat)"
    echo "  BOOTSTRAP_ADMIN_EMAIL  Override default admin@BASE_DOMAIN"
    echo "  BOOTSTRAP_ADMIN_NAME   Fallback if --admin-name not provided (default: admin)"
    exit 0
}

DOMAIN=""
ADMIN_EMAIL="${BOOTSTRAP_ADMIN_EMAIL:-$DEFAULT_ADMIN_EMAIL}"
ADMIN_NAME="${BOOTSTRAP_ADMIN_NAME:-admin}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)      usage ;;
        --domain)       DOMAIN="$2"; shift 2 ;;
        --admin-email)  ADMIN_EMAIL="$2"; shift 2 ;;
        --admin-name)   ADMIN_NAME="$2"; shift 2 ;;
        *)              shift ;;
    esac
done

if [[ -z "$DOMAIN" ]]; then
    echo "ERROR: --domain is required."
    echo "Usage: $(basename "$0") --domain <domain> --admin-email <email>"
    exit 1
fi

[[ -n "$ADMIN_EMAIL" ]] || ADMIN_EMAIL="$DEFAULT_ADMIN_EMAIL"

# Build compose files array (same pattern as stoatctl deploy core)
COMPOSE_OVERRIDE="${STOAT_DIR}/overrides/docker-compose.override.yml"
COMPOSE_FILES=(-f "${UPSTREAM_DIR}/compose.yml")
[[ -f "${COMPOSE_OVERRIDE}" ]] && COMPOSE_FILES+=(-f "${COMPOSE_OVERRIDE}")

# Helper: run mongosh inside the database container
mongosh_eval() {
    cd "${UPSTREAM_DIR}"
    docker compose "${COMPOSE_FILES[@]}" exec -T database mongosh --quiet --eval "$1"
}

echo "=== Stoat Bootstrap ==="
echo "Domain:      ${DOMAIN}"
echo "Admin email: ${ADMIN_EMAIL}"
echo "Admin name:  ${ADMIN_NAME}"
echo ""

# -------------------------------------------------------------------
# Preflight
# -------------------------------------------------------------------
echo "Preflight checks..."

command -v jq &>/dev/null || {
    echo "ERROR: jq is required. Install with: sudo apt-get install -y jq"
    exit 1
}

cd "${UPSTREAM_DIR}"
DB_STATUS=$(docker compose "${COMPOSE_FILES[@]}" ps database --format '{{.Status}}' 2>/dev/null || true)
if ! echo "$DB_STATUS" | grep -qi "up"; then
    echo "ERROR: database container is not running (status: ${DB_STATUS:-unknown})"
    exit 1
fi
echo "  OK: database container running"
echo ""

# -------------------------------------------------------------------
# 7a. Moderator system user
# -------------------------------------------------------------------
echo "7a. Moderator system user..."

MOD_USER_ID=$(mongosh_eval '
    const u = db.getSiblingDB("revolt").users.findOne(
        {username: "Moderator"}, {_id: 1}
    );
    if (u) print(u._id);
')
MOD_USER_ID=$(echo "$MOD_USER_ID" | tr -d '[:space:]')

if [[ -n "$MOD_USER_ID" ]]; then
    echo "    Already exists: ${MOD_USER_ID}"
else
    MOD_EMAIL="moderator@${DOMAIN}"
    MOD_PASSWORD=$(openssl rand -base64 24)

    # Create account via Revolt API
    echo "    Creating account via API..."
    curl -sf -X POST "https://${DOMAIN}/api/auth/account/create" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"${MOD_EMAIL}\",\"password\":\"${MOD_PASSWORD}\"}" \
        >/dev/null 2>&1 || true

    # Force-verify email (SMTP is not configured)
    # shellcheck disable=SC2016
    mongosh_eval '
        db.getSiblingDB("revolt").accounts.updateOne(
            {email: "'"${MOD_EMAIL}"'"},
            {$set: {"verification.status": "Verified"}}
        );
    ' >/dev/null

    # Login to get session token
    echo "    Logging in..."
    LOGIN_RESP=$(curl -sf -X POST "https://${DOMAIN}/api/auth/session/login" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"${MOD_EMAIL}\",\"password\":\"${MOD_PASSWORD}\"}" 2>&1) || true

    SESSION_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.token // empty' 2>/dev/null)
    if [[ -z "$SESSION_TOKEN" ]]; then
        echo "    ERROR: Could not login as Moderator."
        echo "    API response: ${LOGIN_RESP}"
        exit 1
    fi

    # Complete onboarding
    echo "    Completing onboarding..."
    curl -sf -X POST "https://${DOMAIN}/api/onboard/complete" \
        -H "Content-Type: application/json" \
        -H "x-session-token: ${SESSION_TOKEN}" \
        -d '{"username":"Moderator"}' \
        >/dev/null 2>&1 || true

    # Fetch user ID
    MOD_USER_ID=$(mongosh_eval '
        const u = db.getSiblingDB("revolt").users.findOne(
            {username: "Moderator"}, {_id: 1}
        );
        if (u) print(u._id);
    ')
    MOD_USER_ID=$(echo "$MOD_USER_ID" | tr -d '[:space:]')

    if [[ -z "$MOD_USER_ID" ]]; then
        echo "    ERROR: Moderator user was not created."
        exit 1
    fi

    echo "    Created: ${MOD_USER_ID}"
    echo "    Password: ${MOD_PASSWORD}"
    echo "    (This is a system account. Store the password securely.)"
fi
echo ""

# -------------------------------------------------------------------
# 7b. Administrator role
# -------------------------------------------------------------------
echo "7b. Administrator role..."

mongosh_eval '
    const hr = db.getSiblingDB("revolt_hr");
    if (hr.roles.countDocuments({_id: "01ADMIN_ROLE"}) === 0) {
        hr.roles.insertOne({
            _id: "01ADMIN_ROLE",
            name: "Administrator",
            permissions: ["*"]
        });
        print("    Created.");
    } else {
        print("    Already exists, skipping.");
    }
'
echo ""

# -------------------------------------------------------------------
# 7c. Admin person
# -------------------------------------------------------------------
echo "7c. Admin person (${ADMIN_EMAIL})..."

mongosh_eval '
    const hr = db.getSiblingDB("revolt_hr");
    const email = "'"${ADMIN_EMAIL}"'";
    if (hr.people.countDocuments({email: email}) === 0) {
        hr.people.insertOne({
            _id: "01ADMIN_PERSON",
            name: "'"${ADMIN_NAME}"'",
            email: email,
            status: "Active",
            positions: [],
            roles: ["01ADMIN_ROLE"]
        });
        print("    Created.");
    } else {
        print("    Already exists, skipping.");
    }
'
echo ""

# -------------------------------------------------------------------
# 7d. PLATFORM_ACCOUNT_ID
# -------------------------------------------------------------------
echo "7d. PLATFORM_ACCOUNT_ID = ${MOD_USER_ID}"

ADMIN_ENV="${STOAT_DIR}/addons/admin-panel/.env.local"
if [[ -f "$ADMIN_ENV" ]]; then
    CURRENT_ID=$(grep '^PLATFORM_ACCOUNT_ID=' "$ADMIN_ENV" | cut -d= -f2)
    if [[ -z "$CURRENT_ID" ]]; then
        sed -i "s/^PLATFORM_ACCOUNT_ID=.*/PLATFORM_ACCOUNT_ID=${MOD_USER_ID}/" "$ADMIN_ENV"
        echo "    Updated ${ADMIN_ENV}"
    elif [[ "$CURRENT_ID" == "$MOD_USER_ID" ]]; then
        echo "    ${ADMIN_ENV} already correct."
    else
        echo "    WARNING: ${ADMIN_ENV} has different value (${CURRENT_ID})."
        echo "    Set manually if needed: PLATFORM_ACCOUNT_ID=${MOD_USER_ID}"
    fi
else
    echo "    Admin panel not yet deployed."
    echo "    When deploying, set PLATFORM_ACCOUNT_ID=${MOD_USER_ID} in .env.local"
fi
echo ""

# -------------------------------------------------------------------
# Done
# -------------------------------------------------------------------
echo "=== Bootstrap complete ==="
echo "  Moderator user:       ${MOD_USER_ID}"
echo "  Admin role:           01ADMIN_ROLE"
echo "  Admin person:         ${ADMIN_EMAIL}"
echo "  PLATFORM_ACCOUNT_ID:  ${MOD_USER_ID}"
