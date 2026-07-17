# Chatwoot AI-Native Runtime and Verification

## Verified repo facts

- Native app roles come from `Procfile.dev`: `backend`, `worker`, `vite`.
- `GET /health` returns `{"status":"woot"}`.
- Non-production seeds create `john@acme.inc` / `Password1!`.
- Local OSS development should not intentionally power Captain or Copilot.

## Canonical local flow

- Start Docker for `postgres` and `redis` from the existing compose file.
- Start Rails, Sidekiq, and Vite through `pnpm dev` (overmind + Procfile.dev).
- Seed the database if the local login is missing.
- Verify `/health`.
- Verify browser login at `/app/login`.
- Verify Captain or Copilot is absent or unusable before OSS AI-agent work.

## PM2-managed local runtime

- If PM2 is already managing this repo, run `pm2 list` before starting new processes.
- Common local process names are `chatwoot-backend`, `chatwoot-worker`, and `chatwoot-vite`; confirm names from `pm2 list`.
- After migrations, frontend changes, or service changes that affect browser verification, restart the Chatwoot PM2 processes and recheck health:

```bash
pm2 restart chatwoot-backend chatwoot-worker chatwoot-vite
curl -sSf http://localhost:3000/health
```

- Use `pm2 logs <name> --lines N --nostream` for worker/backend evidence. Prefer persisted DB evidence for final claims when logs are noisy.

## Production and task-process isolation

- This workstation's `kozmopath-web`/`kozmopath-worker` production roles and `chatwoot-backend`/`chatwoot-worker` development roles use the same checkout and currently reach the same PostgreSQL and Redis services. Treat them as mutually exclusive owners during branch-specific live QA.
- Before deterministic queue testing, inspect `pm2 list`, the process working directories, `ss -ltn`, and `Sidekiq::ProcessSet`. Stop only the conflicting named production role, then start or restart the matching task-owned role through `with-chatwoot-env.sh`.
- Never leave both `kozmopath-worker` and `chatwoot-worker` consuming the shared queues. A second worker makes message ownership and branch-code evidence nondeterministic.
- Port `3000` likewise has one owner. Do not claim feature code is loaded until the serving Rails process points at the expected checkout/HEAD and `/health` passes.
- When QA ends, stop the task worker, resume `kozmopath-worker`, restore `kozmopath-web` if it was displaced, and verify the production health boundary. Leave unrelated PM2 processes untouched.
- Check the active Sidekiq process count without dumping configuration:

```bash
.agents/skills/chatwoot-ai-native-test/scripts/with-chatwoot-env.sh bundle exec rails runner \
  'puts({ process_count: Sidekiq::ProcessSet.new.size }.to_json)'
```

## Checked-in runtime files

- Process orchestration: `Procfile.dev` (Rails, Sidekiq, Vite)
- Native env wrapper: `.agents/skills/chatwoot-ai-native-test/scripts/with-chatwoot-env.sh`

## Procfile process names (from Procfile.dev)

- `backend` (Rails on port 3000)
- `worker` (Sidekiq)
- `vite` (Vite dev server)

## Canonical commands

- Infra: `docker compose up -d postgres redis`
- App: `pnpm dev`
- Seed: `bundle exec rails db:seed`
- Health: `curl -sSf http://localhost:3000/health`

## Browser smoke flow

- Open `http://localhost:3000/app/login`.
- Sign in with `john@acme.inc` / `Password1!`.
- Wait for an authenticated dashboard URL.
- If login fails, seed the database and retry before treating it as a blocker.

## Local env rules

- Keep `.env` as the shared baseline.
- Keep `.env.local` as the ignored developer override.
- Do not populate local `CAPTAIN_OPEN_AI_*`, `OPENROUTER_API_KEY`, or derived `OPENAI_API_KEY` values unless a future task explicitly requires Captain.
- Restart the dev processes (stop with Ctrl+C and re-run `pnpm dev`) after `.env.local` changes so the loader re-reads both files.

## Verification contract

- Run the narrowest unit tests for any new pure logic.
- Run `curl http://localhost:3000/health` after boot.
- Run a real browser login check with `agent-browser` using the seeded user.
- Re-run the browser check after later runtime or auth-affecting changes.
- For inbox-bound AI tests, verify one intended Sidekiq consumer before traffic and restore the production worker afterward.
