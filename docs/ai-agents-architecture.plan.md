# Built-in AI Agents for Self-Hosted Chatwoot - Architecture Plan

## 1) Problem framing

Self-hosted Chatwoot needs configurable built-in AI agents that live inside the product, use Chatwoot's existing inbox/conversation/admin patterns, and stay upgrade-safe. The design must avoid the Captain licensing path, avoid duplicating current webhook-bot behavior, and keep the first delivery focused on prompts, model/provider configuration, and tools (including admin-configured custom HTTP tools, with a safe path for custom function plugins later).

## 2) Goals / non-goals

### Goals

- Build directly into OSS Chatwoot, not behind Captain licensing.
- Reuse existing Chatwoot primitives where verified: `AgentBot`, `AgentBotInbox`, pending conversations, `bot_handoff!`, account settings, Active Storage, Sidekiq/ActiveJob, JSONB, pgvector.
- Integrate into existing dashboard settings/admin UX patterns.
- Keep runtime opt-in and upgrade-safe.
- Deliver v1 around:
  - agent CRUD
  - prompts/instructions
  - model/provider configuration
  - tool selection
  - account-level custom HTTP tools
- Provide a phased path for knowledge base, routing, and richer multi-agent behavior.

### Non-goals

- No implementation code in this task.
- No arbitrary code execution from DB-stored “custom functions”.
- No replacement of existing webhook `AgentBot` flows.
- No Captain namespace reuse as the primary product path.
- No speculative marketplace, billing, quota, or model-observability platform work beyond what supports the requested roadmap.

## 3) Verified Facts vs Assumptions

| Type                  | Item                                                                                                                                               | Evidence / note                                                                                                                                                                                                                                                                 | Impact on design                                                                                                    |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| Verified fact         | OSS bot primitive already exists: `AgentBot` + `AgentBotInbox` + inbox-level active bot semantics                                                  | `app/models/agent_bot.rb:20-37`, `app/models/agent_bot_inbox.rb:14-28`, `app/models/inbox.rb:169-172`                                                                                                                                                                           | Reuse as compatibility layer instead of inventing a new inbox-bot lifecycle                                         |
| Verified fact         | New conversations in bot-enabled inboxes become `pending`                                                                                          | `app/models/conversation.rb:254-265`                                                                                                                                                                                                                                            | AI-agent architecture should preserve this instead of re-implementing state transitions                             |
| Verified fact         | `Conversation#bot_handoff!` already reopens and dispatches handoff                                                                                 | `app/models/conversation.rb:161-164`                                                                                                                                                                                                                                            | Human handoff should reuse this primitive                                                                           |
| Verified fact         | Post-message hook exists and is already the strongest internal async AI trigger seam                                                               | `app/services/message_templates/hook_execution_service.rb:16-20,62`, `enterprise/app/services/enterprise/message_templates/hook_execution_service.rb:4-10,32-40`                                                                                                                | Recommended runtime should enqueue from this seam                                                                   |
| Verified fact         | Account settings use JSONB + schema validation + `store_accessor`                                                                                  | `app/models/account.rb:34-92`, `app/controllers/api/v1/accounts_controller.rb:46-52,94-100`                                                                                                                                                                                     | Feature flags and account-level AI toggles should follow this pattern                                               |
| Verified fact         | Global config uses `InstallationConfig` / `GlobalConfigService`, and this is not a verified encrypted secret store                                 | `app/models/installation_config.rb:22,35-47`, `lib/global_config.rb:40-57`; verified encrypted storage patterns are `app/models/integrations/hook.rb:24-25` and `app/models/user.rb:82-84`                                                                                      | Installation-level AI config may hold non-secret enablement/defaults only; v1 must not store provider secrets there |
| Verified fact         | Repo has encrypted-field patterns using `encrypts`                                                                                                 | `app/models/integrations/hook.rb:24-25`, `app/models/user.rb:82-84`                                                                                                                                                                                                             | Per-agent/per-tool secrets should use encrypted columns, not plaintext JSONB                                        |
| Verified fact         | Account APIs use REST controllers + Pundit + Jbuilder partials/presenters                                                                          | `app/controllers/api/v1/accounts/agent_bots_controller.rb:1-50`, `app/policies/agent_bot_policy.rb:2-27`, `app/views/api/v1/models/_agent_bot.json.jbuilder:1-10`                                                                                                               | New APIs should match this contract style                                                                           |
| Verified fact         | Dashboard settings are Vue-based, routed under settings aggregation, with reusable shells                                                          | `app/javascript/dashboard/routes/dashboard/settings/settings.routes.js:7-47`, `app/javascript/dashboard/components-next/sidebar/Sidebar.vue:574-696`, `.../SettingsWrapper.vue:1-23`, `.../Wrapper.vue:1-45`, `.../SettingsLayout.vue:1-42`, `.../BaseSettingsHeader.vue:8-115` | New admin pages should use existing Vue/Vuex/settings-shell patterns                                                |
| Verified fact         | pgvector is already present and used by enterprise tables with `vector(1536)` + ivfflat indexes                                                    | `Gemfile:186-188`, `db/schema.rb:14-20,160-167,296-311`, `db/migrate/20250104200055_create_captain_tables.rb:3-5,67-89`                                                                                                                                                         | Knowledge retrieval can use local proven DB patterns, but should be phased                                          |
| Verified fact         | Active Storage is the existing upload primitive                                                                                                    | `db/schema.rb:88-113`, `enterprise/app/models/captain/document.rb:27-30`, `app/presenters/mail_presenter.rb:75-84`                                                                                                                                                              | Knowledge uploads should use Active Storage                                                                         |
| Verified fact         | There is no verified first-class durable DB table for generic tool execution logs                                                                  | repo search evidence; closest patterns are `copilot_messages` and OTEL spans                                                                                                                                                                                                    | If durable execution history is needed, add explicit OSS tables rather than assuming an existing log store          |
| Verified fact         | Overlay-sensitive seams include `Inbox`, `Conversation`, `MessageTemplates::HookExecutionService`, `AsyncDispatcher`, account settings permissions | `app/models/inbox.rb:249-251`, `app/models/conversation.rb:345-347`, `app/services/message_templates/hook_execution_service.rb:62`, `app/controllers/api/v1/accounts_controller.rb:119`, `app/dispatchers/async_dispatcher.rb:26`                                               | Recommendation should minimize edits here and prefer new OSS namespaces plus small seam extensions                  |
| Assumption (low risk) | A dedicated run ledger table will be preferable to encoding run metadata on messages/conversations                                                 | No verified existing durable run table                                                                                                                                                                                                                                          | Recommendation includes a new table, so correctness does not depend on an unverified message metadata shape         |

