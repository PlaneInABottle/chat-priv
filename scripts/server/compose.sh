#!/usr/bin/env bash

set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
env_args=(--env-file "$root/.env")

for path in "$root/.env.local" "$root/.env.server.local"; do
  if [ -f "$path" ]; then
    env_args+=(--env-file "$path")
  fi
done

exec docker --context default compose "${env_args[@]}" -f "$root/docker-compose.server.yaml" "$@"
