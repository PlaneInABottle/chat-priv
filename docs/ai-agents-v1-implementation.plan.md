# OSS AI Agents v1 - Implementation Plan

## Goal of v1 slice

Deliver the first OSS-native AI agent product slice described in `docs/ai-agents-architecture.plan.md`, focused only on configurable single agents with prompt/system-message configuration, per-agent provider/model settings, minimal tool support, inbox binding through a shadow `AgentBot`, internal async reply generation from the existing post-message hook, and an admin-managed but first-class `AI Agents` left-sidebar product area.

This slice should feel built into Chatwoot OSS, not routed through Captain, and must remain upgrade-safe by reusing verified primitives instead of inventing a parallel bot lifecycle.

## Non-goals for this slice

- No v2 knowledge base ingestion, chunking, embeddings, or pgvector dependency (`docs/ai-agents-architecture.plan.md:223-224,248-255,529-552`).
- No v3 multi-agent orchestration, router profiles, or delegation (`docs/ai-agents-architecture.plan.md:256-261,602-621`).
- No DB-stored executable custom functions; only built-in tools plus account-level custom HTTP tools (`docs/ai-agents-architecture.plan.md:23-30,554-600`).
- No Captain namespace reuse in the OSS product path (`docs/ai-agents-architecture.plan.md:11-21,112-150,701-717`).
- No speculative shared provider profile system, marketplace, quota layer, or admin diagnostics beyond what v1 strictly needs (`docs/ai-agents-architecture.plan.md:29,240-247,775-777`).

## Current state (evidence)

- Existing OSS bot lifecycle already provides the compatibility surface we want to reuse: `AgentBot` owns bot sender identity and inbox binding (`app/models/agent_bot.rb:20-37`), `AgentBotInbox` binds bot-to-inbox (`app/models/agent_bot_inbox.rb:14-28`), and inboxes with active bots force new conversations to `pending` via `Inbox#active_bot?` and `Conversation#determine_conversation_status` (`app/models/inbox.rb:169-172`, `app/models/conversation.rb:254-261`).
- Existing handoff primitive is already correct for v1 and must remain the only one: `Conversation#bot_handoff!` (`app/models/conversation.rb:161-164`).
- The narrowest internal runtime seam already exists in `MessageTemplates::HookExecutionService`, and Enterprise Captain already prepends the same seam for async response scheduling (`app/services/message_templates/hook_execution_service.rb:4-20,62`; `enterprise/app/services/enterprise/message_templates/hook_execution_service.rb:4-10,52-80`).
- Account settings and settings-permit patterns are already established in `Account` JSONB schema and `Api::V1::AccountsController` (`app/models/account.rb:34-93`, `app/controllers/api/v1/accounts_controller.rb:46-100`).
- Inbox bot binding already has an OSS controller path we can either narrow or replace with an AI-agent-specific endpoint (`app/controllers/api/v1/accounts/inboxes_controller.rb:53-65,97-99`).
- Existing dashboard patterns clearly distinguish first-class left-nav workspaces from settings-only admin screens: `Contacts` is a top-level sidebar group with a dedicated route tree outside `/settings` (`app/javascript/dashboard/components-next/sidebar/Sidebar.vue:387-448`, `app/javascript/dashboard/routes/dashboard/contacts/routes.js:6-68`), while Agent Bots and other admin configuration live under `Settings` and `/settings/...` (`app/javascript/dashboard/routes/dashboard/settings/settings.routes.js:33-69`, `app/javascript/dashboard/routes/dashboard/settings/agentBots/agentBot.routes.js:9-25`).
- Captain proves Chatwoot can mount an AI-like workspace as a top-level left-nav area, but it is enterprise-gated and must remain separate from OSS AI Agents (`app/javascript/dashboard/components-next/sidebar/Sidebar.vue:316-385`, `app/javascript/dashboard/routes/dashboard/dashboard.routes.js:16-32`, `app/javascript/dashboard/routes/dashboard/captain/captain.routes.js:20-30`).
- Enterprise already extends `Inbox#active_bot?` for Captain, so inbox-responder exclusivity must be enforced deliberately rather than assumed (`enterprise/app/models/enterprise/inbox.rb:10-16`).

## Verified facts vs assumptions

### Verified facts

| Type     | Fact                                                                                                                                                             | Evidence                                                                                                                                                                                                                                                                                                                    | Planning impact                                                                                  |
| -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Verified | Recommended v1 product path is OSS-native `AiAgent` + shadow `AgentBot`, not webhook-first and not Captain reuse                                                 | `docs/ai-agents-architecture.plan.md:154-224`                                                                                                                                                                                                                                                                               | Plan should stay inside new OSS namespaces plus narrow seams                                     |
| Verified | v1 scope is prompts, provider/model config, tools, inbox binding, runtime, and admin-only settings                                                               | `docs/ai-agents-architecture.plan.md:227-239`                                                                                                                                                                                                                                                                               | No KB or orchestration work should enter this plan                                               |
| Verified | In Chatwoot, a first-class left-nav area uses a top-level sidebar group plus a route tree outside `/settings`, while settings-only screens live under `Settings` | `app/javascript/dashboard/components-next/sidebar/Sidebar.vue:387-448,573-696`, `app/javascript/dashboard/routes/dashboard/contacts/routes.js:13-66`, `app/javascript/dashboard/routes/dashboard/settings/settings.routes.js:33-69`, `app/javascript/dashboard/routes/dashboard/settings/agentBots/agentBot.routes.js:9-25` | Clarified v1 UI must not ship as a settings-only leaf if it is meant to feel like a product area |
| Verified | The current frontend roadmap wording still places AI Agents next to settings/Agent Bots rather than as its own product workspace                                 | `docs/ai-agents-architecture.plan.md:650-652,675-677`, `docs/ai-agents-v1-implementation.plan.md:498-575`                                                                                                                                                                                                                   | Remaining UI roadmap needs correction before further frontend work                               |
| Verified | Runtime must resolve applicability from `inbox.agent_bot&.ai_agent`, not generic `active_bot?`                                                                   | `docs/ai-agents-architecture.plan.md:468-479,714-715`                                                                                                                                                                                                                                                                       | Prevents accidental scheduling for webhook bots or Captain-only inboxes                          |
| Verified | Provider/tool secrets must use encrypted columns and must not go into `InstallationConfig`, account settings, or JSONB blobs                                     | `docs/ai-agents-architecture.plan.md:381-388,681-690`                                                                                                                                                                                                                                                                       | Schema and API contracts must redact/forbid secret echoing                                       |
| Verified | The repo contains Captain-related inbox behavior and overlay seams, but this OSS AI workstream is now explicitly constrained to OSS-only changes                 | `docs/ai-agents-architecture.plan.md:429-433,709-717`, user boundary dated 2026-03-26                                                                                                                                                                                                                                       | OSS phases must protect OSS entry points only and defer reciprocal cross-edition enforcement     |
| Verified | `Conversation#bot_handoff!` is already the required handoff primitive                                                                                            | `app/models/conversation.rb:161-164`                                                                                                                                                                                                                                                                                        | No parallel handoff service                                                                      |
| Verified | Message hook seam already exists and is prepended by Enterprise                                                                                                  | `app/services/message_templates/hook_execution_service.rb:16-20,62`; `enterprise/app/services/enterprise/message_templates/hook_execution_service.rb:4-10`                                                                                                                                                                  | Runtime seam must stay narrow and overlay-safe                                                   |

