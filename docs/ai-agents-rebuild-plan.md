# AI Agents v1 — OSS-Only Implementation Plan

## Problem Statement

Build a lean OSS-only AI agent feature for Chatwoot that behaves like an assignable bot, not an auto-reply system. The v1 plan must reuse existing OSS assignment, inbox-bot, account settings/limits, and background-job patterns while explicitly excluding Enterprise/Captain behavior.

## Approach

Smallest viable OSS implementation: reuse `AgentBot` assignment and inbox binding as the delivery mechanism, add an AI-specific branching path for assigned conversations only, store account-level configuration in existing `settings` / `limits` JSONB patterns, and run LLM generation asynchronously through a retrying job.

## Success Criteria

- [ ] AI never replies unless the conversation is explicitly assigned to an AI-capable `AgentBot`
- [ ] OSS implementation does not rely on or modify Captain / Enterprise behavior
- [ ] Per-account AI model and conversation allowance are stored via existing account settings/limits patterns, not new `accounts` columns
- [ ] Simulator stays ephemeral, rate-limited, and excluded from usage limits
- [ ] Provider failures retry 3 times asynchronously, then hand off the conversation automatically

---

## Product Decisions Locked In

| Topic | Decision |
|---|---|
| AI count | **One AI agent per account in v1**; extendable later |
| Triggering | **Assignment-based only**; no auto-reply on inbound messages |
| Assignment UX | **Reuse the existing agent-bot assignment semantics/path wherever possible in v1**; do not invent a separate `Assign to AI` interaction if current `AgentBot` assignment can be reused cleanly |
| Configuration surface | **Separate AI configuration surface in the sidebar**, while conversation handoff still uses existing agent-bot-style assignment semantics |
| Provider | **OpenRouter** for v1 |
| Simulator | **Ephemeral**; no message persistence, no usage counting |
| Failure handling | **3 async retries, then auto handoff** |
| Model config | **Per-account via super admin**, not per pricing plan |
| Usage control | **Conversation-based allowance/limit exists** |
| Availability | **Inbox binding controls where the AI can be assigned** |
| Scope boundary | **OSS-only**; Enterprise/Captain explicitly out of scope |

---

## Current State (evidence)

- `Account` already has JSONB `settings` and `limits`, plus additive settings validation; this is the established extension pattern instead of adding new account columns (`app/models/account.rb:10-14`, `app/models/account.rb:34-92`).
- Super admin already persists account `limits` as hash data (`app/controllers/super_admin/accounts_controller.rb:36-40`).
- Inbox-to-bot binding already exists through `AgentBotInbox`, inbox routes, and `set_agent_bot` (`config/routes.rb:213-217`, `app/controllers/api/v1/accounts/inboxes_controller.rb:53-65`, `app/models/inbox.rb:71-74`).
- Conversation assignment already supports `AgentBot` assignees in API/service/UI paths (`app/controllers/api/v1/accounts/conversations/assignments_controller.rb:3-44`, `app/services/conversations/assignment_service.rb:8-41`, `app/javascript/dashboard/api/inbox/conversation.js:65-73`, `app/javascript/dashboard/routes/dashboard/conversation/ConversationAction.vue:82-116`).
- Current `AgentBotListener` only dispatches webhook-style bots and returns early unless `outgoing_url` is present; AI cannot assume the existing webhook path works unchanged (`app/listeners/agent_bot_listener.rb:18-25`, `app/listeners/agent_bot_listener.rb:61-70`).
- Inbox bot presence currently affects conversation status via `inbox.active_bot?`; v1 must ensure disabled AI does not make an inbox behave like an active bot (`app/models/inbox.rb:169-172`, `app/models/conversation.rb:254-265`).
- Existing LLM formatting already filters out activity/template messages and excludes private notes unless explicitly enabled; this is the right baseline for AI context selection (`app/services/llm_formatter/conversation_llm_formatter.rb:26-65`).
- `Message.chat` scope excludes `activity` type and `private: true` messages, but does **NOT** exclude `template` type messages (`app/models/message.rb:115-117`). The LLM formatter (`conversation_llm_formatter.rb:29-65`) excludes both `activity` and `template`. The AI context builder must use the stricter LLM formatter filtering, not `Message.chat` alone.
- Existing retry patterns use background jobs with `retry_on`, not synchronous `sleep` loops (`app/jobs/hook_job.rb:1-3`).
- Rack::Attack already uses account-scoped throttles for costly account endpoints; the simulator should follow this pattern (`config/initializers/rack_attack.rb:187-221`).
- Enterprise already extends inbox bot behavior for Captain, which is exactly why this v1 plan must declare a strict OSS-only boundary (`enterprise/app/models/enterprise/inbox.rb:10-16`).

