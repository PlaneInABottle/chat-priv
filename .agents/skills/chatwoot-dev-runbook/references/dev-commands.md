# Dev Commands

## Contents

- [Install and environment basics](#install-and-environment-basics)
- [Start the repo](#start-the-repo)
- [Docker development runtime](#docker-development-runtime)
- [Test and lint entrypoints](#test-and-lint-entrypoints)
- [Build and storybook-style entrypoints](#build-and-storybook-style-entrypoints)

## Install and environment basics

Repo-backed command entrypoints from `AGENTS.md` and `package.json`:

```bash
bundle install && pnpm install
eval "$(rbenv init -)"
```

Use `bundle exec` for Ruby CLI commands.

## Start the repo

Current repo entrypoints:

```bash
pnpm dev
pnpm start:dev
pnpm start:test
overmind start -f ./Procfile.dev
```

Current Procfiles show:

- `Procfile.dev`: Rails on port `3000`, Sidekiq, and Vite
- `Procfile.test`: Rails on port `5050`, Vite, and Sidekiq under `RAILS_ENV=test`

## Docker development runtime

The Docker runtime is production-isolated and starts only the services a job needs.
The native `pnpm dev` path above stays valid.

Entry point: `scripts/dev/compose.sh` - a thin wrapper over native `docker compose`
with the dev env files, project `kozmopath-dev`, and three files:
`docker-compose.yaml` + `docker-compose.dev.yaml` + `docker-compose.dev.voice.yaml`,
plus `docker-compose.dev.frontend.yaml` for the frontend/HMR topology.
`.env.server.local` is never loaded.

### Which service set for which job

| Job | Command | Services started |
| --- | --- | --- |
| API, rails console, rspec, rake, sidekiq | `scripts/dev/compose.sh core` | postgres, redis, rails, sidekiq |
| Browser UI, HMR, screenshots | `scripts/dev/compose.sh frontend` | core + vite |
| Email flows, inbound/outbound mail | `scripts/dev/compose.sh mail` | core + mailhog |
| Voice agent work (needs LiveKit/telephony) | `scripts/dev/compose.sh voice` | core + voice-agent |
| Everything except voice | `scripts/dev/compose.sh all` | core + vite + mailhog |

Set membership is declarative: `core`/`frontend`/`mail`/`voice`/`all` remove the
optional services that do not belong to the set (`rm -sf`, data volumes untouched), so
`all` -> `core` really leaves only `postgres redis rails sidekiq` running.

`vite` is behind the `frontend` profile, `mailhog` behind `mail`, `voice-agent` behind
`voice`, and the Dockerfile base target behind `build`, so `core` never waits for them.

**`core` cannot render the dashboard.** Chatwoot serves its JavaScript from Vite in
development, so without the vite service the layout still returns 200 but the entry
bundle 404s (or the manifest is missing on a fresh checkout) and every
`vite_dev_server_running?` probe costs a ~5s DNS timeout for the absent `vite` host.
Measured: `/app/login` renders in 0.29s with vite, 5.3s without; browser navigation to
the dashboard did not complete in 3 minutes without vite. Use `core` for backend, API,
console, rspec and rake work; use `frontend`/`all` for anything a browser renders.

### Two topologies

`core`/`mail`/`voice` give rails its own network; `frontend`/`all` put rails in the
vite network namespace so `localhost:3036` is the same address for the container and
the browser (this is what makes HMR possible - see below). Switching between the two
recreates the rails container (~35s, measured) and the wrapper removes the vite
container when you switch back to a backend-only set, because in the frontend topology
vite is the service that publishes 3050.

### Common commands

```bash
scripts/dev/compose.sh frontend          # start core + vite
scripts/dev/compose.sh frontend --build  # same, rebuilding images
scripts/dev/compose.sh ps                # full project view, whatever set created it
scripts/dev/compose.sh logs -f rails
scripts/dev/compose.sh migrate           # bundle exec rails db:chatwoot_prepare
scripts/dev/compose.sh console           # bundle exec rails console
scripts/dev/compose.sh test spec/models/user_spec.rb   # rspec against chatwoot_test
scripts/dev/compose.sh testprep          # load the schema into chatwoot_test (once)
scripts/dev/compose.sh sh                # shell in the rails container
scripts/dev/compose.sh config            # base model (profiles hidden unless enabled)
scripts/dev/compose.sh down              # stop and remove containers, keep dev volumes
scripts/dev/compose.sh down -v           # also destroy the dev database and volumes
```

Anything that is not a subcommand above is passed straight to `docker compose`.

First run only: `scripts/dev/compose.sh build base` builds `chatwoot:development`
(the rails and vite images are `FROM` it). That build is slow - measured ~35 min on
this host because `grpc` compiles its C++ extension; `chatwoot:development` is 4.09 GB.
`db:chatwoot_prepare` on the empty dev database takes ~34s and runs the seeds, which
create `john@acme.inc` / `Password1!`.

Tests run through `scripts/dev/compose.sh test <spec paths>`, which pins
`RAILS_ENV=test` **and** `POSTGRES_DATABASE=chatwoot_test`; without the second variable
`.env` would point the suite at the development database. On a fresh database run
`scripts/dev/compose.sh testprep` once first (~11s) - verified: `test spec/models/user_spec.rb`
gives `41 examples, 0 failures` in ~16s.

Measured startup on this host (warm volumes, single build already done):

| Set | `up -d` returns | ready |
| --- | --- | --- |
| `core` | 7s | 28s (`/health` 200) |
| `core` -> `frontend` | 5s | 40s (rails recreated, hands off port 3050 to vite) |
| `mail` | 7s | 30s |
| `all` | 5s | 38s |

### Ports

| Service | Host (loopback only) | Container |
| --- | --- | --- |
| rails | 3050 | 3000 |
| vite | 3036 | 3036 |
| postgres | 5433 | 5432 |
| redis | 6380 | 6379 |
| mailhog UI / SMTP | 8026 / 1026 | 8025 / 1025 |
| voice-agent health / metrics | 9190 / 9191 | 9090 / 9091 |

In `frontend`/`all` the 3050 binding belongs to the vite service, because rails shares
its namespace; `docker compose ps` shows that, and it is expected.

### Hot reload

Bind mount plus `RAILS_ENV=development` means edits reload without a rebuild:

- Ruby/ERB: the Rails reloader picks the change up on the next request.
- `.vue`/`.js`/styles: Vite HMR pushes the update into the open browser tab.

Rebuild or restart is needed only when image inputs change, not source:

- `docker/Dockerfile`, `docker/dockerfiles/*`, `docker/entrypoints/*` -> `--build`.
- `Gemfile.lock`, `package.json`, `pnpm-lock.yaml` -> `scripts/dev/compose.sh up -d`
  is enough: the entrypoints run `bundle install` / `pnpm install --force` on start.
- `services/voice_agent/uv.lock` -> `scripts/dev/compose.sh voice --build`.

Two details worth knowing before you debug HMR:

- Vite 7 rejects an unknown `Host` header (DNS rebinding guard). The `vite` service
  sets `__VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS=vite` so the vite_ruby proxy path
  answers 200 instead of `403 Blocked request. This host ("vite") is not allowed.`
- HMR cannot be tunnelled through Rails: vite_ruby proxies with `Net::HTTP`, which
  strips the hop-by-hop `Upgrade` header, so the socket opens and dies (code 1006).
  That is why the frontend topology uses `VITE_RUBY_SKIP_PROXY=true` and absolute
  dev asset URLs, so the browser talks to Vite directly.

### Isolation from the production runtime on this host

- Compose project `kozmopath-dev`; own network, own `dev_*` named volumes, own
  postgres/redis containers. Never point dev at 5432/6379.
- Never publish 3000, 5432, 6379, 9090, 9091 - those belong to the production stack.
- `./` is bind-mounted; `/app/log` and `/app/tmp` are dev volumes because production
  writes those same checkout paths. `/app/storage` is instead the gitignored host
  directory `tmp/dev-storage` (`git check-ignore` -> `.gitignore:/tmp/*`) bind-mounted
  in, so the owner stays host uid 1000 = container `chatwoot` and file uploads work.
  A named volume there is created root-owned and Active Storage fails with
  `Errno::EACCES` on `/app/storage/*`. The wrapper creates that directory before `up`
  because Docker would create a missing bind source as root.
- No external writes: `ACTIVE_STORAGE_SERVICE=local`, SMTP to mailhog with empty
  credentials, `ENABLE_PUSH_RELAY_SERVER=false`, empty `ASSET_CDN_HOST`, `FORCE_SSL=false`.
- Never run `docker system prune`, `docker volume prune`, or `down -v` on anything you
  did not create.
- Dev and production share this checkout, so a temporal edit to tracked source is
  visible in `git status`: `git restore` it after measuring. Running `db:migrate`
  also rewrites schema annotations (`annotate` touched `enterprise/app/models/call.rb`),
  so check `git status` after a `migrate` run.

## Test and lint entrypoints
```bash
pnpm test
pnpm test:watch
pnpm test:coverage
pnpm eslint
pnpm eslint:fix
bundle exec rspec spec/path/to/file_spec.rb
bundle exec rspec spec/path/to/file_spec.rb:LINE
pnpm ruby:prettier
```

For local RSpec runs that need the repo's native test env wrapper, use:

```bash
RAILS_ENV=test POSTGRES_DATABASE=chatwoot_test .agents/skills/chatwoot-ai-native-test/scripts/with-chatwoot-env.sh rbenv exec bundle exec rspec spec/path/to/file_spec.rb
```

Use `rbenv exec ruby -c` for syntax checks; the system Ruby may reject syntax supported by the repo Ruby.

## Build and storybook-style entrypoints

```bash
pnpm build:sdk
pnpm story:dev
pnpm story:build
pnpm story:preview
pnpm sync:i18n
```
