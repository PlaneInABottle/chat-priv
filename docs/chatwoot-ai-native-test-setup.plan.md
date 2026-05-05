# Chatwoot AI-Native Test Setup - Implementation Plan

## Problem Statement

This repo already contains most of the building blocks for AI-native development, but they are split across global skills, repo-local runbooks, Procfiles, and Docker files. The missing pieces are a thin Chatwoot-specific skill, an explicit native-process env-loading strategy for `.env.local`, and a reliable sync step from local AI env values into DB-backed `InstallationConfig` records so OpenRouter-backed Chatwoot AI paths can be verified instead of assumed.

## Approach

Smallest-viable setup: keep Docker for stateful services, use PM2 only for native app processes that mirror `Procfile.dev`, add one explicit local env bridge for PM2, and add one explicit AI config sync step to write OpenRouter-compatible settings into Chatwoot's existing `InstallationConfig` records.

## Success Criteria

- [ ] A new repo-local skill `chatwoot-ai-native-test` exists and stays thin by deferring generic guidance to existing skills.
- [ ] Native PM2-managed Rails/Sidekiq/Vite processes load `.env` + `.env.local` explicitly rather than relying on implicit dotenv behavior.
- [ ] Local OpenRouter values from `.env.local` are written into `CAPTAIN_OPEN_AI_*` installation configs before AI verification.
- [ ] Chatwoot can be verified later through `http://localhost:3000/health` and browser login with `john@acme.inc` / `Password1!`.
- [ ] Each later implementation phase includes both targeted unit tests and real browser verification.

## Current state (evidence)

### Facts observed

- Native dev shape is already defined by `Procfile.dev` with `backend`, `worker`, and `vite` roles: `Procfile.dev:1-4`.
- Existing start scripts already point at Procfiles/Overmind rather than PM2: `package.json:11-13`, `chatwoot-dev-runbook/references/dev-commands.md:21-35`.
- Docker Compose is already suitable for infra services and uses `.env`, not `.env.local`: `docker-compose.yaml:14`, `docker-compose.yaml:39`, `docker-compose.yaml:99`, `docker-compose.yaml:114`; `.dockerignore:2-3`.
- `.env.local` is ignored by git, but no checked-in repo file explicitly loads `.env.local`: `.gitignore:88-90`; repo search found no literal `.env.local` references.
- Rails does call `Dotenv::Rails.load` during boot: `config/application.rb:11-15`, but the checked-in native process definitions are inconsistent about explicit dotenv usage (`worker` uses `dotenv`, `backend` and `vite` do not): `Procfile.dev:1-4`.
- Main AI/Captain runtime paths read `InstallationConfig`, not env, for `CAPTAIN_OPEN_AI_API_KEY`, `CAPTAIN_OPEN_AI_MODEL`, and `CAPTAIN_OPEN_AI_ENDPOINT`: `config/initializers/ai_agents.rb:5-23`, `lib/llm/config.rb:33-47`, `config/installation_config.yml:185-197`.
- `ConfigLoader` syncs YAML metadata into `installation_configs`, but does not read env values: `lib/config_loader.rb:7-32`, `lib/config_loader.rb:40-67`.
- One enterprise path still reads `ENV['OPENAI_API_KEY']` directly while using `CAPTAIN_OPEN_AI_ENDPOINT` for the URL: `enterprise/app/models/enterprise/concerns/article.rb:68-81`.
- Seeded local login exists for non-production: `db/seeds.rb:11-30` creates `john@acme.inc` / `Password1!` and skips confirmation on line `29`.
- Health endpoint exists at `GET /health`: `config/routes.rb:38`, `app/controllers/health_controller.rb:3-6`.
- Dashboard/admin app is Vue-based: `app/javascript/dashboard/routes/index.js:1-17`, `app/javascript/dashboard/components-next/sidebar/Sidebar.vue:1-10`, `tailwind.config.js:24-36`.
- No repo-local skill equivalent to `chatwoot-ai-native-test` exists; the nearest local runbook is `chatwoot-dev-runbook`: `.agents/skills/chatwoot-dev-runbook/SKILL.md:1-18`.
- OpenRouter is not first-class in repo code; current AI config is OpenAI-compatible and endpoint-aware. OpenRouter docs use `https://openrouter.ai/api/v1`, while Chatwoot app code appends `/v1`, so Chatwoot should store the provider root as `https://openrouter.ai/api`: OpenRouter quickstart docs; `config/initializers/ai_agents.rb:16-18`; `enterprise/app/models/enterprise/concerns/article.rb:79-81`.