## 4) Architecture drivers / constraints

- **YAGNI/KISS:** v1 should not require knowledge-base ingestion, generalized actor abstraction, or DB-stored executable code.
- **DRY:** reuse inbox pending/open/handoff semantics instead of creating parallel AI conversation states.
- **Upgrade safety:** keep invasive core edits to a minimum; prefer new OSS models/controllers/services plus one small runtime seam.
- **Overlay safety:** avoid Captain namespace dependency and prevent OSS AI agents from colliding with enterprise Captain inbox handling.
- **Security:** secrets encrypted at rest, SSRF-safe HTTP tools, strict account scoping, opt-in feature flags.
- **Operational simplicity:** Sidekiq/ActiveJob for async work, Active Storage for uploads, JSONB for flexible configs, pgvector only when KB is enabled.

### Current state (evidence)

- Existing webhook bots already own the inbox-pending lifecycle and can be attached to exactly one inbox binding through `AgentBotInbox` (`app/models/agent_bot_inbox.rb:14-28`, `app/models/inbox.rb:169-172`).
- Existing enterprise Captain uses the same message-hook seam to enqueue async responses and perform handoff (`enterprise/app/services/enterprise/message_templates/hook_execution_service.rb:4-10,32-40,56-76`).
- Existing enterprise Captain also proves account-scoped assistants, inbox joins, documents, vector embeddings, and custom HTTP tools as viable local patterns, but those live in enterprise-specific namespaces and policies (`enterprise/app/models/captain/assistant.rb:19-121`, `enterprise/app/models/captain/document.rb:23-154`, `enterprise/app/models/captain/custom_tool.rb:26-100`, `enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb:1-73`).
- Existing settings pages already provide the route/layout/store/API conventions needed for OSS admin integration (`app/javascript/dashboard/routes/dashboard/settings/settings.routes.js:7-47`, `app/javascript/dashboard/api/ApiClient.js:5-60`, `app/javascript/dashboard/store/modules/agentBots.js:23-186`).

## 5) Multiple architecture approaches

### Approach A - Webhook-first on top of existing `AgentBot`

#### Description

Treat “built-in AI agent” mostly as UI/config sugar over the existing webhook bot flow. Chatwoot stores prompts/provider config, but runtime is external (or proxied) and still invoked through webhook-style dispatch.

#### Components

- Existing `AgentBot`, `AgentBotInbox`, `AgentBotListener`, `AgentBots::WebhookJob`
- New settings UI for prompts/provider/tool config
- External or proxy runtime service

#### Data flow

1. Inbox binds to `AgentBot`.
2. New conversation becomes `pending`.
3. Listener/webhook job sends payload to runtime.
4. Runtime calls bot token endpoints back into Chatwoot for replies/handoff.

#### Pros

- Lowest OSS core change.
- Reuses existing token auth and inbox lifecycle.
- Minimal conflict with existing webhook bot behavior.

#### Cons

- Not truly “built into Chatwoot”.
- Tool execution and knowledge retrieval live outside the core app.
- Harder to make custom tools/custom functions first-class in admin UX.
- More operational moving parts and weaker upgrade self-containment.

#### Upgrade / overlay impact

- Low code impact, but operational dependency stays external.
- No Captain collision, but also no real internal-runtime benefit.

#### Why / why not

- **Why:** fastest proof-of-concept.
- **Why not:** fails the user’s stated priority to build directly into Chatwoot.

---

### Approach B - OSS-ify / extract the Captain assistant stack

#### Description

Take the enterprise Captain assistant model/controllers/runtime patterns and move or mirror them into OSS, renaming the UX to built-in AI agents.

#### Components

- Captain-style assistant, inbox, document, custom-tool, scenario, and runtime services
- Existing enterprise route/API/UI patterns as primary implementation base

#### Data flow

1. Inbox binds to assistant.
2. Message hook schedules internal response builder.
3. Assistant runtime executes tools and KB lookup.
4. Response or handoff is posted back into conversation.

#### Pros

- Richest feature set fastest.
- Proven internal patterns already exist in repo.
- Already includes multi-agent, docs, tools, async runtime examples.

#### Cons

- Tightly coupled to Captain licensing path and enterprise namespaces.
- Highest future merge/conflict risk with upstream Chatwoot enterprise overlays.
- Pulls in more than v1 needs.
- Violates the request to avoid the Captain path.

#### Upgrade / overlay impact

- Highest impact; directly overlaps current enterprise overlays and APIs.

#### Why / why not

- **Why:** strong reference architecture.
- **Why not:** not acceptable as the primary OSS product path.

---

### Approach C - Recommended: OSS-native `AiAgent` bounded context with `AgentBot` compatibility layer

#### Description

Create a new OSS AI-agent domain (`AiAgent`, `AiCustomTool`, `AiAgentRun`, later KB tables) while reusing `AgentBot` as the inbox/conversation compatibility primitive. Each AI agent owns one shadow `AgentBot`. Inbox binding stays on `AgentBotInbox`, so existing pending/handoff/message-sender behavior remains intact. Internal runtime is triggered from the existing post-message hook, not from outgoing webhooks.

#### Components

- New OSS models/tables: `AiAgent`, `AiAgentToolBinding`, `AiCustomTool`, `AiAgentRun`, optional `AiToolCall`
- Optional later KB tables: `AiKnowledgeSource`, `AiKnowledgeChunk`, `AiAgentKnowledgeSource`
- Existing compatibility primitives: `AgentBot`, `AgentBotInbox`, `Conversation#bot_handoff!`
- Runtime services/jobs under new OSS namespace, e.g. `AiAgents::*`
- Settings UI under existing dashboard settings routes/shells

#### Data flow

1. Admin creates `AiAgent`; system creates/links a shadow `AgentBot`.
2. Inbox binds to the shadow `AgentBot` using existing association semantics.
3. New conversations remain `pending` automatically through existing `inbox.active_bot?` behavior.
4. Incoming message hook detects that the active bot is backed by an `AiAgent` and enqueues an internal response job.
5. Runtime loads prompt/config/tools, executes provider call + tool calls.
6. Runtime posts a normal outgoing bot message via the linked `AgentBot`, or calls `conversation.bot_handoff!`.

