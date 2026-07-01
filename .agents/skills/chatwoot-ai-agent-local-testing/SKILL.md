---
name: chatwoot-ai-agent-local-testing
description: Verify Chatwoot OSS AI-agent behavior against real local customer messages by binding a valid AI agent to a real inbox, sending public inbox API traffic, and checking live replies, handoff outcomes, tool usage, or AI usage-limit accounting. Use when you need a truthful local demo or investigation of inbox-bound AI-agent behavior, especially to prove human handoff or quota behavior on inbox 617 and to confirm what appears in the real conversation thread.
---

# Chatwoot AI Agent Local Testing

Use this skill for real local customer-message AI-agent verification only.

## Quick navigation

- **Live inbox handoff workflow**: Read [references/live-inbox-handoff-workflow.md](references/live-inbox-handoff-workflow.md).

## Boundaries

- Defer local runtime boot, `/health`, and seeded-login checks to `chatwoot-ai-native-test`.
- Defer repo command entrypoints to `chatwoot-dev-runbook`.
- Defer generic API/UI verification workflow to `ai-native-workflow`.
- Defer browser mechanics and snapshot discipline to `agent-browser`.
- Normal non-handoff AI text replies should persist as public AgentBot messages on the current live path; still verify each run through the public API, UI, or datastore before claiming behavior.
