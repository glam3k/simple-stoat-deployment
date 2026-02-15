# simple-stoat-deployment

Infrastructure, deployment, and operations wrapper for [Stoat](https://github.com/revoltchat/self-hosted) (StoatChat) self-hosted instance.

## What This Repo Does

- **Provisions** a fresh Ubuntu LTS VPS with SSH hardening, firewall, fail2ban, Docker, and log rotation
- **Deploys** Stoat using the upstream Docker Compose stack with security headers injected
- **Manages addons** — Authentik SSO, admin panel, and maintenance mode as independent stacks
- **Backs up** MongoDB + file uploads to S3-compatible storage
- **Restores** from backups (same server or fresh VPS)
- **Updates** safely with snapshot reminders, diff warnings, and rollback instructions

The upstream [revoltchat/self-hosted](https://github.com/revoltchat/self-hosted) repo is included as a git submodule under `upstream/`. We never fork or modify upstream code.

## Prerequisites

- A Vultr VPS (or similar) running Ubuntu LTS, 2 vCPU / 2GB RAM minimum
- A domain with DNS pointing to the VPS IP (plus subdomains for addons)
- SSH key access to the VPS as root

## Quickstart

```bash
# 1. Clone this repo onto the VPS
git clone --recurse-submodules <repo-url> /opt/stoat
cd /opt/stoat

# 2. Configure hostnames once
cp .env.example .env
nano .env  # set BASE_DOMAIN + subdomains for stoat/auth/admin

# 3. Provision the VPS (run as root, one time)
sudo bin/provision.sh

# 4. Log out and reconnect as the deploy user
ssh deploy@YOUR-VPS-IP

# 5. Deploy Stoat (admin HR records seed automatically as admin@BASE_DOMAIN)
bin/stoatctl deploy core

# 6. Set up backups
cp overrides/env/backup.env.template backup.env
nano backup.env  # fill in S3 credentials
bin/stoatctl backup --local-only  # test backup locally (uploads when config is set)
```

The root `.env` file is the single source of truth for hostnames. Set
`BASE_DOMAIN=<domain>' (for example) plus optional `STOAT_SUBDOMAIN`,
`AUTH_SUBDOMAIN`, and `ADMIN_SUBDOMAIN`. The deploy scripts derive
`stoat.<domain>`, `sso.<domain>`, and `admin.<domain>` (overridable via
`*_FQDN`) and log the values they use.

During bootstrap the admin HR records are created automatically using the
`admin@BASE_DOMAIN` address (override by setting `BOOTSTRAP_ADMIN_EMAIL` if you
need a different contact).

### Addons

After the core stack is running, deploy addons as needed:

```bash
# Authentik SSO (identity provider for admin panel)
bin/stoatctl deploy authentik

# Admin panel (requires Authentik to be set up first)
bin/stoatctl deploy admin

# Maintenance page (standalone — use when Stoat is down)
bin/stoatctl deploy maintenance --domain example.com
```

`bin/stoatctl` is the single entry point for deploying, stopping, and destroying
services. It reads the root `.env`, derives the required hostnames, and logs the
URLs it targets.

## Repo Structure

```
bin/
  stoatctl                # Python CLI (deploy/stop/destroy/backup/restore)
  provision.sh            # VPS hardening (root, run once)
  bootstrap.sh            # Seed system accounts + admin HR records
  healthcheck.sh          # Container/HTTP/disk/memory checks
  rebuild_caddy.sh        # Assemble Caddyfile from base + fragments

docs/
  runbook.md              # SSH, logs, restart, troubleshooting
  security.md             # Hardening checklist + verification commands
  backup-restore.md       # Backup setup, restore procedures
  update-procedure.md     # Safe update workflow + rollback

overrides/
  docker-compose.override.yml  # Digest-pinned infra images
  Caddyfile.base               # Base Caddyfile with routes + headers
  Caddyfile.d/                 # Per-addon Caddy fragments (auto-assembled)
  env/
    backup.env.template        # S3 backup config template

addons/
  authentik/              # Authentik Docker compose stack
  admin-panel/            # Stoat admin panel (Next.js, submodule)
  maintenance/            # Standalone maintenance page

upstream/                 # git submodule -> revoltchat/self-hosted
```

## Data Persistence

See [docs/data-persistence.md](docs/data-persistence.md) for where each service stores data and what survives upgrades.

## Docs

- [Operations Runbook](docs/runbook.md) — day-to-day operations
- [Security Checklist](docs/security.md) — hardening verification
- [Backup & Restore](docs/backup-restore.md) — backup setup and restore procedures
- [Update Procedure](docs/update-procedure.md) — safe update workflow
- [Data Persistence](docs/data-persistence.md) — where data lives and what survives upgrades