#### Pros

- Best fit for user priorities.
- Reuses proven Chatwoot primitives without reusing Captain product boundaries.
- Minimizes core-flow edits.
- Preserves current inbox/conversation semantics and sender identity.
- Keeps OSS/enterprise contracts cleaner than a Captain extraction.

#### Cons

- Requires new OSS domain tables and runtime services.
- Adds a shadow-bot indirection that must be documented.
- Still needs one carefully designed runtime seam in the post-message flow.

#### Upgrade / overlay impact

- Moderate but bounded.
- Most work lands in new OSS namespaces.
- Overlay-sensitive coordination is mainly around message-hook routing and inbox-binding exclusivity with Captain.

#### Why / why not

- **Why:** highest leverage with the lowest long-term upgrade pain.
- **Why not:** more initial work than webhook-only, but materially safer and more product-aligned.

## 6) Recommended architecture with rationale

**Recommendation:** Implement OSS-native AI agents as a new bounded context that reuses `AgentBot` only as a compatibility/sender/binding primitive.

### Rationale

- It preserves current `pending` and `bot_handoff!` behavior without creating parallel state machines.
- It keeps built-in AI in OSS Chatwoot instead of routing users through Captain.
- It avoids duplicating the existing webhook-bot lifecycle while still allowing internal runtime.
- It isolates most complexity in new tables/services/controllers/UI rather than deep edits to `Inbox`, `Conversation`, or dispatcher internals.
- It gives a clean feature-flag boundary: no enabled flag, no inbox binding, no behavior change.
- It allows v1 to ship prompts + provider/model config + tools without dragging KB/vector complexity into the first release.
- It remains compatible with future OSS/enterprise coexistence because AI-agent inbox binding can be made mutually exclusive with Captain inbox binding.

### Recommended high-level structure

- **OSS domain:** `AiAgent`, `AiCustomTool`, `AiAgentToolBinding`, `AiAgentRun`, optional `AiToolCall`.
- **Compatibility layer:** `AiAgent belongs_to :agent_bot`; one shadow bot per AI agent.
- **Runtime seam:** a single OSS call from the existing message hook into `AiAgents::InboundRouter.enqueue_if_applicable(message)`.
- **Handoff:** always through `Conversation#bot_handoff!`.
- **Message identity:** outgoing AI replies are persisted as normal bot messages from the shadow `AgentBot`.
- **KB:** deferred to v2 with pgvector-backed retrieval; v1 does not depend on vector.

## 7) Phased roadmap

### v1 - configurable built-in agents (first delivery)

- Account-level feature flags and installation kill switch.
- Agent CRUD.
- Prompt/instruction storage.
- Provider/model config with per-agent encrypted secrets only.
- Built-in tool registry with minimal write surface (`handoff_to_human`) plus account-level custom HTTP tools.
- Inbox binding via shadow `AgentBot` reuse.
- Internal async response generation from the post-message hook.
- `ai_agent_runs` table for backend idempotency and audit.
- Safe runtime failure handling, bounded retries, and human handoff.
- Admin-only settings visibility.

### v1.1 - hardening / operator usability

- Run ledger admin API/UI visibility.
- Optional `ai_tool_calls` table and admin visibility for redacted tool traces.
- Playground/test-run endpoint for admins.
- Better disabled/deleted-agent handling UX.
- Better redaction and retention controls for tool execution history.

### v2 - knowledge base

- Active Storage uploads + URL ingestion.
- Extraction/chunking pipeline.
- pgvector embeddings and retrieval.
- KB tool enablement per agent.
- Graceful “KB disabled” fallback when vector capability is unavailable.

### Optional v3 - richer routing / multi-agent orchestration

- Topic/scenario router.
- Structured sub-agent delegation.
- Plugin-style custom server-side function registry.
- Shared account-level knowledge collections reusable across agents.

## 8) Detailed domain model / database schema proposal

### 8.1 Core v1 tables

#### `ai_agents`

- **Purpose:** primary OSS AI-agent record.
- **Key columns:**
  - `id`
  - `account_id` FK, indexed, not null
  - `agent_bot_id` FK, unique, not null
  - `name` string, not null
  - `description` text
  - `enabled` boolean, default true, not null
  - `tombstoned_at` datetime, nullable
  - `provider` string, not null
  - `model` string, not null
  - `endpoint_url` text, nullable
  - encrypted provider secret columns (for example `api_key`, optional `api_secret`)
  - `config` jsonb default `{}` not null
  - `prompt_template` text, not null
  - `handoff_prompt` text, nullable
  - `handoff_message` text, nullable
  - timestamps
- **Indexes:**
  - `index_ai_agents_on_account_id`
  - `index_ai_agents_on_agent_bot_id` unique
  - optional `index_ai_agents_on_account_id_and_enabled`
- **Notes:**
  - `config` holds non-secret generation knobs only (temperature, max_tokens, stop behavior, tool policy, etc.). Do not store secrets in JSONB.
  - v1 decision: AI-agent deletion is logical, not destructive. `DELETE` tombstones the `AiAgent`, unbinds inboxes, and preserves the shadow `AgentBot` to keep historical sender identity intact.
  - Runtime eligibility is `enabled == true && tombstoned_at.nil?`.

#### `ai_custom_tools`

- **Purpose:** account-scoped admin-configured HTTP tools.
- **Key columns:**
  - `id`, `account_id`
  - `slug` unique per account
  - `title`, `description`
  - `enabled` boolean
  - `http_method` enum/string (`GET`, `POST` initially)
  - `endpoint_url` text
  - `request_template` text
  - `response_template` text
  - `auth_type` enum/string (`none`, `bearer`, `basic`, `api_key`)
  - `auth_config` jsonb for non-secret shape only (`header name`, `location`)
  - encrypted secret columns for token/key/password
  - `param_schema` jsonb
  - `timeout_ms` integer default 5000
  - timestamps
- **Indexes:**
  - unique `(account_id, slug)`
  - `(account_id, enabled)`
- **Notes:**
  - The enterprise `safe_endpoint_validatable` concern is only a partial reference (`enterprise/app/models/concerns/safe_endpoint_validatable.rb:1-84`), not sufficient as-is.
  - v1 OSS requirements are stricter: create/update-time hostname validation plus execution-time DNS revalidation, private-range blocking, no self-calls, no raw IP targets, encrypted auth secrets outside JSONB, and explicit redirect policy.

