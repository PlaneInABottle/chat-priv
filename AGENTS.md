# Chatwoot Development Guidelines

## Build / Test / Lint
- **[Frontend] Node toolchain**: use the Node version in `.nvmrc` (currently Node 24) and the Corepack-managed pnpm version from `package.json` (pnpm 10). Do not run tests or builds with a globally selected older Node/pnpm pair.
- **[Both] Setup**: `bundle install && pnpm install` because dependencies span Ruby gems and pnpm packages.
- **[Both] Infrastructure**: `docker compose up -d postgres redis` starts the stateful local dependencies defined in `docker-compose.yaml`. Inspect `docker compose ps` first and reuse healthy existing containers.
- **[Both] Run Dev**: `pnpm dev` or `overmind start -f ./Procfile.dev` starts Rails, Sidekiq, and Vite from the checked-in Procfile.
- **[Both] Managed Dev Runtime**: for agent-managed native runs, use separate PM2 processes named `chatwoot-backend`, `chatwoot-worker`, and `chatwoot-vite`. Start Rails and Sidekiq through `.agents/skills/chatwoot-ai-native-test/scripts/with-chatwoot-env.sh` so native host overrides win over Docker-oriented `.env` values, and start Vite with the Node version from `.nvmrc`. Inspect `pm2 list` first and only stop or replace processes owned by the current task.
- **[Both] Readiness**: `curl -sSf http://localhost:3000/health` must return `{"status":"woot"}` before browser or API verification.
- **[Both] Run Project (foreman)**: `pnpm start:dev` or `pnpm start:test` because these scripts map to the current `package.json` Procfile runners.
- **[Frontend] Browser verification**: when using `agent-browser` for Chatwoot UI checks, prefer the reusable Chatwoot browser profile instead of `agent-browser` named sessions because the profile is the repo-standard persistent browser context.
- **[Backend] Seed Local Test Data**: `bundle exec rails db:seed` (quickly populates minimal data for standard feature verification).
- **[Backend] Seed Search Test Data**: `bundle exec rails search:setup_test_data` (bulk fixture generation for search/performance/manual load scenarios).
- **[Backend] Seed Account Sample Data (richer test data)**: `Seeders::AccountSeeder` is available as an internal utility and is exposed through Super Admin `Accounts#seed`, but can be used directly in dev workflows too:
  - UI path: Super Admin → Accounts → Seed (enqueues `Internal::SeedAccountJob`).
  - CLI path: `bundle exec rails runner "Internal::SeedAccountJob.perform_now(Account.find(<id>))"` (or call `Seeders::AccountSeeder.new(account: Account.find(<id>)).perform!` directly).
- **[Frontend] Lint JS/Vue**: `pnpm eslint` / `pnpm eslint:fix` because the script targets `app/**/*.{js,vue}`.
- **[Backend] Lint Ruby**: `pnpm ruby:prettier` or `bundle exec rubocop -a` because RuboCop is the configured formatter.
- **[Frontend] Test JS**: `pnpm test`, `pnpm test:watch`, or `pnpm test:coverage` because these are the Vitest scripts in `package.json`.
- **[Backend] Test Ruby**: `bundle exec rspec spec/path/to/file_spec.rb` because there is no npm wrapper for RSpec.
- **[Backend] Single Test**: `bundle exec rspec spec/path/to/file_spec.rb:LINE_NUMBER` because RSpec supports line targeting.
- **[Frontend] Build**: `pnpm build:sdk` and `pnpm story:build` because those are the only build scripts defined.
- **[Frontend] Histoire**: `pnpm story:dev` / `pnpm story:preview` because Histoire is the component explorer.
- **[Both] Ruby Version**: manage Ruby via `rbenv` and `.ruby-version` because Bundler must match the project Ruby.
- **[Both] rbenv setup**: prefer `rbenv exec bundle ...` or `rbenv exec ruby ...`; ensure `$HOME/.rbenv/bin` is on `PATH` instead of using shell `eval`.
- **[Both] Bundle exec**: always prefer `bundle exec` for Ruby CLI tasks because the gemset is locked in `Gemfile.lock`.