### Low-risk assumptions to keep explicit

| Type       | Assumption                                                                                                           | Why low risk                                                                                                               | Resolution strategy                                                                 |
| ---------- | -------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| Assumption | v1 can ship with a single concrete provider adapter shape while keeping a minimal adapter interface                  | The approved architecture already avoids speculative provider abstractions (`docs/ai-agents-architecture.plan.md:523-527`) | Implement only the minimum adapter contract needed for the first supported provider |
| Assumption | AI-agent inbox binding should use a dedicated AI-agent endpoint instead of overloading raw `set_agent_bot` long-term | Approved architecture prefers `/inboxes/:id/ai_agent` (`docs/ai-agents-architecture.plan.md:421-433`)                      | Keep old bot binding intact; add AI-agent-specific binding path for new flow        |
| Assumption | Browser verification for runtime can use a real inbox/widget flow rather than a synthetic only-admin path            | Existing browser-testable settings and inbox patterns already exist                                                        | Treat browser verification as checkpoint, not architecture dependency               |

### High / critical runtime assumptions resolved or explicitly avoided

- **Resolved:** v1 does not require pgvector or KB capability (`docs/ai-agents-architecture.plan.md:223-224,533-552`).
- **Resolved:** v1 does not depend on Captain routes, Captain models, or Captain assistant state (`docs/ai-agents-architecture.plan.md:209-214,701-717`).
- **Resolved:** provider secrets are per-agent only; no shared installation-secret store is required in v1 (`docs/ai-agents-architecture.plan.md:381-388`).
- **Avoided:** no speculative custom-function execution path is needed (`docs/ai-agents-architecture.plan.md:23-30,595-600`).

## Runtime / dev workflow assumptions that affect implementation and testing

- Use the repo’s normal dev stack with PM2/native app runtime and Docker-backed stateful services only where needed, per `ai-native-workflow` and the repo runbook.
- Use targeted unit tests for new Ruby/Vue logic, and use real browser verification via `agent-browser` for settings and inbox flows once UI exists.
- Treat browser verification as mandatory evidence for UI-visible phases and for at least one end-to-end pending-conversation runtime path.

## Success criteria

- [ ] Admin can create and edit an OSS AI agent with prompt, provider/model config, and minimal tool bindings.
- [ ] Admin can reach `AI Agents` from a first-class main left-sidebar entry backed by a dedicated route tree outside `/settings`.
- [ ] Each AI agent owns one shadow `AgentBot`, and inbox binding reuses existing pending conversation semantics.
- [ ] Incoming messages in AI-agent-bound inboxes enqueue exactly one internal AI response path from the post-message hook.
- [ ] Handoff always uses `Conversation#bot_handoff!`.
- [ ] Existing webhook `AgentBot` flows remain unchanged.
- [ ] OSS AI binding fails safely when conflicting responder state is already visible from OSS.
- [ ] All new secret-bearing paths are admin-only and never echo decrypted secrets.
- [ ] Every phase has targeted unit tests, and UI-visible phases have real browser verification checkpoints.

---

## Roadmap alignment update (2026-03-26 clarification)

- **Clarified product goal:** AI Agents must feel like a real Chatwoot product capability, not a hidden admin setting. In repo terms, that means a top-level sidebar item and a dedicated route tree, not only a child route under `Settings`.
- **Internal admin/config surface:** prompt/system-message editing, model/provider selection, secret entry, enable/disable, tool configuration, and inbox binding remain admin-owned surfaces in v1.
- **First-class product navigation surface:** the canonical entry point for v1 should be `AI Agents` in the main left sidebar, implemented like other workspace areas (top-level sidebar group + non-`/settings` routes), even if visibility is still limited to admins.
- **Runtime/chat behavior:** inbox binding, pending conversation reuse, bot reply posting, and human handoff remain backend/runtime concerns and should stay decoupled from where the UI entry point lives.
- **v1 / later split:**
  - **v1 must deliver:** first-class `AI Agents` sidebar presence, core agent management screens, working inbox binding path, and real runtime behavior.
  - **v1 can keep secondary surfaces minimal:** tools management and inbox-setting shortcuts can be less polished than the core agent workspace, but they should live under or clearly link from `AI Agents`, not redefine the feature as settings-only.
  - **Later phases (v1.1+):** run history, playground, deeper diagnostics, KB, and richer workspace expansion.

## OSS-only boundary update (2026-03-26 workstream constraint)