#### `ai_agent_tool_bindings`

- **Purpose:** per-agent tool enablement and ordering.
- **Key columns:**
  - `id`, `ai_agent_id`
  - `tool_source` string (`built_in`, `custom_http`, `custom_function`)
  - `tool_key` string for built-ins / future plugin functions
  - `ai_custom_tool_id` nullable FK
  - `enabled` boolean default true
  - `position` integer
  - `config` jsonb default `{}` not null
  - timestamps
- **Indexes:**
  - `(ai_agent_id, tool_source, tool_key)` unique where `ai_custom_tool_id` null
  - `(ai_agent_id, ai_custom_tool_id)` unique where present
- **Notes:** built-in tools are code-registered, not DB-defined.

#### `ai_agent_runs`

- **Purpose:** durable backend idempotency and audit ledger in v1; admin visibility is added in v1.1.
- **Key columns:**
  - `id`, `account_id`, `ai_agent_id`, `conversation_id`, `triggering_message_id`
  - `status` string/enum (`queued`, `running`, `succeeded`, `handoff`, `failed`, `skipped`, `timed_out`)
  - `model_provider`, `model_name`
  - `handoff_reason` string
  - `error_class`, `error_message`
  - `usage` jsonb default `{}`
  - `metadata` jsonb default `{}`
  - `started_at`, `finished_at`, timestamps
- **Indexes:**
  - unique `triggering_message_id`
  - `(conversation_id, created_at desc)`
  - `(ai_agent_id, created_at desc)`
- **Retention notes:** keep 30-90 days by default; older rows may be pruned asynchronously.

#### Optional v1.1 `ai_tool_calls`

- **Purpose:** durable per-tool execution trace for admin troubleshooting.
- **Key columns:** run FK, tool key/source, status, duration, redacted request/response summaries, error fields.
- **Retention notes:** shorter retention than `ai_agent_runs`; redact PII/secrets before persistence.

### 8.2 v2 knowledge-base tables

#### `ai_knowledge_sources`

- `id`, `account_id`, `name`, `source_type` (`url`, `upload`), `source_url`, `status`, `metadata`, timestamps
- `has_one_attached :file`
- store extraction error/status summary, not raw provider responses.

#### `ai_agent_knowledge_sources`

- join table between `ai_agents` and `ai_knowledge_sources`
- unique `(ai_agent_id, ai_knowledge_source_id)`

#### `ai_knowledge_chunks`

- `id`, `account_id`, `ai_knowledge_source_id`, `chunk_index`, `content`, `token_count`, `metadata`, `embedding :vector(...)`, timestamps
- indexes on source FK and ivfflat embedding index.
- embedding dimension is a v2 implementation decision and should initially align with the provider/embedding stack selected then; `1536` is only a local reference point because current enterprise tables use it (`db/schema.rb:160-167,296-311`).

### 8.3 Secrets strategy

- **Installation defaults:** keep installation-level provider enablement, allowed providers, and non-secret default model/endpoint hints in `InstallationConfig` / `GlobalConfigService`.
- **Forbidden in v1:** no provider API keys, shared bearer tokens, or other secrets in `InstallationConfig`, `GlobalConfig`, or account `settings`.
- **Per-agent secrets:** encrypted columns on `ai_agents`; this is the only v1 provider-secret storage mode.
- **Per-tool secrets:** encrypted columns on `ai_custom_tools`.
- **Rule:** no provider API keys or custom-tool secrets in JSONB, request templates, audit payloads, or rendered API responses.
- **Future extension rule:** if shared installation-scoped secrets are needed later, add a dedicated encrypted installation credential store; do not repurpose `InstallationConfig` / `GlobalConfig` for secrets.

## 9) API contract design

### 9.1 Agent CRUD

- `GET /api/v1/accounts/:account_id/ai_agents`
  - list agents for the account
  - response includes summary metadata, enabled state, inbox count, provider/model, updated_at
- `POST /api/v1/accounts/:account_id/ai_agents`
  - creates agent and shadow `AgentBot`
  - request summary:
    - `name`, `description`
    - `prompt_template`, optional `handoff_prompt`, `handoff_message`
    - `provider`, `model`, `endpoint_url`
    - provider secret fields stored only as per-agent encrypted credentials
    - `config` object
    - `tool_bindings` array
- `GET /api/v1/accounts/:account_id/ai_agents/:id`
- `PATCH /api/v1/accounts/:account_id/ai_agents/:id`
- `DELETE /api/v1/accounts/:account_id/ai_agents/:id`
  - tombstones agent, unbinds inboxes via linked `AgentBotInbox`, disables future runtime eligibility, and preserves the shadow `AgentBot`
  - no hard delete of the shadow bot in v1

### 9.2 Operations

- `POST /api/v1/accounts/:account_id/ai_agents/:id/playground` (v1.1)
  - admin-only preview run against supplied message history; does not mutate conversations
- `GET /api/v1/accounts/:account_id/ai_agents/:id/runs` (v1.1)
  - recent run ledger
- `POST /api/v1/accounts/:account_id/ai_agents/:id/disable`
- `POST /api/v1/accounts/:account_id/ai_agents/:id/enable`

### 9.3 Inbox binding

- Preferred API surface:
  - `GET /api/v1/accounts/:account_id/inboxes/:id/ai_agent`
  - `PUT /api/v1/accounts/:account_id/inboxes/:id/ai_agent`
    - `{ "ai_agent_id": 123 }` to bind
    - `{ "ai_agent_id": null }` to unbind
- Implementation note: this endpoint internally manages the linked shadow `AgentBotInbox`, preserving current inbox semantics.
- Binding enforcement is not UI-only. v1 requires:
  - OSS model/service-level validation that rejects binding when the inbox is Captain-bound.
  - Reciprocal enterprise overlay validation on Captain binding paths that rejects binding when `inbox.agent_bot&.ai_agent` is present.
  - The same rule enforced on create, update, and rebind operations, not just first-time creation.

### 9.4 Custom tools

- `GET /api/v1/accounts/:account_id/ai_custom_tools`
- `POST /api/v1/accounts/:account_id/ai_custom_tools`
- `GET /api/v1/accounts/:account_id/ai_custom_tools/:id`
- `PATCH /api/v1/accounts/:account_id/ai_custom_tools/:id`
- `DELETE /api/v1/accounts/:account_id/ai_custom_tools/:id`
- `GET /api/v1/accounts/:account_id/ai_tools/catalog`
  - returns built-in registry + enabled custom HTTP tools

