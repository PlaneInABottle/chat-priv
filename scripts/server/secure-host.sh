#!/usr/bin/env bash

set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
  printf 'Run this script with sudo: sudo %s\n' "$0" >&2
  exit 77
fi

command -v ufw >/dev/null
ip link show tailscale0 >/dev/null
ip link show wlo1 >/dev/null

ufw default deny incoming
ufw default allow outgoing
ufw allow in on tailscale0 to any port 22 proto tcp comment 'SSH over Tailscale only'
ufw allow in on wlo1 from 192.0.2.12 to any port 22 proto tcp comment 'Beszel tunnel from tablet'
ufw --force enable
ufw status verbose
