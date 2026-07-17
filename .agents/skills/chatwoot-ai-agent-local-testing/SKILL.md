---
name: chatwoot-ai-agent-local-testing
description: Verify Chatwoot OSS AI-agent behavior against real local customer messages, persisted tool/LLM evidence, and channel UI behavior. Use for inbox-bound catalog searches, recommendations, interactive options and stale selections, public API text fallback, human handoff, quota accounting, or truthful stateful demos without hardcoded fixture IDs.
---

# Chatwoot AI Agent Local Testing

Use this skill for real local customer-message AI-agent verification only.

## Quick navigation

- **Live inbox handoff workflow**: Read [references/live-inbox-handoff-workflow.md](references/live-inbox-handoff-workflow.md).
- **Catalog and interactive-option E2E**: Read [references/catalog-options-e2e.md](references/catalog-options-e2e.md).

## Boundaries

- Defer local runtime boot, `/health`, and seeded-login checks to `chatwoot-ai-native-test`.
- Defer repo command entrypoints to `chatwoot-dev-runbook`.
- Defer generic API/UI verification workflow to `ai-native-workflow`.
- Defer browser mechanics and snapshot discipline to `agent-browser`.
- Read `docs/ai-agent-catalog-runtime.md` before changing catalog orchestration or selection contracts; this skill verifies behavior and does not redefine the architecture.
- Discover account, agent, inbox, and conversation identifiers from current records. Never persist session-specific IDs or authentication material in this skill.
- Normal non-handoff AI text replies should persist as public AgentBot messages on the current live path; still verify each run through the public API, UI, or datastore before claiming behavior.