### 9.5 Knowledge base (v2)

- `GET/POST/PATCH/DELETE /api/v1/accounts/:account_id/ai_knowledge_sources`
- `POST /api/v1/accounts/:account_id/ai_agents/:id/knowledge_sources/:knowledge_source_id`
- `DELETE /api/v1/accounts/:account_id/ai_agents/:id/knowledge_sources/:knowledge_source_id`

### 9.6 Request/response shape conventions

- Use account-scoped REST controllers + Pundit + Jbuilder partials, matching current account APIs.
- Never return decrypted secrets after create/update.
- Include a stable `capabilities` object in agent show responses so the frontend can gray out KB/tools based on feature flags.

### 9.7 Permissions / authz

- **Admin:** full CRUD for agents, bindings, tools, KB, and provider secrets.
- **Agent:** no v1 visibility to AI settings screens or secret-bearing APIs.
- **Bot token auth:** unchanged; internal runtime should not require opening new bot-token surfaces beyond existing allowlist (`app/controllers/concerns/access_token_auth_helper.rb:30-39`).

## 10) Runtime architecture

### Inbound message trigger path

1. Message arrives in a conversation.
2. Existing `MessageTemplates::HookExecutionService` runs.
3. Add one OSS delegation point after existing template checks: `AiAgents::InboundRouter.enqueue_if_applicable(message)`.
4. Router conditions:
   - installation AI feature enabled
   - account AI feature enabled
   - message is incoming
   - conversation is still `pending`
   - `inbox.agent_bot` exists
   - `inbox.agent_bot.ai_agent` exists and is enabled and not tombstoned
   - inbox is not Captain-bound
   - routing applicability is resolved from the explicit `inbox.agent_bot -> ai_agent` association, not from generic `active_bot?` alone
5. Router enqueues `AiAgents::ResponseJob`.

### Async job flow

1. Acquire per-conversation mutex (reuse `MutexApplicationJob` pattern).
2. Create or reuse `ai_agent_runs` row using `triggering_message_id` as idempotency key.
3. Re-read conversation/message/agent state.
4. Resolve the actionable binding again from `conversation.inbox.agent_bot&.ai_agent` inside the job.
5. Bail out safely with `skipped` or `failed` if:
   - conversation no longer pending
   - newer incoming message supersedes this one and a later run is already queued/running
   - agent was disabled or tombstoned
   - inbox binding changed or was removed
   - provider credentials are missing
   - inbox is now Captain-bound
6. Build context from recent conversation history + contact/conversation attributes.
7. Execute provider adapter.
8. Execute tool calls via tool executor if requested.
9. Persist final status:
   - normal reply -> create outgoing message from shadow `AgentBot`
   - handoff -> create optional transfer message, then `conversation.bot_handoff!`
   - failure -> follow the concrete default failure policy below

### Idempotency / concurrency

- Unique `ai_agent_runs.triggering_message_id` prevents duplicate completed runs.
- Per-conversation mutex prevents parallel double replies.
- Before posting a response, re-check that the conversation is still pending and this run is still the newest actionable run.

### Timeout / error handling

#### Default v1 failure policy

- **Policy:** OSS AI agents fail open to a human by default. They do not keep conversations pending after configuration/state/runtime failures.
- **Missing provider credentials:** no retry; mark run `failed` with config error metadata; if the conversation is still pending, post the configured handoff/fallback message if available and call `conversation.bot_handoff!`.
- **Disabled/tombstoned agent:** no retry; mark run `skipped`; if the conversation is still pending, call `conversation.bot_handoff!` without attempting an AI reply.
- **Removed or changed inbox binding:** no retry; mark run `skipped`; if the conversation is still pending under the old bot-owned pending state, call `conversation.bot_handoff!` so the conversation does not remain stuck.
- **Provider timeout:** one bounded retry with short backoff only if the same triggering message is still the latest actionable user message and the conversation remains pending; on second timeout mark `timed_out` and hand off.
- **Tool timeout:** treat the tool call as failed; if the tool is optional, allow the provider flow to continue without tool output once; if the tool is required for the current step, mark run `failed` and hand off.
- **Unexpected runtime exception:** mark run `failed`, capture redacted error metadata, and hand off if the conversation is still pending.

#### Compatibility note

- Preserve existing `keep_pending_on_bot_failure` semantics for webhook bots only; OSS AI-agent failure handling uses the explicit fail-open policy above and must not alter webhook bot behavior.

### Provider abstraction

- Use an OSS `AiAgents::Providers::BaseAdapter` with concrete adapters per provider.
- Only provider-specific behavior belongs in adapters; orchestration stays provider-agnostic.
- No external/provider behavior is assumed in this plan beyond standard request/response capability; provider-specific nuances can be verified during implementation if needed.

## 11) Knowledge base design

### Scope recommendation

- **Not required for v1.**
- **Design now, implement in v2.** This avoids making first release dependent on vector ingestion.

### Storage and ingestion

- Uploads use Active Storage on `ai_knowledge_sources`.
- URLs are ingested asynchronously and normalized into extracted text.
- Chunking job writes `ai_knowledge_chunks` rows with metadata (`source_id`, page number, chunk index, content hash).

### Retrieval

- Use pgvector embeddings on `ai_knowledge_chunks.embedding` with the same proven index style as existing vector tables.
- Retrieval tool does top-k semantic lookup scoped by account + linked knowledge sources.
- Retrieved chunks are injected into the model context with source labels for optional citation UX.

### Fallback if vector unavailable

- Do **not** make general AI agents depend on vector.
- If the `vector` extension is unavailable in a target self-hosted deployment, KB features stay disabled behind capability flags; prompt/tool-based agents continue to work.
- This keeps the recommendation free of high-risk runtime assumptions.

## 12) Tool system design

### Design principles

- Built-in tools are code-registered, not DB-authored.
- Admin-configured tools are HTTP-only in v1.
- Future “custom functions” are plugin-registered server-side functions, not arbitrary DB code.

### Built-in tools (v1 / v2)

- `handoff_to_human` (v1, required)
- `search_knowledge_base` (v2, only when KB enabled)

### Why keep built-ins minimal

