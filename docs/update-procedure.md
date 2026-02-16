# Update Procedure

## Pre-Update Checklist

- [ ] Check upstream release notes / notices for breaking changes
- [ ] Decide if infrastructure images need to be bumped; update `overrides/docker-compose.override.yml` if so
- [ ] Take a Vultr snapshot (Snapshots -> Add Snapshot)
- [ ] Run a backup: `cd /opt/stoat && bin/stoatctl backup`
- [ ] Verify the backup completed successfully

## Running the Update

1. SSH into the VPS as the deploy user and `cd /opt/stoat`.
2. Pull the latest infra repo + submodules:
   ```bash
   git pull --ff-only
   git submodule sync --recursive
   git submodule update --init --recursive
   ```
   (If you're bumping the upstream Stoat commit or overrides yourself, do that
   locally and push before pulling on the server.)
3. Redeploy the core stack:
   ```bash
   bin/stoatctl deploy core
   ```
   This rebuilds the Caddyfile, pulls pinned images, restarts the compose stack,
   reruns the health check, and bootstraps if needed.
4. Redeploy addons if their code or env files changed:
   ```bash
   bin/stoatctl deploy authentik
   bin/stoatctl deploy admin
   ```

That's all the update.sh script used to do; keeping the steps explicit makes it
 clearer when each part succeeds.

### What's preserved during an update

- **All data** — MongoDB, MinIO uploads, RabbitMQ queues (bind mounts under `upstream/data/`)
- **Config** — `Revolt.toml` and `.env.web` are never touched by update
- **TLS certificates** — Docker volume `caddy-data` (auto-managed by Caddy)
- **Addon stacks** — Authentik, admin panel, etc. are separate compose stacks and unaffected
- **Caddyfile** — regenerated from `overrides/Caddyfile.base` + `overrides/Caddyfile.d/*.caddy` fragments

### What changes during an update

- Docker images are pulled to the digests pinned in `overrides/docker-compose.override.yml`
- The upstream submodule is synced to the commit pinned in this repo's git
- The assembled `upstream/Caddyfile` is regenerated (but the source fragments are unchanged)

## Pinned Docker Images

Stoat's application containers are versioned upstream, but every infrastructure dependency (MongoDB, KeyDB, RabbitMQ, MinIO, Caddy, and the web client) is pinned by **digest** in `overrides/docker-compose.override.yml`. `stoatctl deploy core`, `stoatctl backup`, `stoatctl restore`, and `healthcheck.sh` all load this override automatically; if the file is missing the commands bail out rather than running with floating tags.

When upstream requires a newer Stoat or infrastructure version, bump both the `upstream/` submodule and the override file in git:

1. Pick the tag you want (e.g., `mongo:7.0.14`).
2. Get the multi-arch digest: `docker buildx imagetools inspect mongo:7.0.14 | awk '/^Digest:/ {print $2; exit}'`.
3. Replace that service's `image:` line with `repo@sha256:...` and keep the trailing comment documenting the tag.
4. In `upstream/`, run `git fetch && git checkout <stoat-tag-or-sha>`, then `git add upstream overrides/docker-compose.override.yml` and commit both pointers.
5. Run `bin/stoatctl deploy core` so Docker pulls the newly pinned digest and Stoat commit.

Tip: `docker compose -f /opt/stoat/upstream/compose.yml -f /opt/stoat/overrides/docker-compose.override.yml images` shows the digests currently deployed.

## Post-Update Verification

1. Visit your Stoat URL and confirm it loads
2. Log in and send a test message
3. Upload a test file
4. Check logs for errors:

```bash
docker compose -f /opt/stoat/upstream/compose.yml -f /opt/stoat/overrides/docker-compose.override.yml \
  logs --since "5m" | grep -iE "error|panic|fatal"
```

## Updating Addons

Addon stacks are independent of the core update. Update them separately:

### Authentik

```bash
# Edit addons/authentik/.env and bump AUTHENTIK_TAG to the desired version
nano /opt/stoat/addons/authentik/.env

# Redeploy (preserves .env, data/, certs/)
bin/stoatctl deploy authentik
```

### Admin Panel

```bash
# Pull latest upstream admin panel code
git submodule update --remote addons/admin-panel/src

# Redeploy (preserves .env.local, rebuilds Docker image)
bin/stoatctl deploy admin
```

## Rollback

### Option 1: Vultr Snapshot (fastest, full rollback)

1. Go to Vultr Console -> Snapshots
2. Restore the pre-update snapshot
3. Wait for VPS to reboot

### Option 2: Roll Back Docker Images

If the issue is with new images but your data is fine:

```bash
cd /opt/stoat/upstream
export COMPOSE_FILE=/opt/stoat/upstream/compose.yml:/opt/stoat/overrides/docker-compose.override.yml

# Check git log for the previous commit
git log --oneline -5

# Checkout the previous version
git checkout <previous-commit-hash>

# Restart with old images
docker compose up -d
```

### Option 3: Restore from Backup

If data was corrupted during update:

```bash
cd /opt/stoat
bin/stoatctl restore latest
```

## Handling Breaking Changes

Upstream occasionally has breaking changes (config format changes, database migrations). Before updating:

1. Check the [upstream README notices section](https://github.com/revoltchat/self-hosted#notices)
2. Look for migration scripts in `upstream/migrations/`
3. If a migration is needed, follow the upstream instructions before running `docker compose up -d`

Known past breaking changes:
- **2024-09-30**: Autumn file server rewrite (requires migration script)
- **2024-11-28**: Config section rename (`api.vapid` -> `pushd.vapid`, `api.fcm` -> `pushd.fcm`, `api.apn` -> `pushd.apn`)

## Update Cadence

- **Monthly at minimum** for routine updates
- **Immediately** for security advisories (check upstream repo and GHSA notices)
