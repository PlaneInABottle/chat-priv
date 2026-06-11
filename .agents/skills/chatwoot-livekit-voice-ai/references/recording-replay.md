# Voice Recording And Replay

Use this reference when changing LiveKit Egress recording, storage adapters, replay URLs, or recording search.

## Scope

- Browser sandbox test calls are not recorded. `Voice::Recordings::StartService` skips `call.test_call?`.
- Conversation-backed LiveKit calls can be recorded when `VoiceInboxSetting#recording_enabled` is true.
- Recording metadata is stored in `VoiceRecording`, not only in `calls.meta`.
- The current storage provider is `s3_compatible`, configured through `VOICE_RECORDING_*` env vars. This supports Cloudflare R2, AWS S3-compatible endpoints, and local MinIO-style endpoints without app-code changes.

## Key Files

- `app/models/voice_recording.rb`
- `app/services/voice/recordings/storage_config.rb`
- `app/services/voice/recordings/start_service.rb`
- `app/services/voice/recordings/stop_service.rb`
- `app/services/voice/recordings/webhook_handler.rb`
- `app/services/voice/livekit/egress_service.rb`
- `app/services/voice/livekit/webhook_verifier.rb`
- `app/controllers/internal/voice/livekit_webhooks_controller.rb`
- `app/controllers/api/v1/accounts/voice/recordings_controller.rb`

## Environment

Required for recording upload and replay URL signing:

```bash
VOICE_RECORDING_STORAGE_PROVIDER=s3_compatible
VOICE_RECORDING_S3_ACCESS_KEY_ID=...
VOICE_RECORDING_S3_SECRET_ACCESS_KEY=...
VOICE_RECORDING_S3_BUCKET=...
VOICE_RECORDING_S3_ENDPOINT=...
VOICE_RECORDING_S3_REGION=auto
VOICE_RECORDING_S3_FORCE_PATH_STYLE=true
VOICE_RECORDING_S3_PREFIX=voice-recordings
```

LiveKit credentials are still read from:

```bash
LIVEKIT_URL=...
LIVEKIT_API_KEY=...
LIVEKIT_API_SECRET=...
```

Do not commit `.env.local`.

Use a dedicated recording bucket or provider credentials that are restricted to the recording bucket/prefix. The app intentionally does not fall back to global `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`, because those credentials may have broader deployment permissions than LiveKit Egress should receive.

## LiveKit Egress

Recording starts through Twirp:

- Service: `livekit.Egress`
- Method: `StartRoomCompositeEgress`
- Token grant: `video.roomRecord: true`
- Body uses `audio_only: true` and one `file_outputs` entry.
- Leave `layout` and `custom_base_url` unset for audio-only recording behavior.

Recording stop is best-effort through `StopEgress`. LiveKit can also auto-stop egress when the room ends.

## Webhook

Configure LiveKit Cloud webhook URL to:

```text
POST /internal/voice/livekit/webhook
```

The endpoint verifies LiveKit's JWT webhook signature with `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET`, including the `sha256` body hash. Do not replace this with the voice-agent internal token.

Handled events:

- `egress_started`
- `egress_updated`
- `egress_ended`

`egress_ended` marks `VoiceRecording` as `completed` or `failed`, updates file metadata, refreshes the voice-call message payload, and broadcasts `voice_call.status_changed`.

## Replay

`Voice::CallSerializer` exposes:

- `recording`
- `recording_url`

Completed recordings use short-lived signed S3-compatible URLs from `Voice::Recordings::StorageConfig`. Do not persist signed URLs into `Message#content_attributes`; the voice-call bubble fetches fresh call details for terminal LiveKit calls and reads `recording_url` from that response.

## Metadata Search

Account-scoped API:

```text
GET /api/v1/accounts/:account_id/voice/recordings
```

Supported filters:

- `status`
- `inbox_id`
- `contact_id`
- `phone`
- `call_status`
- `handoff_status`
- `from`
- `to`
- `limit`

This is metadata filtering only. Do not add transcript full-text or semantic search here without a separate search design.

## Focused Verification

Use local Postgres host override if the shell inherited Docker-style `POSTGRES_HOST=postgres`:

```bash
eval "$(rbenv init -)"
POSTGRES_HOST=localhost bundle exec rspec \
  spec/services/voice/livekit/egress_service_spec.rb \
  spec/services/voice/livekit/webhook_verifier_spec.rb \
  spec/services/voice/recordings/query_spec.rb \
  spec/services/voice/recordings/start_service_spec.rb \
  spec/services/voice/recordings/stop_service_spec.rb \
  spec/services/voice/recordings/storage_config_spec.rb \
  spec/services/voice/recordings/webhook_handler_spec.rb \
  spec/services/voice/call_finalizer_spec.rb \
  spec/requests/internal/voice/livekit_webhooks_spec.rb \
  spec/requests/api/v1/accounts/voice/recordings_spec.rb
```