## Code Style
- **[Backend] Ruby**: follow RuboCop rules (150 character max line length) because `.rubocop.yml` enforces the style.
- **[Frontend] Vue/JS**: follow ESLint (Airbnb base + Vue 3 recommended) because `.eslintrc.js` is the single source of truth.
- **[Frontend] Vue Components**: use PascalCase because Vue tooling and imports assume that casing.
- **[Frontend] Events**: use camelCase because event listeners are case-sensitive in templates.
- **[Both] I18n**: avoid bare strings in templates because UI text must remain localized.
- **[Backend] Error Handling**: use custom exceptions (`lib/custom_exceptions/`) because shared rescue logic expects them.
- **[Backend] Models**: validate presence/uniqueness and add DB indexes because data integrity must be enforced at the database level.
- **[Frontend] Type Safety**: define prop types (`defineProps` or typed `props`) because PropTypes are not used and contracts still need validation.
- **[Backend] Params**: keep strong params strict because controller security depends on it.
- **[Both] Naming**: use clear, descriptive names with consistent casing because reviews prioritize readability.
- **[Frontend] Vue API**: prefer Composition API with `<script setup>` for new or migrated components because Vue 3 is the standard API.

## Styling (Frontend only)
- **[Frontend] Tailwind first**: use Tailwind utility classes in templates because the design system is Tailwind-first.
- **[Frontend] SCSS entrypoints**: place shared styles in existing SCSS entrypoints (`app/javascript/dashboard/assets/scss/`, `app/javascript/widget/assets/scss/`, `app/javascript/survey/assets/scss/`, `app/javascript/portal/application.scss`) because Tailwind is wired through those files.
- **[Frontend] `@apply` usage**: use `@apply` in SCSS when utilities are reused because it matches current styling patterns.
- **[Frontend] Scoped styles**: add scoped CSS only when utilities cannot express the UI because scoped CSS is harder to maintain.
- **[Frontend] Colors**: pull tokens from `tailwind.config.js` because it is the canonical palette.

## General Guidelines
- **[Both] MVP focus**: keep changes minimal and happy-path only because the surface area is large.
- **[Both] Avoid unnecessary defensive programming** because it slows iteration and obscures intent.
- **[Both] Ship the happy path first** because production feedback should drive guardrails.
- **[Both] Prefer minimal, readable code** because clarity beats cleverness in reviews.
- **[Both] Break down complex tasks** into small, testable units because CI and review cycles are faster.
- **[Both] Iterate after confirmation** because the project favors incremental delivery.
- **[Both] Targeted tests are required** when behavior, authorization, security controls, migrations, or public contracts change. Prefer the narrowest relevant existing spec files and add regression coverage for new logic.
- **[Both] Remove dead/unreachable/unused code** when touched because it reduces maintenance load.
- **[Both] Avoid duplicate implementations** because multiple versions drift quickly.
- **[Both] Prefer `with_modified_env` in specs** because it is the repo helper for env isolation.
- **[Both] In reloading/parallel specs, compare `error.class.name`** because class equality can break with reloading.
- **[Both] MVP scope does not weaken safety**: happy-path guidance never overrides authorization, SSRF protection, rate limiting for expensive endpoints, data integrity, or zero-downtime deployment requirements.

## Git Workflow

- Work in the normal checkout on a dedicated task branch by default. Do not create a git worktree unless the user explicitly requests one.
- Verify `git status` and `HEAD` before edits, and preserve all pre-existing dirty or untracked files.
- Never use `git reset`, `git clean`, checkout-based discard, or force push to remove user work without explicit authorization.
- Only stage files that belong to the current task; review the staged diff before committing.

## Commit Messages
- **[Both] Use Conventional Commits** (`type(scope): subject`) because release tooling expects that format.
- **[Both] Example**: `feat(auth): add user authentication` because scopes improve changelog clarity.
- **[Both] Do not reference AI tools** in commit messages because it adds noise to history.

## PR Description Format

- Start with a short, user-facing paragraph describing the product change.
- Add a `Closes` section with relevant issue links (GitHub, Linear, etc.).
- For feature PRs, add `How to test` from a product/UX standpoint.
- For bugfix PRs, use `How to reproduce` when helpful.
- Optionally add a `What changed` section for implementation highlights.
- Do not add a `How this was tested` section listing specs/commands.