- Conversation/contact/account state can be injected directly into prompt context instead of exposed as extra tools.
- This avoids duplicating existing Chatwoot data-access functionality behind unnecessary tool calls.

### Custom HTTP tools (v1)

- Account admin defines endpoint, method, parameter schema, request template, response template, auth mode, timeout.
- Safety boundaries:
  - HTTPS only
  - no localhost / app self-calls / raw IPs
  - create/update-time hostname validation is required, but not sufficient
  - execution-time DNS resolution and revalidation before every request is required
  - block loopback, link-local, private, multicast, and otherwise reserved/internal address ranges after DNS resolution
  - redirects disabled by default in v1; if a redirect policy is ever introduced later, every hop must be revalidated with the same DNS/private-range checks
  - explicit timeout
  - bounded response size
  - redacted secrets in logs, run history, and any durable tool-call traces
  - redact authorization headers, API keys, passwords, and rendered secret values before persistence or exception capture
  - account-scoped ownership and permission checks
  - request templating must not expose decrypted secrets back into model-visible transcripts or admin-visible history

### Security baseline for tool execution

- The current enterprise safe-endpoint concern is a useful partial reference only (`enterprise/app/models/concerns/safe_endpoint_validatable.rb:1-84`).
- v1 OSS requirements are stricter because execution safety cannot rely on create-time validation alone.
- Tool execution should run through one dedicated executor service so DNS checks, redirect policy, timeouts, response truncation, and redaction are applied consistently.

### Custom function/plugin model (v3 recommendation)

- Add a registry, e.g. `AiAgents::Tools::Registry.register(:my_tool, handler: ...)`.
- DB only stores enablement/bindings and presentation metadata.
- Executable logic ships as server code in self-hosted deployments, not stored in the database.
- This is safer, easier to review, and upgrade-safe relative to DB-stored code.

## 13) Multi-agent and routing design

### v1 routing model

- One bound `AiAgent` per inbox through its shadow `AgentBot`.
- No true sub-agent orchestration in v1.
- Prompt can still describe allowed scenarios, but runtime is single-agent.

### v2/v3 routing model

- Add optional `routing_mode` in agent config:
  - `single_agent`
  - `scenario_router`
  - `delegation`
- Add child scenario definitions only when the single-agent path is proven insufficient.

### Recommended design

- Keep multi-agent out of v1.
- When added later, model it as a router + child agent profiles inside the same `AiAgent` bounded context, not as Captain-style namespace reuse.

## 14) Human handoff flow

### Primary flow

1. Model selects `handoff_to_human`, or runtime classifies a safe-failure state.
2. Optional outgoing transfer message is created from the shadow bot.
3. `conversation.bot_handoff!` is called.
4. Existing downstream handoff event behavior remains intact.

### Handoff triggers

- explicit tool call
- confidence/routing fallback
- missing provider secret
- disabled/deleted agent detected at runtime
- repeated timeout/tool failure

### Legacy / malformed state handling

- If conversation already moved to `open` or `resolved`, do nothing and mark run `skipped`.
- If inbox binding disappeared mid-run, do not post a bot reply.
- If shadow bot exists but `AiAgent` record is deleted/disabled, unbind or hand off on the next actionable message.

## 15) Frontend integration plan

### Routes

- Add an `aiAgents` settings module under `app/javascript/dashboard/routes/dashboard/settings/` and register it in `settings.routes.js`.
- Add one sidebar entry in `components-next/sidebar/Sidebar.vue` near existing `Agent Bots` / automation settings.

### Screens

- **AI Agents list**: list, search, enable/disable, delete, inbox count.
- **AI Agent create/edit**: prompt, provider/model config, credentials, tool bindings.
- **Custom Tools list**: account-level HTTP tools.
- **Inbox settings integration**: bind/unbind AI agent from inbox settings screen.
- **Run history / playground**: v1.1.
- **Legacy Agent Bots surface**: shadow bots are hidden from the default list; if shown via a deep link or internal admin/debug surface, they are clearly marked system-managed and read-only.

### Frontend architecture patterns

- Use existing settings shells: `SettingsWrapper.vue`, `Wrapper.vue`, `SettingsLayout.vue`, `BaseSettingsHeader.vue`.
- Use Vuex modules + `dashboard/api/ApiClient.js` style clients.
- Follow CRUD patterns already used in Agents / Agent Bots / Automation / Inboxes.

### i18n

- Add English source keys under `app/javascript/dashboard/i18n/locale/en/` and include them from `.../en/index.js`.
- Do not add non-English source changes in repo.

### Feature flags in UI

- Hide routes/sidebar/screens unless installation + account AI flags are enabled.
- Disable KB-specific controls when KB capability is false.
- Keep all AI settings/admin screens admin-only in v1.

## 16) Security and compliance considerations

- Encrypt provider and tool secrets with Active Record encryption.
- Forbid provider or tool secrets in `InstallationConfig`, `GlobalConfig`, account `settings`, JSONB config blobs, request templates, and rendered API responses.
- Never echo secrets in API responses, job payloads, logs, audits, or durable run/tool-call history.
- Strict account scoping on every agent, tool, run, and knowledge record.
- Custom HTTP tools must be SSRF-safe at both validation time and execution time.
- Execution-time tool protection must include DNS re-resolution, private-range rejection, self-call rejection, redirect policy enforcement, bounded response size, and redaction before persistence.
- Keep tool and provider timeouts short and bounded.
- Avoid DB-stored executable code.
- Keep bot-token endpoint surface unchanged unless an explicit need is proven.
- Default all AI settings and secret-bearing APIs to admin-only in v1.

## 17) Scalability / performance considerations

- Use Sidekiq/ActiveJob for all provider/tool/KB work.
- Apply per-conversation mutex locking to avoid reply storms.
- Keep v1 context building bounded (recent messages, not full transcript dumps).
- Make tool execution serial by default in v1; parallel tool execution can wait for v2/v3.
- Use pgvector ivfflat indexes only for KB-enabled deployments.
- Prune run/tool-call history on a retention schedule.

## 18) Upgrade compatibility / enterprise overlay considerations

- New work should land primarily in new OSS namespaces/files.
- Avoid copying Captain models/controllers/UI into OSS.
- Keep edits to overlay-sensitive OSS files narrowly scoped:
  - `MessageTemplates::HookExecutionService`
  - possibly `AgentBot` for association wiring
  - account settings permit list / schema only for feature flags
