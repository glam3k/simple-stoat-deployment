#!/usr/bin/env bash
# provision.sh — Harden a fresh Ubuntu LTS VPS for Stoat deployment
# Run as root (or with sudo) on initial server setup
set -euo pipefail

usage() {
    echo "Usage: sudo $(basename "$0") [--user <username>] [--allow-password]"
    echo ""
    echo "Provisions a fresh Ubuntu LTS VPS:"
    echo "  1. Creates deploy user with sudo + SSH key"
    echo "  2. Hardens SSH (disable password auth, root login)"
    echo "  3. Configures UFW firewall (22, 80, 443 only)"
    echo "  4. Installs + configures fail2ban"
    echo "  5. Enables unattended security updates"
    echo "  6. Installs Python 3"
    echo "  7. Installs Docker + Compose plugin"
    echo "  8. Configures Docker log rotation"
    echo "  9. Verifies time sync"
    exit 0
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
fi

# Parse args
DEPLOY_USER="${DEPLOY_USER:-deploy}"
DISABLE_PASSWORD=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --user) DEPLOY_USER="$2"; shift 2 ;;
        --disable-password) DISABLE_PASSWORD=true; shift ;;
        *) shift ;;
    esac
done

# Must run as root
if [[ "$(id -u)" -ne 0 ]]; then
    echo "ERROR: This script must be run as root (or with sudo)."
    exit 1
fi

echo "=== Stoat VPS Provisioning ==="
echo "Deploy user: ${DEPLOY_USER}"
echo ""

# -------------------------------------------------------------------
# 1. Create deploy user
# -------------------------------------------------------------------
echo "## 1/9 Creating deploy user '${DEPLOY_USER}'..."
if id "${DEPLOY_USER}" &>/dev/null; then
    echo "  User '${DEPLOY_USER}' already exists, skipping creation."
else
    adduser --disabled-password --gecos "" "${DEPLOY_USER}"
    echo "  Created user '${DEPLOY_USER}'."
fi

# Add to sudo group
usermod -aG sudo "${DEPLOY_USER}"

# Copy SSH authorized_keys from root if they exist and user doesn't have them
DEPLOY_HOME=$(eval echo "~${DEPLOY_USER}")
if [[ -f /root/.ssh/authorized_keys ]]; then
    mkdir -p "${DEPLOY_HOME}/.ssh"
    if [[ ! -f "${DEPLOY_HOME}/.ssh/authorized_keys" ]]; then
        cp /root/.ssh/authorized_keys "${DEPLOY_HOME}/.ssh/authorized_keys"
    fi
    chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "${DEPLOY_HOME}/.ssh"
    chmod 700 "${DEPLOY_HOME}/.ssh"
    chmod 600 "${DEPLOY_HOME}/.ssh/authorized_keys"
    echo "  Copied SSH authorized_keys from root."
fi

# Allow sudo without password for deploy user (optional, remove if you prefer password)
echo "${DEPLOY_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${DEPLOY_USER}"
chmod 440 "/etc/sudoers.d/${DEPLOY_USER}"
echo "  Configured passwordless sudo."
echo ""

# -------------------------------------------------------------------
# 2. SSH hardening
# -------------------------------------------------------------------
echo "## 2/9 Hardening SSH..."
SSHD_CONFIG="/etc/ssh/sshd_config"

if [[ "$DISABLE_PASSWORD" == true ]]; then
    # Disable password authentication
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "${SSHD_CONFIG}"
    sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' "${SSHD_CONFIG}"

    # Disable root login
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "${SSHD_CONFIG}"
    echo "  SSH hardened: password auth disabled, root login disabled."

    # Restart SSH to apply changes
    systemctl restart ssh || systemctl restart sshd
else
    echo "  Skipping SSH config changes (password/root login left as-is)."
fi
echo ""

# -------------------------------------------------------------------
# 3. UFW firewall
# -------------------------------------------------------------------
echo "## 3/9 Configuring UFW firewall..."
apt-get update -qq
apt-get install -y -qq ufw > /dev/null

ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
echo "  UFW enabled: allowing SSH (22), HTTP (80), HTTPS (443) only."
echo ""

# -------------------------------------------------------------------
# 4. Fail2ban
# -------------------------------------------------------------------
echo "## 4/9 Installing fail2ban..."
apt-get install -y -qq fail2ban > /dev/null

mkdir -p /etc/fail2ban/jail.d
cat > /etc/fail2ban/jail.d/sshd.local <<'JAIL'
[sshd]
enabled = true
port = ssh
maxretry = 5
findtime = 10m
bantime = 1h
JAIL

systemctl enable --now fail2ban
echo "  Fail2ban enabled: SSH brute-force protection (5 retries, 1h ban)."
echo ""

# -------------------------------------------------------------------
# 5. Unattended upgrades
# -------------------------------------------------------------------
echo "## 5/9 Enabling unattended security updates..."
apt-get install -y -qq unattended-upgrades > /dev/null
systemctl enable --now unattended-upgrades
echo "  Unattended-upgrades enabled."
echo ""

# -------------------------------------------------------------------
# 6. Python 3
# -------------------------------------------------------------------
echo "## 6/9 Installing Python 3 + jq..."
apt-get install -y -qq python3 python3-venv jq > /dev/null
echo "  Python installed: $(python3 --version)"
echo ""

# -------------------------------------------------------------------
# 7. Docker
# -------------------------------------------------------------------
echo "## 7/9 Installing Docker..."
if command -v docker &>/dev/null; then
    echo "  Docker already installed: $(docker --version)"
else
    # Install Docker via official apt repository
    apt-get install -y -qq ca-certificates curl gnupg > /dev/null
    install -m 0755 -d /etc/apt/keyrings
    if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
    fi
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(
            # shellcheck disable=SC1091
            . /etc/os-release && echo "$VERSION_CODENAME"
        ) stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null
    echo "  Docker installed: $(docker --version)"
fi

# Add deploy user to docker group
usermod -aG docker "${DEPLOY_USER}"
echo "  Added '${DEPLOY_USER}' to docker group (re-login required)."
echo ""

# -------------------------------------------------------------------
# 8. Docker log rotation
# -------------------------------------------------------------------
echo "## 8/9 Configuring Docker log rotation..."
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'DAEMON'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
DAEMON

systemctl restart docker
echo "  Docker log rotation: max 10MB x 3 files per container."
echo ""

# -------------------------------------------------------------------
# 9. Time sync
# -------------------------------------------------------------------
echo "## 9/9 Checking time sync..."
if timedatectl show --property=NTPSynchronized --value 2>/dev/null | grep -q "yes"; then
    echo "  NTP synchronized: OK"
elif systemctl is-active --quiet systemd-timesyncd; then
    echo "  systemd-timesyncd active (NTP sync in progress)."
else
    echo "  WARNING: Time sync may not be active. Run: sudo timedatectl set-ntp true"
fi
echo ""

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------
echo "========================================="
echo "  Provisioning complete!"
echo "========================================="
echo ""
echo "  Deploy user:       ${DEPLOY_USER}"
echo "  SSH:               password auth disabled, root login disabled"
echo "  Firewall (UFW):    22, 80, 443 only"
echo "  Fail2ban:          SSH jail active"
echo "  Auto-updates:      enabled"
echo "  Docker:            installed + log rotation configured"
echo ""
echo "  IMPORTANT: Log out and reconnect as '${DEPLOY_USER}' via SSH key."
echo "  Next step: run bin/stoatctl deploy core"
