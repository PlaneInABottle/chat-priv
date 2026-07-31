#!/usr/bin/env bash

set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"

rbenv_root="${RBENV_ROOT:-${HOME}/.rbenv}"
if [ -x "${rbenv_root}/bin/rbenv" ]; then
  export RBENV_ROOT="$rbenv_root"
  export PATH="${RBENV_ROOT}/bin:${RBENV_ROOT}/shims:${PATH}"
fi

exec rbenv exec bundle exec ruby -e '
  require "dotenv"

  original_env = ENV.to_hash
  [".env", ".env.local", ".env.server.local"].each do |path|
    next unless File.exist?(path)

    Dotenv.parse(path).each do |key, value|
      ENV[key] = value unless original_env.key?(key)
    end
  end

  ENV["RAILS_ENV"] = "production"
  ENV["NODE_ENV"] = "production"
  ENV["RAILS_SERVE_STATIC_FILES"] = "true"
  ENV["RAILS_LOG_TO_STDOUT"] = "true"
  ENV["INSTALLATION_ENV"] ||= "linux_script"

  required_keys = ENV.fetch("SERVER_REQUIRED_KEYS", "").split
  missing = required_keys.select { |key| ENV[key].to_s.strip.empty? }
  if ENV["SERVER_ROLE"] == "voice" && %w[GOOGLE_API_KEY OPENAI_API_KEY].all? { |key| ENV[key].to_s.strip.empty? }
    missing << "GOOGLE_API_KEY or OPENAI_API_KEY"
  end
  abort "Missing required server environment variables: #{missing.join(", ")}" if missing.any?

  if %w[web worker].include?(ENV["SERVER_ROLE"])
    abort "VIPS_BLOCK_UNTRUSTED must be set to 1" unless ENV["VIPS_BLOCK_UNTRUSTED"] == "1"

    require "ruby-vips"
    abort "libvips 8.13 or newer and ruby-vips 2.2.1 or newer are required" unless Vips.respond_to?(:block_untrusted)
  end

  exec(*ARGV)
' "$@"
