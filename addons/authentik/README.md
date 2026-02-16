# Authentik Add-on

This directory packages a Docker Compose stack for [Authentik](https://goauthentik.io/) so you can run an identity provider on the same VPS as Stoat. The stack includes Postgres, Redis, the Authentik server, and the background worker, all joined to the shared `stoat` Docker network so Caddy (and future add-ons) can reach it without exposing any extra ports.

## Files

- `docker-compose.yml` — Authentik services (Postgres, Redis, server, worker)
- `.env.example` — starter variables you must copy to `.env`
- `data/`, `certs/`, `custom-templates/` — created at deploy time to persist Authentik storage

## Quick start

1. Copy the example env file:

   ```bash
   cd /opt/stoat/addons/authentik
   cp .env.example .env
   # edit .env with secure values (PG_PASS, AUTHENTIK_SECRET_KEY, SMTP, etc.)
   ```

2. Deploy via `stoatctl` (reads hostnames from `/opt/stoat/.env`):

   ```bash
   bin/stoatctl deploy authentik
   ```

   This validates hostnames from `.env`, ensures the shared Docker network
   exists, syncs this directory from the repo, runs `docker compose up -d`,
   writes a Caddy fragment to `overrides/Caddyfile.d/authentik.caddy`, and
   rebuilds the Caddyfile.

3. Point DNS for your Authentik hostname to the VPS IP.

4. Visit the Authentik URL, complete the setup wizard, and create a dedicated application + provider for the Stoat admin panel. Save the client ID/secret; you will need them when configuring the admin panel.

## Data persistence

All data is preserved across redeploys. The deploy script's rsync excludes:
- `.env` — your secrets
- `data/` — Authentik application data
- `certs/` — TLS certificates
- `custom-templates/` — email templates

Postgres data lives in a Docker volume defined in the addon's `docker-compose.yml`.

## Resource limits

The Authentik Postgres and Redis containers enforce conservative defaults so the
add-on cannot steal the entire VPS:

| Variable | Default | Description |
|----------|---------|-------------|
| `AUTHENTIK_POSTGRES_CPUS` | `1` | CPU limit for the Postgres container |
| `AUTHENTIK_POSTGRES_MEMORY` | `1g` | Memory limit for Postgres |
| `AUTHENTIK_POSTGRES_MEMORY_RESERVATION` | `512m` | Guaranteed memory for Postgres |
| `AUTHENTIK_REDIS_CPUS` | `0.5` | CPU limit for Redis |
| `AUTHENTIK_REDIS_MEMORY` | `256m` | Memory limit for Redis |
| `AUTHENTIK_REDIS_MEMORY_RESERVATION` | `128m` | Guaranteed memory for Redis |

Set these variables in `/opt/stoat/.env` to match your VPS sizing before running
`bin/stoatctl deploy authentik`. `stoatctl` forwards the root `.env` values to
`docker compose`, so no additional overrides are necessary.

## Notes

- All services bind their HTTP/S ports to `127.0.0.1`, so the UI is only reachable via SSH tunnel or Caddy.
- Include `/opt/stoat/addons/authentik` in your VPS snapshots/backups if you need to restore Authentik.
- Consult the official docs for advanced configuration: https://goauthentik.io/docs/installation/docker-compose
