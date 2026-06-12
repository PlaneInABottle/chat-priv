---
name: chatwoot-livekit-voice-ai
description: Build, run, debug, or verify the native Chatwoot Voice AI MVP that uses LiveKit rooms, explicit LiveKit agent dispatch, the Python voice_agent worker, Gemini realtime mode, browser test calls, SIP/telephony provider bootstrapping, transcript persistence, and local PM2 runtime checks. Use when working on voice inbox settings, `Voice::Livekit::*` services, `Voice::Telephony::*` services, `services/voice_agent`, or agent-browser validation of voice calls.
---

# Chatwoot LiveKit Voice AI

Use this skill for the native Voice AI MVP path only.

## Quick Navigation

- **Local verification workflow**: Read [references/local-verification.md](references/local-verification.md).
- **Local Asterisk/SIP failures**: Read [references/local-verification.md#local-sip-incident-notes](references/local-verification.md#local-sip-incident-notes).
- **Recording and replay workflow**: Read [references/recording-replay.md](references/recording-replay.md).

## Boundaries

- Use `chatwoot-dev-runbook` for generic Rails/Vite/RSpec commands.
- Use `pm2-runtime-operator` for PM2 lifecycle details.
- Use `agent-browser` for browser mechanics and snapshot-first UI interaction.
- Use LiveKit docs MCP before changing LiveKit Agent, dispatch, SIP, or realtime-provider behavior.
- Do not commit `.env.local`; it holds LiveKit, Gemini, and internal-token secrets.
