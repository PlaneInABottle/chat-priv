# Live Inbox and Handoff Workflow

## Contents

- [Prerequisites](#prerequisites)
- [Supported runtime path](#supported-runtime-path)
- [Public API message flow](#public-api-message-flow)
- [AI usage-limit verification](#ai-usage-limit-verification)
- [Verification checklist](#verification-checklist)
- [Truthful caveat about normal replies](#truthful-caveat-about-normal-replies)
- [Browser verification focus](#browser-verification-focus)
- [Rollback](#rollback)

## Prerequisites

- Confirm local Chatwoot runtime health and seeded browser login first through `chatwoot-ai-native-test`.
- Use repo command entrypoints from `chatwoot-dev-runbook` instead of restating them here.
- Use the existing AI-agent controller path, not the legacy inbox `set_agent_bot` path, for AI inbox binding.
- Discover the current target instead of assuming an account, AI-agent, or inbox ID:

```bash
.agents/skills/chatwoot-ai-native-test/scripts/with-chatwoot-env.sh bundle exec rails runner '
  AiAgent.includes(agent_bot: { inboxes: :channel }).find_each do |agent|
    inboxes = agent.agent_bot&.inboxes.to_a.map { |inbox| { id: inbox.id, name: inbox.name, channel: inbox.channel_type } }
    puts({ account_id: agent.account_id, ai_agent_id: agent.id, name: agent.name, enabled: agent.enabled?, inboxes: inboxes }.to_json)
  end
'
```

## Supported runtime path

1. Snapshot the current AI agent with `GET /api/v1/accounts/:account_id/ai_agents/:id`.
2. Select an existing valid agent and compatible test inbox from the discovery output.
3. If the scenario requires a prompt change, update only current schema keys and retain the complete original response for restoration:

```json
{
  "name": "<existing agent name>",
  "enabled": true,
  "prompt": "If the customer asks for a human, refund, escalation, billing dispute, or says the phrase HANDOFF NOW, call the human_handoff tool immediately. For the tool call, use a short customer_message, a short internal_note, reason that quotes the trigger, and labels only from the allowed list. Otherwise answer briefly.",
  "config": {
    "tools": {
      "enabled": ["human_handoff"],
      "human_handoff": {
        "allowed_labels": ["ai_handoff"]
      }
    }
  },
  "inbox_ids": ["<verified inbox id>"]
}
```

4. Verify the saved response shows the target under `agent_bot.inbox_ids`.
5. Verify the binding directly in `agent_bot_inboxes` before sending messages.

## Real inbound demo flow

1. Create a public contact on the verified API or widget inbox.
2. Create a public conversation for that contact.
3. Post an incoming public message through `/public/api/v1/inboxes/:inbox_identifier/contacts/:source_id/conversations/:display_id/messages`.
4. For the handoff proof, use a deterministic trigger such as `HANDOFF NOW: I need a human for my billing dispute.`
5. Verify end-to-end evidence in at least two places:
   - conversation thread / state in the UI
   - persisted runtime evidence such as `messages`, `conversations.additional_attributes`, `labels`, or `ai_agent_tool_executions`

## Public API message flow

- Use `Channel::Api#identifier` in the public URL, not the numeric inbox id. Discover it with `Channel::Api.includes(:inbox)` and do not copy identifiers into durable documentation.
- Contact create path: `POST /public/api/v1/inboxes/:identifier/contacts`.
- Conversation create path: `POST /public/api/v1/inboxes/:identifier/contacts/:source_id/conversations`.
- Message create path: `POST /public/api/v1/inboxes/:identifier/contacts/:source_id/conversations/:display_id/messages`.
- Public message create responses include the database message `id`, integer `message_type`, and `conversation_id` as the conversation display id. If polling is flaky, verify directly in `messages` by conversation id and message id.
- For local live tests, wait for the response buffer and worker before judging results. Persisted evidence is stronger than command output from a long polling script.

## AI usage-limit verification

- Super Admin can set account AI settings under `/super_admin/accounts/:id/edit`: monthly conversation limit and same-customer reuse window.
- Store admins see aggregate usage under `/app/accounts/:id/settings/ai-agents`; this report should not expose the AI model.
- Test conversations under `/api/v1/accounts/:account_id/ai_agents/:id/test_conversations` are simulator traffic and must not create `AiAgentUsageEvent` rows.
- Live quota proof should cover these cases:
  - first live customer message creates one consumed `AiAgentUsageEvent`;
  - same contact inside the reuse window can receive multiple live replies while still having one usage event;
  - a different contact consumes another event until the monthly limit is reached;
  - a new contact after exhaustion gets no public AI answer, no LLM call, no usage event, and an open conversation with a private AgentBot note plus `ai_handoff_reason: ai_usage_limit_exhausted`.
- Query `AiAgents::Usage::Summary.new(account: Account.find(id), include_recent_events: true).payload` for the canonical local accounting snapshot.
- For concurrency regressions, verify that a reused in-flight reservation cannot be released into an uncounted successful reply: a successful reused response should leave one consumed event.

## Verification checklist

- Re-fetch the AI agent after update and confirm `agent_bot.inbox_ids` contains the target inbox.
- Confirm the binding row exists in `agent_bot_inboxes` for the target inbox before sending messages.
- For a normal message, verify the incoming customer message exists and that `AgentBots::AiResponseJob` ran before claiming any AI activity.
- For a normal message, verify the outgoing public AgentBot reply appears before claiming success.
- For catalog/tool tests, verify both the public message and persisted `ai_agent_tool_executions`; public customer messages may intentionally hide raw tool-call metadata.
- For a handoff message, verify all of the following when present:
  - outgoing customer-facing bot handoff message
  - outgoing private note from the agent bot
  - `ai_handoff_*` fields in `conversations.additional_attributes`
  - open conversation state after handoff
  - tool execution evidence from `GET /api/v1/accounts/:account_id/ai_agents/:ai_agent_id/tool_executions`
  - any assignee, notification, or label side effects that the live account configuration actually produced

## Truthful caveat about normal replies

- Live handoff behavior is demonstrably persisted today: the handoff tool can create a visible bot message, a private note, labels, and `ai_handoff_*` conversation attributes.
- Normal non-handoff AI text replies are also expected to persist as public AgentBot messages on the current live path.
- Still report only what the public API, UI, and datastore show for the current session; do not infer success without direct evidence.

## Browser verification focus

- Use `agent-browser` snapshot-first discipline.
- Confirm whether the conversation becomes open again, whether a bot handoff message is visible, whether a private note appears, and whether labels or other handoff markers are visible.

## Rollback

1. Restore the pre-demo AI agent payload through the same `PATCH /api/v1/accounts/:account_id/ai_agents/:id` path.
2. Restore prior `inbox_ids` exactly, or remove the verified target inbox if it was newly attached for the demo.
3. Keep test conversation IDs for traceability instead of deleting runtime evidence unless the user explicitly asks.
