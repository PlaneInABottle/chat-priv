#!/usr/bin/env bash

set -euo pipefail

role="${1:-}"
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

case "$role" in
  web)
    required_keys='SECRET_KEY_BASE FRONTEND_URL POSTGRES_HOST POSTGRES_DATABASE POSTGRES_USERNAME POSTGRES_PASSWORD REDIS_URL LIVEKIT_URL LIVEKIT_API_KEY LIVEKIT_API_SECRET VOICE_AGENT_INTERNAL_TOKEN VIPS_BLOCK_UNTRUSTED'
    command=(bundle exec rails server -b 127.0.0.1 -p "${PORT:-3000}" -e production)
    ;;
  worker)
    required_keys='SECRET_KEY_BASE FRONTEND_URL POSTGRES_HOST POSTGRES_DATABASE POSTGRES_USERNAME POSTGRES_PASSWORD REDIS_URL LIVEKIT_URL LIVEKIT_API_KEY LIVEKIT_API_SECRET VOICE_AGENT_INTERNAL_TOKEN VIPS_BLOCK_UNTRUSTED'
    command=(bundle exec sidekiq -C config/sidekiq.yml)
    ;;
  voice)
    required_keys='LIVEKIT_URL LIVEKIT_API_KEY LIVEKIT_API_SECRET CHATWOOT_INTERNAL_API_URL VOICE_AGENT_INTERNAL_TOKEN VOICE_AGENT_NAME VOICE_AGENT_HEALTH_HOST VOICE_AGENT_HEALTH_PORT VOICE_AGENT_PROMETHEUS_PORT'
    voice_python='/opt/kozmopath/voice-agent-current/bin/python'
    [[ -x "$voice_python" ]] || {
      printf 'Voice agent interpreter is missing or not executable: %s\n' "$voice_python" >&2
      exit 1
    }
    command=(bash -c 'cd -- "$1" && exec "$2" agent.py start' _ "$root/services/voice_agent" "$voice_python")
    ;;
  *)
    printf 'Usage: %s <web|worker|voice>\n' "$0" >&2
    exit 64
    ;;
esac

export SERVER_ROLE="$role"
export SERVER_REQUIRED_KEYS="$required_keys"

exec "$root/scripts/server/with-server-env.sh" "${command[@]}"
