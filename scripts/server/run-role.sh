#!/usr/bin/env bash

set -euo pipefail

role="${1:-}"
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

case "$role" in
  web)
    required_keys='SECRET_KEY_BASE FRONTEND_URL POSTGRES_HOST POSTGRES_DATABASE POSTGRES_USERNAME POSTGRES_PASSWORD REDIS_URL LIVEKIT_URL LIVEKIT_API_KEY LIVEKIT_API_SECRET VOICE_AGENT_INTERNAL_TOKEN'
    command=(bundle exec rails server -b 127.0.0.1 -p "${PORT:-3000}" -e production)
    ;;
  worker)
    required_keys='SECRET_KEY_BASE FRONTEND_URL POSTGRES_HOST POSTGRES_DATABASE POSTGRES_USERNAME POSTGRES_PASSWORD REDIS_URL LIVEKIT_URL LIVEKIT_API_KEY LIVEKIT_API_SECRET VOICE_AGENT_INTERNAL_TOKEN'
    command=(bundle exec sidekiq -C config/sidekiq.yml)
    ;;
  voice)
    required_keys='LIVEKIT_URL LIVEKIT_API_KEY LIVEKIT_API_SECRET CHATWOOT_INTERNAL_API_URL VOICE_AGENT_INTERNAL_TOKEN VOICE_AGENT_NAME'
    command=(uv run --directory services/voice_agent --frozen python agent.py start)
    ;;
  *)
    printf 'Usage: %s <web|worker|voice>\n' "$0" >&2
    exit 64
    ;;
esac

export SERVER_ROLE="$role"
export SERVER_REQUIRED_KEYS="$required_keys"

exec "$root/scripts/server/with-server-env.sh" "${command[@]}"
