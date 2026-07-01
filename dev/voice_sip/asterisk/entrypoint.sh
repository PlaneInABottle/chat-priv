#!/usr/bin/env sh
set -eu

mkdir -p /etc/asterisk
mkdir -p /var/log/asterisk/cdr-csv

for template in /config/*.template; do
  target="/etc/asterisk/$(basename "${template%.template}")"
  envsubst < "$template" > "$target"
  sed -i '/=$/d' "$target"
done

cp /config/*.conf /etc/asterisk/ 2>/dev/null || true

exec asterisk -f -vvv
