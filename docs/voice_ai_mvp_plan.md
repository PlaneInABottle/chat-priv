# Native Chatwoot Voice AI MVP Plan

## Summary

Build voice AI as a native Chatwoot product while using LiveKit for realtime rooms and media. Chatwoot/Rails owns calls, contacts, conversations, mandatory transcript persistence, handoff, summaries, settings, and later recordings. A separate Python `services/voice_agent` worker joins LiveKit rooms and runs the AI voice session.

Enterprise voice code may remain in the repository, but the new voice AI implementation must not depend on Enterprise-only classes. Shared voice primitives for this feature live under `app/`.

## Core Decisions

- Use Python for the LiveKit agent worker because LiveKit Python has broader STT/TTS/LLM provider coverage and stronger advanced speech support.
- Support both architectures:
  - `pipeline`: separate STT + LLM + TTS, preferred for tuning Turkish phone-call quality.
  - `realtime`: provider-native realtime audio, initially Gemini Live API via LiveKit Google plugin.
- Store every final transcript segment automatically in DB. Transcript saving is system-owned, not an AI tool decision.
- Start without Netgsm. First prove browser caller -> LiveKit room -> Python AI -> Chatwoot transcript/handoff.
- Add recording/audio saving later using LiveKit Insights or Egress after transcript and handoff are stable.

## Gemini Live Notes

- `VOICE_AGENT_ARCHITECTURE=realtime` enables provider-native realtime audio.
- `VOICE_AGENT_REALTIME_PROVIDER=gemini` selects Gemini Live as the first realtime provider.
- Default realtime model should be a stable Gemini 2.5 native audio model.
- `gemini-3.1-flash-live-preview` is allowed for experiments, but has LiveKit compatibility limits:
  - no compatible mid-session `generate_reply()`
  - no compatible `update_instructions()`
  - no compatible `update_chat_ctx()`
  - no affective dialog or proactive audio
  - tool calls are synchronous
- For Gemini 3.1, initial instructions must carry the greeting/behavior because proactive greeting via `generate_reply()` is skipped.

## Phases

1. Rails voice foundation
   - Add OSS-owned `Call`, `VoiceInboxSetting`, and `CallTranscriptSegment`.
   - Add account-scoped test call APIs and internal voice-agent APIs.
   - Create calls through an API inbox for MVP.
   - Append transcript segments through internal authenticated Rails endpoints.

2. Native Chatwoot Voice Call UI MVP
   - Add Rails LiveKit token generation.
   - Let a browser caller and Chatwoot agent join the same LiveKit room from Chatwoot-native UI.
   - Keep LiveKit call state separate from Twilio/WhatsApp client code.

3. Python voice worker
   - Add `services/voice_agent` with `uv`.
   - Implement `pipeline` and `gemini_realtime` modes.
   - Persist transcript segments from LiveKit session events.
   - Expose handoff/end as AI-callable tools, but keep transcript persistence automatic.

4. Human handoff
   - AI requests handoff.
   - Rails assigns conversation to fallback team.
   - Chatwoot agent joins and takes over.
   - AI becomes silent or leaves after takeover.

5. Summary and debugging
   - Summarize ended calls from persisted transcript.
   - Add call detail/debug views for transcript, summary, room, worker events, and errors.

6. Recording/audio saving
   - Add admin recording setting and consent UX.
   - Use LiveKit recording/egress to persist audio metadata and playback URLs.
   - Add retention/delete behavior.

7. Netgsm/SIP
   - Configure LiveKit inbound SIP trunk and dispatch rules.
   - Map Netgsm caller/called numbers from LiveKit SIP participant attributes.
   - Reuse the same Rails/Python flow.
   - Add Asterisk only if direct Netgsm -> LiveKit fails.

## Test Scenarios

- Simulated call creates call, contact, conversation, and `voice_call` message.
- Transcript append always persists and is account scoped.
- Internal voice API rejects missing/wrong token.
- Python worker can run in `pipeline` mode.
- Python worker can run in `gemini_realtime` mode.
- Gemini 3.1 mode does not call proactive `generate_reply()`.
- LiveKit call does not trigger Twilio client code.
- Handoff assigns the configured fallback team.
- Ended call stores duration, transcript, and summary placeholder.

## Review Follow-ups

- Decide whether the Python worker should fail closed when `/agent_context` is unavailable instead of falling back to legacy dispatch metadata.
- Consider replacing migration JSON join metadata with an explicit temporary/source column if this migration needs more backfill complexity.
- Keep text AI agents and voice agents as separate domains, but share common tool-definition helpers where behavior is truly identical.
