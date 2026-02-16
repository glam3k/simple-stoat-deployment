# Operations Runbook

Day-to-day operations for the Stoat VPS.

## SSH Access

```bash
ssh deploy@YOUR-VPS-IP
# or
ssh deploy@chat.example.com
```

## Paths

| What | Path |
|------|------|
| Infra repo | `/opt/stoat` |
| Upstream (compose) | `/opt/stoat/upstream` |
| Scripts | `/opt/stoat/bin/` |
| Data (DB, files) | `/opt/stoat/upstream/data/` |
| Config | `/opt/stoat/upstream/Revolt.toml` |
| Web env | `/opt/stoat/upstream/.env.web` |
| Caddyfile (assembled) | `/opt/stoat/upstream/Caddyfile` |
| Caddyfile source | `/opt/stoat/overrides/Caddyfile.base` |
| Caddy fragments | `/opt/stoat/overrides/Caddyfile.d/*.caddy` |
| Image overrides | `/opt/stoat/overrides/docker-compose.override.yml` |
| Backup config | `/opt/stoat/backup.env` |
| Authentik | `/opt/stoat/addons/authentik/` |
| Admin panel | `/opt/stoat/addons/admin-panel/` |

## Docker Compose Helper

Run this once per SSH session so every `docker compose` command automatically loads the pinned override file:

```bash
export COMPOSE_FILE=/opt/stoat/upstream/compose.yml:/opt/stoat/overrides/docker-compose.override.yml
cd /opt/stoat/upstream
```

## Viewing Logs

```bash
# All services
docker compose logs -f --tail 100

# Specific service
docker compose logs -f api
docker compose logs -f caddy
docker compose logs -f database
docker compose logs -f events

# Addon logs
cd /opt/stoat/addons/authentik && docker compose logs -f
cd /opt/stoat/addons/admin-panel && docker compose logs -f

# System logs
journalctl -u docker --since "1 hour ago"
sudo journalctl -u ssh --since "1 hour ago"
```

## Service Management

```bash
# Check status
docker compose ps

# Restart a single service
docker compose restart api
docker compose restart caddy

# Restart everything
docker compose down && docker compose up -d

# Stop everything
docker compose down
```

## Deploy Commands

`bin/stoatctl` orchestrates deployments using `/opt/stoat/.env` as the single
source of truth.

```bash
# Core Stoat stack (deploy/stop/destroy)
bin/stoatctl deploy core
bin/stoatctl stop core
bin/stoatctl destroy core

# Addons
bin/stoatctl deploy authentik
bin/stoatctl deploy admin
bin/stoatctl deploy maintenance --domain example.com

# Re-run bootstrap standalone (e.g., to fix HR records)
bin/bootstrap.sh --domain chat.example.com --admin-email you@example.com

# Rebuild Caddyfile without redeploying
bin/rebuild_caddy.sh
```

## Resource Limits

The overrides file enforces conservative CPU/RAM limits for the core Stoat stack.
Adjust them in `/opt/stoat/.env` before deploying if your VPS has more (or less)
capacity:

| Service | CPU var (default) | Memory limit var (default) |
|---------|-------------------|---------------------------|
| MongoDB | `STOAT_DB_CPUS=1.5` | `STOAT_DB_MEMORY=2g` |
| KeyDB | `STOAT_REDIS_CPUS=0.5` | `STOAT_REDIS_MEMORY=512m` |
| RabbitMQ | `STOAT_RABBIT_CPUS=0.5` | `STOAT_RABBIT_MEMORY=1g` |
| MinIO | `STOAT_MINIO_CPUS=0.5` | `STOAT_MINIO_MEMORY=1g` |
| API | `STOAT_API_CPUS=1` | `STOAT_API_MEMORY=1g` |
| Events | `STOAT_EVENTS_CPUS=1` | `STOAT_EVENTS_MEMORY=1g` |
| Web | `STOAT_WEB_CPUS=0.5` | `STOAT_WEB_MEMORY=512m` |

Each service also has a `_MEMORY_RESERVATION` knob (see `.env.example`). Because
`stoatctl` always runs `docker compose` with the root `.env`, these values apply
automatically during deploys—no need to edit the upstream compose file.

## Readiness Waits

`bin/stoatctl wait-for-ready` blocks until a given service is passing its
readiness probes (same logic used in CI), so you can restart components and
have the CLI watch for them to settle.

```bash
# Core stack (wraps bin/healthcheck.sh)
bin/stoatctl wait-for-ready core

# Authentik readiness probe
bin/stoatctl wait-for-ready authentik

# Admin panel HTTPS check (use --insecure if you're trusting the internal CA)
bin/stoatctl wait-for-ready admin --insecure
```

## Health Check

```bash
/opt/stoat/bin/healthcheck.sh --domain chat.example.com
```

## Common Issues

### Disk Full

Symptoms: services crash, uploads fail, database errors.

```bash
# Check disk usage
df -h /
du -sh /opt/stoat/upstream/data/*

# Check Docker disk usage
docker system df

# Clean up unused images/volumes
docker system prune -f
```

### Out of Memory

Symptoms: services killed by OOM killer, random crashes.

```bash
# Check memory
free -h

# Check what's using memory
docker stats --no-stream

# Check OOM kills
dmesg | grep -i "out of memory"
```

If persistent, upgrade VPS size.

### TLS Certificate Renewal Failed

Caddy auto-renews Let's Encrypt certificates. If it fails:

```bash
# Check Caddy logs
docker compose logs caddy | grep -i "tls\|cert\|acme"

# Ensure port 80 is reachable (needed for HTTP challenge)
sudo ufw status | grep 80

# Restart Caddy to retry
docker compose restart caddy

# Quick HTTPS probe
bin/stoatctl wait-for-ready admin
```

Note: Let's Encrypt has a rate limit of 5 certificates per exact domain per 168 hours. If you hit this limit, wait for it to reset or use ZeroSSL as an alternative CA (see the `zerossl-ca` branch).

### MongoDB Issues

```bash
# Check DB health
docker compose exec database mongosh --eval "db.runCommand('ping')"

# Check DB size
docker compose exec database mongosh --eval "db.stats()"

# Check HR records (admin panel RBAC)
docker compose exec -T database mongosh revolt_hr --quiet --eval 'db.people.find().pretty()'
```

### Admin Panel SSO Not Working

1. Verify the person record email matches your Authentik login:
   ```bash
   docker compose exec -T database mongosh revolt_hr --quiet --eval 'db.people.find().pretty()'
   ```
2. Verify the role exists:
   ```bash
   docker compose exec -T database mongosh revolt_hr --quiet --eval 'db.roles.find().pretty()'
   ```
3. Check admin panel `.env.local` has correct values for `AUTHENTIK_ID`, `AUTHENTIK_SECRET`, `AUTHENTIK_ISSUER`
4. Verify Redis is reachable (should be `redis://redis:6379/0`, not `localhost`)
5. Check admin panel logs: `cd /opt/stoat/addons/admin-panel && docker compose logs -f`

### Can't Connect After Provisioning

If locked out after SSH hardening:

1. Use Vultr web console (VNC) to access the VPS
2. Fix `/etc/ssh/sshd_config`
3. `systemctl restart ssh`

## Maintenance Mode

To show a maintenance page while the core stack is down:

```bash
# Stop Stoat (frees ports 80/443)
bin/stoatctl stop core

# Start maintenance page
bin/stoatctl deploy maintenance --domain example.com

# ... do maintenance work ...

# Stop maintenance page (frees ports 80/443)
bin/stoatctl stop maintenance

# Bring Stoat back
bin/stoatctl deploy core
```
