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

Fill every blank value required by the enabled integrations. Web and worker must use the same `SECRET_KEY_BASE`. Keep `VIPS_BLOCK_UNTRUSTED=1`; startup also requires libvips 8.13 or newer so untrusted Active Storage uploads cannot use unsafe image loaders. Keep `CHATWOOT_INTERNAL_API_URL=http://127.0.0.1:3000` because the Voice worker runs on the same host. For Cloudflare R2, replace `<cloudflare-account-id>` with the account identifier and use an Object Read & Write token restricted to only the configured bucket. Keep the bucket private, with its `r2.dev` URL and custom domains disabled.

The attachment and Voice-recording variables intentionally use the same private bucket and separate Voice objects under `voice-recordings/`. R2's browser CORS policy must allow only `https://app.kozmopath.com`, methods `GET`, `HEAD`, and `PUT`, headers `Content-Type`, `Content-MD5`, and `Content-Disposition`, and may expose `ETag`. The `AWS_*CHECKSUM*` settings keep Rails' existing MD5 integrity check while preventing the AWS SDK from adding a second checksum that R2 rejects.

## Stateful services

The server Compose file intentionally contains only PostgreSQL and Redis on the native Docker `default` context. Docker Desktop was removed after the native cutover because its stale CLI plugins overrode the packaged Compose version; it is not part of the server or rollback path. The external volumes prevent `docker compose down -v` from deleting project state. Create them once on the native context, then use the wrapper so `.env.local` and `.env.server.local` override `.env` without passing unrelated application secrets into the containers:

```bash
docker --context default volume inspect kozmopath-server_postgres_data >/dev/null 2>&1 || docker --context default volume create kozmopath-server_postgres_data
docker --context default volume inspect kozmopath-server_redis_data >/dev/null 2>&1 || docker --context default volume create kozmopath-server_redis_data
scripts/server/compose.sh up -d
scripts/server/compose.sh ps
```

Both published ports bind to loopback. Never expose PostgreSQL or Redis through the router, Caddy, or a public tunnel.

## Host firewall

Before leaving this machine unattended, enable the host firewall. The checked-in script denies inbound traffic by default, permits SSH over `tailscale0`, and permits only `192.0.2.12` on `wlo1` to establish the Beszel reverse tunnel:

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
/home/mirza/.local/bin/uv lock --check --directory services/voice_agent
```

Take a verified PostgreSQL backup before migrations. Do not restore over the active database to test a backup; use a disposable database for restore drills.

### Provision the Voice environment

The Voice role never invokes `uv` at runtime. It executes the stable path `/opt/kozmopath/voice-agent-current/bin/python`, while that symlink targets an immutable, commit-addressed environment. The deployment operator uses `/home/mirza/.local/bin/uv` only to provision locked dependencies. The environment must use `/usr/bin/python3.12`, be owned by `root:root`, and be readable and executable—but not writable—by the password-locked `kozmopath` runtime account.

Provision only after review and commit, from a clean checkout at the exact reviewed revision. Never reuse, overwrite, sync in place, or relocate an existing environment:

```bash
REVIEWED_SHA=$(git rev-parse HEAD)
[[ "$REVIEWED_SHA" =~ ^[0-9a-f]{40}$ ]]
test -z "$(git status --porcelain --untracked-files=no)"
DEST="/opt/kozmopath/voice-agent-$REVIEWED_SHA"
[[ ! -e "$DEST" && ! -L "$DEST" ]]

