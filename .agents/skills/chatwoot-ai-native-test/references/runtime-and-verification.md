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
