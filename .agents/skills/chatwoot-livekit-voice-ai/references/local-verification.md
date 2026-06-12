# Local Verification Workflow

## Contents

- [Prerequisites](#prerequisites)
- [Runtime](#runtime)
- [Fast Checks](#fast-checks)
- [Browser Test Call](#browser-test-call)
- [Datastore Proof](#datastore-proof)
- [Worker Log Proof](#worker-log-proof)
- [Cleanup](#cleanup)
- [Local SIP Incident Notes](#local-sip-incident-notes)
- [Common Failures](#common-failures)

## Prerequisites

- `.env.local` must define `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `CHATWOOT_INTERNAL_API_URL`, `VOICE_AGENT_INTERNAL_TOKEN`, `VOICE_AGENT_NAME`, `VOICE_AGENT_ARCHITECTURE`, and provider-specific keys such as `GOOGLE_API_KEY`.
- For Gemini realtime, use `VOICE_AGENT_ARCHITECTURE=realtime` and `VOICE_AGENT_REALTIME_PROVIDER=gemini`.
- Keep `.env.local` out of git. Never print or commit secret values.
- The Python worker entrypoint is `services/voice_agent/agent.py`.
- The Rails dispatch path is `Voice::Livekit::AgentDispatchService`.
- Voice agents are separate from text AI agents. Configure them in Settings -> Voice AI -> Voice agents. Assign API sandbox inboxes inside each voice agent; do not use a separate global voice setup tab. Voice inbox settings select `voice_agent_id`; do not expect `ai_agent_id`, setting-level `greeting`, or setting-level `instructions`.
- Super Admin controls account-level Voice AI access and limits under `/super_admin/accounts/:id/edit`. Test calls are excluded from monthly minute and concurrent-call limits, but Voice AI must still be enabled for the account.
- Integration tools such as `ikas_catalog_search` and `ikas_lookup_order` are enabled per voice agent. Ikas tools also require the account `ikas_integration` feature, a connected `ikas` hook, and a completed storefront catalog sync.
- SIP/phone-number routing is modeled separately from browser test calls:
  - `VoiceProviderConnection` stores the account-level provider connection (`test_sip`, `manual_sip`, `netgsm`, or `livekit_number`).
  - `VoiceNumber` maps a dialed number and optional LiveKit trunk/dispatch IDs to a `VoiceInboxSetting`.
  - Super Admin config pages are `/super_admin/voice_provider_connections` and `/super_admin/voice_numbers`.
  - Real SIP-dispatched LiveKit calls can be bootstrapped when the worker POSTs `/internal/voice/calls/:provider_call_id/agent_context` with LiveKit job metadata. The bootstrapper resolves the voice number, creates a normal conversation-backed LiveKit `Call`, and returns the voice-agent runtime context.
- The local SIP harness lives in `dev/voice_sip`. It uses Dockerized Asterisk as a fake SIP provider:
  - Copy `dev/voice_sip/.env.example` to `dev/voice_sip/.env`.
  - Fill `VOICE_SIP_ACCOUNT_ID`, `VOICE_SIP_VOICE_INBOX_SETTING_ID`, `VOICE_SIP_PHONE_NUMBER`, `LIVEKIT_SIP_HOST`, and SIP auth values.
  - Run `dev/voice_sip/bin/setup-local-sip.sh`.
  - Start Asterisk with `cd dev/voice_sip && docker compose up -d --build`.
  - Register a softphone directly to the Mac LAN IP on UDP `5060` using `ASTERISK_SOFTPHONE_USER` / `ASTERISK_SOFTPHONE_PASSWORD`, then dial `ASTERISK_DIAL_EXTENSION`.
  - The harness uses split SIP transports: UDP `5060` advertises `ASTERISK_SOFTPHONE_*` addresses to the local softphone, while UDP `5061` advertises `ASTERISK_EXTERNAL_*` addresses to LiveKit Cloud.
  - If Asterisk contacts show a Linphone/Flexisip public relay instead of the phone LAN IP, the phone is not testing the local path. Disable the Linphone proxy/tunnel or use a local desktop softphone.

## Runtime

Use PM2-managed processes:

```bash
pm2 list
pm2 restart chatwoot-backend --update-env
pm2 restart chatwoot-worker --update-env
pm2 restart chatwoot-voice-agent --update-env
```

Start the voice agent if missing:

```bash
pm2 start zsh --name chatwoot-voice-agent -- -lc 'set -a; source /Users/Y_ALTAY1/Documents/simWoot/chatwoot/.env.local; set +a; cd /Users/Y_ALTAY1/Documents/simWoot/chatwoot/services/voice_agent; uv run python agent.py dev'
```

Start the Chatwoot Sidekiq worker if missing:

```bash
pm2 start zsh --name chatwoot-worker -- -lc 'set -a; source /Users/Y_ALTAY1/Documents/simWoot/chatwoot/.env.local; set +a; cd /Users/Y_ALTAY1/Documents/simWoot/chatwoot; eval "$(rbenv init -)"; bundle exec sidekiq -C config/sidekiq.yml'
```

The voice agent must log `registered worker` with `agent_name` matching `VOICE_AGENT_NAME`. The Sidekiq worker is required for live conversation-thread updates because Chatwoot broadcasts `message.created` and `message.updated` through queued `ActionCableBroadcastJob`s.

## Fast Checks

```bash
curl -fsS http://localhost:3000/health
python3 -m py_compile services/voice_agent/agent.py
set -a; source .env.local; set +a; uv run --directory services/voice_agent python -c "import agent; print(agent.voice_agent_architecture()); print(type(agent.build_session()).__name__)"
set -a; source .env.local; set +a; eval "$(rbenv init -)"; bundle exec rspec spec/services/voice/test_call_builder_spec.rb spec/services/voice/livekit/agent_dispatch_service_spec.rb spec/services/voice/telephony/inbound_call_bootstrapper_spec.rb spec/services/voice/transcript_appender_spec.rb spec/requests/internal/voice/calls_spec.rb
```

Use `uv lock --check --directory services/voice_agent` after dependency changes.

## Browser Test Call

1. Open `/app/accounts/:account_id/settings/voice-ai` with `agent-browser`.
2. Snapshot before clicking.
3. On the Voice agents tab, select or create the voice agent.
4. In that agent's Inbox assignments panel, assign an API sandbox inbox, choose fallback team/recording/status, then save the voice agent. The local verified path used account `36`, but always verify current local data.
5. On the Test call tab, choose the same voice agent and one of its assigned API inboxes. For Ikas voice tests, confirm `ikas_catalog_search` and `ikas_lookup_order` are checked after Ikas is connected and synced.
6. Click `Start test call`.
7. Confirm no floating incoming-call popup appears. Browser test calls are marked with `test_call: true`, do not create a normal Chatwoot conversation/contact/message, and are owned by the Voice AI settings panel.
8. Wait until `Join as test caller` is enabled and the setup fields are disabled.
9. Click `Join as test caller`.
10. Wait for the Browser status to become `Connected` and for the worker to connect to the realtime provider and post transcript.
11. To verify handoff tool detection, say a human-handoff request such as `Temsilciye baglanmak istiyorum`; after the worker calls `request_human_handoff`, confirm the `Transcript and tool calls` panel shows a `request_human_handoff` tool event via realtime updates. If the browser reconnects or misses a websocket event, use `Refresh` once to resync the current call payload.
12. End the call from the settings panel with `End test call`.
13. Confirm the Call status becomes `completed`, Browser status becomes `Disconnected`, and setup fields are editable again.

For the browser-only MVP flow, use `Join as test caller` in the Voice AI settings page to simulate the customer side. Default browser test calls intentionally have no conversation handoff surface. If human-agent takeover needs to be tested later, use a separate handoff rehearsal flow that creates an explicitly marked test conversation. The browser sends a per-tab `client_session_id` when requesting a LiveKit token; this prevents same-account tabs from reusing one LiveKit participant identity and disconnecting each other.

The floating incoming-call popup is LiveKit-aware. Accepting a LiveKit call from the popup should request `/api/v1/accounts/:account_id/voice/calls/:id/token`, move the popup from `Incoming call` to `Call in progress`, and stop the ringtone. The conversation bubble should treat that same tab's active popup session as connected, rather than offering another `Join live call` action for the same call. A hard browser reload does not rehydrate the local LiveKit media connection; rely on the server call status and stale-call finalizer after reload.

Expected proof:

- Rails returns `201 Created` for `/api/v1/accounts/:id/voice/test_calls`.
- The call payload includes `test_call: true`, `test_call_source: voice_ai_settings`, `test_call_initiated_by_user_id`, and nil `conversation_id`, `contact_id`, and `message_id`.
- The call metadata includes `voice_agent_id` and `voice_agent_dispatch.status = dispatched`.
- The worker fetches `/internal/voice/calls/:provider_call_id/agent_context` and receives voice-agent instructions, runtime provider/model/voice, and the enabled voice tool schemas.
- The worker receives a LiveKit job request for the room.
- After caller joins, the worker connects to the realtime provider.
- `POST /internal/voice/calls/:provider_call_id/transcript` stores at least one transcript segment.
- `POST /internal/voice/calls/:provider_call_id/tool_call` stores voice-agent tool events in `voice_tool_events` rows related to the call.
- The settings `Transcript and tool calls` panel updates in realtime over ActionCable. Use `Refresh` only as a manual resync after websocket reconnect or missed events.

For SIP/telephony-provider calls, expected additional proof:

- A `VoiceNumber` exists for the dialed number or LiveKit trunk/dispatch identifiers.
- The worker POSTs `/internal/voice/calls/:provider_call_id/agent_context` with job metadata containing at least one resolver signal such as `voice_number_id`, `to_number`, `livekit_inbound_trunk_id`, or `livekit_dispatch_rule_id`.
- Rails creates or reuses a `Call.livekit` row with `conversation_id`, `contact_id`, and `message_id` present.
- Call metadata includes `voice_number_id`, `voice_provider_connection_id`, `voice_inbox_setting_id`, `voice_agent_id`, and `livekit_room_name`.

## Handoff Rehearsal

Default browser test calls do not create normal Chatwoot conversations and cannot be handed off. Handoff testing should use a separate rehearsal flow or a real conversation-backed LiveKit call. For conversation-backed calls, verify:

1. The LiveKit voice-call message shows `Join live call`, `Take over`, and `End call`.
2. `POST /internal/voice/calls/<livekit_room_name>/handoff` marks `handoff_status: requested`.
3. `POST /api/v1/accounts/:account_id/voice/calls/:id/take_over` marks `handoff_status: accepted`, `ai_status: silent`, assigns the conversation, and removes agent worker participants when present.
4. `POST /api/v1/accounts/:account_id/voice/calls/:id/end` marks the call completed, refreshes the voice-call message payload, and calls LiveKit `DeleteRoom` so browser/SIP/agent participants leave the media room.

## Datastore Proof

Use Rails runner for direct evidence:

```bash
set -a; source .env.local; set +a; eval "$(rbenv init -)"; bundle exec rails runner 'call = Call.livekit.where(account_id: 19).order(id: :desc).first; puts({ id: call.id, status: call.status, room: call.livekit_room_name, test_call: call.test_call?, conversation_id: call.conversation_id, contact_id: call.contact_id, message_id: call.message_id, dispatch: call.meta["voice_agent_dispatch"], transcript: call.transcript, tool_events: call.voice_tool_events.order(:id).map { |event| { tool: event.tool, status: event.status, duration_ms: event.duration_ms, source: event.source } }, segments: call.transcript_segments.order(:id).map { |segment| { role: segment.role, text: segment.text, source: segment.source, conversation_id: segment.conversation_id } } }.to_json)'
```

Report only what is present in the DB/UI/logs. Do not infer audio success from dispatch alone.

## Worker Log Proof

Bounded log command:

```bash
pm2 logs chatwoot-voice-agent --lines 160 --nostream
```

Useful markers:

- `registered worker`
- `received job request`
- `received assignment`
- `connecting to Gemini Realtime API` or equivalent provider log
- `start reading stream`
- `session closed` after caller disconnect

Old PM2 logs can contain stale failures. Use `pm2 flush chatwoot-voice-agent` only when you need a clean proof window.

## Cleanup

Always end browser-created calls from the UI when possible.

If a manually created test dispatch is orphaned, delete the dispatch through LiveKit and mark the local call completed. Use a room-admin token, not participant tokens. Keep this as an emergency cleanup, not the normal path.

First identify recent calls:

```bash
set -a; source .env.local; set +a; eval "$(rbenv init -)"; bundle exec rails runner 'puts Call.livekit.order(id: :desc).limit(5).map { |call| { id: call.id, status: call.status, room: call.livekit_room_name, dispatch: call.meta["voice_agent_dispatch"] } }.to_json'
```

## Local SIP Incident Notes

This local failure chain happened during Asterisk -> LiveKit SIP testing and should be checked before guessing at model or prompt issues.

Symptoms:

- Phone could register/call, but the caller heard no AI or the call stopped answering.
- Chatwoot conversation showed a LiveKit call but `ai_status` stayed `waiting`.
- Some calls ended locally but the UI stayed stale.
- Logs contained old PM2 Python crashes, Rails `422 Phone number has already been taken`, or Asterisk CDR CSV errors.

Verified causes and fixes:

- **Wrong SIP/NAT shape**: the phone was sometimes reaching Asterisk through Linphone/Flexisip relay while Asterisk advertised one public address to both the local phone and LiveKit. The local harness now uses split transports: local softphone on UDP `5060` with `ASTERISK_SOFTPHONE_*` LAN addresses, LiveKit on UDP `5061` with `ASTERISK_EXTERNAL_*` public addresses.
- **Duplicate contact creation**: SIP-dispatched calls can reuse the same caller number. If `/internal/voice/calls/:provider_call_id/agent_context` returns `422 Phone number has already been taken`, fix or verify `Voice::InboundCallBuilder#ensure_livekit_contact!` reuses `account.contacts.find_by(phone_number: from_number)` before creating a LiveKit-identifier contact.
- **AI status stuck at waiting**: the worker must post lifecycle events. `agent_listening` or `agent_session_started` should move `ai_status` to `active`; `agent_session_ended` should move it to `completed`. Do not infer active AI from room dispatch alone.
- **Voice-call serialization crash**: if Rails logs mention `undefined method voice_recordings`, guard recording payload/URL access with `respond_to?(:voice_recordings)` for local class-load/overlay safety.
- **Asterisk CDR CSV error after hangup**: `Unable to open /var/log/asterisk/cdr-csv/Master.csv` is local harness logging noise, not a media-path failure. The harness entrypoint should create `/var/log/asterisk/cdr-csv`.
- **Misread Asterisk context**: `[from-livekit] exten => _.,1,Hangup()` handles inbound INVITEs from LiveKit, not RTP on an already bridged outbound call. Do not treat that line as proof that AI audio is being killed.

Useful proof commands:

```bash
# Enable only for a short call, then turn both off.
docker compose -f dev/voice_sip/docker-compose.yml exec -T asterisk asterisk -rx 'pjsip set logger on'
docker compose -f dev/voice_sip/docker-compose.yml exec -T asterisk asterisk -rx 'rtp set debug on'
docker compose -f dev/voice_sip/docker-compose.yml exec -T asterisk asterisk -rx 'rtp set debug off'
docker compose -f dev/voice_sip/docker-compose.yml exec -T asterisk asterisk -rx 'pjsip set logger off'
```

Healthy evidence from a real local SIP call:

- Asterisk shows RTP packets both from the softphone side and LiveKit media side, and sends packets to both sides.
- Voice agent logs show `start reading stream`, realtime provider connection, user and assistant transcript segments, optional `executing tool`, and `session closed` with `error: null`.
- Rails logs show successful `agent_context`, `transcript`, optional `execute_tool`, `end`, and `event` requests.
- The `Call.livekit` row ends with `status: completed`, `from_number` set to the real caller number, `ai_status: completed`, transcript segments present, and a sane `end_reason` such as `caller_disconnected`.

Ignore or de-prioritize these during local SIP debugging unless the call path itself fails:

- Old PM2 error logs from previous restarts. Use the latest room name or `pm2 flush` for a clean window.
- Asterisk startup warnings for ALSA/JACK, unused CDR/CEL database modules, missing optional codecs, or deprecated modules.
- Gemini 3.1 proactive greeting warnings; for SIP calls it may wait for caller speech before answering.

## Common Failures

- `Start test call` returns `422`: check Rails logs for the real error, then reproduce with `Voice::TestCallBuilder.perform!` in Rails runner.
- `Start test call` returns `403`: confirm Super Admin has enabled Voice AI for the account. Store admins can see current voice usage and limits on `/app/accounts/:account_id/settings/voice-ai`, but cannot change those account limits.
- Worker starts but no dispatch: confirm `VOICE_AGENT_NAME` matches the worker registration and the Rails dispatch payload.
- Dispatch succeeds but no transcript: confirm a standard participant joined the room; the worker waits for a caller before starting the session.
- DB state changes but the conversation UI does not update: confirm `chatwoot-worker` is running; without Sidekiq, queued ActionCable broadcasts will not reach the browser.
- SIP call creates a room but no AI answer: check `agent_context` first. A `422 Phone number has already been taken` means contact reuse by phone number is broken.
- SIP call appears connected but no audio: prove RTP both ways with Asterisk RTP debug. If only one side has RTP, inspect advertised/contact addresses before changing Rails or AI code.
- SIP call works but logs are unreadable: disable Asterisk `pjsip set logger` and `rtp set debug` after the proof window.
- Turn-detector model errors in realtime mode: pipeline-only imports probably loaded too early. Realtime mode should only register the provider plugin it uses.
- Hanging unjoined rooms: `VOICE_AGENT_WAIT_FOR_PARTICIPANT_TIMEOUT_SECONDS` should end rooms that never receive a caller.
