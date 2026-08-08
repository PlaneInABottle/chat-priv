# AiAgents: Pending-Status Gate — Implementation Plan

**Status**: ACTIVE (supersedes `docs/ai-agent-human-takeover-plan.md`, which is kept as an obsolete design record — see that file's header note).

**Date**: 2026-08-08

## Problem Statement

The OSS AiAgents stack keeps replying to customer messages until the AI-initiated handoff flag (`ai_handoff_completed`) is set. There is no product-level gate tying AI replies to a conversation state. The user's final, binding decision replaces the previously planned assignee-based gate with a **pending-status gate**:

1. The AI replies **only** while `conversation.status == pending` ("Beklemede"). No assignee-based stop.
2. The human agent's **first reply moves the conversation pending → open automatically**; after that, incoming customer messages must NOT get AI replies.
3. Assignment alone (human or bot as assignee) has **no effect** on the gate (verified: `Conversations::AssignmentService` never changes status).
4. Handoff stays terminal (`human_handoff` tool → `ai_handoff_completed` + `bot_handoff!`); **NEW**: during handoff, try one best-effort human assignment; if nobody becomes assignable, the bot stays stopped and exactly one private note is added.
5. Reopening of resolved conversations is **DEFERRED** (see Follow-Up Decisions); under this plan, a resolved conversation reopened by a customer message will become `pending!` again (existing behavior, `message.rb:460-470`) and the AI WILL resume — unless/until a later decision changes reopen mechanics.
6. Deployment is **unconditional** (no env flag) — the silent-bot state is a live trust bug and the change is migration-free and reversible (code-only). A single documented escape hatch lives inside the gate module.

## Success Criteria

- [ ] New conversations in an AI inbox start `pending` and receive AI replies (unchanged happy path).
- [ ] AI replies stop the moment the conversation leaves `pending` (open/resolved/snoozed) — at both schedule time and execution time.
- [ ] A human's first reply in an AI conversation flips pending → open automatically and permanently silences the AI for that conversation.
- [ ] Assigning a human while the conversation stays pending does NOT stop the AI.
- [ ] `human_handoff` retains today's terminal semantics + idempotency; best-effort assignment is attempted once; zero or one "not assigned" private note per conversation.
- [ ] Webhook bots (incl. human-assigned conversations) are untouched.
- [ ] All listed specs pass; RuboCop clean on changed files; EE behavior intact (no method-name collisions).

## Verified Facts vs Assumptions

| # | Item | Evidence | Fact / Assumption |
|---|------|----------|-------------------|
| 1 | New AI-inbox conversations start `pending` | `determine_conversation_status` `conversation.rb:276-283` (`self.status = :pending if inbox.active_bot?`); `inbox.rb:175-178` (`active_bot?` = `agent_bot_inbox&.active? || dialogflow hooks`) | FACT |
| 2 | Status enum values | `conversation.rb:81` (`open:0, resolved:1, pending:2, snoozed:3`) | FACT |
| 3 | Assignment never changes status | `app/services/conversations/assignment_service.rb:16-30` (`assign_agent`/`assign_agent_bot` save assignee fields only) | FACT |
| 4 | Human reply does not flip status in OSS today | `message.rb:448-458` (`mark_pending_conversation_as_open_for_human_response` gated by stub `captain_pending_conversation?` → false) | FACT |
| 5 | EE-only real implementation of the stub | `enterprise/app/models/enterprise/message.rb:18-44` (`Enterprise::Message` full method override, no `super`, gated by `CaptainInbox.exists?`); wired at `app/models/message.rb:495` (`Message.prepend_mod_with('Message')`) | FACT |
| 6 | Handoff tool flow + idempotency | `app/services/ai_agents/tools/human_handoff_service.rb:63-75` (`execute_live_handoff!` guard `handoff_already_completed`; `mark_handoff_completed!` `:106-117`; `handoff_completed?` `:123-125`; `test_mode?` early return `:35`) | FACT |
| 7 | Handoff is a terminal tool, once | `orchestrator.rb:52` `MAX_HUMAN_HANDOFF_CALLS = 1`; `orchestrator.rb:731-767` `safety_handoff_result` routes through the same `HumanHandoffService` (fail-open) | FACT |
| 8 | Usage limiter sets the handoff flag directly (do not touch) | `app/services/ai_agents/usage/limiter.rb:74-81` `exhausted_handoff!`, `:150-160` (`'ai_handoff_completed' => true`, `handoff_completed?` `:162-163`) | FACT |
| 9 | LiveProcessor gate order + AI resolution | `live_processor.rb:12-15` (perform gate chain), `HANDOFF_COMPLETED_KEY` `:2`, `handoff_completed?` `:58-61`, `ai_agent` resolution `:42-44` (`assignee_agent_bot&.ai_agent || inbox.agent_bot&.ai_agent`) | FACT |
| 10 | Listener schedule path | `agent_bot_listener.rb:79-92` (`process_ai_bot_event` → `ResponseBuffer.schedule!`), `agent_bots_for` `:65-77`, webhook path `:108-114` (`process_webhook_bot_event`, unchanged) | FACT |
| 11 | `AgentBot#ai?` exists | `agent_bot.rb:46` (`enum bot_type: { webhook: 0, ai: 1 }` → predicate) | FACT |
| 12 | `Inbox#available_agents` exists | `app/models/concerns/inbox_agent_availability.rb:4-12`, included by Inbox | FACT |
| 13 | `AutoAssignment::AgentAssignmentService` API | `pattr_initialize [:conversation!, :allowed_agent_ids!]`, `perform` round-robin over online agents (`app/services/auto_assignment/agent_assignment_service.rb:5-14,18-29`) | FACT |
| 14 | i18n `ai_agents:` block exists (en + tr) | `config/locales/en.yml:34`, `config/locales/tr.yml:21` | FACT |
| 15 | Overlay check: no EE overlays on any touched AiAgents class | grep on `enterprise/` — only `Enterprise::Message` and unrelated modules found | FACT (re-verify during Phase 3 per repo rule) |
| 16 | Reopen mechanics | `message.rb:439-446` (`reopen_conversation`), `:460-470` (`reopen_resolved_conversation` → `pending!` when `inbox.active_bot?`) | FACT — deferred decision below |
| 17 | Webhook path parity (incl. human-assigned) | `agent_bot_listener_spec.rb:31-70` webhook cases reference `conversation` with `assignee: user` (`:10`) | FACT |

**Zero unresolved CRITICAL/HIGH items.** The only open product question (reopen semantics) is a deferred decision, not a blocker.

## Implementation Status (2026-08-08, live updates)

| Phase | Status | Notes |
|---|---|---|
| 1 (ReplyPolicy) | DONE | `app/services/ai_agents/reply_policy.rb` + spec; green |
| 3 (LiveProcessor gate) | DONE | `reply_gate_allows?` replaces local `handoff_completed?`; spec green |
| 4 (Listener gate) | DONE | `process_ai_bot_event` gated; unused `ai_handoff_completed?` removed; spec green |
| 5 (Message model) | DONE — **OSS only** | User decision (2026-08-08): do NOT touch Enterprise/Captain. `5.2 EE alignment` and the `spec/enterprise` additions were REVERTED to HEAD. `pending_ai_agent_conversation?` is OSS-only; verified `rg` shows zero `enterprise/` matches. Accepted consequence: in an EE-enabled build (DISABLE_ENTERPRISE=false) the EE full override (no super) would shadow the OSS auto-open — deployment sets `DISABLE_ENTERPRISE=true` (`.env:75`, `.env.server.local:9` → `ChatwootApp.extensions == %w[]` `lib/chatwoot_app.rb:46-54`), so the OSS path is the only active one. Plan sections mentioning EE alignment (5.2, EE spec rows) are obsolete; do not implement. |
| 6 (Handoff assignment) | DONE | best-effort assignment via AutoAssignment::AgentAssignmentService (allowed_agent_ids = available_agents.map(&:user_id)); one 'not assigned' private note; rescue StandardError + warn; i18n key ai_agents.handoff_not_assigned_note in en+tr; 13 handoff specs green |
| 7 (Docs) | DONE | catalog-runtime.md LiveProcessor row updated; rebuild-plan pointer added; superseded marker confirmed on human-takeover plan |
| 8 (Deferred) | documented | — |

---

## Phase 1: Add `AiAgents::ReplyPolicy` — the single gate authority

**Owner**: @implementer (backend)
**Dependencies**: None
**Complexity**: LOW

### Tasks

- **1.1** Create `app/services/ai_agents/reply_policy.rb`:

```ruby
class AiAgents::ReplyPolicy
  # Escape hatch (single documented override point): flip to false via a future ENV
  # check ONLY if an emergency stop is ever required; do not add flag checks elsewhere.
  HANDOFF_COMPLETED_KEY = 'ai_handoff_completed'

  class << self
    def can_reply?(conversation)
      conversation.pending? && !handoff_completed?(conversation)
    end

    def handoff_completed?(conversation)
      attrs = conversation.additional_attributes
      attrs.is_a?(Hash) && attrs[HANDOFF_COMPLETED_KEY] == true
    end
  end
end
  ```

- **1.2** Write `spec/services/ai_agents/reply_policy_spec.rb`: `pending + no flag → true`; `open/resolved/snoozed + no flag → false`; `pending + flag → false`; non-Hash `additional_attributes` → false.

### Acceptance

- [ ] New spec green: `bundle exec rspec spec/services/ai_agents/reply_policy_spec.rb`
- [ ] No code changes to any other file.

---

## 3: LiveProcessor execution-time gate

**Owner**: @implementer (backend)
**Dependencies**: Phase 1
**Complexity**: LOW

**Avoided**: touching `ResponseBuffer`/`AiResponseJob` — status is re-validated at execution inside `perform`, which covers the schedule→execute race without new locks (race is accepted and documented in Risks; a flip after the check is bounded to one buffered reply, matching today's behavior for handoff).

### 3.1 Changes in `app/services/ai_agents/live_processor.rb`

- Replace `return if handoff_completed?` (`:14`) with the gate call:

  ```ruby
  return unless eligible_message?
  return unless AiAgents::ReplyPolicy.can_reply?(conversation)
  return false if response_already_persisted?
  ```

- Remove the now-unused private `handoff_completed?` (`:58-61`) and the `HANDOFF_COMPLETED_KEY` constant (`:2`) from this file (dead code removal per AGENTS.md; auth stays via ReplyPolicy).
- Add an explicit log line when the gate rejects:

  ```ruby
  unless AiAgents::ReplyPolicy.can_reply?(conversation)
    Rails.logger.info("[AiAgents] Reply skipped: conversation=#{conversation.id} status=#{conversation.status} handoff=#{AiAgents::ReplyPolicy.handoff_completed?(conversation)}")
    return
  end
  ```

  (Keeps behavior identical; slight perf cost of two `can_reply?` calls is fine per MVP guidance. Implementer discretion: inline the log without a second `handoff_completed?` call is acceptable if desired.)

### 3.2 Tests (edit in place)

- In `spec/services/ai_agents/live_processor_spec.rb` (existing `let`s for ai_agent/inbox support `stub_available_agents`):
  - Reuse existing negative-case contexts (no ai_agent / disabled / account disabled) — must stay green.
  - New case: conversation still `open` (after `bot_handoff!`) → `perform` returns nil, `Messages::MessageBuilder` never called.

### Acceptance

- [ ] New contexts green; entire file green: `bundle exec rspec spec/services/ai_agents/live_processor_spec.rb`
- [ ] No other callers of `handoff_completed?` left in `live_processor.rb`.

---

## 4: Schedule-time gate in AgentBotListener

**Owner**: @implementer (backend)
**Dependencies**: Phase 1
**Complexity**: LOW

### 4.1 Changes in `app/listeners/agent_bot_listener.rb`

- **Do NOT touch** `process_webhook_bot_event` (`:108-114`) nor `agent_bots_for` (`:65-77`) — webhook bots (incl. human-assigned conversations) keep existing delivery. This is a parity invariant.
- In `process_ai_bot_event` replace lines 87-88:

```ruby
def process_ai_bot_event(agent_bot, message)
  return unless eligible_ai_message?(message)
  return unless AiAgents::ReplyPolicy.can_reply?(message.conversation)
  return unless agent_bot.ai_agent&.enabled?

  AiAgents::ResponseBuffer.schedule!(message)
end
```

- Remove the now-unused private `ai_handoff_completed?` (`:103-106`). Verify no other references (only `:88` uses it today).

### 4.2 Tests

- New RSpec file `spec/listeners/agent_bot_listener_spec.rb` — existing webhook cases (`:31-69` webhook delivery incl. assignee bot; AI-bot cases with `outgoing_url` present) must stay green.
- New `describe '#message_created (AI bot)'` context:
  - AI bot + conversation `pending` → `AgentBots::AiResponseJob` scheduled.
  - AI bot + conversation `open` → no scheduling.
  - AI bot + pending + `ai_handoff_completed: true` → no scheduling.
  - Human-assigned conversation (`assignee: user`, pending) + AI inbox bot → **still scheduled** (decision 3).
  - Webhook bot + conversation open with human assignee → `AgentBots::WebhookJob` still delivered exactly once (parity).

### Acceptance 2

- [ ] Listener spec green: `bundle exec rspec spec/listeners/agent_bot_listener_spec.rb`
- [ ] Existing 355-line spec untouched aside from the new context ("diff-friendly").

---

## 5: Human-reply → open (OSS Message model)

**Owner**: @implementer (backend)
**Dependencies**: Phase 1 (for naming consistency)
**Complexity**: MEDIUM

**EE collision check performed**: `config/initializers/01_inject_enterprise_edition_module.rb` prepends `Enterprise::Message` onto `Message` (`app/models/message.rb:495`). EE's `mark_pending_conversation_as_open_for_human_response` is a **full override without `super`**. New predicate `pending_ai_agent_conversation?` (no EE counterpart — verified via grep) → no name clash. EE's `captain_pending_conversation?` is preserved untouched.

### 5.1 Changes in `app/models/message.rb` (OSS)

```ruby
def mark_pending_conversation_as_open_for_human_response
  return unless captain_pending_conversation? || pending_ai_agent_conversation?
  return unless human_response?
  return if parameters
end
```

**Important**: verify `human_response?` + `private?` guards are placed BEFORE `captain_pending_conversation?`/`pending_ai_agent_conversation?` to keep semantic parity with the EE override, e.g.:

```ruby
def mark_pending_conversation_as_open_for_human_response
  return unless human_response?    # existing order
  return if private?
  return unless captain_pending_conversation? || pending_ai_agent_conversation?
  conversation.open!
end
```

Add the new predicate (mirror LiveProcessor resolution, `live_processor.rb:43`):

```ruby
def pending_ai_agent_conversation?
  return false unless conversation.pending?
  agent_bot = conversation.assignee_agent_bot || conversation.inbox.agent_bot
  agent_bot&.ai? && agent_bot.ai_agent&.enabled?
end
```

**Where is `mark_pending_conversation_as_open_for_human_response` invoked?** `Message#after_create` hooks — confirmed usage at `message.rb:444`-adjacent callback wiring (see `app/models/message.rb` `after_create` block; keep exactly the existing trigger). BB path (incoming) only: `self.incoming?` check inside the callback; outbound doesn't flip status.

**5.2 EE alignment (required by AGENTS.md "Keep OSS/Enterprise contracts aligned")**

- Keep `Enterprise::Message#mark_pending_conversation_as_open_for_human_response` a full override; change its guard to `return unless captain_pending_conversation? || pending_ai_agent_conversation?` (it can reach into the OSS-defined predicate since `Enterprise::Message` prepends Message and the method is looked up on the instance). Also keep its `template_bootstrap_message?` extra guard + activity message + Current-user swap exactly as-is.
- Add `spec/enterprise/models/message_spec.rb` covering: EE captain inbox → existing auto-open still fires (`captain` matchers unchanged); EE conversation with AI agent inbox, no Captain, human reply → auto-open; EE AI conversation without a pending status → no state change.

### 5.3 Tests

- `spec/models/message_spec.rb`: 
  - pending AI-agent conversation (inbox with active `agent_bot_inbox` + AiAgent enabled) + human outgoing reply → status becomes `open`.
  - pending AI conversation with `ai_handoff_completed: true` already, human replies → status stays `pending`? (Note: conversation already open in practice; assert safe no-op `open!` when pending... if it's already `open`, `open!` is a no-op — assert status unchanged.)
  - pending non-AI conversation (webhook bot or no bot) + human reply → stays `pending` (OSS behavior preserved).
  - `captain_pending_conversation?` still `false` in OSS (stub untouched) → captain path never fires without the new predicate.

### Acceptance

- [ ] `bundle exec rspec spec/models/message_spec.rb` and (if touched) `spec/enterprise/models/message_spec.rb` green.
- [ ] EE's `captain_pending_conversation?` untouched; no EE spec regressions.

---

## 6: Handoff best-effort assignment + one not-assigned note

**Owner**: @implementer (backend)
**Dependencies**: Phase 4 done (handoff flow live on pending gate)
**Complexity**: MEDIUM

### 6.1 Changes in `app/services/ai_agents/tools/human_handoff_service.rb`

- Keep `call` + `test_mode?` early return (`:35`) as-is, so test-mode never performs assignment or notes.
- In `execute_live_handoff!` after `conversation.bot_handoff!` (`:72`) add one step:

```ruby
mark_handoff_completed!(result: result)
conversation.bot_handoff!
attempt_best_effort_assignment!
result
```

- New private methods:

```ruby
def attempt_best_effort_assignment!
  return if conversation.assignee.present? || conversation.assignee_agent_bot_id.present?

  AutoAssignment::AgentAssignmentService.new(
    conversation: conversation,
    allowed_agent_ids: conversation.inbox.available_agents.map(&:user_id) # user IDs, NOT InboxMember IDs (verified `inbox_agent_availability.rb:4-16` returns InboxMember records; `agent_assignment_service.rb:23-29` intersects user ids)
  ).perform
  add_not_assigned_note! unless conversation.assignee.present?
rescue StandardError => e
  Rails.logger.warn("[AiAgents] Best-effort human assignment failed for conversation=#{conversation.id}: #{e.class.name}: #{e.message}")
  add_not_assigned_note!
end

def add_not_assigned_note!
  Messages::MessageBuilder.new(nil, conversation.reload, {
    content: I18n.t('ai_agents.handoff_not_assigned_note', locale: conversation.account.locale),
    private: true,
    sender_type: 'AgentBot',
    sender_id: ai_agent.agent_bot_id
  }).perform
end
```

- **Idempotency reasoning**: `execute_live_handoff!` runs once per conversation because `handoff_completed?` check (`:66`) and `mark_handoff_completed!` are terminal; a second tool invocation returns `live_error_result('handoff_already_completed')` before this step — so no second assignment attempt and no duplicate note. `ResponseBuffer` replay semantics unchanged.
- **No change** to `mark_handoff_completed!` (`:106-117`) or its `additional_attributes` — learning capture and quality summary consumers read `ai_handoff_completed` as before.
- **No change** to `usage/limiter.rb` (`:74-81`, `:150-160`) or orchestrator safety handoff (`:731-763`) — they call the same service, so both get the assignment attempt for free and remain idempotent.

### i18n (Phase 6b — same commit or immediately following)

- `config/locales/en.yml` under existing `ai_agents:` block (`:34`) add:
  ```yaml
  ai_agents:
    handoff_not_assigned_note: 'Handoff completed — no agents were available for automatic assignment. An agent can pick up this conversation from the inbox.'
  ```
- Mirror in `config/locales/tr.yml` (`:21` block) — Turkish equivalent (translate; e.g. "Devir tamamlandı — otomatik atama için uygun ajan bulunamadı. Ajan, bu görüşmeyi kutu listesinden üstlenebilir." or similar native wording; keep en/tr aligned per repo policy).
- Do NOT duplicate the `ai_agents` block; append the key.

### Tests

- `spec/services/ai_agents/tools/human_handoff_service_spec.rb` (151 lines) add a `describe '#call (live mode)'`:
  - `context 'auto assignment succeeds'`: stub `AutoAssignment::AgentAssignmentService` not needed — create 1 online agent member; after `call`, `conversation.assignee` present, no private note with the new key, status `open`, `ai_handoff_completed == true`.
  - `context 'no assignable agent (nobody online)'`: `conversation.assignee` stays nil, exactly **one** private note containing `ai_agents.handoff_not_assigned_note` text exists, status `open`.
  - `context 'assignment service raises'`: rescue path — no exception escapes, one note added, warn logged (assert via `expect(Rails.logger).to receive(:warn)`).
  - `context 'handoff idempotency'`: second live call returns `error_code == 'handoff_already_completed'` and message count for the not-assigned note stays 1.
  - `context 'assignee already present'`: pre-assigned human — service skips assignment attempt (`expect_any_instance_of(AutoAssignment::AgentAssignmentService).not_to receive(:perform)`) and adds no note.
  - `test_mode` remains unchanged: no notes, no assignment.

### Acceptance

- [ ] `bundle exec rspec spec/services/ai_agents/tools/human_handoff_service_spec.rb` green (all old cases + new).
- [ ] i18n keys present in en+tr; `bundle exec rubocop` clean on changed files.

---

## 7: Docs + superseded note

**Owner**: @implementer (docs)
**Dependencies**: Phase 2 (final state)
**Complexity**: LOW

- **7.1** Add one line at the very top of `docs/ai-agent-human-takeover-plan.md`:
  ```
  > SUPERSEDED — design record only. The implementable design is now `docs/ai-agent-pending-gate-plan.md` (pending-status gate, assignment does not stop the AI).
  ```
  Keep the rest of the file untouched (obsolete record).
- **7.2** In `docs/ai-agent-catalog-runtime.md`: update the runtime boundary table/row that governs "AI replies to customer messages" to read "AI replies only while `status == pending` (verified by `AiAgents::ReplyPolicy` at schedule + execute); human's first reply opens the conversation and silences the AI; `human_handoff` remains terminal; assignment does not silence". Fix any prose that contradicts the pending gate (e.g., "assignee stops bot" statements).
- **7.3** Add under "Follow-Up Decisions" in this plan (7.3 modifies this file, not a new doc).
- **7.4** Note in `docs/ai-agents-architecture.plan.md` is NOT required (it's the v1 plan; leave untouched unless it directly contradicts the gate — check, and if it does, add a one-line pointer to this plan).

### Acceptance

- [ ] Both docs updated; no functional code changed in this phase.

---

## 8: Deferred follow-up decisions (documented, NOT implemented)

| # | Item | Current behavior under this plan | Needed decision |
|---|------|----------------------------------|-----------------|
| 1 | **Resolved → reopen** | `reopen_resolved_conversation` (`message.rb:460-470`) sets `pending!` for `inbox.active_bot?` → a re-contact on a resolved AI conversation makes it pending again → **the AI resumes replying** (unchanged today's behavior, but now observable under the gate). The user explicitly deferred: reopen mechanics might be changed (e.g., reopen to `open!` for bot inboxes, or keep pending but suppress AI until human). | Decide reopen semantics for bot inboxes; possibly requires a product spec for "resolved = human took over" assumption. |
| 2 | Where to put "human first reply opens" for non-AI-conversation workflows | No change (OSS applies only to `pending_ai_agent_conversation?`). | Not required. |
| 3 | EE `Enterprise::Message#mark_pending_conversation_as_open_for_human_response` adds `pending_ai_agent_conversation?` OR — keep | Done in this plan | None (both editions aligned). |
| 4 | Persistent "no agents available" UX | Note added; no UI change | Optional future UX: show a banner in conversation for admins when handoff had no assignable agent. |

Deferred items are NOT accepted for now; do not implement in this PR.

---

## Success Criteria Checklist (final)

- [ ] New conversation in AiAgent inbox → `pending`, AI replies (existing default preserved, verified by spec + manual).
- [ ] Conversation manually marked open / resolved / snoozed (with AI still enabled) → **no** AI reply on next customer message (listener + processor both silent).
- [ ] Human first reply → `open!` automatically + AI silent afterwards (message spec).
- [ ] Assignee stays nil + pending on purpose → AI still replies.
- [ ] Handoff tool: bot_handoff → open + `ai_handoff_completed`; one best-effort auto-assign attempt when unassigned; one private note if no assignee; no duplicate on replay; test_mode unchanged.
- [ ] Webhook bots (with/without human assignee) unchanged.
- [ ] i18n key exists in `en` and `tr` under `ai_agents:`.
- [ ] `docs/ai-agent-human-takeover-plan.md` marked superseded; `docs/ai-agent-catalog-runtime.md` boundary row accurate; this plan lists deferred items 1-4.
- [ ] Rollback possible by reverting this 1 PR (see Rollback).

---

## Blast Radius / Affected Entry Points

| Entry point | Reason | Compatibility guarantee |
|-------------|--------|------------------------|
| `AgentBotListener#message_created` (AI path) | gate at schedule time; webhook path untouched | webhook bots + assignee webhook bot cases keep delivering (`listener_spec:38-69`) |
| `AgentBots::AiResponseJob` → `LiveProcessor#perform` | execute-time re-check; races window bounded | no dequeue-time changes; idempotency via `ResponseBuffer` tokens + `response_already_persisted?` unchanged |
| `Message` model `mark_pending_conversation_as_open_for_human_response` | new predicate; EE override untouched and now ORs the predicate | EE captain behavior + activity message intact |
| `HumanHandoffService#execute_live_handoff!` | assignment attempt + note inside the terminal path | `human_handoff` tool semantic ID (`MAX_HUMAN_HANDOFF_CALLS` stays 1), test_mode, error codes, idempotency |
| `AiAgents::Usage::Limiter#exhausted_handoff!` (usage/limiter.rb:74-81,150-160) | NOT modified | flags + quality summary consumers (`ai_handoff_completed` readers) see identical payloads |
| i18n `config/locales/en.yml` + `tr.yml` | new key under existing `ai_agents:` block | no keys removed/renamed; both locales in sync |
| `docs/ai-agent-catalog-runtime.md`, `docs/ai-agent-human-takeover-plan.md` | docs accuracy | single-line superseded marker + boundary row update |
| Specs: live_processor, listener, handoff service, message model, reply policy (new), EE message (new) | behavior verification | targeted files only |

## Allowed Scope / Forbidden Scope

- **Allowed**
  - `app/services/ai_agents/reply_policy.rb` (new)
  - `app/services/ai_agents/live_processor.rb` (gate + dead-code removal)
  - `app/listeners/agent_bot_listener.rb` (gate at schedule time; remove unused `ai_handoff_completed?`)
  - `app/models/message.rb` (predicate + OR in auto-open)
  - `app/services/ai_agents/tools/human_handoff_service.rb` (assignment + note)
  - `config/locales/en.yml`, `config/locales/tr.yml` (`ai_agents.handoff_not_assigned_note`)
  - `docs/ai-agent-catalog-runtime.md`, `docs/ai-agent-human-takeover-plan.md` (superseded marker)
  - Specs: `spec/services/ai_agents/reply_policy_spec.rb` (new), `spec/services/ai_agents/live_processor_spec.rb`, `spec/listeners/agent_bot_listener_spec.rb`, `spec/models/message_spec.rb`, `spec/services/ai_agents/tools/human_handoff_service_spec.rb`, `spec/enterprise/models/message_spec.rb` (new)
- **Forbidden** (explicit non-goals):
  - No change to `Conversations::AssignmentService`, `Usage::Limiter` exhausted_handoff path, `orchestrator.rb` handoff/limits, `ResponseBuffer` internals, `webhook path`.
  - No env flag gating the whole feature (escape hatch note only, inside `ReplyPolicy`).
  - No migration, no schema change, no queue/background job changes, no UI changes.
  - Do NOT implement reopen-mechanics decision (deferred). Do NOT repurpose `ai_handoff_completed` or make the gate dependent on assignees.

## Invariants

| Invariant | Why | How to verify |
|---|---|---|
| Conversations in `open`/`resolved`/`snoozed` get NO AI reply (schedule + execute both block) | pending gate contract | `live_processor_spec` open-conversation case; `listener_spec` open-conversation no-AiResponseJob |
| Assignee present (human or bot) does NOT stop AI while pending | decision 3 | listener spec "assigned + pending → still scheduled"; handoff spec assignee-skip case |
| Webhook-bot parity incl. human-assigned → webhook delivery unchanged | product-visible payload contract | existing listener webhook cases (38-69) fully green |
| `human_handoff` tool semantics: terminal, idempotent, test_mode unchanged, ONE auto-assign attempt, ONE note max | tool contract | handoff service spec: first-call live passes; 2nd call `handoff_already_completed`; note count = 1 |
| `ai_handoff_completed` payload + consumers untouched (usage limiter, learning capture, quality summary) | data contract | git diff on `usage/limiter.rb` + `orchestrator.rb` must be empty |
| EE `Enterprise::Message` override keeps `captain_pending_conversation?` + activity-message behavior | EE parity | pre-existing enterprise specs + new OSS predicate unit |
| No AI reply for non-pending incoming "hello" in an AI inbox with AI enabled | core gate | manual + spec |

## Behavior That Must Not Change

- Webhook-bot delivery for ALL conversations including those with human assignees — `listener_spec.rb` webhook contexts still expect exact `AgentBots::WebhookJob` calls.
- `response_already_persisted?` duplicate-reply prevention and buffer claim/release semantics.
- Usage limiter reserve/consume/release; `exhausted_handoff!` sets flag directly.
- Safety handoff (`orchestrator.rb:731-767`) → same `HumanHandoffService` path with assignment attempt (no new failure mode — rescue-then-note).
- New conversations created by campaigns / contact creation with `inbox.active_bot?` starting `pending` (conversation.rb:276-288).
- `determine_conversation_status` ordering (blocked contact → resolved beats pending).

## Manual / API Verification Recipe (dev browser/CDP or curl)

- **Setup**: seed account+inbox+A even. `bundle exec rails db:seed`; create AiAgent; add inbox to agent_bot_inbox (active). Ensure an agent user online (dev seed) — for assignment test.
- **V3 widget flow** (or `add-message` API if widget faster):
  1. New conversation → wait few sec (buffer 5s) → AI replies (this proves default pending gate passes) — status shows "Beklemede".
  2. Assign an agent while conversation still pending → send one new customer message → AI still replies (assignee alone no effect).
  3. Human (seeded agent) sends a reply from dashboard → conversation flips to `open` (API: `GET /api/v1/accounts/:id/conversations/:cid` shows status open) → send a new customer message → NO AI response after buffer window; `AgentBots::AiResponseJob` not created (check `conversation.messages` count).
  4. Force re-pending via UI (set status pending) → new customer message → AI replies again (gate is status-driven).
  5. Trigger `human_handoff` (tool/custom message in dev only) with **nobody online**: after handoff, exactly 2 private notes (handoff brief + the 1 new not-assigned note), status open; second customer message → NO AI reply; replay same handoff args → `handoff_already_completed`.
  6. Webhook-bot inbox with `outgoing_url`: customer message with human assignee → `Sidekiq` `AgentBots::WebhookJob` still fired (log; `AgentBot webhook event received`).
  7. Resolved conversation (existing) → customer writes → status back to `pending` (reopen confirm) → AI resumes (DOCUMENTED deferred behavior; verify manually to record reality).
- **API-only** smoke: `curl` POST client message (`POST /api/v1/accounts/.../conversations...` or `/public/api` widget API with `message_created` event) → poll conversation status + AI replies via `GET`.

## Validation Matrix

| Check | Command | Proves |
|---|---|---|
| Unit gate | `bundle exec rspec spec/services/ai_agents/reply_policy_spec.rb` | gate authority contract |
| Execution-time | `bundle exec rspec spec/services/ai_agents/live_processor_spec.rb` | open → silent; pending → replies; handoff flag still respected; duplicate-reply idempotency |
| Schedule-time | `bundle exec rspec spec/listeners/agent_bot_listener_spec.rb` | webhook parity 31-69 re green; AI pending gate; assigned-pending still schedules |
| Handoff | `bundle exec rspec spec/services/ai_agents/tools/human_handoff_service_spec.rb` | assign attempt, note idempotency, no-assignable note, rescue log, test_mode unchanged |
| Human-reply→open | `bundle exec rspec spec/models/message_spec.rb` | OSS message flips pending AI conversations; non-AI untouched; EE behavior |
| EE | `bundle exec rspec spec/enterprise/models/message_spec.rb` (new) | captain behavior intact, AiAgents auto-open works in EE |
| Lint | `bundle exec rubocop -a` on `app/models/message.rb app/listeners/agent_bot_listener.rb app/services/ai_agents/*.rb app/services/ai_agents/tools/human_handoff_service.rb` | style gate |
| Docs | `git diff --stat docs/` | superseded marker + boundary update present |
| No forbidden diffs | `git diff --stat -- app/services/conversations/assignment_service.rb app/services/ai_agents/usage/limiter.rb` (exit 1 expected no diff) | untouched invariants |

Full spec sweep (optional but recommended): `bundle exec rspec spec/services/ai_agents spec/listeners/agent_bot_listener_spec.rb spec/models/message_spec.rb`.

## Evidence Owners

| Item | Owner | Proof |
|---|---|---|
| Gate authority tests | @implementer | `reply_policy_spec.rb` green |
| Execution-time silence for open conversations | @implementer | live_processor_spec new case |
| Schedule-time silence | @implementer | listener spec new context |
| Webhook parity (incl. human-assigned) | @implementer | listener webhook contexts stay green |
| Handoff assignability note idempotency | @implementer | handoff service spec |
| Human-reply→open in EE + OSS | @implementer | message_spec + `spec/enterprise` |
| i18n en+tr alignment | @implementer | `git diff config/locales/` |
| Docs superseded marker | @implementer | head of `ai-agent-human-takeover-plan.md` |
| Invariants (items above) | @analyzer (gate review) | full-matrix re-run |

## Review Gates

| Gate | After Phase | Focus for @analyzer |
|---|---|---|
| G1 | Phase 1 | ReplyPolicy API + spec; constant/helper naming; no collisions with `HANDOFF_COMPLETED_KEY` |
| G2 | Phase 3 | execute-time gate ordering + log; `conversation` reload subtlety (`conversation` may be stale in `perform` vs caller reload) |
| G3 | Phase 4 | schedule/execute double-check consistency; webhook path untouched; `agents_bots_for` unchanged |
| G4 | Phase 5 | EE override collision (verified via `01_inject_enterprise_edition_module.rb` + `prepend_mod_with('Message')`); `mark_pending...` guard ordering (`human_response?`/`private?`) identical to EE |
| G5 | Phase 6 | handoff service: rescue scope (`StandardError` only, warn, no raise), note count=1 by design, test_mode unchanged, `AssigneeService` not modified |
| G6 | Phase 7 | docs content accuracy; no stale prose contradicting the gate; superseded note present |

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| **Reopen race (DEFERRED)**: customer reopens a resolved conversation → `pending!` → AI resumes replying (message.rb:460-470) | HIGH (behavior exists today) | MEDIUM (AI resumes after human closed it) | Deferred decision recorded in §Follow-Up Decisions/risk table; plan keeps today's reopen behavior; a product change to reopen mechanics will be a separate PR |
| **Enqueue-vs-status flip race** (listener sees pending, human replies before `LiveProcessor#perform`) | MEDIUM | LOW (one AI reply may land after human reply; no duplicates/second) | execute-time gate re-checks `pending?`+handoff; deterministic double-write safety via `with_lock` + `response_already_persisted?` already in place; listing-run logs at gate rejection |
| **EE `Enterprise::Message` method-name collision with new predicate** | VERIFIED LOW (name `pending_ai_agent_conversation?` free) | HIGH if collided | Grep + G4 gate; EE override keeps its exact method name, only ORs the predicate (review proof) |
| **Handoff helper raising** (e.g., `available_agents` returns `none`) | LOW | LOW | `rescue StandardError` + warn; note still added; return path unchanged; test covers raise |
| Double private note on replay (retry after partial failure at `perform` stage) | LOW (idempotency guard is 1 line above) | LOW | `handoff_already_completed` early-return; G5 test asserts count 1 |
| Assignment stealing an auto-assigned conversation from a team | LOW (only in handoff context, assignee nil) | LOW | skip when already assigned (`assignee` present) per spec |

## Rollback

- **Whole plan**: single revert of the feature branch (all phases land under one PR or branch; code-only, no migration). `docs/` markers are cosmetically obsolete on revert — safe.
- **Phase-level**: each phase is independently revertable by reverting its commit; phase 3 (message) revert removes human-reply auto-open while handoff notes remain (no functional hazard).
- **Escape hatch** (operational, not default): if a silent-bot regression surfaces post-merge, gate can be flipped inside `AiAgents::Policy` (single seam) — no other code path reads status otherwise.

## Decision Log

| Decision | Chosen | Rejected | Rationale |
|---|---|---|---|
| Gate module | `AiAgents::Policy` class with class methods | concern module / direct `pending? && !flag` inline | single authority, EE seam, trivially spec'd; class-with-class-methods matches `ResponseBuffer`/`HumanHandoffService` style of the AiAgents stack |
| Human-reply predicate | Separate `pending_ai_agent_conversation?` on `Message` (units: `pending? && (assignee_agent_bot || inbox.agent_bot)&.ai? && ai_agent&.enabled?`) | Reusing `captain_pending_conversation?`; renaming EE method; writing the OR inline in pre-flippers | no EE name collision; mirrors LiveProcessor ai_agent resolution (`live_processor.rb:43`) |
| Execution-time placement | check in `LiveProcessor#perform` replacing `handoff_…?` | adding to `AgentBots::AiResponseJob` / buffer internal | minimize touched surface |
| Assignment attempt scope | inside `HumanHandoffService.execute_live_handoff!` after `bot_handoff!`, rescue-scoped | in `LiveProcessor` after tool result | tool service has `conversation` + `trigger_message`; test mode naturally skipped; safety handoff path inherits it |
| Not-assigned note | one private message with `ai_agents.handoff_not_assigned_note` locale key | activity label / channel manipulation | minimal surface, visible to agents only, i18n-correct |
| Defers | reopen mechanics & UI banner | - | user explicitly postponed; documented in plan table |

## Notes

- This plan supersedes `docs/ai-agent-human-takeover-plan.md` (assignee-gate design). Do not implement that file.
- REPLICATE the "MARK ANY HUMAN-first-reply in ANY pending conversation" nuance: the OSS auto-open currently limited to `pending_ai_agent_conversation?` — webhook-only or dialogflow conversations have no `ai_agent`, so they keep old behavior (`message.rb:448-458` unchanged, `captain_pending_conversation?` false in OSS).
- The gate constant `HANDOFF_COMPLETED_KEY` lives in `AiAgents::Policy` (single source; the tool service still reads the same key with its own comparison — acceptable duplication, or refactor to `Policy.handoff_completed?` in a follow-up; the tool's method uses the raw attribute for persistence, keep as-is).
- `conversation.inbox` may be nil-defensive? No — `pending_ai_agent_conversation?` requires `pending?` first; `inbox` is present for all persisted conversations (`belongs_to :inbox` required). `assignee_agent_bot` may be nil (human assignee resets it, `conversation.rb:270-274`) — therefore OR-delegation to `inbox.agent_bot` preserves the same behavior LiveProcessor uses (`live_processor.rb:43`).
- i18n: keep en + tr key sets aligned; the repo maintains those as the only source locales.
- No AIAgent/EE overlay exists for `ReplyPolicy` today; EE consumer only for message overrides. Verify once more at Phase 5 diff time via `rg -n "pending_ai_agent_conversation|ReplyPolicy" enterprise` (no matches expected).