---

## Verified Facts vs Assumptions

| Type | Item | Evidence / Notes |
|---|---|---|
| Verified fact | Account-level extensibility already uses JSONB `settings` / `limits` | `app/models/account.rb:10-14`, `app/models/account.rb:34-92` |
| Verified fact | Super admin can persist `limits` today | `app/controllers/super_admin/accounts_controller.rb:36-40` |
| Verified fact | Inbox bot binding already has OSS routes/controller flow | `config/routes.rb:213-217`, `app/controllers/api/v1/accounts/inboxes_controller.rb:53-65` |
| Verified fact | Conversation assignment already supports `AgentBot` assignees | `app/controllers/api/v1/accounts/conversations/assignments_controller.rb:3-44`, `app/services/conversations/assignment_service.rb:8-41` |
| Verified fact | Existing listener path is webhook-specific and cannot be reused blindly for AI | `app/listeners/agent_bot_listener.rb:61-70` |
| Verified fact | `AgentBotListener#agent_bots_for` collects both `conversation.assignee_agent_bot` AND inbox-level `active_inbox_agent_bot`; v1 AI dispatch must use assignment path only | `app/listeners/agent_bot_listener.rb:47-53` |
| Verified fact | `AgentBot.bot_type` enum currently has only `webhook: 0`; v1 must add `ai: 1` for explicit runtime discrimination | `app/models/agent_bot.rb:37` |
| Verified fact | `Message.chat` does NOT exclude `template` type messages; LLM formatter does; AI context must use the stricter filter | `app/models/message.rb:115-117`, `app/services/llm_formatter/conversation_llm_formatter.rb:29-65` |
| Verified fact | Existing formatter already gives a bounded/filterable message-construction pattern | `app/services/llm_formatter/conversation_llm_formatter.rb:29-65` |
| Verified fact | Existing inbox active-bot behavior can affect new-conversation status | `app/models/inbox.rb:169-172`, `app/models/conversation.rb:259-265` |
| Verified fact | Existing production throttling pattern is account-scoped Rack::Attack | `config/initializers/rack_attack.rb:187-221` |
| Assumption | A dedicated OSS AI settings namespace on `account.settings` and allowance namespace on `account.limits` will fit current validation without requiring new account columns | Consistent with current additive JSONB usage; implementation still must confirm exact key names |
| Assumption | The cleanest v1 runtime is `AgentBot` + AI-specific listener branch/job rather than a brand-new bot transport system | Supported by existing assignment/inbox plumbing, but exact class split remains an implementation choice |
| Locked product decision | AI availability is configured in a separate sidebar surface, but conversation handoff reuses the existing `AgentBot` assignment semantics/path in v1 wherever possible | Keeps admin setup distinct while avoiding a second assignment interaction for v1 |

---

## Scope Boundary

### In scope

- OSS-only AI agent v1
- Assignment-based AI responses only
- OpenRouter provider integration
- Account-level settings/limits storage via existing JSONB patterns
- Inbox binding workflow for AI availability
- Conversation assignment UX path for assigning an AI bot
- Ephemeral simulator endpoint with rate/cost guard

### Explicitly out of scope

- Enterprise / Captain implementation, overlays, parity work, or Captain feature reuse
- Auto-reply on all inbound messages
- Per-plan billing logic
- Multi-agent orchestration
- Tool calling / knowledge base / analytics dashboards / prompt libraries

### Deferred scope (very short)

- Multiple AI agents per account
- Rich analytics beyond basic usage tracking
- Advanced simulator token/cost breakdown

---

## v1 Design Decisions

