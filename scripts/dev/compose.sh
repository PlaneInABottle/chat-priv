#!/usr/bin/env bash

set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
env_args=(--env-file "$root/.env")

# Dev interpolation only. .env.server.local is deliberately left out: it carries
# the production profile and must never reach the local development stack.
if [ -f "$root/.env.local" ]; then
  env_args+=(--env-file "$root/.env.local")
fi

files=(
  -f "$root/docker-compose.yaml"
  -f "$root/docker-compose.dev.yaml"
  -f "$root/docker-compose.dev.voice.yaml"
)

compose() { docker compose "${env_args[@]}" "${files[@]}" "$@"; }

# Frontend work needs HMR, which its own overlay makes possible; see the file header.
compose_frontend() { compose -f "$root/docker-compose.dev.frontend.yaml" --profile frontend "$@"; }

# Lifecycle commands run against the superset model so teardown and inspection also
# cover services created by an earlier `frontend`/`mail`/`voice` run.
compose_features() { compose -f "$root/docker-compose.dev.frontend.yaml" --profile frontend --profile mail --profile voice "$@"; }

# A service set is declarative: services outside the requested set are removed, so
# `all` -> `core` really leaves only the backend running. `rm -sf` never touches the
# data volumes of postgres/redis.
prune_services() {
  for service in "$@"; do
    compose_features rm -sf "$service" >/dev/null 2>&1 || true
  done
}

# /app/storage is a host bind mount; Docker would create a missing source directory as
# root, so it has to exist as the invoking user first.
ensure_storage_dir() { mkdir -p "$root/tmp/dev-storage"; }

usage() {
  cat <<'USAGE'
Usage: scripts/dev/compose.sh <command> [args...]

Start a service set (services outside the set are removed):
  core       postgres redis rails sidekiq   backend work: API, console, rspec, rake
  frontend   core + vite                    browser UI work with HMR
  mail       core + mailhog                 email flows, inbox on http://localhost:8026
  voice      core + voice-agent             needs LiveKit or telephony credentials
  all        core + vite + mailhog          (voice stays separate by design)

core/mail/voice and frontend/all are two topologies: browser UI work needs the
frontend one because it is what makes HMR possible. Switching between them recreates
the rails container (~35s).

Tasks inside the running rails container:
  migrate    bundle exec rails db:chatwoot_prepare
  console    bundle exec rails console
  test       bundle exec rspec against chatwoot_test (run testprep once first)
  testprep   load the schema into chatwoot_test (RAILS_ENV=test)
  sh         shell

Everything else is passed straight to docker compose:
  scripts/dev/compose.sh ps
  scripts/dev/compose.sh logs -f rails
  scripts/dev/compose.sh down      # keeps dev volumes
  scripts/dev/compose.sh down -v   # destroys the dev database and volumes
USAGE
}

case "${1:-}" in
  '') usage; exit 2 ;;
  core) shift; ensure_storage_dir; prune_services vite mailhog voice-agent; compose up -d postgres redis rails sidekiq "$@" ;;
  frontend) shift; ensure_storage_dir; prune_services mailhog voice-agent; compose_frontend up -d "$@" ;;
  mail) shift; ensure_storage_dir; prune_services vite voice-agent; compose --profile mail up -d "$@" ;;
  voice) shift; ensure_storage_dir; prune_services vite mailhog; compose --profile voice up -d "$@" ;;
  all) shift; ensure_storage_dir; prune_services voice-agent; compose_frontend --profile mail up -d "$@" ;;
  # Inspection and teardown must see services started by any earlier set.
  ps) shift; compose_features ps "$@" ;;
  logs) shift; compose_features logs "$@" ;;
  down) shift; compose_features down "$@" ;;
  stop) shift; compose_features stop "$@" ;;
  migrate) shift; compose exec -T rails bundle exec rails db:chatwoot_prepare "$@" ;;
  console) shift; compose exec rails bundle exec rails console "$@" ;;
  # POSTGRES_DATABASE must be pinned: .env sets it to the development database, and
  # RAILS_ENV=test alone would run the suite against dev data (see AGENTS.md native path).
  test) shift; compose exec -T -e RAILS_ENV=test -e POSTGRES_DATABASE=chatwoot_test rails bundle exec rspec "$@" ;;
  testprep) shift; compose exec -T -e RAILS_ENV=test -e POSTGRES_DATABASE=chatwoot_test rails bundle exec rails db:test:prepare "$@" ;;
  sh) shift; compose exec rails sh "$@" ;;
  help|-h|--help) usage ;;
  *) compose "$@" ;;
esac