- This implementation roadmap is now constrained to **OSS AI-agent work only**.
- The plan must **not require editing Enterprise/Captain files** or adding `spec/enterprise` coverage for this workstream.
- OSS phases may still defend OSS behavior using OSS-visible state and existing OSS seams.
- True reciprocal cross-edition enforcement is **deferred**. In v1, the requirement is narrower: OSS AI entry points must fail safely and must not require Captain-side changes to proceed.

---

## Phase 1: Feature gating and configuration contract

**Owner**: @implementer (backend/settings)
**Dependencies**: None
**Complexity**: LOW

### Scope

Add the installation kill switch and account-level AI feature flags/settings contract needed to hide the feature safely until later phases land.

### Exact likely file areas

- `config/installation_config.yml`
- `app/models/account.rb`
- `app/controllers/api/v1/accounts_controller.rb`
- Likely specs: `spec/models/account_spec.rb`, `spec/controllers/api/v1/accounts_controller_spec.rb` or equivalent request specs

### Data model / API / runtime / UI / test changes

- **Data model:** extend account settings schema and `store_accessor` only for non-secret AI toggles.
- **API:** permit new account setting keys through the existing account settings update path; do not introduce AI CRUD yet.
- **Runtime:** no runtime behavior yet beyond feature-flag read paths.
- **UI:** no new screen yet; keep all UI hidden by default until later phases.
- **Tests:** schema validation, permit-list regression, and default-disabled behavior tests.

### Tasks

- Add installation-level non-secret AI enablement/default keys only.
- Add account-level AI feature toggle shape following existing settings JSON schema patterns.
- Verify unrelated account settings updates still merge unchanged.

### Unit-test expectations

- Validate new account settings keys are accepted while unrelated invalid shapes are still rejected.
- Validate account settings update does not overwrite unrelated settings.
- Validate feature flags default to disabled when absent.

### Browser verification checkpoint

- **Not applicable yet**; no UI surface should appear in this phase.

### Regression checks

- Existing account settings update flow still works for non-AI keys.
- No AI-related settings are exposed to non-admin users through existing account APIs.

### Risks and rollback notes

- **Risk:** overloading `settings` with secret-bearing fields. **Mitigation:** restrict phase to boolean/non-secret defaults only.
- **Risk:** permit-list regression for unrelated account settings. **Mitigation:** keep diff isolated to new keys and merge semantics.
- **Rollback:** revert new settings keys and permit-list additions; no data migration rollback needed if no new persisted rows exist.

### Stop conditions

- Stop if this phase starts introducing provider secrets, AI CRUD, or UI routes.
- Stop if implementation requires changing unrelated account settings behavior.

### Acceptance criteria

- [ ] Installation and account gating keys exist and are non-secret only.
- [ ] Default state is off.
- [ ] Existing account settings behavior remains unchanged.

---

## Phase 2: Core AI agent schema and shadow-bot model contract

**Owner**: @implementer (backend/domain)
**Dependencies**: Phase 1
**Complexity**: MEDIUM

### Scope

Create the minimum persistent domain for v1: `ai_agents` and `ai_agent_runs`, plus the one-to-one shadow `AgentBot` ownership contract.

### Exact likely file areas

- `db/migrate/*create_ai_agents*.rb`
- `db/migrate/*create_ai_agent_runs*.rb`
- `app/models/ai_agent.rb`
- `app/models/agent_bot.rb`
- Likely specs: `spec/models/ai_agent_spec.rb`, `spec/models/agent_bot_spec.rb`

### Data model / API / runtime / UI / test changes

- **Data model:** add `ai_agents` with encrypted provider secret columns, config JSONB for non-secret knobs, prompt fields, enabled/tombstone state, and `agent_bot_id` uniqueness; add `ai_agent_runs` for idempotency/audit.
- **API:** none yet beyond model serialization readiness.
- **Runtime:** no enqueue path yet; only persistence contracts.
- **UI:** none yet.
- **Tests:** model validations, encrypted-field behavior, tombstone eligibility semantics, one-to-one shadow-bot association.

### Tasks

- Create `AiAgent` model with `belongs_to :agent_bot` and account scoping.
- Add reverse association from `AgentBot` to `AiAgent` for explicit `inbox.agent_bot&.ai_agent` resolution.
- Define tombstone-safe deletion semantics in the model/service contract, but do not build delete API yet.
- Create `AiAgentRun` schema with `triggering_message_id` uniqueness and status fields.

### Unit-test expectations

- Validate an AI agent cannot exist without account, shadow bot, name, provider, model, and prompt template.
- Validate secret fields are encrypted-at-rest using the repo’s existing encrypted-column pattern.
- Validate shadow bot association is unique and preserved when agent is tombstoned.
- Validate `AiAgentRun` uniqueness on `triggering_message_id`.

### Browser verification checkpoint

- **Not applicable yet**; backend-only persistence phase.

### Regression checks

- Existing `AgentBot` records without an `AiAgent` continue to behave as normal webhook bots.
- Existing inbox pending/open behavior remains unchanged because no runtime hook changes ship in this phase.

### Risks and rollback notes

- **Risk:** accidentally changing `AgentBot` webhook semantics while adding association wiring. **Mitigation:** additive association only; no enum/type changes.
- **Risk:** secrets leaking into JSONB config. **Mitigation:** validate allowed config keys and keep secret columns separate.
- **Rollback:** revert migrations and associations before any downstream phases depend on them.

### Stop conditions

- Stop if the phase starts binding inboxes, scheduling runtime, or exposing UI.
- Stop if deletion semantics require hard-deleting historical `AgentBot` senders.

### Acceptance criteria

- [ ] `AiAgent` and `AiAgentRun` schemas exist with correct non-secret vs secret separation.
- [ ] `AgentBot` can resolve its linked `AiAgent` without changing existing bot behavior.
- [ ] No runtime behavior changes are introduced yet.

---

## Phase 3: Inbox binding and OSS responder exclusivity

**Owner**: @implementer (backend/bindings)
**Dependencies**: Phase 2
**Complexity**: MEDIUM

### Scope

Add the AI-agent-to-inbox binding path that internally manages `AgentBotInbox`, while enforcing OSS-side responder exclusivity from the OSS AI binding path only. The phase should protect OSS AI binding from conflicting inbox state visible to OSS, without requiring Enterprise/Captain edits.

