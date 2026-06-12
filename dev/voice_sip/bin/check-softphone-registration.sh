#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -f dev/voice_sip/.env ]]; then
  echo "Copy dev/voice_sip/.env.example to dev/voice_sip/.env first" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source dev/voice_sip/.env
set +a

contacts="$(docker compose -f dev/voice_sip/docker-compose.yml exec -T asterisk asterisk -rx 'pjsip show contacts')"
endpoint="$(docker compose -f dev/voice_sip/docker-compose.yml exec -T asterisk asterisk -rx "pjsip show endpoint ${ASTERISK_SOFTPHONE_USER}")"

echo "$contacts"
echo

if ! grep -q "${ASTERISK_SOFTPHONE_USER}/sip:${ASTERISK_SOFTPHONE_USER}@" <<<"$contacts"; then
  echo "No registered softphone contact found for ${ASTERISK_SOFTPHONE_USER}." >&2
  exit 1
fi

contact_hosts="$(
  grep "${ASTERISK_SOFTPHONE_USER}/sip:${ASTERISK_SOFTPHONE_USER}@" <<<"$contacts" |
    sed -E "s/.*${ASTERISK_SOFTPHONE_USER}\\/sip:${ASTERISK_SOFTPHONE_USER}@([^: ]+).*/\\1/"
)"

if ! grep -Eq '^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.|127\.)' <<<"$contact_hosts"; then
  cat >&2 <<EOF
Softphone is not registered directly from a local/private address.

This usually means the softphone is using a public SIP proxy/relay account. Local SIP audio tests
will be unreliable or silent in that mode.

Configure a local SIP account:
  Server: ${ASTERISK_SOFTPHONE_SIGNALING_ADDRESS}
  Port: 5060
  Transport: UDP
  Username: ${ASTERISK_SOFTPHONE_USER}
  Password: ${ASTERISK_SOFTPHONE_PASSWORD}
  Codecs: G.722, PCMU, or PCMA
  Disable: proxy/relay, SRTP, ICE, and Opus-only profiles
EOF
  exit 2
fi

if ! grep -q 'allow.*(g722|ulaw|alaw)' <<<"$endpoint"; then
  echo "Softphone endpoint does not allow the expected local codecs: g722, ulaw, alaw." >&2
  exit 3
fi

echo "Softphone registration looks local and codec configuration is compatible."