- Enforce inbox responder exclusivity:
  - if an inbox is Captain-bound, reject OSS AI-agent binding in OSS model/service validation and controller flow
  - if an inbox is OSS AI-agent-bound, reject Captain binding through enterprise-mirrored validation and controller/service enforcement
  - enforce the rule on both create and update/rebind paths, not just in settings UI
- Explicit enterprise mirror points are required because current `CaptainInbox` validation only covers uniqueness (`enterprise/app/models/captain_inbox.rb:17-22`) and current Captain inbox binding is controller-driven (`enterprise/app/controllers/api/v1/accounts/captain/inboxes_controller.rb:10-19`).
- Runtime applicability must resolve from `inbox.agent_bot&.ai_agent`, so even if a legacy `active_bot?` path exists, OSS AI scheduling will not occur unless the explicit association is present.
- Preserve existing public contracts for `AgentBot`, Inbox, Conversation, and existing settings APIs.
- Mirror any unavoidable seam changes in enterprise overlays only where required for parity, not by moving OSS AI features under enterprise.

## 19) Blast radius / affected entry points

- `app/services/message_templates/hook_execution_service.rb` - new OSS delegation point for internal AI runtime scheduling.
- `app/models/agent_bot.rb` - 1:1 association to new `AiAgent` shadow owner.
- `app/controllers/api/v1/accounts/inboxes_controller.rb` or a new inbox-AI binding controller - bind/unbind API.
- `app/controllers/api/v1/accounts_controller.rb` + `app/models/account.rb` - account feature flags/settings schema.
- `enterprise/app/models/captain_inbox.rb` + `enterprise/app/controllers/api/v1/accounts/captain/inboxes_controller.rb` - reciprocal responder exclusivity enforcement.
- `app/javascript/dashboard/routes/dashboard/settings/settings.routes.js` - settings route registration.
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` - settings navigation entry.
- New OSS models/controllers/views/store/api files for AI agents and tools.
- Future KB blast radius: Active Storage, background ingestion jobs, vector-backed tables.

## 20) Invariants

| Invariant                                                                                                 | Why it matters                                                     | How to verify later                                                                                  |
| --------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------- |
| Inboxes with an active bot still create new conversations as `pending`                                    | Existing bot behavior must remain stable                           | Regression test on inbox with webhook bot and inbox with AI agent shadow bot                         |
| `Conversation#bot_handoff!` remains the only handoff primitive used by OSS AI agents                      | Prevents parallel handoff semantics                                | Runtime test that handoff always transitions pending -> open via existing method                     |
| Existing webhook `AgentBot` flows do not change                                                           | Avoid breaking installed self-hosted bots                          | Regression path through `AgentBotListener` + webhook job for non-AI bots                             |
| AI runtime only responds while conversation is still `pending`                                            | Prevents double-reply after human takeover                         | Concurrent message/race tests with open/resolved transitions                                         |
| OSS AI routing only applies when `inbox.agent_bot&.ai_agent` resolves to an enabled, non-tombstoned agent | Prevents accidental scheduling off generic `active_bot?` semantics | Router and job tests with webhook bot, no bot, shadow bot, and Captain-bound inboxes                 |
| One inbox cannot be actively bound to both Captain and OSS AI agent handling                              | Prevents double scheduling and conflicting responders              | Dual-binding tests through OSS binding API, Captain binding API, and model/service validation layers |
| Missing/invalid provider secrets never leave a conversation permanently stuck because of OSS AI           | Safety for malformed config                                        | Trigger path with missing creds and verify fail-open handoff policy                                  |
| Shadow `AgentBot` records are preserved when an `AiAgent` is deleted/tombstoned                           | Preserves historical sender identity                               | Delete/tombstone flow plus historical message rendering verification                                 |
| AI settings and secret-bearing APIs are admin-only in v1                                                  | Reduces accidental secret exposure                                 | Policy/API/UI authorization checks                                                                   |
| KB features are optional and do not block non-KB agents                                                   | Avoids vector dependency for v1                                    | Install with KB disabled / vector unavailable and verify prompt+tools still work                     |

## 21) Behavior-that-must-not-change

- Existing webhook bot event delivery and `AgentBots::WebhookJob` behavior for non-AI bots must not change.
- Inboxes without an active bot must continue opening conversations normally instead of forcing `pending`.
- Existing bot-authenticated conversation status updates that call `bot_handoff!` must keep working (`app/controllers/api/v1/accounts/conversations_controller.rb:81-98` from prior findings).
- Existing Captain-only inbox handling must continue to work when Captain is present and OSS AI agents are disabled/unbound.
- Existing account settings update semantics (`settings.merge!`) must remain stable for unrelated settings.

## 22) Validation matrix with exact areas to test later during implementation

| Check                                       | Exact area / path                                                                                                                 | Proves                                                                     |
| ------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| Webhook bot regression                      | Existing webhook `AgentBot` bound to inbox; incoming message path through `AgentBotListener`                                      | Non-AI bots still behave exactly as before                                 |
| Pending conversation regression             | Inbox with active shadow bot; create new conversation                                                                             | Reused `AgentBotInbox` semantics still mark conversation `pending`         |
| Internal AI response path                   | Pending conversation in AI-agent-bound inbox where `inbox.agent_bot&.ai_agent` resolves; incoming message after post-message hook | AI runtime is triggered from the intended seam and posts one reply         |
| Handoff path                                | Pending conversation where runtime chooses handoff                                                                                | Existing `bot_handoff!` semantics are preserved                            |
| Missing secret safety                       | AI agent enabled but provider secret missing                                                                                      | Conversation is safely handed off; no stuck pending state                  |
| Disabled/deleted agent mid-flight           | Agent disabled, tombstoned, or binding removed after job enqueue                                                                  | Job exits safely and does not post stale response                          |
| Captain exclusivity via OSS API             | Attempt to bind OSS AI agent to Captain-bound inbox through OSS API                                                               | OSS binding path rejects the dual-binding attempt                          |
| Captain exclusivity via Captain API         | Attempt to bind Captain assistant to OSS AI-agent-bound inbox through Captain API                                                 | Enterprise binding path rejects the dual-binding attempt                   |
| Captain exclusivity via model/service layer | Simulated bind/rebind path bypassing UI                                                                                           | Dual-binding remains impossible even without UI constraints                |
| Shadow bot tombstone lifecycle              | Delete/tombstone an AI agent that already sent messages                                                                           | Historical sender identity remains intact and bot is not hard-deleted      |
| Installation secret prohibition             | Inspect installation config and API payload handling after agent create/update                                                    | No provider secret is persisted into `InstallationConfig` / `GlobalConfig` |
| Tool SSRF guardrails (create-time)          | Custom HTTP tool with localhost/IP/self URL                                                                                       | Unsafe endpoints are rejected at validation time                           |
| Tool SSRF guardrails (execution-time)       | Tool hostname that resolves to a private/internal range or attempts redirect                                                      | Unsafe execution is blocked even after DNS resolution or redirect          |
| Tool timeout handling                       | Slow custom HTTP tool                                                                                                             | Runtime handles timeout without duplicate bot messages                     |
| Admin-only settings visibility              | Non-admin user attempts AI settings route/API access                                                                              | Secret-bearing settings remain admin-only                                  |
| UI settings integration                     | Settings route + sidebar + CRUD pages                                                                                             | Admin UX follows existing settings patterns                                |
| KB capability fallback (v2)                 | Deployment with KB capability false                                                                                               | Non-KB agents remain functional                                            |

