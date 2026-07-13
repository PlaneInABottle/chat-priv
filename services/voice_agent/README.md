# Voice Agent Service

Python LiveKit worker for native Chatwoot voice AI.

The Rails app owns calls, conversations, transcripts, handoff, and summaries. This service only joins LiveKit rooms, speaks/listens, and reports mandatory call events back to Rails.

Required environment:

- `LIVEKIT_URL`
- `LIVEKIT_API_KEY`
- `LIVEKIT_API_SECRET`
- `OPENAI_API_KEY` when a voice agent uses the OpenAI realtime provider
- `CHATWOOT_INTERNAL_API_URL`
- `VOICE_AGENT_INTERNAL_TOKEN`
- `VOICE_AGENT_NAME`: LiveKit worker name used for explicit dispatch
- `VOICE_AGENT_ARCHITECTURE`: `pipeline` or `realtime`
- `VOICE_AGENT_REALTIME_PROVIDER`: worker fallback provider, `gemini` or `openai`
- `VOICE_AGENT_OPENAI_REALTIME_MODEL`: defaults to `gpt-realtime-2.1`
- `VOICE_AGENT_OPENAI_VOICE`: defaults to `marin`
- `GOOGLE_API_KEY` when `VOICE_AGENT_ARCHITECTURE=realtime` and `VOICE_AGENT_REALTIME_PROVIDER=gemini`
- `VOICE_AGENT_WAIT_FOR_PARTICIPANT_TIMEOUT_SECONDS`: defaults to `120`; ends unjoined dispatched rooms instead of waiting forever
- `VOICE_AGENT_MAX_CONCURRENT_JOBS`: per-worker admission cap, defaults to `10`
- `VOICE_AGENT_HEALTH_PORT`: LiveKit connection-aware health endpoint port, defaults to `9090`
- `VOICE_AGENT_PROMETHEUS_PORT`: optional Prometheus endpoint for active jobs, worker load, and process metrics
- `VOICE_AGENT_DRAIN_TIMEOUT_SECONDS`: graceful shutdown window, defaults to `1200`

Modes:

- `pipeline`: separate STT, LLM, and TTS. This is best for tuning Turkish transcription and voice quality independently.
- `realtime`: provider-native realtime audio using Gemini Live or OpenAI Realtime through LiveKit plugins.

OpenAI realtime uses `gpt-realtime-2.1` with low reasoning effort, semantic VAD, and `gpt-realtime-whisper` input transcription. Runtime provider, model, voice, and language are selected per voice agent by Super Admin; environment variables are fallbacks and new-agent deployment defaults.

Gemini 3.1 note:

`gemini-3.1-flash-live-preview` currently does not support mid-session `generate_reply`, `update_instructions`, or `update_chat_ctx` in LiveKit Agents. The worker avoids proactive greeting for that model and relies on initial instructions plus normal caller turns.

Development command:

```bash
uv run python agent.py dev
```

Production command:

```bash
uv run python agent.py start
```

## Docker

The voice worker runs as a separate container beside Rails and Sidekiq. The image installs the locked Python dependencies, runs as an unprivileged user, and starts in production mode by default.

For the development stack, keep voice credentials in `.env.local` and start the service with:

```bash
docker compose up -d --build voice-agent
docker compose ps voice-agent
docker compose logs --tail=160 voice-agent
```

The development Compose service overrides `CHATWOOT_INTERNAL_API_URL` to `http://rails:3000` and publishes health and metrics only on localhost ports `9090` and `9091`.

For the production stack, put the required voice variables in `.env` and run:

```bash
docker compose -f docker-compose.production.yaml up -d --build voice-agent
```

Production does not publish the worker health or metrics ports to the host. Other services can reach them only through the internal Compose network.

The SDK health endpoint is `GET /` on `VOICE_AGENT_HEALTH_PORT`. It returns `200` only while the worker is connected and healthy. When `VOICE_AGENT_PROMETHEUS_PORT` is set, metrics are available at `GET /metrics` on that port.

For a 25-call initial capacity target, use three workers capped at 10 jobs each and scale out before average active jobs exceed 60% of the fleet cap. Confirm the OpenAI project rate limit supports the target before running a provider-backed load test.
