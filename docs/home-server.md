# Kozmopath home server runtime

This is the interim single-machine topology for the Kozmopath fork:

| Role | Runtime | Reason |
| --- | --- | --- |
| PostgreSQL | Docker Desktop | Stateful data with a named volume and a loopback-only port |
| Redis | Docker Desktop | Persistent Sidekiq queue/cache with a named volume and a loopback-only port |
| Rails web | PM2 | Runs the checked-out fork directly and binds only to `127.0.0.1:3000` |
| Sidekiq worker | PM2 | Uses the exact same checkout, Ruby bundle, and environment as Rails |
| Voice worker | PM2 | Uses the fork's locked Python environment and drains on shutdown |
| Caddy | systemd | Public TLS/reverse proxy once DNS is ready |
| Tailscale | systemd | Private administration and SSH access |

Do not run Vite in production. Compile assets once before restarting the PM2 roles.

## Environment

Create the ignored production override and restrict its permissions:

```bash
cp .env.server.example .env.server.local
chmod 600 .env.server.local
```

Fill every blank value required by the enabled integrations. Web and worker must use the same `SECRET_KEY_BASE`. Keep `CHATWOOT_INTERNAL_API_URL=http://127.0.0.1:3000` because the Voice worker runs on the same host.

## Stateful services

The server Compose file intentionally contains only PostgreSQL and Redis. Its volumes are external so `docker compose down -v` cannot delete them. Create them once, then use the wrapper so `.env.local` and `.env.server.local` override `.env` without passing unrelated application secrets into the containers:

```bash
docker volume inspect kozmopath-server_postgres_data >/dev/null 2>&1 || docker volume create kozmopath-server_postgres_data
docker volume inspect kozmopath-server_redis_data >/dev/null 2>&1 || docker volume create kozmopath-server_redis_data
scripts/server/compose.sh up -d
scripts/server/compose.sh ps
```

Both published ports bind to loopback. Never expose PostgreSQL or Redis through the router, Caddy, or a public tunnel.

## Host firewall

Before leaving this machine unattended, enable the host firewall. The checked-in script denies inbound traffic by default and permits SSH only over `tailscale0`:

```bash
sudo scripts/server/secure-host.sh
```

Do not disable SSH password authentication until a tested public key exists in `~/.ssh/authorized_keys`. Restricting port 22 to Tailscale provides the immediate network boundary without locking out the current password-only account.

## Prepare a release checkout

Use Node from `.nvmrc`, the Corepack-managed pnpm version, and the Ruby version from `.ruby-version`:

```bash
bundle install
pnpm install --frozen-lockfile
NODE_OPTIONS='--max-old-space-size=4096 --openssl-legacy-provider' scripts/server/with-server-env.sh bundle exec rake assets:precompile
POSTGRES_STATEMENT_TIMEOUT=600s scripts/server/with-server-env.sh bundle exec rails db:chatwoot_prepare
uv sync --locked --directory services/voice_agent
```

Take a verified PostgreSQL backup before migrations. Do not restore over the active database to test a backup; use a disposable database for restore drills.

## PM2 roles

Start or reload the three stateless roles together:

```bash
pm2 startOrReload ecosystem.server.config.cjs --update-env
pm2 save
pm2 list
```

Readiness checks:

```bash
curl -fsS http://127.0.0.1:3000/health
curl -fsS http://127.0.0.1:9090/
curl -fsS http://127.0.0.1:9091/metrics
```

The server profile disables `sidekiq_alive`: PM2 supervises the worker directly, so a second Sidekiq capsule and port 7433 would only add threads and attack surface.

## Public access

Keep SSH on Tailscale. The production Caddy configuration is in `ops/caddy/Caddyfile`. The public hostname must resolve to this server before Caddy can issue a certificate. Before customer traffic, choose one public path:

1. Cloudflare Tunnel to `http://127.0.0.1:3000`, or
2. DNS plus router forwarding of only ports 80/443 to Caddy.

Do not expose PM2, Docker, PostgreSQL, Redis, Voice health/metrics, or Caddy's admin endpoint. Confirm `FRONTEND_URL`, webhook URLs, SMTP, inbound email, and object storage use the final public hostname.

For the direct Caddy path, first point DNS to the home connection and forward router ports 80/443 to this machine. Then validate and install the configuration and open only those two public ports:

```bash
caddy validate --config ops/caddy/Caddyfile
sudo install -m 644 ops/caddy/Caddyfile /etc/caddy/Caddyfile
sudo ufw allow 80/tcp comment 'Caddy HTTP certificate redirect'
sudo ufw allow 443/tcp comment 'Caddy HTTPS'
sudo systemctl enable --now caddy
```

Do not run these publication commands while `www.app.kozmopath.com` still points to another provider.

## Backup and migration

Back up PostgreSQL with a custom-format `pg_dump`, validate it with `pg_restore --list`, and store a copy off this computer. Redis is not the system of record, but preserving its RDB avoids dropping queued work during a controlled move. Keep attachment data in the configured S3-compatible object store; if local storage is used, back up `storage/` separately.

For a later Render migration: stop customer writes and Sidekiq, take a final database dump, restore it into a clean PostgreSQL 16 database, run `db:chatwoot_prepare`, compare invariant counts, start Redis/Web/Worker/Voice, execute smoke tests, and only then move DNS.
