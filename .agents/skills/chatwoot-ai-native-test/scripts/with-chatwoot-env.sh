#!/usr/bin/env bash

set -euo pipefail

if ! command -v rbenv >/dev/null 2>&1; then
  rbenv_root="${RBENV_ROOT:-${HOME}/.rbenv}"

  if [ -x "${rbenv_root}/bin/rbenv" ]; then
    export RBENV_ROOT="${rbenv_root}"
    export PATH="${RBENV_ROOT}/bin:${RBENV_ROOT}/shims:${PATH}"
  fi
fi

if [ "$#" -eq 0 ]; then
  printf 'Usage: %s <command> [args...]\n' "$0" >&2
  exit 1
fi

bundle exec ruby -e '
  require "dotenv"

  original_env = ENV.to_hash

  [".env", ".env.local"].each do |path|
    next unless File.exist?(path)

    Dotenv.parse(path).each do |key, value|
      next if original_env.key?(key)

      ENV[key] = value
    end
  end

  exec(*ARGV)
' "$@"
