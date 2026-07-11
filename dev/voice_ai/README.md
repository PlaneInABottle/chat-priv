# Deterministic Voice AI Test Harness

This harness sends a prerecorded customer turn through the real Chatwoot test-call API, LiveKit room, voice worker, and configured realtime provider. Unlike Chromium's fake microphone, it publishes the WAV file exactly once.

It verifies, by default:

- the call is an isolated test call with no customer conversation;
- caller speech is transcribed;
- the AI produces a transcript after the caller turn;
- the caller receives agent audio;
- each requested tool completes exactly as many times as specified;
- the call is ended even when an assertion fails.

The complete received agent audio, including the greeting, is written to a WAV file. The JSON result is printed to stdout and assertion failures exit with status `1`.

## Prerequisites

- Chatwoot, Sidekiq, and `services/voice_agent` are running.
- `.env.local` contains valid LiveKit and realtime-provider credentials.
- Voice AI is enabled for the account.
- The selected voice agent is assigned to the selected API inbox.
- The input is a mono, 16-bit PCM WAV file.

Convert an existing recording with FFmpeg:

```bash
ffmpeg -i customer-question.m4a -ac 1 -ar 48000 -c:a pcm_s16le /tmp/customer-question.wav
```

## Authentication

Use a local account administrator. Keep credentials in the shell environment instead of command history:

```bash
export CHATWOOT_TEST_EMAIL='admin@example.com'
export CHATWOOT_TEST_PASSWORD='local-password'
```

As an alternative, set all three Devise token headers: `CHATWOOT_ACCESS_TOKEN`, `CHATWOOT_CLIENT`, and `CHATWOOT_UID`.

## Run A Scenario

Set `VOICE_TEST_ACCOUNT_ID`, `VOICE_TEST_INBOX_ID`, and `VOICE_TEST_VOICE_AGENT_ID` to the numeric ids for the assigned test path, then run:

```bash
uv run --project services/voice_agent python3 dev/voice_ai/run_scenario.py \
  --account-id "$VOICE_TEST_ACCOUNT_ID" \
  --inbox-id "$VOICE_TEST_INBOX_ID" \
  --voice-agent-id "$VOICE_TEST_VOICE_AGENT_ID" \
  --wav /tmp/customer-question.wav \
  --expect-caller-text 'siparis'
```

The ids can instead be passed as numeric CLI values. `CHATWOOT_BASE_URL` defaults to `http://localhost:3000`.

Tool scenario example:

```bash
uv run --project services/voice_agent python3 dev/voice_ai/run_scenario.py \
  --account-id "$VOICE_TEST_ACCOUNT_ID" \
  --inbox-id "$VOICE_TEST_INBOX_ID" \
  --voice-agent-id "$VOICE_TEST_VOICE_AGENT_ID" \
  --wav /tmp/handoff-request.wav \
  --expect-tool human_handoff
```

One `--expect-tool human_handoff` requires exactly one execution, which catches repeated terminal actions. Repeat the flag only when a scenario intentionally expects more than one execution. The harness waits for Chatwoot's `ai_status=active` readiness signal before publishing audio; `--ready-delay` adds a small post-readiness buffer when a provider needs it.

Use `--response-wav` to choose the received-audio path. Otherwise it is stored under `/tmp/chatwoot-voice-ai/`.

## Scope

This is a deterministic functional test, not an acoustic quality scorer or load test. It proves that one finite customer utterance traverses the production media and API path and produces durable results. Run multiple processes separately when concurrency behavior needs to be measured; the harness intentionally keeps a single scenario easy to diagnose.

Realtime-provider calls can incur usage charges. The harness never creates a normal inbox conversation, but transcripts and tool events remain attached to the isolated test `Call` record according to the installation's retention policy.

## Fast Checks

```bash
uv run --project services/voice_agent python3 dev/voice_ai/test_run_scenario.py
uvx ruff check dev/voice_ai/run_scenario.py dev/voice_ai/test_run_scenario.py
```