### Assumptions to keep explicit

- PM2 is available locally or can be installed later; this plan does not assume it is already installed.
- The provided `.env.local` contains a valid OpenRouter API key, but this plan does not assume any existing alias variables beyond that key.

---

## Phase 1: Add the lean repo-local skill

**Owner**: @implementer (skills + workflow)
**Dependencies**: None
**Complexity**: LOW

### Tasks

- [ ] Create `.agents/skills/chatwoot-ai-native-test/SKILL.md` with a narrow description: Chatwoot-specific native dev/test workflow, local AI config sync, PM2/Docker split, seeded login, and required verification checkpoints.
- [ ] Create `.agents/skills/chatwoot-ai-native-test/references/runtime-and-verification.md` with only Chatwoot-specific commands and evidence-backed caveats; defer generic PM2/browser/AI-native guidance to existing skills.
- [ ] Keep the skill metadata explicit about when to load it: local Chatwoot runtime prep, AI-native verification, seeded-login browser checks, and post-phase validation.
- [ ] Validate the skill with the repo/local skill validator later rather than adding unrelated code.

### Acceptance Criteria

- [ ] The new skill exists under `.agents/skills/chatwoot-ai-native-test/` and does not duplicate global skill bodies.
- [ ] The skill points readers back to `ai-native-workflow`, `chatwoot-dev-runbook`, `pm2-runtime-operator`, and `agent-browser` for generic guidance.
- [ ] The skill includes the verified seeded credentials and health check route.

---

## Phase 2: Add explicit native env loading and PM2 topology

**Owner**: @implementer (runtime setup)
**Dependencies**: Phase 1
**Complexity**: MEDIUM

### Tasks

- [ ] Add a tiny checked-in env loader script at `scripts/dev/with-chatwoot-env.sh` that explicitly loads `.env` first and `.env.local` second for native app processes, then `exec`s the requested command.
- [ ] In that loader, explicitly map the OpenRouter secret into native runtime compatibility env only where needed: prefer `OPENROUTER_API_KEY` as the single local secret source, and export `OPENAI_API_KEY` from it only if `OPENAI_API_KEY` is absent so the known enterprise env-only path remains functional.
- [ ] Add a PM2 ecosystem file at `ecosystem.dev.config.cjs` that mirrors `Procfile.dev` exactly: one process each for Rails, Sidekiq, and Vite, all launched through `scripts/dev/with-chatwoot-env.sh`.
- [ ] Keep Docker usage out of PM2; later startup should use existing `docker compose` service subsets for `postgres` and `redis` only, with `mailhog` documented as optional for email-heavy verification.
- [ ] Update the new skill reference with the exact startup split and restart rule: if `.env.local` changes, restart PM2 processes through the ecosystem so the wrapper re-reads files.
- [ ] Add/update unit-level tests only for any new pure logic extracted to support env resolution; do not add browser or integration specs for PM2 itself.

### Acceptance Criteria

- [ ] PM2 startup later can use one checked-in ecosystem file instead of ad-hoc one-off commands.
- [ ] Native process env behavior no longer depends on implicit `.env.local` loading.
- [ ] Docker remains the source for infra startup; `docker-compose.yaml` is reused instead of forked.

### Recommended `.env.local` strategy

- [ ] Keep `.env` as the shared baseline because checked-in Docker and repo automation use `.env`: `docker-compose.yaml:14,39,99,114`; `.circleci/config.yml:273-280`; deployment setup scripts.
- [ ] Keep `.env.local` as the ignored developer override file and secret source because `*.local` is already gitignored: `.gitignore:88-90`.
- [ ] Put the real OpenRouter secret in **one** variable: `OPENROUTER_API_KEY=...`.
- [ ] Put non-secret provider settings in `.env.local` as explicit Chatwoot-facing values:
  - `CAPTAIN_OPEN_AI_ENDPOINT=https://openrouter.ai/api`
  - `CAPTAIN_OPEN_AI_MODEL=<chosen-openrouter-model>`