### Exact likely file areas

- `app/controllers/api/v1/accounts/inboxes_controller.rb` **or** new `app/controllers/api/v1/accounts/inboxes/ai_agents_controller.rb`
- New binding service area, likely `app/services/ai_agents/inbox_binding_service.rb`
- `app/models/agent_bot.rb`
- `app/models/agent_bot_inbox.rb`
- Likely specs: inbox binding request specs + OSS service/model specs

### Data model / API / runtime / UI / test changes

- **Data model:** reuse `AgentBotInbox`; no new table.
- **API:** add or narrow AI-agent-specific inbox bind/unbind endpoint returning the bound `AiAgent`/shadow-bot summary.
- **Runtime:** still no message scheduling, but binding must preserve `pending` semantics via existing `inbox.active_bot?` behavior.
- **UI:** no new UI yet; API-only contract.
- **Tests:** binding, unbinding, rebinding, OSS-side exclusivity rejection, and pending-conversation preservation.

### Tasks

- Add dedicated bind/unbind flow that maps `ai_agent_id` to its shadow `AgentBot`.
- Enforce rejection when the inbox is already reserved by another automated responder state visible to OSS.
- Keep exclusivity enforcement inside the OSS AI binding endpoint/service and model validation; do not require changes to Captain binding paths.
- Ensure rebinding and unbinding do not leave stale `AgentBotInbox` state.

### Unit-test expectations

- Validate binding an `AiAgent` attaches its shadow bot through `AgentBotInbox`.
- Validate unbinding removes the inbox binding without deleting the shadow bot.
- Validate inboxes already reserved by another responder configuration visible to OSS reject OSS AI binding with a stable conflict error.
- Validate new conversations in bound inboxes still open as `pending`.

### Browser verification checkpoint

- **Optional API-backed admin smoke check** once a temporary debug path exists; otherwise defer browser proof to Phase 7 when UI lands.

### Regression checks

- Existing raw webhook bot binding behavior still works for non-AI bots.
- Inboxes without any bot still create open conversations normally.

### Risks and rollback notes

- **Risk:** dual-responder state caused by conflicting inbox configuration. **Mitigation:** enforce exclusivity at the OSS controller + service/model boundary, not UI only.
- **Risk:** breaking legacy webhook bot binding path. **Mitigation:** add dedicated AI-agent binding instead of mutating generic bot binding semantics.
- **Rollback:** remove new AI-agent-specific endpoint/service and preserve old `AgentBotInbox` rows.

### Stop conditions

- Stop if the phase requires editing Enterprise/Captain files or adding cross-edition coupling.
- Stop if binding logic depends on generic `active_bot?` instead of explicit `agent_bot.ai_agent` resolution.

### Acceptance criteria

- [ ] AI agents can bind/unbind inboxes through shadow bots.
- [ ] OSS AI binding rejects inboxes already reserved by conflicting responder state visible to OSS.
- [ ] Existing pending semantics are preserved.

---

## Phase 4: AI agent CRUD API for prompt and provider/model configuration

**Owner**: @implementer (backend/API)
**Dependencies**: Phase 2
**Complexity**: MEDIUM

### Scope

Expose account-scoped admin CRUD for `AiAgent`, including prompt/system-message fields, provider/model configuration, enabled/tombstone behavior, and safe response serialization.

### Exact likely file areas

- `config/routes.rb`
- `app/controllers/api/v1/accounts/ai_agents_controller.rb`
- `app/policies/ai_agent_policy.rb`
- `app/views/api/v1/accounts/ai_agents/*.jbuilder`
- Possibly `app/presenters/` or serializer helper if needed for redaction/capabilities
- Likely specs: request/policy/view specs for `ai_agents`

### Data model / API / runtime / UI / test changes

- **Data model:** use `AiAgent` from Phase 2; soft-delete/tombstone behavior becomes externally reachable.
- **API:** list/show/create/update/delete/toggle endpoints; never return decrypted secrets; include stable capabilities summary.
- **Runtime:** no message execution yet, but create/update must keep `enabled` + tombstone semantics coherent.
- **UI:** still no final settings page, but API contract becomes stable for frontend consumption.
- **Tests:** request authorization, secret redaction, create/update validations, delete/tombstone behavior, admin-only access.

### Tasks

- Create account-scoped REST endpoints and policy.
- Create shadow `AgentBot` automatically on agent create.
- Tombstone on delete and unbind inboxes without deleting the shadow bot.
- Expose safe show/list payloads including provider/model, inbox count summary, enabled state, and capabilities.

### Unit-test expectations

- Validate admin can create agent with prompt/provider/model and encrypted secret input.
- Validate non-admin cannot access secret-bearing AI APIs.
- Validate show/list responses never include decrypted secrets.
- Validate delete tombstones the agent, preserves shadow bot, and unbinds inboxes.

### Browser verification checkpoint

- **Not applicable yet** unless a temporary manual API console is used; primary browser verification begins in Phase 7.

### Regression checks

- Existing `AgentBot` CRUD endpoints remain unchanged for non-AI bots.
- Existing account policies and admin access rules remain unchanged outside the new AI endpoints.

### Risks and rollback notes

- **Risk:** exposing secrets in Jbuilder or error payloads. **Mitigation:** explicit allowlist serialization and negative tests.
- **Risk:** delete flow removing historical bot sender identity. **Mitigation:** tombstone `AiAgent`, preserve `AgentBot`.
- **Rollback:** disable routes/controller and keep migrated rows inert behind flags.

### Stop conditions

- Stop if API starts supporting KB, run history, or shared provider profiles.
- Stop if create/update contracts require storing secrets in account or installation settings.

### Acceptance criteria

- [ ] Admin-only CRUD exists for prompt/provider/model configuration.
- [ ] Create automatically provisions a shadow `AgentBot`.
- [ ] Delete tombstones the agent and preserves historical sender identity.

---

## Phase 5: Minimal tools domain and catalog

