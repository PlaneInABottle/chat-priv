# Voice AI Follow-ups

This tracks deferred Voice AI work that is useful, but not required for the current replay/SIP blocker pass.

## Before Launch

- Add `aria-live` announcements for new live transcript segments, tool events, and call state changes.
- Improve the live call controls UX when takeover is unavailable by showing the reason in text or tooltip.
- Add a conversation/inbox live-call badge for calls currently handled by AI.
- Add call summary auto-population after call end.
- Add business-hours and holiday routing before real customer rollout.

## Technical Cleanup

- Extract duplicated voice recording start behavior into one helper/service used by inbound builder, SIP bootstrapper, and finalizer paths.
- Keep Enterprise `Call` overlay cleanup as a separate task; do not touch it during OSS Voice AI blocker fixes.
- Consider batching `Voice::CallSerializer` lookups if conversation pages begin showing many voice-call messages.
- Revisit `MessageList.vue` voice-call detail fetching if one API call per voice message becomes visible in production traces.

## Product Ideas

- Call history table in the Voice AI usage tab.
- Structured-instruction playground with Ikas context preview.
- Tool configuration panels with provider-specific availability and test buttons.
- Post-call CSAT survey flow.
- Voice order lookup and order-placement tools after the support/replay flow is stable.