1. **OSS-only / non-Captain boundary**
   - This feature is a standalone OSS capability.
   - Do not depend on Captain associations, Captain usage logic, or Enterprise inbox behavior.
   - Preserve current Enterprise seams by keeping OSS changes isolated and generic.

2. **Assignment-based behavior only**
   - AI should respond only when `conversation.assignee_agent_bot` is explicitly set to the AI bot.
   - Specifically, v1 AI dispatch must check `conversation.assignee_agent_bot` **only** — it must **NOT** use the `active_inbox_agent_bot` path from `AgentBotListener#agent_bots_for`. This is critical because `agent_bots_for` collects both conversation-assigned and inbox-level bots, and responding to inbox-level bots would violate the "no auto-reply" invariant.
   - Inbox binding controls **availability for assignment** (which inboxes can assign to this AI), not autonomous reply behavior.
   - Add `ai: 1` to the `AgentBot.bot_type` enum to explicitly identify AI bots at runtime, rather than relying on implicit `outgoing_url.blank?` checks.

3. **Config storage**
   - Store per-account model/provider settings in `account.settings`.
   - Store conversation allowance/usage metadata in `account.limits`, consistent with existing limits patterns. Per-conversation first-response tracking must use an atomic mechanism (e.g., `AiAgentConversation` unique index on `[ai_agent_id, conversation_id]`, or a `first_ai_response_at` timestamp on the conversation record) — **not** in Enterprise `custom_attributes`, which is out of scope.

4. **Listener/runtime path**
   - Do **not** assume `AgentBotListener` webhook dispatch works as-is.
   - v1 must either:
     - add an AI-specific branch inside `AgentBotListener`, or
     - route AI work into a separate listener/service path invoked from the same event entry point.
   - Either option must preserve current webhook bot behavior unchanged.

5. **Disabled behavior**
   - Disabled AI must not make an inbox behave like an active bot.
   - Inbox availability checks must distinguish an enabled AI binding from a disabled one so new conversations do not stay `pending` incorrectly.

6. **Context building**
   - Preserve product intent of using conversation context, but use a **bounded eligible-context strategy**.
   - Baseline for eligible context in v1:
     - recent conversation messages only,
     - exclude `activity` and `template` messages,
     - exclude private notes by default,
     - cap by configured max eligible messages and/or formatter token budget.

7. **Failure handling**
   - Use a background job for generation.
   - Retry 3 times asynchronously using job retry semantics.
   - After final failure, auto hand off the conversation to humans.

8. **Conversation-limit correctness**
   - Count usage at the first successful AI response for a conversation.
   - The plan must include an atomic/locked write path to prevent double-counting or overrun when concurrent jobs race on the same conversation.

9. **Inbox availability + assignment UX**
    - Inbox binding determines whether the AI bot is available for assignment in that inbox.
    - Separate from that, conversation UI must let an agent explicitly hand a conversation to AI through the existing `AgentBot` assignment semantics/path wherever possible.
    - Do not invent a separate v1 `Assign to AI` interaction if the current assignment flow can be reused cleanly.
    - The AI remains a distinct configuration surface in the sidebar; only the conversation-level handoff semantics are shared with agent bots.

10. **Simulator guardrails**
    - Simulator remains non-persistent and excluded from conversation allowance.
    - Add endpoint throttling / guardrails so it cannot become an unbounded cost sink.

---

## Implementation Plan

## Phase 1: Lock the OSS data contract
**Owner**: @implementer (backend)
**Dependencies**: None
**Complexity**: MEDIUM

### Tasks
- [ ] Define the v1 OSS-only configuration contract using `account.settings` and `account.limits` rather than new account columns.
- [ ] Document exact key namespaces for provider/model/enabled state and conversation allowance/usage metadata.
- [ ] Document the minimal AI agent record shape needed to link to an `AgentBot` without introducing v1-only overengineering.
- [ ] Verify super admin update flow can persist the chosen settings/limits shape.

### Likely files / areas
- `app/models/account.rb`
- `app/controllers/super_admin/accounts_controller.rb`
- `app/controllers/api/v1/accounts_controller.rb`

### Acceptance Criteria
- [ ] No new `accounts` columns are required in the plan
- [ ] Per-account model config is clearly described as super-admin-managed settings data
- [ ] Conversation allowance storage is clearly described without plan-level billing logic