**Owner**: @implementer (backend/tools)
**Dependencies**: Phase 4
**Complexity**: MEDIUM

### Scope

Add the smallest viable tool surface for v1: built-in `handoff_to_human`, account-level custom HTTP tools, and per-agent tool bindings.

### Exact likely file areas

- `db/migrate/*create_ai_custom_tools*.rb`
- `db/migrate/*create_ai_agent_tool_bindings*.rb`
- `app/models/ai_custom_tool.rb`
- `app/models/ai_agent_tool_binding.rb`
- `app/controllers/api/v1/accounts/ai_custom_tools_controller.rb`
- `app/controllers/api/v1/accounts/ai_tools_controller.rb` or equivalent catalog endpoint
- Likely service area: `app/services/ai_agents/tools/registry.rb`, `app/services/ai_agents/tools/safe_endpoint_validator.rb`
- Likely specs: OSS model/request/service specs for validation, redaction, and catalog behavior

### Data model / API / runtime / UI / test changes

- **Data model:** add `ai_custom_tools` and `ai_agent_tool_bindings` with encrypted auth fields and non-secret auth config.
- **API:** custom tool CRUD + tool catalog endpoint that merges built-in and enabled custom tools.
- **Runtime:** execution can remain deferred until Phase 6, but catalog and validation contracts must be stable here.
- **UI:** no final UI yet, but API becomes ready for settings forms.
- **Tests:** SSRF-safe validation, secret redaction, binding uniqueness, built-in tool catalog presence.

### Tasks

- Create custom tool model with strict validation boundaries from the approved architecture.
- Add built-in tool registry with only `handoff_to_human` enabled in v1.
- Add agent-tool binding persistence.
- Expose tool catalog payload for the future settings UI.

### Unit-test expectations

- Validate localhost/raw-IP/self-call/private-range endpoints are rejected at create/update time.
- Validate auth secrets are encrypted and never rendered back.
- Validate one agent cannot bind the same tool twice.
- Validate tool catalog always contains `handoff_to_human` even with zero custom tools.

### Browser verification checkpoint

- **Not applicable yet**; browser validation of tool forms belongs to Phase 7.

### Regression checks

- No existing integration/webhook endpoint validation paths are altered.
- AI-disabled accounts cannot access tool CRUD even if routes exist.

### Risks and rollback notes

- **Risk:** implementing only create-time safety and missing execution-time revalidation. **Mitigation:** keep this phase to persistence/catalog validation only; Phase 6 owns execution revalidation.
- **Risk:** tool scope drift into custom server-side functions. **Mitigation:** limit registry to built-in handoff + HTTP tool metadata.
- **Rollback:** drop tool routes/models while leaving agent CRUD intact.

### Stop conditions

- Stop if this phase starts executing HTTP calls.
- Stop if built-in tool list expands beyond `handoff_to_human` without a proven v1 need.

### Acceptance criteria

- [ ] Custom HTTP tools can be created safely and stored without secret leakage.
- [ ] Agents can persist tool bindings.
- [ ] Tool catalog exposes built-in handoff + enabled custom tools only.

---

## Phase 6: Runtime seam, response job, tool execution, and fail-open handoff

**Owner**: @implementer (backend/runtime)
**Dependencies**: Phases 3, 4, 5
**Complexity**: HIGH

### Scope

Activate the internal runtime path: hook-based routing, idempotent response job, provider call orchestration, tool execution, bounded retry/timeout handling, and fail-open human handoff.

### Exact likely file areas

- `app/services/message_templates/hook_execution_service.rb`
- `app/services/ai_agents/inbound_router.rb`
- `app/jobs/ai_agents/response_job.rb`
- `app/services/ai_agents/runtime/*`
- `app/services/ai_agents/providers/*`
- `app/services/ai_agents/tools/executor.rb`
- Possible supporting area: `app/jobs/concerns/` or reuse of existing mutex job pattern
- Likely specs: OSS service/job specs, tool executor specs, and OSS request-level regression specs

### Data model / API / runtime / UI / test changes

- **Data model:** write `ai_agent_runs` as the durable idempotency/audit ledger.
- **API:** no new public CRUD required; runtime remains internal.
- **Runtime:** add the one OSS delegation point in the message hook; route only when installation/account flags are on, conversation is pending, and `inbox.agent_bot&.ai_agent` resolves to an enabled, non-tombstoned agent whose OSS binding state is still valid.
- **UI:** none required for activation, but this phase unlocks browser-verifiable inbox replies.
- **Tests:** router gating, idempotency, per-conversation mutex behavior, missing-secret fail-open path, disabled/tombstoned agent path, binding-changed path, webhook non-regression, execution-time tool safety and timeout handling.

### Tasks

- Add `AiAgents::InboundRouter.enqueue_if_applicable(message)` to the existing hook seam.
- Implement `AiAgents::ResponseJob` with re-read of conversation/message/agent state and `triggering_message_id` idempotency.
- Implement minimal provider orchestration sufficient for the first provider.
- Implement tool executor with execution-time DNS/private-range checks and short timeouts.
- Ensure normal reply posts as outgoing message from shadow `AgentBot`; handoff always calls `conversation.bot_handoff!`.

### Unit-test expectations

- Validate webhook bots still only use existing webhook flow.
- Validate router does not schedule when AI flags are off, conversation is not pending, the AI binding is no longer valid, or `agent_bot.ai_agent` is absent/disabled.
- Validate duplicate runs for the same message collapse through `ai_agent_runs.triggering_message_id`.
- Validate missing credentials, binding changes, and disabled/tombstoned agents fail open without stuck pending conversations.
- Validate execution-time tool DNS/redirect/private-range checks block unsafe requests.

### Browser verification checkpoint

- Start app stack, bind an AI agent to a real inbox, send an incoming message through a browser-testable channel (web widget or equivalent UI path), and verify one of:
  - one bot reply appears from the bound shadow bot, or
  - configured handoff occurs and the conversation leaves `pending`.
- Capture at least one `agent-browser` snapshot before send, after send, and after bot reply/handoff.