- [ ] Do **not** store `/v1` in `CAPTAIN_OPEN_AI_ENDPOINT`; app code appends `/v1` itself: `config/initializers/ai_agents.rb:16-18`, `enterprise/app/models/enterprise/concerns/article.rb:79-81`.
- [ ] Let the loader script expose `OPENAI_API_KEY` from `OPENROUTER_API_KEY` only for runtime compatibility, instead of duplicating the secret in multiple env keys.

---

## Phase 3: Add explicit AI config sync into InstallationConfig

**Owner**: @implementer (backend runtime config)
**Dependencies**: Phase 2
**Complexity**: MEDIUM

### Tasks

- [ ] Add one explicit sync command/script, preferably `scripts/dev/sync_ai_installation_config.rb`, that reads the already-loaded env and writes `CAPTAIN_OPEN_AI_API_KEY`, `CAPTAIN_OPEN_AI_MODEL`, and `CAPTAIN_OPEN_AI_ENDPOINT` into `InstallationConfig`.
- [ ] Make the sync deterministic and idempotent: rerunning it should update the same keys without creating alternate config paths.
- [ ] Source the API key from `OPENROUTER_API_KEY` first, with optional fallback to `CAPTAIN_OPEN_AI_API_KEY` if explicitly provided later.
- [ ] Fail fast with a clear message if the API key or endpoint is missing, because silent partial config would create false-positive runtime assumptions.
- [ ] Reuse existing Chatwoot config storage instead of adding new tables, new provider abstractions, or OpenRouter-specific persistent config keys.
- [ ] Add/update unit tests for the pure write/sync logic if implemented as a small Ruby service/helper; keep browser/API verification outside language-specific integration tests.
- [ ] Update the new skill reference with the required ordering: DB/Redis up → app boot available → run sync → verify health/UI → run feature verification.

### Acceptance Criteria

- [ ] AI runtime later reads the OpenRouter-backed values from the same `InstallationConfig` keys that current Chatwoot code already expects.
- [ ] The sync path is idempotent and explicit, not hidden inside app boot.
- [ ] No new provider-specific storage model is introduced.

---

## Phase 4: Add verified startup and post-phase verification workflow

**Owner**: @implementer (verification)
**Dependencies**: Phase 3
**Complexity**: LOW

### Tasks

- [ ] Document the canonical later startup sequence in the new skill/reference and keep it aligned with checked-in files.
- [ ] Define one health check, one seeded-login browser smoke test, and one post-phase verification contract that future implementers must follow after each code phase.
- [ ] Ensure the contract requires both: (a) targeted unit tests for touched logic and (b) real browser verification via `agent-browser`.
- [ ] Keep verification minimal and repeatable; do not introduce heavy E2E suites or speculative tooling.

### Acceptance Criteria

- [ ] Later operators can start infra/app/runtime verification from one short sequence.
- [ ] Browser verification is explicit enough to hand directly to an implementer.
- [ ] The workflow remains lean and upgrade-safe.

---

## Deliverables

| Phase   | Files Created/Modified                                                                                                                                                                                                |
| ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Phase 1 | `.agents/skills/chatwoot-ai-native-test/SKILL.md`, `.agents/skills/chatwoot-ai-native-test/references/runtime-and-verification.md`                                                                                    |
| Phase 2 | `scripts/dev/with-chatwoot-env.sh`, `ecosystem.dev.config.cjs`, `.agents/skills/chatwoot-ai-native-test/references/runtime-and-verification.md`                                                                       |
| Phase 3 | `scripts/dev/sync_ai_installation_config.rb`, `spec/lib/dev/sync_ai_installation_config_spec.rb` or equivalent narrow unit-test file, `.agents/skills/chatwoot-ai-native-test/references/runtime-and-verification.md` |
| Phase 4 | `.agents/skills/chatwoot-ai-native-test/references/runtime-and-verification.md`                                                                                                                                       |