## Project-Specific
- **[Both] Translations**: English and Turkish are maintained customer-facing source locales in this fork. Keep corresponding `en` and `tr` keys aligned; leave other community locales to Crowdin unless explicitly requested.
- **[Backend] Backend i18n**: update matching keys in `config/locales/{en,tr}.yml` because Rails loads backend translations from those YAML files.
- **[Frontend] Dashboard i18n**: update matching files under `app/javascript/dashboard/i18n/locale/{en,tr}/**` because the dashboard composes both maintained locales from those trees.
- **[Frontend] Widget/Survey i18n**: update matching keys in `app/javascript/{widget,survey}/i18n/locale/{en,tr}.json` because those apps import locale JSON directly.
- **[Frontend] Sync i18n**: run `pnpm sync:i18n` when the dashboard English `index.js` import list changes; the script copies that import manifest to the other dashboard locale folders and stages them.
- **[Frontend] Message bubbles**: use `app/javascript/dashboard/components-next/` because legacy message bubbles are being deprecated.

## AI Agent Catalog and Interactive Options

- **[Backend] Catalog response contract**: `ikas_catalog_search` is a normal tool. After a successful result, the model may answer in natural free-form language using catalog fields plus its own reasoning. Do not reintroduce semantic keyword regexes, evidence-only prose authorization, or a deterministic catalog-answer renderer unless the product requirement explicitly changes.
- **[Backend] Structural safeguards**: keep catalog query/tool budgets, bounded empty/truncated-output retries, one bounded unknown-tool correction, internal protocol leakage checks, trusted URL sanitization, live-response idempotency, and tool-side validation. These are operational or structural controls, not semantic claim policing.
- **[Backend] LLM payload boundary**: full sanitized tool events remain available for persistence and debugging; `AiAgents::LlmToolResultPresenter` creates the smaller model-facing catalog payload. Keep compaction separate from `IkasCatalogMvp::QueryEngine` and do not discard fields required by prompts or customer answers without updating its focused specs.
- **[Both] Option contract**: `present_options` is enabled by default unless the agent configuration explicitly disables it. Capability is decided by `supports_ai_input_select?` (default false); test conversations, Web Widget, and WhatsApp support it, while `Channel::Api` currently receives normal text fallback. Do not add a static channel-class allowlist.
- **[Both] Selection safety**: preserve selection contract version `1`, opaque option values, catalog-ID validation at creation, and stale-prompt rejection after later customer input. Widget retries of the same selection return the existing response, duplicate WhatsApp deliveries do not create another message, and the test panel permits only one submission; every path rejects a conflicting second selection.
- **[Both] Realistic verification**: load `chatwoot-ai-agent-local-testing` for stateful catalog/options/API testing. Use discoverable account/agent/inbox records rather than hardcoded IDs, verify public messages plus `AiAgentToolExecution`/`AiAgentLlmCall` persistence, and include typo-heavy input, changed constraints, no-match, free-form continuation, toggle-off, stale selection, repeated selection, and unsupported-channel text fallback.
- **[Both] Architecture reference**: read `docs/ai-agent-catalog-runtime.md` before changing Orchestrator, catalog result presentation, output sanitation, option capabilities, or selection handling.

## Home Server Production Runtime