### Regression checks

- Existing webhook `AgentBotListener` / `AgentBots::WebhookJob` path remains unchanged for non-AI bots.
- Non-AI inbox and bot flows continue using their existing behavior when OSS AI routing is not applicable.
- Conversations that leave `pending` before the job runs do not receive stale AI replies.

### Risks and rollback notes

- **Risk:** double-scheduling from ambiguous routing or stale binding state. **Mitigation:** explicit `inbox.agent_bot&.ai_agent` routing, OSS binding-state checks, and OSS regression tests.
- **Risk:** duplicate or stale replies. **Mitigation:** per-conversation mutex + `triggering_message_id` uniqueness + latest-actionable-state recheck.
- **Risk:** unsafe HTTP tool execution. **Mitigation:** dedicated executor with execution-time revalidation and bounded timeouts.
- **Rollback:** remove the hook delegation point and disable AI feature flags; existing persisted agent data can remain inert.

### Stop conditions

- Stop if runtime begins using generic `active_bot?` as the sole routing signal.
- Stop if failures leave pending conversations stuck.
- Stop if tool execution cannot prove execution-time safety checks.

### Acceptance criteria

- [ ] Internal AI runtime is triggered only from the approved seam and only for explicitly AI-bound inboxes.
- [ ] One triggering message produces at most one actionable run.
- [ ] Failure paths hand off safely without breaking existing webhook or other non-AI flows.

---

## Phase 7: First-class AI Agents product area and core management UI

**Owner**: @implementer (frontend/navigation)
**Dependencies**: Phases 4, 6
**Complexity**: HIGH

### Scope

Deliver the first user-visible AI Agents workspace as a dedicated top-level left-sidebar area with its own route tree outside `/settings`. In v1 this workspace can remain admin-visible only, but it must be product-prominent and must own core agent list/create/edit flows.

### Exact likely file areas