## File / Path Impact List

### New files (recommended)

- `.agents/skills/chatwoot-ai-native-test/SKILL.md`
- `.agents/skills/chatwoot-ai-native-test/references/runtime-and-verification.md`
- `scripts/dev/with-chatwoot-env.sh`
- `ecosystem.dev.config.cjs`
- `scripts/dev/sync_ai_installation_config.rb`
- `spec/lib/dev/sync_ai_installation_config_spec.rb` (or nearest narrow Ruby unit-spec location matching the implementation)

### Existing files expected to remain unchanged

- `Procfile.dev`
- `docker-compose.yaml`
- `config/application.rb`
- `config/installation_config.yml`

### Existing files to reference, not edit unless implementation forces it

- `db/seeds.rb`
- `config/routes.rb`
- `app/controllers/health_controller.rb`
- `.agents/skills/chatwoot-dev-runbook/SKILL.md`
- `.agents/skills/chatwoot-dev-runbook/references/dev-commands.md`

## Blast Radius / Affected Entry Points

- `Procfile.dev` parity - PM2 should mirror this shape, not redefine roles.
- `docker-compose.yaml` service subset startup - Docker remains responsible for Postgres/Redis and optional Mailhog.
- AI/Captain runtime - reads `InstallationConfig` via `config/initializers/ai_agents.rb:9-18` and `lib/llm/config.rb:33-47`.
- Enterprise article generation path - still depends on `OPENAI_API_KEY` env at runtime: `enterprise/app/models/enterprise/concerns/article.rb:68-81`.
- Browser login path - unauthenticated users are redirected to `/app/login`: `app/javascript/dashboard/routes/index.js:16-18`.

## Allowed Scope / Forbidden Scope

- Allowed: local dev/runtime setup files, one thin repo-local skill, one explicit AI config sync path, one PM2 ecosystem file, one env loader, narrow unit tests for new logic, and verification documentation.
- Forbidden: changing Chatwoot production deployment flow, refactoring AI provider architecture, changing Docker Compose topology beyond service selection guidance, adding new persistent config tables, adding broad E2E suites, or modifying unrelated product features.

## Invariants

| Invariant                                              | Why it matters                                                     | How to verify                                                                                        |
| ------------------------------------------------------ | ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------- |
| `Procfile.dev` remains the native role source of truth | Avoid drift between Overmind/native and PM2 runtime shapes         | Compare PM2 ecosystem roles against `Procfile.dev:1-4`                                               |
| Docker Compose remains `.env`-based                    | Avoid breaking existing repo and deployment assumptions            | Verify no compose file changes are required; later `docker compose config` shows existing files only |
| AI runtime continues using `CAPTAIN_OPEN_AI_*` keys    | Reuse existing Chatwoot config paths instead of inventing new ones | Later inspect `InstallationConfig` rows and confirm reads via app behavior                           |
| Endpoint excludes `/v1` in stored config               | Prevent malformed `.../v1/v1/...` requests                         | Later inspect stored config and run one AI smoke request path                                        |

## Behavior That Must Not Change

- Existing non-AI local boot path must still work for developers using `.env` only - validated by health check and standard startup.
- Seeded login credentials and dashboard redirect behavior must stay intact - validated by seeded login browser test.
- Docker infra behavior for Postgres/Redis must remain compatible with current compose files - validated by `docker compose ps` later.

## Recommended PM2 / Docker Startup Strategy

- **Docker**: later run only infra services from existing compose: `postgres`, `redis`, and optionally `mailhog` when email flows are under test.
- **PM2**: later run exactly three native app processes through the env loader and ecosystem file: Rails server, Sidekiq worker, and Vite dev server.
- **Why this split is simplest**: it reuses the checked-in infra definitions and the checked-in native app shape without forcing app code into containers during iterative UI/backend work.
- **Why not rely on implicit `.env.local`**: repo evidence shows explicit `.env` usage for Docker and inconsistent dotenv usage for native processes; explicit loader + PM2 ecosystem removes ambiguity.

## Validation Matrix

