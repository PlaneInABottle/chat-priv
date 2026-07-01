# Voice Agent Service

Python LiveKit worker for native Chatwoot voice AI.

The Rails app owns calls, conversations, transcripts, handoff, and summaries. This service only joins LiveKit rooms, speaks/listens, and reports mandatory call events back to Rails.

Required environment:

- `LIVEKIT_URL`
- `LIVEKIT_API_KEY`
- `LIVEKIT_API_SECRET`
- `OPENAI_API_KEY` or LiveKit Inference configuration
- `CHATWOOT_INTERNAL_API_URL`
- `VOICE_AGENT_INTERNAL_TOKEN`
- `VOICE_AGENT_NAME`: LiveKit worker name used for explicit dispatch
- `VOICE_AGENT_ARCHITECTURE`: `pipeline` or `realtime`
- `VOICE_AGENT_REALTIME_PROVIDER`: `gemini` for the first realtime implementation
- `GOOGLE_API_KEY` when `VOICE_AGENT_ARCHITECTURE=realtime` and `VOICE_AGENT_REALTIME_PROVIDER=gemini`
- `VOICE_AGENT_WAIT_FOR_PARTICIPANT_TIMEOUT_SECONDS`: defaults to `120`; ends unjoined dispatched rooms instead of waiting forever

Modes:

- `pipeline`: separate STT, LLM, and TTS. This is best for tuning Turkish transcription and voice quality independently.
- `realtime`: provider-native realtime audio. The first provider is Gemini Live API via LiveKit's Google plugin; OpenAI/AWS realtime can be added behind the same architecture flag later.

Gemini 3.1 note:

`gemini-3.1-flash-live-preview` currently does not support mid-session `generate_reply`, `update_instructions`, or `update_chat_ctx` in LiveKit Agents. The worker avoids proactive greeting for that model and relies on initial instructions plus normal caller turns.

Development command:

```bash
uv run python agent.py dev
```
