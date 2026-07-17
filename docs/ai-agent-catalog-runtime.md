# AI Agent Catalog and Option Runtime

This document describes the current production contract. Historical `*.plan.md` files are design records, not runtime authority.

## Component boundaries

| Component | Responsibility |
| --- | --- |
| `AiAgents::ToolPromptPolicy` | Gives the model channel-independent conversation rules and tool-specific guidance. |
| `AiAgents::Orchestrator` | Runs bounded model/tool iterations, recovery, final customer-facing output, and turn telemetry. |
| `IkasCatalogMvp::QueryEngine` | Resolves catalog queries and returns structured candidates, clarification groups, or no-match results. |
| `AiAgents::LlmToolResultPresenter` | Removes debug-heavy catalog fields and caps candidates only in model-facing tool messages. |
| `AiAgents::ToolOutputSanitizer` | Repairs or removes customer-visible HTTP links that are not present in tool output. It does not judge natural-language claims. |
| `AiAgents::LiveProcessor` | Loads bounded conversation history, prevents duplicate live replies, persists the outgoing message, and accounts for usage. |
| `AiAgents::Tools::PresentOptionsService` | Validates and creates a terminal `input_select` response with 2–10 choices. |
| `AiAgents::OptionSelectionService` | Validates live widget/WhatsApp selections, rejects stale or conflicting submissions, and preserves idempotency. |
| `AiAgentTestConversation` | Implements the equivalent persisted selection contract for the dashboard simulator. |

## Catalog flow

1. The model receives only enabled tools that still fit the turn budget.
2. `ikas_catalog_search` accepts one query or an ordered `queries` batch. The orchestrator caps total catalog query units per customer turn and records truncation telemetry when only a prefix fits.
3. The full sanitized tool event is persisted for admin debugging. `LlmToolResultPresenter` separately supplies a compact result to the next model call: up to eight candidates for a single result and four per child of a batch, with only customer-useful candidate fields.
4. The model writes the customer answer in natural language. It may reason, compare, and recommend; catalog prose is not authorized or rejected through semantic regular expressions.
5. Concrete catalog fields should come from tool output by prompt contract. Customer-visible HTTP links are structurally restricted to URLs returned by tools. Structured catalog options accept only identifiers returned by the latest successful catalog event.
6. `LiveProcessor` persists at most one public AgentBot response for the triggering incoming message.

The compact model payload is not the audit record. Do not replace the persisted tool result with the compact form, and do not move presentation-only limits into the query engine.

## Recovery and safety boundaries

- Model/tool work is bounded by iteration, calls-per-response, and per-tool budgets.
- One unknown tool call may be returned to the model with the exact available tool names for correction. Repeated invalid calls fail closed.
- Empty output receives one bounded retry. A `finish_reason=length` response is never exposed as a fragment; the incomplete retry may use the explicit hard-capped larger completion allowance.
- Customer-facing finalization exists for internal tool/protocol leakage, not to enforce semantic evidence rules.
- Tool results are untrusted model context. Prompt instructions embedded in catalog data do not override the system policy.
- Provider or persistence exceptions remain visible to the queue retry path. Do not convert operational failures into a successful empty response.
- Human handoff remains the terminal recovery when no customer-safe response exists. Invalid `present_options` may be restated by the model as plain text without inventing catalog options.

## Interactive option contract

`AiAgents::ChannelCapabilities` asks the channel object for `supports_ai_input_select?`; the concern defaults to false. Test conversations always support options. `Channel::WebWidget` and `Channel::Whatsapp` opt in. `Channel::Api` currently stays on natural text responses.

The terminal message uses:

```json
{
  "content_type": "input_select",
  "items": [{ "title": "Visible label", "value": "opaque UUID" }],
  "ai_agent": { "selection": { "version": 1 } }
}
```

General conversational choices may use model-provided labels. Product, category, color, size, and variant choices must be resolved from catalog identifiers by `PresentOptionsService`; only the returned label and an opaque UUID are exposed to the customer.

A selection is valid only for the original conversation/contact and active prompt. Any later incoming customer message supersedes the prompt. A repeated widget request for the same value returns the existing incoming message, and duplicate WhatsApp deliveries do not create another message. The dashboard simulator permits only one submission. Every path rejects a conflicting second answer.

## Observability

- `AiAgentToolExecution` stores tool key, sanitized arguments/result, status, duration, mode, and conversation context.
- `AiAgentLlmCall` stores bounded request/response metadata, finish reason, step name, and retry request options.
- Live outgoing messages store the triggering message ID, option-selection metadata when present, and safe turn telemetry/source attribution.
- Merchant-facing message bubbles must not expose raw tool arguments, tool events, model-provider metadata, or internal identifiers. Use the Super Admin tool-execution/LLM-call surfaces or bounded sanitized Rails/PM2 inspection for debugging.

Never log or document authentication headers, integration credentials, environment values, full customer data, or temporary fixture identifiers.

## Change verification

Start with the narrowest affected specs, then cover the combined boundaries when Orchestrator or tool contracts change:

```bash
bundle exec rspec \
  spec/services/ai_agents/orchestrator_spec.rb \
  spec/services/ai_agents/live_processor_spec.rb \
  spec/services/ai_agents/llm_tool_result_presenter_spec.rb \
  spec/services/ai_agents/tool_output_sanitizer_spec.rb \
  spec/services/ai_agents/tool_executor_spec.rb \
  spec/services/ai_agents/tool_prompt_policy_spec.rb \
  spec/lib/ikas_catalog_mvp/query_engine_spec.rb
```

For options, add the present-options, option-selection, channel-capability, test-conversation controller, widget, and WhatsApp request/provider specs. Run focused dashboard/widget component tests for rendering changes. Then use `chatwoot-ai-agent-local-testing` for real stateful messages; native specs alone do not prove queue, persistence, channel capability, and browser behavior together.