---

## Phase 2: Define runtime entry path and disabled-state safety
**Owner**: @implementer (backend)
**Dependencies**: Phase 1
**Complexity**: HIGH

### Tasks
- [ ] Define the AI runtime entry as either `AgentBotListener` branching or a separate AI dispatch path from the same event boundary.
- [ ] Preserve existing webhook bot flow unchanged.
- [ ] Specify that only explicitly assigned AI bot conversations are eligible for AI response.
- [ ] Define how disabled AI binding is excluded from `active_bot?` behavior so disabled AI does not leave conversations `pending` or otherwise behave like an active bot.
- [ ] Define background-job execution and retry/handoff behavior; remove any synchronous retry/sleep wording.
- [ ] Define concurrency protection for first-response conversation counting.

### Likely files / areas
- `app/listeners/agent_bot_listener.rb`
- `app/models/inbox.rb`
- `app/models/conversation.rb`
- `app/jobs/agent_bots/webhook_job.rb` or new AI job area

### Acceptance Criteria
- [ ] The plan no longer assumes webhook-only listener behavior is sufficient
- [ ] The disabled-state behavior is explicitly safe for inbox and conversation status flows
- [ ] Retry strategy is asynchronous and ends in auto handoff after 3 failures
- [ ] Race-condition handling for conversation allowance is called out explicitly

---

## Phase 3: Define inbox binding and conversation assignment workflows
**Owner**: @implementer (backend + frontend)
**Dependencies**: Phase 2
**Complexity**: MEDIUM

### Tasks
- [ ] Reuse or minimally extend existing inbox bot binding workflow so AI availability is tied to inboxes.
- [ ] Reuse existing `AgentBot` assignment semantics/path for conversation handoff in v1 wherever possible; avoid a separate `Assign to AI` interaction.
- [ ] Keep AI as a separate sidebar configuration surface while sharing the existing conversation assignment path.
- [ ] If any UI/API extension is required, keep it minimal and compatible with the current assignments controller/service flow.

### Likely files / areas
- `config/routes.rb`
- `app/controllers/api/v1/accounts/inboxes_controller.rb`
- `app/controllers/api/v1/accounts/conversations/assignments_controller.rb`
- `app/services/conversations/assignment_service.rb`
- `app/javascript/dashboard/api/inbox/conversation.js`
- `app/javascript/dashboard/routes/dashboard/conversation/ConversationAction.vue`

### Acceptance Criteria
- [ ] The plan clearly separates inbox availability from explicit conversation assignment
- [ ] The plan names the OSS API/workflow used to bind AI availability to inboxes
- [ ] The plan locks the conversation handoff to the existing `AgentBot` assignment UX/API path in v1 wherever possible
- [ ] The plan removes ambiguity about a separate v1 `Assign to AI` flow

---

## Phase 4: Define context building and simulator boundaries
**Owner**: @implementer (backend + frontend)
**Dependencies**: Phase 3
**Complexity**: MEDIUM

### Tasks
- [ ] Replace “full conversation history” wording with a bounded eligible-context strategy.
- [ ] Explicitly exclude private notes and activity/template messages from default AI context.
- [ ] Keep simulator ephemeral, non-persistent, and outside usage counting.
- [ ] Add a simulator endpoint guard strategy (account/user throttle and basic payload bounds).
- [ ] Keep simulator scope to prompt/result validation only; no speculative cost analytics in v1.

### Likely files / areas
- `app/services/llm_formatter/conversation_llm_formatter.rb`
- `app/models/message.rb`
- `config/initializers/rack_attack.rb`
- future AI simulate controller / dashboard AI page area

### Acceptance Criteria
- [ ] Default context excludes private/activity/template content
- [ ] Context is explicitly bounded in the plan
- [ ] Simulator is explicitly ephemeral and guarded against abuse

---

## Deliverables

| Phase | Deliverable |
|---|---|
| Phase 1 | OSS account settings/limits contract for AI config + allowance |
| Phase 2 | Safe runtime path, disabled-state behavior, async retry/handoff, race-condition note |
| Phase 3 | Inbox binding workflow + explicit conversation assignment workflow |
| Phase 4 | Bounded context strategy + ephemeral simulator guardrails |