| Check                    | Command / Method                                                                                                                             | Proves                                                               |
| ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| Infra up                 | `docker compose up -d postgres redis` then `docker compose ps`                                                                               | Required stateful services are ready without starting app containers |
| PM2 app boot             | `pm2 start ecosystem.dev.config.cjs` then `pm2 list`                                                                                         | Native app roles start under named PM2 processes                     |
| Health check             | `curl -sSf http://localhost:3000/health`                                                                                                     | Rails booted successfully and responds on the expected port          |
| Seed data                | `bundle exec rails db:seed` (or existing prepare flow) then inspect login in browser                                                         | Local seeded user exists                                             |
| AI config sync           | `bundle exec rails runner scripts/dev/sync_ai_installation_config.rb` or equivalent runner form                                              | OpenRouter-backed values are written to `InstallationConfig`         |
| Browser login            | `agent-browser open http://localhost:3000/app/login` → `snapshot -i` → fill `john@acme.inc` / `Password1!` → submit → wait for dashboard URL | Browser path is actually usable                                      |
| Negative login case      | Repeat browser login with wrong password and verify sign-in does not reach dashboard                                                         | Auth failure path still behaves safely                               |
| Post-phase unit check    | Run only targeted unit tests for touched files                                                                                               | Logic changes are covered without adding brittle integration tests   |
| Post-phase browser check | Re-run `agent-browser` on the changed UI/workflow after each phase                                                                           | Real UI behavior matches expectations                                |

## What to test after each future phase

- **After skill-only changes**: validate the skill structure locally and confirm no runtime files changed.
- **After runtime/env changes**: targeted unit tests for any new Ruby helper/service, plus health check and seeded login.
- **After AI config sync changes**: targeted unit tests for sync logic, verify stored `InstallationConfig` values, then run one browser path that exercises the affected feature if available.
- **After UI/backend feature phases later**: run the narrowest relevant unit tests first, then browser-verify the exact changed path plus one nearby unchanged path.

## Evidence Owners

| Item                               | Owner        | Proof Required                                                    |
| ---------------------------------- | ------------ | ----------------------------------------------------------------- |
| Skill thinness / non-duplication   | @implementer | Skill diff showing delegation to existing skills                  |
| Explicit `.env.local` loading      | @implementer | Loader script + PM2 ecosystem diff                                |
| AI config stored in DB-backed keys | @implementer | Rails runner output or DB inspection of `InstallationConfig` rows |
| Health endpoint availability       | @implementer | `curl` output from `/health`                                      |
| Browser login viability            | @implementer | `agent-browser` trace/screenshot or command transcript            |
| Scope control                      | @analyzer    | Review confirming no unrelated app/runtime refactor               |

## Failure Signals

- PM2 processes only work when started from a manually primed shell, which would mean env loading is still implicit.
- Stored AI endpoint includes `/v1`, causing double-appended request paths.
- `OPENROUTER_API_KEY` is present but AI features still read blank `CAPTAIN_OPEN_AI_API_KEY`, meaning DB sync is missing or incomplete.
- Browser login succeeds only intermittently or requires non-seeded credentials, meaning setup instructions are not deterministic.

## Review Gates

| Gate       | After Phase | Focus Area                                                                             |
| ---------- | ----------- | -------------------------------------------------------------------------------------- |
| **Gate 1** | Phase 1     | Skill is thin, correctly scoped, and evidence-backed                                   |
| **Gate 2** | Phase 2     | PM2/Docker split is explicit, minimal, and not relying on implicit env behavior        |
| **Gate 3** | Phase 3     | AI config sync writes only existing `CAPTAIN_OPEN_AI_*` keys and remains idempotent    |
| **Gate 4** | Phase 4     | Verification workflow is concrete, repeatable, and includes both unit + browser checks |

## Risk Assessment

