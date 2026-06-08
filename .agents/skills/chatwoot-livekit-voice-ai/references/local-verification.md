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
pm2 restart chatwoot-voice-agent --update-env
```

Start the worker if missing:

```bash
pm2 start zsh --name chatwoot-voice-agent -- -lc 'set -a; source /Users/Y_ALTAY1/Documents/simWoot/chatwoot/.env.local; set +a; cd /Users/Y_ALTAY1/Documents/simWoot/chatwoot/services/voice_agent; uv run python agent.py dev'
```

The worker must log `registered worker` with `agent_name` matching `VOICE_AGENT_NAME`.

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
5. Wait until `Join as caller` is enabled.
6. Click `Join as caller`.
7. Wait for the worker to connect to the realtime provider and post transcript.
8. Click `Refresh` if the transcript panel does not update immediately.
9. End the call from the UI.

Expected proof:

- Rails returns `201 Created` for `/api/v1/accounts/:id/voice/test_calls`.
- The call metadata includes `voice_agent_dispatch.status = dispatched`.
- The worker receives a LiveKit job request for the room.
- After caller joins, the worker connects to the realtime provider.
- `POST /internal/voice/calls/:provider_call_id/transcript` stores at least one transcript segment.

## Datastore Proof

Use Rails runner for direct evidence:

```bash
set -a; source .env.local; set +a; eval "$(rbenv init -)"; bundle exec rails runner 'call = Call.livekit.where(account_id: 19).order(id: :desc).first; puts({ id: call.id, status: call.status, room: call.livekit_room_name, dispatch: call.meta["voice_agent_dispatch"], transcript: call.transcript, segments: call.transcript_segments.order(:id).map { |segment| { role: segment.role, text: segment.text, source: segment.source } } }.to_json)'
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
- Turn-detector model errors in realtime mode: pipeline-only imports probably loaded too early. Realtime mode should only register the provider plugin it uses.
- Hanging unjoined rooms: `VOICE_AGENT_WAIT_FOR_PARTICIPANT_TIMEOUT_SECONDS` should end rooms that never receive a caller.
