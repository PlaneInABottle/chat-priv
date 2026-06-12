# Local SIP Voice AI Harness

This harness lets a softphone call the local Chatwoot Voice AI stack through a fake SIP provider:

```text
Softphone -> local Asterisk -> LiveKit SIP -> LiveKit room -> voice agent -> Chatwoot
```

Production swaps only the provider side:

```text
Customer phone -> Netgsm -> LiveKit SIP -> LiveKit room -> voice agent -> Chatwoot
```

## What This Tests

- Real SIP signaling into LiveKit.
- LiveKit SIP participant creation.
- LiveKit agent dispatch to `services/voice_agent/agent.py`.
- Chatwoot SIP bootstrap through `/internal/voice/calls/:provider_call_id/agent_context`.
- Conversation-backed `Call` creation, transcript storage, and tool execution.

## Prerequisites

- Docker is installed.
- `lk` CLI is installed and authenticated to the target LiveKit project.
- `uv` is installed.
- `.env.local` contains valid `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `VOICE_AGENT_INTERNAL_TOKEN`, `VOICE_AGENT_NAME`, and provider model keys.
- Chatwoot backend, worker, and `chatwoot-voice-agent` PM2 processes are running.
- Voice AI is enabled for the target account.
- A `VoiceAgent` exists and is assigned to a `VoiceInboxSetting`.

## Setup

1. Copy the local SIP env:

```bash
cp dev/voice_sip/.env.example dev/voice_sip/.env
```

2. Fill in `dev/voice_sip/.env`:

- `VOICE_SIP_ACCOUNT_ID`: target Chatwoot account id.
- `VOICE_SIP_VOICE_INBOX_SETTING_ID`: the voice inbox setting to route calls to.
- `VOICE_SIP_PHONE_NUMBER`: fake number for this test, for example `+908501112233`.
- `LIVEKIT_SIP_HOST`: LiveKit SIP endpoint without `sip:`, for example `abc123.sip.livekit.cloud`.
- `LIVEKIT_SIP_AUTH_USERNAME` and `LIVEKIT_SIP_AUTH_PASSWORD`: credentials Asterisk uses when sending INVITEs to LiveKit.
- `ASTERISK_SOFTPHONE_USER` and `ASTERISK_SOFTPHONE_PASSWORD`: local softphone credentials.
- `ASTERISK_SOFTPHONE_SIGNALING_ADDRESS` and `ASTERISK_SOFTPHONE_MEDIA_ADDRESS`: your Mac's LAN IP when calling from a phone on the same network.

Find the SIP host in LiveKit Cloud project settings, or use:

```bash
lk project list --json
```

The SIP URI is based on the project id without the `p_` prefix:

```text
ProjectId p_abc123 -> sip:abc123.sip.livekit.cloud
```

Leave `LIVEKIT_SIP_TRUNK_NAME` and `LIVEKIT_SIP_DISPATCH_NAME` blank unless you need custom names. The provisioner defaults them to names that include `VOICE_SIP_PHONE_NUMBER`.

3. Provision Chatwoot and LiveKit:

```bash
dev/voice_sip/bin/setup-local-sip.sh
```

The script:

- Creates or updates a `VoiceProviderConnection`.
- Creates or updates a `VoiceNumber`.
- Creates or reuses a LiveKit inbound SIP trunk.
- Creates or reuses a LiveKit SIP dispatch rule with `roomConfig.agents`.
- Updates `VoiceNumber` with the LiveKit trunk/rule ids.

4. Start Asterisk:

```bash
cd dev/voice_sip
docker compose up -d --build
```

5. Configure a softphone:

- SIP server: your Mac LAN IP, for example `192.168.1.13` when calling from a phone.
- Port: `5060`
- Transport: UDP
- Username: value of `ASTERISK_SOFTPHONE_USER`
- Password: value of `ASTERISK_SOFTPHONE_PASSWORD`
- Preferred codecs: G.722, PCMU, or PCMA. Avoid Opus-only softphone profiles for this local harness; the default Asterisk image can transcode G.722 to the LiveKit PCMU/PCMA leg, but does not include an Opus transcoder.

6. Dial:

```text
9000
```

or dial the full `VOICE_SIP_PHONE_NUMBER` if the softphone supports `+` numbers.

## Inspect Asterisk

```bash
dev/voice_sip/bin/asterisk-console.sh
```

Useful Asterisk commands:

```text
pjsip show endpoints
pjsip show contacts
pjsip set logger on
rtp set debug on
```

## Verify In Chatwoot

After a successful call:

- A `Call.livekit` row exists.
- `conversation_id`, `contact_id`, and `message_id` are present.
- `meta.voice_number_id`, `meta.voice_provider_connection_id`, `meta.voice_inbox_setting_id`, and `meta.voice_agent_id` are present.
- The conversation appears in the assigned inbox.
- Transcript segments are appended while the call proceeds.

Quick datastore check:

```bash
set -a; source .env.local; set +a; eval "$(rbenv init -)"; \
bundle exec rails runner 'call = Call.livekit.order(id: :desc).first; puts({ id: call.id, status: call.status, room: call.livekit_room_name, conversation_id: call.conversation_id, meta: call.meta.slice("voice_number_id", "voice_provider_connection_id", "voice_inbox_setting_id", "voice_agent_id") }.to_json)'
```

## NAT And Audio Notes

SIP signaling can work while RTP audio fails. The harness uses two SIP transports:

- `5060/udp` for the local softphone leg. It should advertise the Mac LAN IP to phones on the same network.
- `5061/udp` for the LiveKit Cloud leg. It can advertise the public IP when cloud SIP/media needs NAT hints.

Local Docker Asterisk is behind multiple NAT layers:

```text
Asterisk container -> Docker VM -> macOS -> router -> LiveKit Cloud
```

If the call reaches LiveKit but audio is one-way or silent:

- For local softphones, set `ASTERISK_SOFTPHONE_SIGNALING_ADDRESS` and `ASTERISK_SOFTPHONE_MEDIA_ADDRESS` to your Mac LAN IP.
- If needed, set `ASTERISK_EXTERNAL_MEDIA_ADDRESS` and `ASTERISK_EXTERNAL_SIGNALING_ADDRESS` to your public IP.
- Keep `ASTERISK_DOCKER_LOCAL_NET=172.16.0.0/12` so Asterisk rewrites Docker container SDP media addresses to the configured external media address.
- If Asterisk logs `Couldn't negotiate stream ... audio ... (nothing)` for the softphone endpoint, check the softphone codec list. G.722, PCMU, or PCMA should be enabled.
- Forward UDP `10000-10100` from your router to this machine.
- If local NAT remains problematic, run the same Asterisk config on a small public VPS. The Chatwoot/LiveKit setup remains the same.

## Cleanup

```bash
cd dev/voice_sip
docker compose down
```

Delete LiveKit trunks/dispatch rules from LiveKit Cloud if you want a clean slate. The setup script reuses resources by name, so repeated runs are safe unless you change names.