---

## Blast Radius / Affected Entry Points

- `app/models/account.rb` — account settings/limits contract
- `app/controllers/super_admin/accounts_controller.rb` — super-admin persistence path for per-account model/limit config
- `app/models/agent_bot.rb` — `bot_type` enum must gain `ai: 1` value for runtime discrimination
- `app/listeners/agent_bot_listener.rb` — main event entry point that currently assumes webhook bots; `agent_bots_for` collects inbox-level bots that v1 AI dispatch must ignore
- `app/models/inbox.rb` — inbox active-bot behavior affects pending-state creation logic
- `app/models/conversation.rb` — conversation status and `assignee_agent_bot` behavior
- `app/controllers/api/v1/accounts/inboxes_controller.rb` — inbox-to-bot binding workflow
- `app/controllers/api/v1/accounts/conversations/assignments_controller.rb` — explicit conversation assignment API
- `app/services/conversations/assignment_service.rb` — assignment semantics for `AgentBot`
- `app/services/llm_formatter/conversation_llm_formatter.rb` — context eligibility and bounding (excludes activity AND template; `Message.chat` alone is insufficient)
- `config/initializers/rack_attack.rb` — simulator rate limiting/cost control
- `app/javascript/dashboard/...` assignment surfaces — explicit UI path for handing a conversation to AI

---

## Allowed Scope / Forbidden Scope

- Allowed: OSS `AgentBot` reuse, AI-specific dispatch branching, account `settings` / `limits`, inbox binding, assignment UX, bounded context, simulator throttling
- Forbidden: Captain-specific paths, Enterprise overlays, full auto-reply workflows, new pricing-plan system, advanced analytics, speculative multi-agent abstractions

---

## Invariants

| Invariant | Why it matters | How to verify |
|---|---|---|
| Existing webhook agent bots keep working | AI v1 must not regress current OSS bot delivery | Preserve separate webhook behavior in listener/runtime plan |
| Human assignment flow remains valid | AI is additive, not a replacement for normal assignment | Existing `User` assignment path remains unchanged |
| Disabled AI behaves like no active AI bot | Prevents pending-state and routing regressions | Check inbox active-bot decision path in final implementation |
| AI does not answer unless explicitly assigned | This is the primary product rule | Validate runtime trigger condition against `assignee_agent_bot` |
| AI handoff uses agent-bot-style assignment semantics in v1 | Avoids introducing a second assignment model or UI path | Trace final conversation handoff through existing assignments controller/service path |
| Simulator never mutates production conversation state | Prevents hidden cost/state side effects | Simulator remains non-persistent and excluded from counters |

---

## Behavior That Must Not Change

- Existing webhook-only `AgentBot` dispatch must remain unchanged for non-AI bots.
- Assigning a human user to a conversation must continue clearing `assignee_agent_bot` exactly as current assignment service does.
- Conversations without an explicitly assigned AI bot must continue behaving as normal human/inbox conversations.
- v1 conversation handoff must not introduce a parallel `Assign to AI` interaction when existing `AgentBot` assignment semantics can be reused.
- Private notes and activity/template messages must not start leaking into AI prompts by default.
- Enterprise/Captain behavior must not be required for OSS AI v1 to function.

---

## Validation Matrix