## 23) Open questions / deferred decisions

- If multiple provider types are added early, is embedded per-agent provider config still sufficient, or should shared provider profiles be introduced sooner?

## 24) Recommended implementation phases with suggested file areas (not code)

### Phase 1 - feature flags and core domain skeleton

- **Goal:** add installation/account gating and core data model.
- **Suggested file areas:**
  - `app/models/account.rb`
  - `app/controllers/api/v1/accounts_controller.rb` (+ enterprise overlay permit extension if needed)
  - `db/migrate/*create_ai_agents*.rb`
  - `db/migrate/*create_ai_agent_runs*.rb`

### Phase 2 - shadow bot compatibility layer

- **Goal:** link `AiAgent` to `AgentBot`, preserve inbox pending semantics, and make shadow bots system-managed/tombstone-safe.
- **Suggested file areas:**
  - `app/models/agent_bot.rb`
  - `app/models/ai_agent.rb`
  - inbox binding controller/model area

### Phase 3 - agent CRUD API

- **Goal:** account-scoped REST endpoints and Jbuilder responses for `AiAgent`.
- **Suggested file areas:**
  - `app/controllers/api/v1/accounts/ai_agents_controller.rb`
  - `app/policies/ai_agent_policy.rb`
  - `app/views/api/v1/accounts/ai_agents/*`

### Phase 4 - custom HTTP tool domain

- **Goal:** account-scoped tool CRUD with encrypted secrets and stricter-than-enterprise safe endpoint validation.
- **Suggested file areas:**
  - `app/models/ai_custom_tool.rb`
  - `app/controllers/api/v1/accounts/ai_custom_tools_controller.rb`
  - `db/migrate/*create_ai_custom_tools*.rb`

### Phase 5 - runtime seam and response job

- **Goal:** internal response generation for pending conversations with explicit `inbox.agent_bot -> ai_agent` applicability and fail-open handoff policy.
- **Suggested file areas:**
  - `app/services/message_templates/hook_execution_service.rb`
  - `app/jobs/ai_agents/response_job.rb`
  - `app/services/ai_agents/inbound_router.rb`

### Phase 6 - tool execution and handoff integration

- **Goal:** bind tools to agents and reuse `bot_handoff!` safely.
- **Suggested file areas:**
  - `app/models/ai_agent_tool_binding.rb`
  - `app/services/ai_agents/tools/*`
  - `app/services/ai_agents/runtime/*`

### Phase 7 - settings UI integration

- **Goal:** settings pages for agents, tools, and inbox binding.
- **Suggested file areas:**
  - `app/javascript/dashboard/routes/dashboard/settings/*ai*`
  - `app/javascript/dashboard/api/*ai*`
  - `app/javascript/dashboard/store/modules/*ai*`

### Phase 8 - v1.1 diagnostics and hardening

- **Goal:** add run history, safe admin observability, and failure UX.
- **Suggested file areas:**
  - diagnostics API/views area
  - settings diagnostics UI area
  - optional `app/models/ai_tool_call.rb`

### Phase 9 - v2 knowledge base

- **Goal:** uploads/URL ingestion, chunking, embeddings, retrieval.
- **Suggested file areas:**
  - `app/models/ai_knowledge_*`
  - `app/jobs/ai_agents/knowledge/*`
  - KB settings/admin UI area

## Deliverables

| Item                                      | Status   |
| ----------------------------------------- | -------- |
| Repo-grounded architecture recommendation | Included |
| At least 3 approaches with tradeoffs      | Included |
| v1-first roadmap                          | Included |
| Verified Facts vs Assumptions             | Included |
| Invariants                                | Included |
| Behavior-that-must-not-change             | Included |
| Blast radius                              | Included |
| Validation matrix                         | Included |

## Decision log

| Decision                      | Chosen                                                   | Rejected                                        | Rationale                                                        | Evidence                                                                                                                   |
| ----------------------------- | -------------------------------------------------------- | ----------------------------------------------- | ---------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| Inbox compatibility primitive | Reuse `AgentBot` + `AgentBotInbox` via shadow bot        | New inbox actor subsystem                       | Smallest change that preserves pending/handoff behavior          | `app/models/inbox.rb:169-172`, `app/models/conversation.rb:254-265`                                                        |
| Runtime trigger seam          | Existing message post-hook with one OSS delegation point | Webhook-only runtime or deep dispatcher rewrite | Strongest verified internal AI seam with minimal blast radius    | `app/services/message_templates/hook_execution_service.rb:16-20,62`, `enterprise/.../hook_execution_service.rb:4-10,32-40` |
| Product boundary              | New OSS `AiAgent` bounded context                        | Captain extraction / aliasing                   | Avoid licensing-path coupling and upgrade pain                   | enterprise Captain evidence vs user requirement                                                                            |
| Secret storage                | Encrypted columns                                        | Plain JSONB secrets                             | Matches verified secure local patterns and avoids secret leakage | `app/models/integrations/hook.rb:24-25`, `app/models/user.rb:82-84`                                                        |
| v1 scope                      | Prompts + provider/model config + tools                  | KB/multi-agent first                            | Meets user priority with lower risk                              | roadmap priorities + pgvector dependency evidence                                                                          |
