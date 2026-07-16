# Kozmopath home server runtime

This is the interim single-machine topology for the Kozmopath fork:

| Role | Runtime | Reason |
| --- | --- | --- |
| PostgreSQL | Native Docker Engine | Stateful data with a named volume and a loopback-only port |
| Redis | Native Docker Engine | Persistent Sidekiq queue/cache with a named volume and a loopback-only port |
| Rails web | PM2 | Runs the checked-out fork directly and binds only to `127.0.0.1:3000` |
| Sidekiq worker | PM2 | Uses the exact same checkout, Ruby bundle, and environment as Rails |
| Voice worker | PM2 | Uses the fork's locked Python environment and drains on shutdown |
| Cloudflare Tunnel | user systemd | Stable outbound-only public route for `app.kozmopath.com` |
| Caddy | systemd | Disabled direct-ingress fallback |
| Tailscale | systemd | Private administration and SSH access |

Do not run Vite in production. Compile assets once before restarting the PM2 roles.

## Environment

Create the ignored production override and restrict its permissions:

```bash
cp .env.server.example .env.server.local
chmod 600 .env.server.local
```

Fill every blank value required by the enabled integrations. Web and worker must use the same `SECRET_KEY_BASE`. Keep `CHATWOOT_INTERNAL_API_URL=http://127.0.0.1:3000` because the Voice worker runs on the same host. For Cloudflare R2, replace `<cloudflare-account-id>` with the account identifier and use an Object Read & Write token restricted to only the configured bucket. Keep the bucket private, with its `r2.dev` URL and custom domains disabled.

The attachment and Voice-recording variables intentionally use the same private bucket and separate Voice objects under `voice-recordings/`. R2's browser CORS policy must allow only `https://app.kozmopath.com`, methods `GET`, `HEAD`, and `PUT`, headers `Content-Type`, `Content-MD5`, and `Content-Disposition`, and may expose `ETag`. The `AWS_*CHECKSUM*` settings keep Rails' existing MD5 integrity check while preventing the AWS SDK from adding a second checksum that R2 rejects.

## Stateful services

The server Compose file intentionally contains only PostgreSQL and Redis on the native Docker `default` context. Docker Desktop remains installed for manual development and rollback inspection, but it is disabled at login, normally stopped, and is not the production datastore. Start or stop it explicitly with `systemctl --user start docker-desktop.service` and `systemctl --user stop docker-desktop.service`. The external volumes prevent `docker compose down -v` from deleting project state. Create them once on the native context, then use the wrapper so `.env.local` and `.env.server.local` override `.env` without passing unrelated application secrets into the containers:

```bash
docker --context default volume inspect kozmopath-server_postgres_data >/dev/null 2>&1 || docker --context default volume create kozmopath-server_postgres_data
docker --context default volume inspect kozmopath-server_redis_data >/dev/null 2>&1 || docker --context default volume create kozmopath-server_redis_data
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

Start or reload only the three Kozmopath roles through the project wrapper:

```bash
scripts/server/reload-pm2.sh
pm2 list
```

The shared PM2 daemon also owns other projects. Project deployment must never run `pm2 reload all`, `pm2 restart all`, `pm2 kill`, or `pm2 save`. The checked-in ecosystem and wrapper target only `kozmopath-web`, `kozmopath-worker`, and `kozmopath-voice`. Saving PM2 startup state is a deliberate host-wide operation performed only after every live process has been audited. Stopping `pm2-mirza.service` intentionally stops every PM2-managed project.

Readiness checks:

```bash
curl -fsS -H 'X-Forwarded-Proto: https' http://127.0.0.1:3000/health
curl -fsS http://127.0.0.1:9090/
curl -fsS http://127.0.0.1:9091/metrics
```

The server profile disables `sidekiq_alive`: PM2 supervises the worker directly, so a second Sidekiq capsule and port 7433 would only add threads and attack surface.

## Public access

Keep SSH on Tailscale. The active publication path is the stable named Cloudflare Tunnel managed by the enabled user service `cloudflared-kozmopath.service`. Its ingress configuration must route only `app.kozmopath.com` to `http://127.0.0.1:3000` and end with a catch-all `http_status:404` rule. The tunnel-specific credential is sufficient at runtime; remove broad Wrangler OAuth credentials and the account-level `cloudflared` certificate after configuration.

The Tunnel is outbound-only, so keep router forwarding and UFW ports 80/443 closed. Keep Caddy disabled. Do not expose PM2, Docker, PostgreSQL, Redis, Voice health/metrics, or Caddy's admin endpoint. Confirm `FRONTEND_URL`, webhook URLs, SMTP, inbound email, and object storage use `https://app.kozmopath.com`.

Verify the active path after reboot:

```bash
systemctl --user is-enabled cloudflared-kozmopath.service
systemctl --user is-active cloudflared-kozmopath.service
curl -fsS https://app.kozmopath.com/health
```

If the named Tunnel is deliberately retired, the production Caddy configuration in `ops/caddy/Caddyfile` remains a direct-ingress fallback. First point DNS to the home connection and forward router ports 80/443 to this machine. Then validate and install the configuration and open only those two public ports:

```bash
caddy validate --config ops/caddy/Caddyfile
sudo install -m 644 ops/caddy/Caddyfile /etc/caddy/Caddyfile
sudo ufw allow 80/tcp comment 'Caddy HTTP certificate redirect'
sudo ufw allow 443/tcp comment 'Caddy HTTPS'
sudo systemctl enable --now caddy
```

Do not run the Caddy publication commands while the Cloudflare Tunnel is active or while `app.kozmopath.com` points to another provider.

## Backup and migration

This installation is currently a restricted demo and has no recurring Kozmopath backup job by owner decision. It is therefore not production-ready for irreplaceable data. The Docker Desktop-to-native-Docker cutover retained the stopped Desktop volumes as rollback material; Desktop must be started manually to inspect or use them. They are not an ongoing backup and must not be deleted until the demo data is disposable.

Back up PostgreSQL with a custom-format `pg_dump`, validate it with `pg_restore --list`, and store a copy off this computer. Redis is not the system of record, but preserving its RDB avoids dropping queued work during a controlled move. Keep attachment data in the configured S3-compatible object store; if local storage is used, back up `storage/` separately.

For a later Render migration: stop customer writes and Sidekiq, take a final database dump, restore it into a clean PostgreSQL 16 database, run `db:chatwoot_prepare`, compare invariant counts, start Redis/Web/Worker/Voice, execute smoke tests, and only then move DNS.