| Check | Command / Method | Proves |
|---|---|---|
| OSS-only boundary review | Confirm planned file list contains OSS paths only and no required `enterprise/` implementation path | v1 stays out of Captain/Enterprise scope |
| Account storage review | Inspect final implementation against `app/models/account.rb` + super admin controller patterns | Settings/limits pattern reused; no Enterprise `custom_attributes` |
| Assignment-only dispatch | Verify AI dispatch checks `conversation.assignee_agent_bot` only, NOT `active_inbox_agent_bot` from `agent_bots_for` | AI never auto-replies based on inbox binding alone |
| Bot type discrimination | Verify `AgentBot.bot_type` gains `ai: 1` enum value and runtime dispatch uses it | AI bots are explicitly identified, not relying on `outgoing_url.blank?` |
| Shared assignment semantics | Confirm the final handoff UX reuses current `AgentBot` assignment semantics/path rather than a separate v1 AI-only interaction | Conversation assignment UX ambiguity is removed |
| Disabled inbox behavior | Trace inbox `active_bot?` and conversation status behavior for disabled AI binding | Disabled AI does not behave as an active bot |
| Listener/runtime split | Review final runtime entrypoint against `app/listeners/agent_bot_listener.rb` | Webhook behavior preserved while AI gets a valid path |
| Context eligibility | Review AI context builder against `ConversationLlmFormatter` filtering (excludes activity AND template); verify `Message.chat` is NOT used as sole filter | Private/activity/template messages are filtered by default |
| Failure handling | Review job design against existing `retry_on` patterns | No synchronous `sleep` retry strategy remains |
| Usage-race protection | Review first-response counting design for idempotent or locked creation path (e.g., unique index on `[ai_agent_id, conversation_id]`) | Conversation allowance is not double-counted under concurrency |
| Simulator abuse guard | Review route/controller/throttle plan against Rack::Attack patterns | Simulator has rate/cost guardrails |

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Reusing webhook listener assumptions breaks AI dispatch | HIGH | HIGH | Explicitly require listener branching or separate AI dispatch path |
| AI dispatch responds to inbox-level bots instead of assigned-only | HIGH | HIGH | v1 AI dispatch must check `conversation.assignee_agent_bot` only, not `active_inbox_agent_bot` from `agent_bots_for` |
| Implicit `outgoing_url.blank?` as AI bot discriminator | MEDIUM | MEDIUM | Add `ai: 1` to `AgentBot.bot_type` enum for explicit runtime discrimination |
| Disabled AI still marks inbox as bot-active | MEDIUM | HIGH | Make disabled-state handling a first-class design item, not a footnote |
| Conversation allowance double-counts under concurrent replies | MEDIUM | HIGH | Require atomic/idempotent first-response accounting |
| `Message.chat` used as sole AI context filter (misses template type) | MEDIUM | MEDIUM | AI context builder must use `ConversationLlmFormatter`-style filtering that excludes both activity AND template |
| Unbounded history creates cost/performance problems | HIGH | MEDIUM | Bound eligible context by message count / formatter budget |
| Simulator becomes a cost sink | MEDIUM | MEDIUM | Add throttle + payload bounds and keep it non-persistent |
| Scope drift into Captain/Enterprise parity | MEDIUM | HIGH | Keep OSS-only boundary explicit in plan and file list |

---

## Remaining Open Questions

None that require user input to proceed with this v1 plan revision.

Implementation-time choice still left to engineers:
- whether AI dispatch lives as a branch inside `AgentBotListener` or as a small separate dispatch path invoked from the same event boundary.

---

## Decision Log

| Decision | Chosen | Rejected | Rationale | Evidence |
|---|---|---|---|---|
| Product trigger | Explicit assignment only | Auto-reply | Matches user decision and existing `AgentBot` assignee flow | `app/controllers/api/v1/accounts/conversations/assignments_controller.rb:3-44` |
| Conversation handoff UX | Reuse existing agent-bot assignment path in v1 wherever possible | Separate v1 `Assign to AI` interaction | Keeps AI setup distinct in the sidebar without creating a second assignment model | `app/controllers/api/v1/accounts/conversations/assignments_controller.rb:3-44`, `app/services/conversations/assignment_service.rb:8-41`, `app/javascript/dashboard/routes/dashboard/conversation/ConversationAction.vue:82-116` |
| Account config storage | `settings` / `limits` JSONB | New `accounts` columns | Matches existing OSS account extension pattern | `app/models/account.rb:10-14`, `app/controllers/super_admin/accounts_controller.rb:36-40` |
| AI runtime delivery | Async job with retries | Inline sync retry/sleep | Matches existing job patterns and avoids blocking request/listener flow | `app/jobs/hook_job.rb:1-3` |
| Context policy | Bounded eligible conversation context | Unbounded full history | Lower risk/cost; already aligned with formatter patterns | `app/services/llm_formatter/conversation_llm_formatter.rb:29-65` |
| Scope boundary | OSS-only | Enterprise/Captain parity in v1 | User explicitly excluded Captain/Enterprise | `enterprise/app/models/enterprise/inbox.rb:10-16` |