pkexec /usr/bin/install -d -o root -g root -m 0755 /opt/kozmopath
pkexec /usr/bin/bash -c 'set -euo pipefail; umask 022; test ! -e "$1"; UV_PROJECT_ENVIRONMENT="$1" exec "$2" sync --locked --directory "$3/services/voice_agent" --python /usr/bin/python3.12' _ "$DEST" /home/mirza/.local/bin/uv /home/mirza/Documents/Projects/chat-priv
pkexec /usr/bin/chown -R root:root "$DEST"
pkexec /usr/bin/chmod -R go-w "$DEST"
pkexec /usr/bin/find "$DEST" -type d -exec /usr/bin/chmod 0755 '{}' +
```

Before activation, reject any unexpected symlink or file resolution outside `$DEST`, except that `$DEST/bin/python` must resolve exactly to `/usr/bin/python3.12`. No path may resolve under `/home`. Verify imports both as the operator and as the isolated runtime account:

```bash
while IFS= read -r -d '' link; do
  resolved=$(readlink -f "$link")
  case "$resolved" in
    "$DEST"/*|/usr/bin/python3.12) ;;
    *) printf 'Rejected external symlink: %s -> %s\n' "$link" "$resolved" >&2; exit 1 ;;
  esac
done < <(/usr/bin/find "$DEST" -type l -print0)
test -z "$(/usr/bin/find "$DEST" -type l -exec readlink -f '{}' \; | /usr/bin/grep '^/home/' || true)"
test "$(readlink -f "$DEST/bin/python")" = /usr/bin/python3.12
"$DEST/bin/python" -c 'import aiohttp, livekit.agents'
pkexec --user kozmopath "$DEST/bin/python" -c 'import aiohttp, livekit.agents'
```

Record the previous target, create a same-directory temporary symlink, validate it, and atomically replace only the stable pointer. A destination or temporary-path collision is a hard stop:

```bash
PREVIOUS_VENV=$(readlink -f /opt/kozmopath/voice-agent-current || true)
TEMP="/opt/kozmopath/.voice-agent-current.$REVIEWED_SHA"
[[ ! -e "$TEMP" && ! -L "$TEMP" ]]
pkexec /usr/bin/ln -s "voice-agent-$REVIEWED_SHA" "$TEMP"
test "$(readlink -f "$TEMP")" = "$DEST"
test "$(readlink -f "$TEMP/bin/python")" = /usr/bin/python3.12
"$TEMP/bin/python" -c 'import aiohttp, livekit.agents'
pkexec /usr/bin/mv -Tf "$TEMP" /opt/kozmopath/voice-agent-current
test "$(readlink -f /opt/kozmopath/voice-agent-current)" = "$DEST"
```

If activation fails before the atomic rename, remove only the task-owned temporary symlink and leave the current pointer unchanged. If it fails after rename but before reload, atomically restore the recorded previous target when one exists; otherwise remove the new pointer and keep Voice disabled. Retain both the previous and reviewed versioned environments through runtime, browser, and observation-window acceptance.

## PM2 roles

The host runs web and worker as the password-locked `kozmopath` system account under the dedicated `kozmopath-pm2.service`. Reload them through the installed host command, which saves only `/var/lib/kozmopath/.pm2`:

```bash
/usr/local/bin/kozmopath-runtime reload
/usr/local/bin/kozmopath-runtime status
```

The runtime account has no supplementary, Docker, sudo, or LXD groups. Its systemd sandbox makes the checkout read-only except for `log/`, `storage/`, and `tmp/`; inherited named ACLs keep new checkout files and the three dotenv files readable but not writable. The project wrapper targets `kozmopath-web` and `kozmopath-worker` by default; `KOZMOPATH_VOICE_ENABLED=1` includes the Voice role only during an explicit Voice deployment. Voice is intentionally disabled in the current saved host runtime. Never run global PM2 lifecycle commands against the shared `/home/mirza/.pm2` daemon.

After the immutable environment and reviewed source/assets are activated as one compatible deployment unit, include Voice explicitly:

```bash
KOZMOPATH_VOICE_ENABLED=1 /usr/local/bin/kozmopath-runtime reload
/usr/local/bin/kozmopath-runtime status
```

Require web and worker to remain online, Voice to remain online beyond PM2 `min_uptime`, and bounded sanitized Voice logs to show successful LiveKit worker registration without restart churn.

Development AI-agent QA may temporarily replace `kozmopath-web`/`kozmopath-worker` with task-owned `chatwoot-backend`/`chatwoot-worker`. These roles share the same checkout, PostgreSQL, and Redis, so never run both workers during deterministic live tests. Stop only the conflicting named role, verify the branch-serving process and exactly one Sidekiq process, then restore `kozmopath-web` and `kozmopath-worker` before ending the session. The detailed sequence is maintained in `.agents/skills/chatwoot-ai-native-test/references/runtime-and-verification.md`.

Readiness checks:

```bash
curl -fsS -H 'X-Forwarded-Proto: https' http://127.0.0.1:3000/health
```

When Voice is explicitly enabled, also require non-empty responses:

```bash
curl -fsS http://127.0.0.1:9090/
curl -fsS http://127.0.0.1:9091/metrics
```

Rollback source, compiled assets, and the Voice environment pointer as one compatible unit. Before restoring/reloading prior source and assets, verify the recorded previous environment with the same ownership, interpreter-resolution, and import checks. Restore its pointer atomically:

```bash
ROLLBACK_TEMP="/opt/kozmopath/.voice-agent-current.rollback-$REVIEWED_SHA"
test -n "$PREVIOUS_VENV"
[[ "$PREVIOUS_VENV" = /opt/kozmopath/voice-agent-* ]]
[[ ! -e "$ROLLBACK_TEMP" && ! -L "$ROLLBACK_TEMP" ]]
pkexec /usr/bin/ln -s "$(basename "$PREVIOUS_VENV")" "$ROLLBACK_TEMP"
test "$(readlink -f "$ROLLBACK_TEMP")" = "$PREVIOUS_VENV"
pkexec /usr/bin/mv -Tf "$ROLLBACK_TEMP" /opt/kozmopath/voice-agent-current
test "$(readlink -f /opt/kozmopath/voice-agent-current)" = "$PREVIOUS_VENV"
```

Then restore prior source and compiled assets before reloading. Reload web and worker without Voice first and require their readiness. Enable Voice only if the restored runner uses `voice-agent-current` and the previous environment passes validation; during the inaugural migration, leave Voice disabled because the pre-change runner invokes inaccessible `uv`. Never delete failed or previous environments during recovery.

The Voice worker calls Rails over loopback HTTP. Its client marks only loopback HTTP requests with `X-Forwarded-Proto: https` so production SSL enforcement does not redirect those requests to a nonexistent TLS listener on port 3000.

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

This installation is currently a restricted demo and has no recurring Kozmopath backup job by owner decision. It is therefore not production-ready for irreplaceable data. The Docker Desktop package was removed without deleting its old user data, but that dormant data is not an ongoing backup or an active rollback runtime and must not be deleted until the demo data is disposable.

Back up PostgreSQL with a custom-format `pg_dump`, validate it with `pg_restore --list`, and store a copy off this computer. Redis is not the system of record, but preserving its RDB avoids dropping queued work during a controlled move. Keep attachment data in the configured S3-compatible object store; if local storage is used, back up `storage/` separately.

For a later Render migration: stop customer writes and Sidekiq, take a final database dump, restore it into a clean PostgreSQL 16 database, run `db:chatwoot_prepare`, compare invariant counts, start Redis/Web/Worker/Voice, execute smoke tests, and only then move DNS.
