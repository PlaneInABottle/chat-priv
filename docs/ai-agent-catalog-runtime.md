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
| `AiAgents::Tools::PresentCatalogProductsService` | Validates a display-only image presentation against the latest catalog candidates and prior presentation state. |
| `AiAgents::CatalogImagePreparer` | Fetches only trusted ikas CDN images, enforces byte/pixel/type limits, and normalizes them to bounded JPEG attachments. |
| `AiAgents::CatalogPresentationDeliveryJob` | Sends a persisted image-message group sequentially so channel providers preserve its order. |
| `AiAgents::ConversationHistoryCompactor` | Represents a multi-message image group as one assistant history entry for follow-up turns. |
| `AiAgents::OptionSelectionService` | Validates live widget/WhatsApp selections, rejects stale or conflicting submissions, and preserves idempotency. |
| `AiAgentTestConversation` | Implements the equivalent persisted selection contract for the dashboard simulator. |

## Catalog flow

1. The model receives only configured tools that pass current account/runtime availability and channel capability checks, and still fit the turn budget.
2. `ikas_catalog_search` accepts one query or an ordered `queries` batch. The orchestrator caps total catalog query units per customer turn and records truncation telemetry when only a prefix fits.
3. The full sanitized tool event is persisted for admin debugging. `LlmToolResultPresenter` separately supplies a compact result to the next model call: up to eight candidates for a single result and four per child of a batch, with only customer-useful candidate fields. Compact stock data retains `in_stock`, `sellable`, and `quantity`.
4. The model writes the customer answer in natural language. It may reason, compare, and recommend; catalog prose is not authorized or rejected through semantic regular expressions.
5. Concrete catalog fields should come from tool output by prompt contract. Customer-visible HTTP links are structurally restricted to URLs returned by tools. Structured catalog options accept only identifiers returned by the latest successful catalog event.
6. `LiveProcessor` persists at most one public AgentBot response for the triggering incoming message.

## Catalog product image contract

`present_catalog_products` is enabled by default when the merchant has a completed image-capable ikas snapshot. Merchants may disable it independently. Test conversations, `Channel::WebWidget`, and `Channel::Whatsapp` support the presentation; `Channel::Api` remains text-only.

The tool is available only after catalog sync has stored canonical image metadata. The model must call `ikas_catalog_search` first and may pass only returned item IDs. It has two modes:

- `products`: one main image for each of one to three distinct products.
- `product_gallery`: up to three ordered images for one exact product.

The presentation is display-only and has no option values or selection callback. A customer sees every image in the group without choosing images one at a time. When the customer asks for more, `continue_previous: true` excludes only delivered products or images by stable internal identity. A failed provider delivery remains eligible for a later continuation, while a successfully delivered image is not repeated. A fresh catalog search is still required in that turn.

Live delivery never sends the ikas CDN URL directly to the customer. The server fetches from the strict HTTPS `cdn.myikas.com` origin, validates type/size/dimensions, strips metadata, converts to JPEG, and persists a normal Chatwoot attachment. Each image is one outgoing message because the WhatsApp providers send one attachment per message. A presentation-scoped mutex serializes duplicate group jobs. Each successful message receives an explicit delivery marker; provider failures stop the group and remain visible to the bounded queue retry.

Variant images are preferred. A product-level representative image is marked in presentation metadata and customer copy must not claim it is the exact variant or color. Fixed price and representative-image labels use the detected conversation/customer language, then the account locale as a fallback. Image groups are compacted to one logical assistant history entry so later phrases such as “the second one” or “show more” retain context without consuming three history slots.

The compact model payload is not the audit record. Do not replace the persisted tool result with the compact form, and do not move presentation-only limits into the query engine.

## Recovery and safety boundaries

- Model/tool work is bounded by iteration, calls-per-response, and per-tool budgets.
- One unknown tool call may be returned to the model with the exact available tool names for correction. Repeated invalid calls fail closed.
- Empty output receives one bounded retry. A `finish_reason=length` response is never exposed as a fragment; the incomplete retry may use the explicit hard-capped larger completion allowance.
- Customer-facing finalization exists for internal tool/protocol leakage, not to enforce semantic evidence rules.
- Tool results are untrusted model context. Prompt instructions embedded in catalog data do not override the system policy.
- Provider or persistence exceptions remain visible to the queue retry path. Do not convert operational failures into a successful empty response.
- Human handoff remains the terminal recovery when no customer-safe response exists. Invalid `present_options` may be restated by the model as plain text without inventing catalog options.
- Catalog image download failures fall back to verified product text/links; delivery and persistence exceptions remain retryable instead of being reported as successful image sends.

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

A selection is valid only for the original conversation/contact and active prompt. Live submissions lock the conversation before the prompt so a concurrent customer message cannot race the stale-prompt check. Any later incoming customer message supersedes the prompt. A repeated widget request for the same value returns the existing incoming message, and duplicate WhatsApp deliveries do not create another message. The dashboard simulator permits only one submission. Every path rejects a conflicting second answer.

## Observability

- `AiAgentToolExecution` stores tool key, recursively redacted arguments/result, status, duration, mode, and conversation context.
- `AiAgentLlmCall` stores bounded, recursively redacted request/response metadata, finish reason, step name, and retry request options.
- Live outgoing messages store the triggering message ID, option-selection metadata when present, and safe turn telemetry/source attribution.
- Catalog image messages additionally store presentation version/ID, sequence/total, item identity, display name, image scope, and whether an attachment was actually persisted. Source CDN URLs are redacted from tool-execution logs.
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
  spec/services/ai_agents/tools/present_catalog_products_service_spec.rb \
  spec/services/ai_agents/catalog_image_preparer_spec.rb \
  spec/services/ai_agents/conversation_history_compactor_spec.rb \
  spec/jobs/ai_agents/catalog_presentation_delivery_job_spec.rb \
  spec/lib/ikas_catalog_mvp/query_engine_spec.rb
```

For options, add the present-options, option-selection, channel-capability, test-conversation controller, widget, and WhatsApp request/provider specs. For product images, cover catalog ingestion, trusted media preparation, terminal orchestration, grouped persistence/delivery, continuation, test-panel cards, widget attachments, and locally simulated WhatsApp provider payloads. Then use `chatwoot-ai-agent-local-testing` for real stateful messages; native specs alone do not prove queue, persistence, channel capability, and browser behavior together.
