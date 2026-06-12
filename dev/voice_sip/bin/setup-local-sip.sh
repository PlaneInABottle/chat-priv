#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -f .env.local ]]; then
  echo ".env.local is required for LiveKit and Chatwoot internal settings" >&2
  exit 1
fi

if [[ ! -f dev/voice_sip/.env ]]; then
  echo "Copy dev/voice_sip/.env.example to dev/voice_sip/.env first" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env.local
# shellcheck disable=SC1091
source dev/voice_sip/.env
set +a

eval "$(rbenv init -)"

mkdir -p dev/voice_sip/.generated

echo "Provisioning Chatwoot VoiceProviderConnection and VoiceNumber..."
bundle exec rails runner dev/voice_sip/bin/provision_chatwoot_number.rb | tee dev/voice_sip/.generated/chatwoot_voice_number.initial.json

export VOICE_SIP_VOICE_NUMBER_ID
VOICE_SIP_VOICE_NUMBER_ID="$(ruby -rjson -e 'puts JSON.parse(File.read("dev/voice_sip/.generated/chatwoot_voice_number.initial.json")).fetch("voice_number_id")')"

echo "Provisioning LiveKit SIP inbound trunk and dispatch rule..."
uv run --project services/voice_agent python dev/voice_sip/bin/provision_livekit_sip.py

export LIVEKIT_SIP_INBOUND_TRUNK_ID
export LIVEKIT_SIP_DISPATCH_RULE_ID
LIVEKIT_SIP_INBOUND_TRUNK_ID="$(ruby -rjson -e 'puts JSON.parse(File.read("dev/voice_sip/.generated/livekit_sip.json")).fetch("livekit_inbound_trunk_id")')"
LIVEKIT_SIP_DISPATCH_RULE_ID="$(ruby -rjson -e 'puts JSON.parse(File.read("dev/voice_sip/.generated/livekit_sip.json")).fetch("livekit_dispatch_rule_id")')"

echo "Updating Chatwoot VoiceNumber with LiveKit IDs..."
bundle exec rails runner dev/voice_sip/bin/provision_chatwoot_number.rb | tee dev/voice_sip/.generated/chatwoot_voice_number.final.json

cat <<EOF

Local SIP provisioning complete.

Start Asterisk:
  cd dev/voice_sip
  docker compose up -d --build

Softphone account:
  SIP server: 127.0.0.1
  Port: 5060 UDP
  Username: ${ASTERISK_SOFTPHONE_USER}
  Password: ${ASTERISK_SOFTPHONE_PASSWORD}

Dial:
  ${ASTERISK_DIAL_EXTENSION}

Generated state:
  dev/voice_sip/.generated/chatwoot_voice_number.final.json
  dev/voice_sip/.generated/livekit_sip.json
EOF
