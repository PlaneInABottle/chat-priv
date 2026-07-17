# Catalog and Interactive-Option E2E

## Contents

- [Runtime isolation](#runtime-isolation)
- [Entry points](#entry-points)
- [Scenario matrix](#scenario-matrix)
- [Assertions](#assertions)
- [Cleanup](#cleanup)

## Runtime isolation

Read the production/task isolation section in `chatwoot-ai-native-test` before starting a worker. This host's development and production roles share PostgreSQL and Redis; deterministic queue evidence requires one Sidekiq consumer. Confirm Rails health and the active branch/HEAD before sending traffic.

## Entry points

Discover current IDs using the safe command in `live-inbox-handoff-workflow.md`. Do not reuse IDs from previous sessions.

- Dashboard simulator: `http://localhost:3000/app/accounts/:account_id/settings/ai-assistants/:ai_agent_id/test`
- Authenticated simulator API: `/api/v1/accounts/:account_id/ai_agents/:ai_agent_id/test_conversations`
- Public API channel: `/public/api/v1/inboxes/:identifier/contacts/.../conversations/.../messages`
- Public widget: use the current inbox's widget token and normal widget client.
- WhatsApp: exercise provider parsing through focused specs or a local simulated inbound payload. Do not send a real external message unless explicitly authorized.

Use the reusable Chatwoot browser profile for the simulator. For authenticated requests, reuse the dashboard's established authenticated client/session without printing cookies or access-token headers.

## Scenario matrix

Use fresh conversations and stateful follow-ups. Vary wording; do not assert one exact model sentence.

1. Send typo-heavy and vague product intent, then ask the agent to recommend rather than choose for it.
2. Change category, budget, color, or dimensions over later turns and verify the latest scope wins while compatible earlier constraints remain.
3. Ask for bounded alternatives and verify `present_options` appears only when useful and supported.
4. Cover two choices and more than three choices. Verify labels are real returned catalog labels for product/category/variant choices.
5. Send newer free text after an option prompt, then verify the old button is disabled and direct submission returns a validation error.
6. Accept one option, repeat the same submission, then try a different second selection. The widget should reuse the existing response, WhatsApp should ignore duplicate delivery, the test panel should reject a second submission, and every path should reject a conflicting answer.
7. Send free text instead of pressing a button and verify normal conversation continues.
8. Exercise a no-match catalog request and verify the answer remains natural without invented product links or leaked tool syntax.
9. Disable `present_options`, verify the saved setting, and confirm the same bounded interaction uses text. Restore the exact prior configuration afterward.
10. Use a `Channel::Api` inbox to verify normal free-form catalog replies and text fallback; this channel does not currently opt into native `input_select`.
11. Include catalog URLs with encoded query keys and verify customer Markdown links remain complete and canonical.
12. Where practical, force adapter failures in specs: unknown tool once, empty output, and `finish_reason=length`. Verify bounded correction/retry and absence of fragments, duplicate execution, or infinite loops.

DeepSeek Flash and other smaller models may vary in prose. Judge structural contracts, persisted state, tool grounding, and recovery boundaries; record non-contractual wording problems separately instead of weakening hard safety or idempotency checks.

## Assertions

For every live scenario, correlate the incoming message, queue execution, outgoing AgentBot message, and persisted records.

- The customer thread contains one public reply for the triggering message.
- `AiAgentToolExecution` contains expected tool keys, statuses, sanitized arguments/results, and no duplicate side effects.
- `AiAgentLlmCall` shows the expected orchestration steps, finish reason, and retry request options when recovery occurred.
- Catalog links in the customer message occur in tool output; raw tool markup, DSML/protocol tags, provider metadata, opaque product IDs, and tool-event JSON are absent.
- An `input_select` outgoing message contains 2–10 items, opaque values, and `content_attributes.ai_agent.selection.version == 1`.
- Test, widget, and WhatsApp selections enforce their documented stale, ownership, single-submission, and duplicate-delivery rules.
- The merchant UI shows a customer-friendly tool summary, while raw diagnostics remain restricted to admin/debug surfaces.

Use bounded Rails runner queries or the Super Admin tool-execution/LLM-call screens for persisted evidence. Redact message content and URLs when reporting outside the local session.

## Cleanup

1. Restore the exact AI-agent prompt, configuration, enabled state, and inbox bindings captured before the test.
2. Stop only task-owned PM2 processes and restore the production web/worker roles according to `chatwoot-ai-native-test`.
3. Keep trace conversations unless deletion was explicitly authorized; label or record their IDs only in the ephemeral test report.
4. Confirm exactly one intended Sidekiq process and recheck local/public health.
