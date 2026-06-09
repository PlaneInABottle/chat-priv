# Local Verification Workflow

## Contents

- [Prerequisites](#prerequisites)
- [Runtime](#runtime)
- [Fast Checks](#fast-checks)
- [Browser Test Call](#browser-test-call)
- [Datastore Proof](#datastore-proof)
- [Worker Log Proof](#worker-log-proof)
- [Cleanup](#cleanup)
- [Common Failures](#common-failures)

## Prerequisites

- `.env.local` must define `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `CHATWOOT_INTERNAL_API_URL`, `VOICE_AGENT_INTERNAL_TOKEN`, `VOICE_AGENT_NAME`, `VOICE_AGENT_ARCHITECTURE`, and provider-specific keys such as `GOOGLE_API_KEY`.
- For Gemini realtime, use `VOICE_AGENT_ARCHITECTURE=realtime` and `VOICE_AGENT_REALTIME_PROVIDER=gemini`.
- Keep `.env.local` out of git. Never print or commit secret values.
- The Python worker entrypoint is `services/voice_agent/agent.py`.
- The Rails dispatch path is `Voice::Livekit::AgentDispatchService`.

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
set -a; source .env.local; set +a; eval "$(rbenv init -)"; bundle exec rspec spec/services/voice/test_call_builder_spec.rb spec/services/voice/livekit/agent_dispatch_service_spec.rb spec/services/voice/transcript_appender_spec.rb spec/requests/internal/voice/calls_spec.rb
```

Use `uv lock --check --directory services/voice_agent` after dependency changes.

## Browser Test Call

1. Open `/app/accounts/:account_id/settings/voice-ai` with `agent-browser`.
2. Snapshot before clicking.
3. Select an API inbox. The local verified path used account `19` and inbox `19`, but always verify current local data.
4. Click `Start test call`.
5. Confirm no floating incoming-call popup appears. Browser test calls are marked with `test_call: true`, do not create a normal Chatwoot conversation/contact/message, and are owned by the Voice AI settings panel.
6. Wait until `Join as test caller` is enabled and the setup fields are disabled.
7. Click `Join as test caller`.
8. Wait for the Browser status to become `Connected` and for the worker to connect to the realtime provider and post transcript.
9. To verify handoff tool detection, say a human-handoff request such as `Temsilciye baglanmak istiyorum`; after the worker calls `request_human_handoff`, confirm the `Transcript and tool calls` panel shows a `request_human_handoff` tool event via realtime updates. If the browser reconnects or misses a websocket event, use `Refresh` once to resync the current call payload.
11. End the call from the settings panel with `End test call`.
12. Confirm the Call status becomes `completed`, Browser status becomes `Disconnected`, and setup fields are editable again.

For the browser-only MVP flow, use `Join as test caller` in the Voice AI settings page to simulate the customer side. Default browser test calls intentionally have no conversation handoff surface. If human-agent takeover needs to be tested later, use a separate handoff rehearsal flow that creates an explicitly marked test conversation. The browser sends a per-tab `client_session_id` when requesting a LiveKit token; this prevents same-account tabs from reusing one LiveKit participant identity and disconnecting each other.

The floating incoming-call popup is LiveKit-aware. Accepting a LiveKit call from the popup should request `/api/v1/accounts/:account_id/voice/calls/:id/token`, move the popup from `Incoming call` to `Call in progress`, and stop the ringtone. The conversation bubble should treat that same tab's active popup session as connected, rather than offering another `Join live call` action for the same call. A hard browser reload does not rehydrate the local LiveKit media connection; rely on the server call status and stale-call finalizer after reload.

Expected proof:

- Rails returns `201 Created` for `/api/v1/accounts/:id/voice/test_calls`.
- The call payload includes `test_call: true`, `test_call_source: voice_ai_settings`, `test_call_initiated_by_user_id`, and nil `conversation_id`, `contact_id`, and `message_id`.
- The call metadata includes `voice_agent_dispatch.status = dispatched`.
- The worker receives a LiveKit job request for the room.
- After caller joins, the worker connects to the realtime provider.
- `POST /internal/voice/calls/:provider_call_id/transcript` stores at least one transcript segment.
- `POST /internal/voice/calls/:provider_call_id/tool_call` stores voice-agent tool events in `voice_tool_events` rows related to the call.
- The settings `Transcript and tool calls` panel updates in realtime over ActionCable. Use `Refresh` only as a manual resync after websocket reconnect or missed events.

## Handoff Rehearsal

Default browser test calls do not create normal Chatwoot conversations and cannot be handed off. Handoff testing should use a separate rehearsal flow or a real conversation-backed LiveKit call. For conversation-backed calls, verify:

1. The LiveKit voice-call message shows `Join live call`, `Take over`, and `End call`.
2. `POST /internal/voice/calls/<livekit_room_name>/handoff` marks `handoff_status: requested`.
3. `POST /api/v1/accounts/:account_id/voice/calls/:id/take_over` marks `handoff_status: accepted`, `ai_status: silent`, assigns the conversation, and removes agent worker participants when present.

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

## Common Failures

- `Start test call` returns `422`: check Rails logs for the real error, then reproduce with `Voice::TestCallBuilder.perform!` in Rails runner.
- Worker starts but no dispatch: confirm `VOICE_AGENT_NAME` matches the worker registration and the Rails dispatch payload.
- Dispatch succeeds but no transcript: confirm a standard participant joined the room; the worker waits for a caller before starting the session.
- DB state changes but the conversation UI does not update: confirm `chatwoot-worker` is running; without Sidekiq, queued ActionCable broadcasts will not reach the browser.
- Turn-detector model errors in realtime mode: pipeline-only imports probably loaded too early. Realtime mode should only register the provider plugin it uses.
- Hanging unjoined rooms: `VOICE_AGENT_WAIT_FOR_PARTICIPANT_TIMEOUT_SECONDS` should end rooms that never receive a caller.
