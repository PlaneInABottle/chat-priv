#!/usr/bin/env bash

set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
pm2_bin="${PM2_BIN:-}"

if [[ -z "$pm2_bin" ]]; then
  pm2_bin=$(command -v pm2 || true)
fi
if [[ -z "$pm2_bin" && -d "$HOME/.nvm/versions/node" ]]; then
  pm2_bin=$(find "$HOME/.nvm/versions/node" -path '*/lib/node_modules/pm2/bin/pm2' -type f \
    | sort -V | tail -n 1)
fi
[[ -x "$pm2_bin" ]] || {
  printf 'Unable to locate an executable PM2 binary\n' >&2
  exit 1
}

exec "$pm2_bin" startOrReload "$root/ecosystem.server.config.cjs" \
  --only kozmopath-web,kozmopath-worker,kozmopath-voice \
  --update-env
