# Admin Panel Add-on

This add-on packages the upstream Stoat admin panel (Next.js app) as a Docker service
attached to the shared `stoat` network.

## Contents
- `src/` — git submodule pointing to the admin panel fork
- `Dockerfile` — builds the panel using Bun
- `docker-compose.yml` — runs the panel container on the `stoat` network
- `.env.local.example` — copy to `.env.local` and fill in values

## Deployment

1. Initialize submodules if you haven't already:
   ```bash
   git submodule update --init --recursive addons/admin-panel/src
   ```
2. Copy env template and fill it out:
   ```bash
   cp addons/admin-panel/.env.local.example addons/admin-panel/.env.local
   nano addons/admin-panel/.env.local
   ```
   Key values:
   - `MONGODB=mongodb://database:27017/revolt` — uses the Docker service name
   - `REDIS=redis://redis:6379/0` — uses the Docker service name (not localhost)
   - `AUTHENTIK_ID` / `AUTHENTIK_SECRET` — from your Authentik OAuth provider
   - `AUTHENTIK_ISSUER` — auto-set from `.env` but verify on first run
   - `NEXTAUTH_URL` — auto-set from `.env` but verify on first run
   - `NEXT_PUBLIC_*` — URLs + contact info baked into the client bundle
   - `PLATFORM_ACCOUNT_ID` — set automatically by `bootstrap.sh`

   The deploy script writes `.env.build` automatically by extracting the
   `NEXT_PUBLIC_*` entries from `.env.local`. Only that small file is copied
   into the Docker image, so tweaking Authentik/DB secrets no longer invalidates
   the build cache — rebuilds are only required when you change the public URLs
   that the React client needs at compile time.

3. Deploy via `stoatctl` (reads hostnames from `/opt/stoat/.env`):
   ```bash
   bin/stoatctl deploy admin
   ```
   This builds the image, runs the compose stack, writes a Caddy fragment to
   `overrides/Caddyfile.d/admin-panel.caddy`, and rebuilds the Caddyfile. Each
   run syncs the derived URLs (NEXTAUTH_URL, AUTHENTIK_ISSUER, NEXT_PUBLIC_*) in
   `.env.local` so edits to the root `.env` propagate automatically.

## HR Database (RBAC)

The admin panel authorizes users via the `revolt_hr` MongoDB database. This is seeded
by `bootstrap.sh` (called automatically by `stoatctl deploy core`) using
`admin@BASE_DOMAIN` (override with `BOOTSTRAP_ADMIN_EMAIL`).

What gets seeded:
- **Administrator role** (`revolt_hr.roles`) — wildcard `["*"]` permissions
- **Admin person record** (`revolt_hr.people`) — links your Authentik email to the admin role
- **PLATFORM_ACCOUNT_ID** — written to `.env.local` automatically

The person record's `email` must match your Authentik login email. If it doesn't match,
update it manually:
```bash
docker compose -f /opt/stoat/upstream/compose.yml \
  -f /opt/stoat/overrides/docker-compose.override.yml \
  exec -T database mongosh revolt_hr --quiet --eval '
    db.people.updateOne(
      { _id: "01ADMIN_PERSON" },
      { $set: { email: "your-authentik-email@example.com" } }
    )
  '
```

## Data persistence

The admin panel is **stateless**. It reads from the core MongoDB instance and authenticates
via Authentik. Redeploying with `stoatctl deploy admin` rebuilds the Docker image but
preserves `.env.local`.

## Notes
- The container binds to 127.0.0.1:3100 by default; all public access should go
  through Caddy (which terminates TLS and proxies to the container on port 3000).
- Because the service joins the `stoat` network, it can reach `database`, `redis`,
  and `authentik-server` without exposing those ports.
- Update the submodule periodically to pick up upstream fixes:
  ```bash
  git submodule update --remote addons/admin-panel/src
  ```