- **[Both] Canonical topology**: use `docker-compose.server.yaml` only for PostgreSQL and Redis, and `ecosystem.server.config.cjs` for the PM2-managed Rails web, Sidekiq worker, and Python Voice worker. Do not recreate the obsolete all-in-Docker Chatwoot runtime for this host.
- **[Both] Persistent data**: the server Compose profile uses external volumes `kozmopath-server_postgres_data` and `kozmopath-server_redis_data`. Create missing volumes explicitly before first start; never delete, reset, or replace them while they contain the active server data.
- **[Both] Compose commands**: use `scripts/server/compose.sh <command>` because it pins the native Docker `default` context and applies `.env`, `.env.local`, and the ignored `.env.server.local` in the intended order without passing unrelated application secrets into database containers. Docker Desktop is disabled at login and normally stopped; start it manually only for development or rollback inspection, and never invoke the server profile with the development Compose file.
- **[Both] Server environment**: copy `.env.server.example` to ignored `.env.server.local`, keep it mode `600`, and run PM2 roles through `scripts/server/with-server-env.sh`. Never print environment files or secret values; verify sensitive settings through presence/shape checks only.
- **[Both] Prepare production code**: install locked dependencies, precompile assets with the Node version from `.nvmrc`, take and validate a PostgreSQL backup, run `db:chatwoot_prepare`, and run `uv sync --locked --directory services/voice_agent` before reloading PM2. The complete operator sequence and migration notes are in `docs/home-server.md`.
- **[Both] Start/reload**: start stateful services with `scripts/server/compose.sh up -d`, then use `scripts/server/reload-pm2.sh`. The wrapper targets only the three names in `ecosystem.server.config.cjs`; never run global `pm2 reload all`, `restart all`, `kill`, or `save` from a project deployment. PM2 startup persistence is a separately audited host-wide operation. The profile includes bounded restart delays so stateless roles can recover while native Docker becomes ready after boot.
- **[Both] Readiness**: require `curl -fsS -H 'X-Forwarded-Proto: https' http://127.0.0.1:3000/health`, `curl -fsS http://127.0.0.1:9090/`, and a non-empty response from `http://127.0.0.1:9091/metrics`. The forwarded-proto header reproduces the Cloudflare boundary and avoids treating Rails' expected loopback HTTPS redirect as health. Require PostgreSQL and Redis to report healthy and all three named PM2 apps to report online.
- **[Both] Debug safely**: begin with `git status`, `pm2 list`, `scripts/server/compose.sh ps`, the three readiness probes, and `ss -ltn`. Use bounded logs such as `pm2 logs <name> --nostream --lines 100` and `scripts/server/compose.sh logs --tail 100 <service>`; sanitize URLs, tokens, message content, and environment values before reporting output.
- **[Both] Network boundary**: Rails, Voice health/metrics, PostgreSQL, Redis, PM2, and Caddy admin must bind only to loopback. The stable named Cloudflare Tunnel may publish only `https://app.kozmopath.com` to `http://127.0.0.1:3000` and must end with a catch-all `http_status:404` ingress rule. The wildcard SSH socket is protected by default-deny UFW: allow it on `tailscale0`, plus only the tablet's exact `192.0.2.12` source on `wlo1` for the Beszel reverse tunnel. Never publish raw ports `3000`, `5432`, `6379`, `7433`, `9090`, or `9091` through UFW, router forwarding, or any tunnel.
- **[Both] Root actions**: on the interactive Linux desktop, prefer a narrowly scoped `pkexec <command>` so PolicyKit presents its graphical authentication dialog. Never request, accept, echo, pipe, store, or log the user's sudo password, and never grant passwordless sudo to a user-writable repository script.
- **[Both] Publication path**: the active home-server path is the enabled user service `cloudflared-kozmopath.service`; keep Caddy disabled as an optional direct-ingress fallback and keep router/UFW ports 80/443 closed while the Tunnel is used. Require the named Tunnel to be active after reboot, public HTTP to redirect to HTTPS, the origin address to remain unpublished, the private R2 bucket to have no public URL/custom domain, and browser/API health checks to pass.
- **[Both] Publication gate**: before customer traffic, require durable S3-compatible attachment and Voice-recording storage, tested off-machine database backups, a successful restore drill, healthy runtime probes, and required CI/security workflows passing on the exact pushed HEAD. SMTP may remain disabled for a restricted demo only when account signup is disabled and no email-dependent invite, recovery, or notification flow is promised; configure and test real SMTP before enabling those flows.
- **[Both] Host reliability**: this single-machine deployment needs stable power and networking. Do not call it unattended-production-ready without a UPS or healthy battery, preferably wired Ethernet, automatic boot of native Docker and PM2, and monitoring for disk, memory, process, database, and backup failures. Recurring Kozmopath backups are intentionally deferred while it remains a restricted demo, so its data is currently disposable by policy.

## Database Migrations

- Use expand/contract deployment sequencing: add compatible schema first, deploy code that stops using old columns, and remove or rename those columns only in a later release after old web and worker processes are gone.
- Keep `db/schema.rb` aligned with migrations because clean test and development databases may load the schema directly instead of replaying every migration.
- Test schema changes only against an explicitly named disposable local/test database. Never reset, drop, or roll back a shared or production database.
- When rollback is supported, restore the previous type, nullability, and default exactly; otherwise document forward-fix recovery.

