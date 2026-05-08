# Live Inbox Handoff Workflow

## Prerequisites

- Confirm local Chatwoot runtime health and seeded browser login first through `chatwoot-ai-native-test`.
- Use repo command entrypoints from `chatwoot-dev-runbook` instead of restating them here.
- Use the existing AI-agent controller path, not the legacy inbox `set_agent_bot` path, for AI inbox binding.

## Supported runtime path

1. Snapshot the current AI agent with `GET /api/v1/accounts/:account_id/ai_agents/:id`.
2. Prefer the existing valid AI agent record such as `Browser Verify Bot`.
3. Update it with only current schema keys:

```json
{
  "name": "Browser Verify Bot",
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
  "inbox_ids": [617]
}
```

4. Verify the saved response shows inbox `617` under `agent_bot.inbox_ids`.
5. Verify the binding directly in `agent_bot_inboxes` before sending messages.

## Real inbound demo flow

1. Create a public contact on inbox `617`.
2. Create a public conversation for that contact.
3. Post an incoming public message through `/public/api/v1/inboxes/:inbox_id/contacts/:contact_id/conversations/:conversation_id/messages`.
4. For the handoff proof, use a deterministic trigger such as `HANDOFF NOW: I need a human for my billing dispute.`
5. Verify end-to-end evidence in at least two places:
   - conversation thread / state in the UI
   - persisted runtime evidence such as `messages`, `conversations.additional_attributes`, `labels`, or `ai_agent_tool_executions`

## Verification checklist

- Re-fetch the AI agent after update and confirm `agent_bot.inbox_ids` contains the target inbox.
- Confirm the binding row exists in `agent_bot_inboxes` for the target inbox before sending messages.
- For a normal message, verify the incoming customer message exists and that `AgentBots::AiResponseJob` ran before claiming any AI activity.
- If no outgoing assistant thread message appears for the normal message, report that truthfully.
- For a handoff message, verify all of the following when present:
  - outgoing customer-facing bot handoff message
  - outgoing private note from the agent bot
  - `ai_handoff_*` fields in `conversations.additional_attributes`
  - open conversation state after handoff
  - tool execution evidence from `GET /api/v1/accounts/:account_id/ai_agents/:ai_agent_id/tool_executions`
  - any assignee, notification, or label side effects that the live account configuration actually produced

## Truthful caveat about normal replies

- Live handoff behavior is demonstrably persisted today: the handoff tool can create a visible bot message, a private note, labels, and `ai_handoff_*` conversation attributes.
- Normal non-handoff AI text replies are not clearly proven to persist into the real conversation thread on the current live path.
- If you try a normal question first, report only what the UI and datastore actually show. Do not promise a visible assistant thread reply unless the session directly proves it.

## Browser verification focus

- Use `agent-browser` snapshot-first discipline.
- Confirm whether the conversation becomes open again, whether a bot handoff message is visible, whether a private note appears, and whether labels or other handoff markers are visible.

## Rollback

1. Restore the pre-demo AI agent payload through the same `PATCH /api/v1/accounts/:account_id/ai_agents/:id` path.
2. Restore prior `inbox_ids` exactly, or clear `617` if it was newly attached for the demo.
3. Keep test conversation IDs for traceability instead of deleting runtime evidence unless the user explicitly asks.