- `app/javascript/dashboard/routes/dashboard/dashboard.routes.js`
- New route area under `app/javascript/dashboard/routes/dashboard/aiAgents/*`
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`
- New API clients under `app/javascript/dashboard/api/*ai*`
- New Vuex modules under `app/javascript/dashboard/store/modules/*ai*`
- Shared layout/helpers reused from settings shells where useful: `app/javascript/dashboard/routes/dashboard/settings/SettingsWrapper.vue`, `.../SettingsLayout.vue`, `.../components/BaseSettingsHeader.vue`
- i18n source: `app/javascript/dashboard/i18n/locale/en/**`
- Likely tests: Vue component/store tests for nav visibility, route gating, list/form behavior

### Data model / API / runtime / UI / test changes

- **Data model:** no new backend schema.
- **API:** consume Phase 4 agent CRUD endpoints first; show tool/binding summaries only if already available without expanding scope.
- **Runtime:** no new runtime logic, but UI must reflect enabled/capability state safely.
- **UI:** top-level `AI Agents` sidebar entry, dedicated route tree, AI agent list, create/edit form for prompt/system message + provider/model + enabled state, admin-only route/sidebar visibility, feature-flag gating, and clear separation from Captain/Settings.
- **Tests:** store actions, form validation, route gating, top-level sidebar visibility, admin-only visibility.

### Tasks

- Add a new AI Agents route tree under `dashboard.routes.js`, outside `settings.routes.js`, so the feature is modeled as a workspace rather than a settings leaf.
- Add a top-level `AI Agents` sidebar group in `Sidebar.vue`, using route meta/feature-flag patterns already enforced by the sidebar provider.
- Build AI Agents list and create/edit screens, reusing existing settings layout primitives for page composition without mounting the feature under `/settings`.
- Show agent status, model/provider summary, and inbox-count/readiness indicators that help the area feel like a real product surface.
- Hide all OSS AI routes and sidebar entries when installation/account flags are off or the current user is not an admin.

### Unit-test expectations

- Validate the top-level sidebar entry and route tree are hidden when flags are off.
- Validate non-admin users cannot reach AI Agents workspace routes.
- Validate create/edit forms enforce required prompt/provider/model fields.
- Validate direct URL access to AI Agents routes is blocked when route meta says it should be hidden.

### Browser verification checkpoint

- Verify admin can navigate to `AI Agents` from the main left sidebar.
- Verify create flow for a new AI agent with prompt/provider/model fields.
- Verify edit flow persists after refresh and remains reachable by direct URL.
- Verify the top-level `AI Agents` entry and routes disappear for a non-admin or when feature flags are disabled.
- Verify unrelated top-level navigation remains unchanged.

### Regression checks

- Existing Settings navigation and Agent Bots settings screen still work for non-AI webhook bots.
- Existing Contacts-style top-level navigation behavior remains unchanged for unrelated product areas.
- Existing non-AI sidebar groups and routes remain unchanged.

### Risks and rollback notes

- **Risk:** shipping a top-level nav item without enough substance behind it. **Mitigation:** keep Phase 7 focused on list/create/edit and readiness/status, not placeholder-only pages.
- **Risk:** UI accidentally coupling to unrelated existing AI-adjacent routes or settings patterns too tightly. **Mitigation:** keep separate routes/store/api namespaces and do not reuse Captain components.
- **Risk:** shadow bots leaking into legacy Agent Bots UX while AI Agents becomes more visible. **Mitigation:** keep system-managed bot hiding/read-only handling in AI-specific flows, not legacy Agent Bots pages.
- **Rollback:** remove route/sidebar/UI modules while leaving backend APIs hidden behind flags.

### Stop conditions

- Stop if AI Agents is still mounted only under `Settings` at the end of the phase.
- Stop if UI work starts depending on Enterprise/Captain routes/components.
- Stop if non-admin users can reach secret-bearing forms.
- Stop if browser verification reveals route/sidebar leakage when flags are off.

### Acceptance criteria

- [ ] Admin users can reach a dedicated top-level `AI Agents` workspace from the main sidebar.
- [ ] Agent list/create/edit flows are browser-verifiable from that workspace.
- [ ] Contacts and legacy Agent Bots UX remain intact and separate.

---

## Phase 8: Secondary admin surfaces for tools and inbox binding

**Owner**: @implementer (frontend/configuration)
**Dependencies**: Phases 3, 5, 7
**Complexity**: MEDIUM

### Scope

Add the remaining admin configuration surfaces needed to make AI Agents practical in v1: custom tool management and inbox bind/unbind flows. These can reuse settings-style UI patterns internally, but the canonical ownership of the feature stays with the `AI Agents` workspace rather than `Settings`.

### Exact likely file areas

- `app/javascript/dashboard/routes/dashboard/aiAgents/*`
- Possible nested tool/binding route areas under `app/javascript/dashboard/routes/dashboard/aiAgents/**`
- `app/javascript/dashboard/routes/dashboard/settings/inbox/Settings.vue`
- `app/javascript/dashboard/routes/dashboard/settings/inbox/components/BotConfiguration.vue` and/or new `AiAgentConfiguration.vue`
- New or extended API clients under `app/javascript/dashboard/api/*ai*`
- New or extended Vuex modules under `app/javascript/dashboard/store/modules/*ai*`
- i18n source: `app/javascript/dashboard/i18n/locale/en/**`
- Likely tests: Vue component/store tests for tool forms and inbox binding behavior

### Data model / API / runtime / UI / test changes

- **Data model:** no new backend schema.
- **API:** consume Phase 3 inbox-binding endpoints and Phase 5 tool endpoints.
- **Runtime:** no new runtime logic; surface current binding/tool capability state only.
- **UI:** custom tools list/create-edit flow, inbox bind/unbind flow, and optional inbox-settings shortcut/entry point that deep-links back to the AI Agents workspace when appropriate.
- **Tests:** tool form validation, safe-state rendering, inbox binding interactions, admin-only visibility.

### Tasks

- Add tools management as a secondary page or child route inside the `AI Agents` workspace.
- Add bind/unbind flow from the AI Agents area as the canonical entry point for assigning inboxes.
- Add an inbox-settings shortcut or embedded selector only if it reduces friction without demoting AI Agents back into a settings-owned surface.
- Keep all tool and binding flows hidden when feature flags are off or the user is not an admin.

### Unit-test expectations

- Validate custom tool forms enforce the safe HTTPS endpoint and required field expectations surfaced by the API.
- Validate inbox binding UI loads current state, saves, disconnects correctly, and reflects Captain exclusivity errors cleanly.
- Validate any inbox-settings shortcut routes or links still respect AI feature flags and admin-only access.

### Browser verification checkpoint

- Verify custom tool create/edit flow for a safe HTTPS endpoint.
- Verify inbox bind/unbind flow persists after refresh.
- Verify admins can move between AI Agents list/detail and tool/binding surfaces without falling back to a settings-only navigation model.
- Verify unrelated navigation remains unchanged while using tool and binding surfaces.

### Regression checks

- Existing Agent Bots settings screen still works for non-AI webhook bots.
- Inbox settings tabs unrelated to AI remain unchanged.
- Unrelated sidebar groups and routes remain unchanged.

### Risks and rollback notes

- **Risk:** reintroducing a settings-only mental model via inbox/tool shortcuts. **Mitigation:** keep `AI Agents` as the canonical entry point and use settings pages only as auxiliary shortcuts where needed.
- **Risk:** too much UI surface in a single frontend step. **Mitigation:** land tools and inbox binding after the core workspace/nav exists.
- **Rollback:** remove tool/binding UI modules and shortcuts while preserving the core AI Agents workspace.

### Stop conditions

- Stop if the only discoverable path to bind inboxes or manage tools becomes `Settings`.
- Stop if browser verification shows AI Agents surfacing as a settings-owned feature instead of a first-class workspace.
- Stop if non-admin users can reach secret-bearing forms.

### Acceptance criteria

- [ ] Tool management and inbox bind/unbind are browser-verifiable.
- [ ] `AI Agents` remains the primary, first-class entry point for these flows.
- [ ] Legacy Agent Bots settings UX remains intact.

---

## Invariants and unchanged behavior

| Invariant / unchanged behavior                                            | Why it matters                                                         | How to verify                                                                         |
| ------------------------------------------------------------------------- | ---------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| New conversations in bot-enabled inboxes still become `pending`           | Reuses existing bot lifecycle instead of inventing a new one           | Model/request tests around inbox binding; runtime/browser verification in bound inbox |
| `Conversation#bot_handoff!` remains the only OSS AI handoff primitive     | Prevents a parallel handoff state machine                              | Job/service tests and runtime browser checkpoint                                      |
| Existing webhook `AgentBot` delivery behavior does not change             | Self-hosted webhook bots must not regress                              | Webhook regression specs around existing listener/job path                            |
| AI runtime never schedules from generic `active_bot?` alone               | Avoids accidental scheduling for webhook bots or stale non-AI bindings | Router tests proving explicit `agent_bot.ai_agent` gating                             |
| OSS AI binding rejects conflicting responder state visible to OSS         | Prevents double responders from the OSS AI entry point                 | OSS binding/service tests proving conflicting assignments are rejected                |
| Missing/invalid provider secrets never leave a conversation stuck pending | Safety for malformed config                                            | Runtime failure-path tests + browser handoff checkpoint                               |
| Shadow `AgentBot` records remain after AI agent tombstone/delete          | Preserves historical sender identity                                   | Delete/tombstone tests and message rendering verification                             |
| AI settings and secret-bearing APIs remain admin-only in v1               | Prevents accidental secret exposure                                    | Policy/request tests + browser role-based route checks                                |

## Regression matrix

| Check                                               | Phase(s) that prove it | Method                                               | Proves                                                                        |
| --------------------------------------------------- | ---------------------- | ---------------------------------------------------- | ----------------------------------------------------------------------------- |
| Account settings merge behavior unchanged           | 1                      | Ruby unit/request tests                              | AI gating does not break unrelated account settings                           |
| Webhook bot regression                              | 6                      | Existing bot-bound inbox regression spec             | Non-AI `AgentBot` behavior is untouched                                       |
| Pending conversation regression                     | 3, 6                   | Model/request tests + runtime scenario               | Shadow bot reuse preserves pending semantics                                  |
| Explicit AI routing only                            | 6                      | Router/job specs                                     | Scheduling only occurs for `inbox.agent_bot.ai_agent`                         |
| Handoff path stability                              | 6                      | Job/service specs + browser runtime checkpoint       | AI hands off only through `bot_handoff!`                                      |
| Missing secret fail-open                            | 6                      | Job/spec scenario with no credentials                | Conversation does not remain stuck pending                                    |
| Disabled/tombstoned agent mid-flight                | 4, 6                   | Delete/disable + job re-read tests                   | No stale AI reply is posted                                                   |
| OSS binding exclusivity                             | 3                      | Request/service specs                                | OSS bind path rejects inboxes already reserved by conflicting responder state |
| Secret prohibition in installation/account settings | 1, 4, 5                | Request/model specs                                  | Secrets stay out of `InstallationConfig` and account settings                 |
| Custom tool SSRF create-time guards                 | 5                      | Model/service specs                                  | Unsafe endpoints are rejected before persistence                              |
| Custom tool execution-time guards                   | 6                      | Executor specs with DNS/private-range/redirect cases | Unsafe execution is blocked at runtime                                        |
| Admin-only AI Agents visibility                     | 4, 7, 8                | Policy/request tests + browser role checks           | Secret-bearing screens stay admin-only                                        |
| Legacy Agent Bots settings stability                | 7, 8                   | Browser/UI regression pass                           | Existing webhook-bot admin UI still works                                     |

## Browser verification matrix

| Checkpoint                                         | Earliest phase | Browser path                                                                | Expected evidence                                                              |
| -------------------------------------------------- | -------------- | --------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| No AI Agents nav visible while flags/UI are absent | 1              | Main sidebar + direct URL attempts                                          | No AI route/entry yet                                                          |
| Runtime reply/handoff from a bound inbox           | 6              | Real inbox/channel flow (web widget or equivalent browser-testable channel) | Snapshot before send, after send, after reply/handoff                          |
| AI Agents top-level workspace loads                | 7              | Main sidebar → AI Agents                                                    | Header, empty/list state, admin-only visibility                                |
| AI agent create/edit works                         | 7              | AI Agents create/edit form                                                  | Required-field validation, save success, reload persistence                    |
| Custom tool create/edit works                      | 8              | AI Agents → Tools                                                           | Safe HTTPS endpoint accepted; unsafe endpoint rejected via surfaced validation |
| Inbox bind/unbind works                            | 8              | AI Agents → selected agent → inbox binding (plus optional inbox shortcut)   | Selected agent persists after refresh; disconnect clears binding               |
| Feature flag hiding works                          | 7, 8           | Same routes with flags off                                                  | Sidebar/route hidden or blocked                                                |
| Unrelated navigation remains intact                | 7, 8           | Main sidebar and direct route access                                        | AI Agents does not disturb other product areas                                 |

## Risks summary and rollback posture

| Phase | Primary risk                                                          | Rollback posture                                                         |
| ----- | --------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| 1     | Polluting account settings with secret-bearing config                 | Revert settings schema/permit changes                                    |
| 2     | Changing `AgentBot` semantics for webhook bots                        | Revert associations/migrations before runtime depends on them            |
| 3     | Dual-binding conflict from conflicting responder state                | Remove AI-agent binding endpoint/service; preserve old bindings          |
| 4     | Secret leakage in API responses                                       | Disable routes behind flags and revert controller/view layer             |
| 5     | Unsafe custom tool persistence or scope drift                         | Remove tool routes/models while keeping agent CRUD intact                |
| 6     | Double replies, stuck pending conversations, unsafe tool execution    | Remove hook delegation and disable flags; data can remain inert          |
| 7     | Top-level nav drift back into settings-only placement or role leakage | Remove workspace routes/sidebar/modules while backend remains flag-gated |
| 8     | Tools/binding shortcuts reintroducing settings-only ownership         | Remove shortcut/tool modules while preserving the core workspace         |

## Definition of done for this slice

- [ ] OSS AI agents can be created, edited, enabled/disabled, and tombstoned by account admins.
- [ ] AI Agents appears as a first-class main left-sidebar area for admins, with a dedicated route tree outside `/settings`.
- [ ] Each AI agent has one system-managed shadow `AgentBot` reused for sender identity and inbox binding.
- [ ] Inbox binding uses existing `AgentBotInbox` semantics and keeps conversations `pending` until reply or handoff.
- [ ] Runtime uses only the approved post-message hook seam and only schedules for explicitly AI-bound inboxes.
- [ ] Minimal tool surface exists: built-in `handoff_to_human` plus account-level custom HTTP tools with persistence-time and execution-time safety.
- [ ] All secret-bearing paths use encrypted columns and never return decrypted secrets.
- [ ] Webhook bots and OSS AI paths have explicit non-regression coverage.
- [ ] UI-visible flows are browser-verified and admin-only.
- [ ] No KB, no multi-agent orchestration, and no DB-stored executable functions were introduced.

## Deferred cross-edition concerns

- Reciprocal enforcement in Captain/Enterprise binding paths is deferred because this workstream is OSS-only.
- Enterprise-specific regression coverage, including `spec/enterprise`, is deferred.
- If future product requirements demand bidirectional OSS↔Enterprise exclusivity, that should be planned as a separate cross-edition workstream with its own overlay review.

## Recommended first implementation phase to execute next

**Start with Phase 1: Feature gating and configuration contract.**

Why this is the best first slice:

- It creates the release-safety boundary before any runtime or UI behavior exists.
- It is the smallest independent change that can land without altering bot behavior.
- It resolves the account/install gating contract needed by every later backend and frontend phase.
- It provides an immediate regression baseline for “feature off means no behavior change.”

## Remaining low-risk open questions

- Which single provider should be the first supported adapter in v1, so Phase 6 stays concrete without over-abstracting?