| Risk                                                                          | Likelihood | Impact | Mitigation                                                                                |
| ----------------------------------------------------------------------------- | ---------- | ------ | ----------------------------------------------------------------------------------------- |
| PM2 caches stale env after `.env.local` changes                               | MEDIUM     | MEDIUM | Use wrapper-based file loading and require PM2 restart via ecosystem after env edits      |
| OpenRouter endpoint stored with `/v1` and double-appended by app code         | MEDIUM     | HIGH   | Store `https://openrouter.ai/api` only; verify against app code before implementation     |
| Main AI paths still fail because env was not synced into `InstallationConfig` | HIGH       | HIGH   | Add explicit sync step and verify rows before browser/API testing                         |
| Enterprise article path diverges from Captain config path                     | LOW        | MEDIUM | Export `OPENAI_API_KEY` from `OPENROUTER_API_KEY` in the loader for runtime compatibility |
| Skill duplicates existing global skills and becomes stale                     | MEDIUM     | LOW    | Keep skill short and Chatwoot-specific; delegate generic behavior to existing skills      |

## Rollback Notes

- Remove `ecosystem.dev.config.cjs` and stop/delete the PM2 processes to return to `pnpm dev` / Overmind workflow.
- Remove `scripts/dev/with-chatwoot-env.sh` to return native startup to existing repo entrypoints.
- Remove `scripts/dev/sync_ai_installation_config.rb` and clear only the affected `CAPTAIN_OPEN_AI_*` `InstallationConfig` values if the sync approach proves wrong.
- Remove the `chatwoot-ai-native-test` skill folder if the repo-local skill adds no durable value.

## Recommended Skill Structure / Content

### `SKILL.md`

- Frontmatter:
  - `name: chatwoot-ai-native-test`
  - `description:` Chatwoot-specific native dev/test setup, PM2 + Docker split, OpenRouter-to-Chatwoot AI config sync, seeded browser login verification, and post-phase unit/browser verification workflow.
- Body sections:
  - Scope and boundaries
  - Quick navigation to existing skills
  - Canonical startup order
  - AI config caveat: `InstallationConfig` vs env
  - Seeded login + health verification

### `references/runtime-and-verification.md`

- Sections:
  - Verified repo facts with file references
  - Later startup sequence
  - `.env.local` rules
  - PM2 process names
  - AI config sync command
  - `agent-browser` login smoke flow
  - Post-phase checklist: targeted unit tests + browser verification

### Explicitly avoid in the skill

- Repeating generic PM2 command docs already covered by `pm2-runtime-operator`
- Repeating generic browser interaction rules already covered by `agent-browser`
- Repeating generic AI-native philosophy already covered by `ai-native-workflow`

## Notes

- No change is required to `Procfile.dev`; mirror it.
- No change is required to `docker-compose.yaml`; select service subsets from it.
- Prefer one secret source (`OPENROUTER_API_KEY`) over duplicated keys in `.env.local`.
- If later implementation needs a helper class for testability, keep it under a narrow `lib/dev/` namespace instead of broad app refactors.

## Decision Log

| Decision                    | Chosen                                              | Rejected                                  | Rationale                                                                                   | Evidence                                                                                        |
| --------------------------- | --------------------------------------------------- | ----------------------------------------- | ------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| Native app process manager  | PM2 ecosystem mirroring `Procfile.dev`              | Overmind-only, Dockerized app processes   | PM2 gives durable named processes while keeping app code native and matching existing roles | `Procfile.dev:1-4`, `package.json:11-13`                                                        |
| Infra runtime               | Existing Docker Compose services for Postgres/Redis | New compose file or fully native DB/Redis | Existing compose file already defines healthy infra services and uses repo conventions      | `docker-compose.yaml:92-129`                                                                    |
| Local secret source         | `.env.local` with explicit loader                   | Implicit dotenv/PM2 behavior              | Repo does not explicitly wire `.env.local`; explicit loading removes ambiguity              | `.gitignore:88-90`, `config/application.rb:11-15`, `Procfile.dev:1-4`                           |
| AI config persistence       | Sync into `InstallationConfig`                      | Env-only runtime                          | Main AI paths read DB-backed config, not env                                                | `config/initializers/ai_agents.rb:9-18`, `lib/llm/config.rb:41-46`, `lib/config_loader.rb:7-32` |
| OpenRouter endpoint storage | `https://openrouter.ai/api`                         | `https://openrouter.ai/api/v1`            | Chatwoot app appends `/v1` itself                                                           | OpenRouter quickstart docs; `config/initializers/ai_agents.rb:16-18`                            |