## Ruby Best Practices
- **[Backend] Compact module/class definitions** because the codebase avoids deep nesting for readability.

## Enterprise Edition Notes
- **[Both] Check `enterprise/` overlays** when changing core behavior because Enterprise code can override OSS.
- **[Both] Use `prepend_mod_with`/`include_mod_with`** (see `config/initializers/01_inject_enterprise_edition_module.rb`) because overlays rely on those hooks.
- **[Both] Keep OSS/Enterprise contracts aligned** because both editions ship the same public APIs.
- **[Both] Add Enterprise specs under `spec/enterprise`** because CI expects mirrored spec structure.
- **[Both] Follow the Enterprise handbook** because it documents required patterns: https://chatwoot.help/hc/handbook/articles/developing-enterprise-edition-features-38

Practical checklist for any change impacting core logic or public APIs
- **[Both] Search in `app` and `enterprise`** before editing because overrides may exist (e.g., `rg -n "FooService|ControllerName|ModelName" app enterprise`).
- **[Both] Consider overlays or extension points** (e.g., `prepend_mod_with`, hooks, configuration) because hard forks drift quickly.
- **[Both] Avoid instance/plan hardcoding in OSS** because Enterprise consumes OSS via configuration and feature flags.
- **[Both] Keep request/response contracts stable** because Enterprise expects OSS API parity.
- **[Both] Mirror renames/moves in `enterprise/`** because the overlay must stay aligned.
- **[Both] Add Enterprise-specific specs under `spec/enterprise`** because behavior changes must be validated in both editions.
- **[Both] Prefer Enterprise modules over OSS edits** when behavior is Enterprise-only because `prepend_mod_with`/`include_mod_with` is the intended hook.

## Branding / White-labeling note

- For user-facing strings that currently contain "Chatwoot" but should adapt to branded/self-hosted installs, prefer applying `replaceInstallationName` from `shared/composables/useBranding` in the UI layer (for example tooltip and suggestion labels) instead of adding hardcoded brand-specific copy.

## Legacy / Exceptions to Know
- **[Frontend] Composition API adoption is mixed** because the repo has both `<script setup>` and Options API components.
- **[Frontend] Keep Options API files as-is** unless migration is requested because large rewrites are risky.
- **[Frontend] Vuex is still active** in dashboard/v3/widget/survey; Pinia is used only for new features (e.g., `dashboard/stores/*.js` for voice calls and companies), not as an ongoing migration.
- **[Frontend] Scoped styles and SCSS utilities exist** even though Tailwind is preferred because legacy styling is still in use.
- **[Frontend] Legacy components remain outside `components-next/`** because the migration is incremental.

## References (Repo Sources)
- **[Frontend] Styling**: `tailwind.config.js`, `postcss.config.js`, `app/javascript/dashboard/assets/scss/`, `app/javascript/widget/assets/scss/`, `app/javascript/survey/assets/scss/`, and `app/javascript/portal/application.scss` because they define the Tailwind pipeline.
- **[Frontend] i18n**: `app/javascript/dashboard/i18n/index.js` and `app/javascript/dashboard/i18n/locale/{en,tr}/**` because they show maintained locale composition.
- **[Frontend] Widget/Survey i18n**: `app/javascript/{widget,survey}/i18n/locale/{en,tr}.json` because those are the maintained app-specific JSON sources.
- **[Backend] i18n**: `config/locales/{en,tr}.yml` because Rails loads maintained backend strings from YAML.
- **[Both] Enterprise overlays**: `enterprise/` and `config/initializers/01_inject_enterprise_edition_module.rb` because they document override wiring.
- **[Both] Translation process**: README section "Translation process" because it links to Crowdin guidelines.

## Last Verified
- **Date**: 2026-07-17
- **Context**: Verified `package.json` scripts, `Procfile.dev`, `Procfile.test`, the development and home-server Compose profiles, PM2 web/worker/Voice roles, loopback listeners and readiness probes, the stable named Cloudflare Tunnel, private EU R2 attachment/Voice storage, production asset compilation, PostgreSQL/Redis persistence, rbenv and Node toolchains, dashboard English/Turkish locale composition, migration/schema workflow, Tailwind pipeline files, Enterprise overlay hooks, and the AI-agent catalog/options orchestration and real-inbox verification boundaries.
