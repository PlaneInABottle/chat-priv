# AiAgents: Stop Automatic Replies After Human Takeover — Implementation Plan

> **SUPERSEDED (2026-08-08)** — design record only. The implementable design is now `docs/ai-agent-pending-gate-plan.md` (pending-status gate; assignment does NOT stop the AI; handoff stays terminal with best-effort assignment). Do not implement this file.

## Problem Statement

The OSS AiAgents stack keeps replying to customer messages after a human agent takes over a conversation. Today the bot is silenced **only** by the AI-initiated handoff flag (`ai_handoff_completed`), set exclusively by the `human_handoff` tool path ([`human_handoff_service.rb:106-117`](app/services/ai_agents/tools/human_handoff_service.rb), read at [`live_processor.rb:58-61`](app/services/ai_agents/live_processor.rb) and [`agent_bot_listener.rb:103-106`](app/listeners/agent_bot_listener.rb)). When a human is **assigned** (manual, API, auto-assign) or writes a **reply**, the AI keeps responding to subsequent customer messages — on both the assignee-bot path and the inbox-level bot path. Product decision (B): the bot must stop automatically when a human agent is assigned to the conversation AND/OR when the human writes their first message.

## Approach

Two read-only, derived gates applied at **both** AI decision points — schedule time (`AgentBotListener#process_ai_bot_event`) and execution time (`AiAgents::LiveProcessor#perform`):

- `conversation.assignee_id.present?` → a human currently holds the conversation (AgentBot assignment never sets `assignee_id`; it clears it — verified below).
- `conversation.first_reply_created_at.present?` → a human has already replied at least once (only human messages set this; bot replies never do — verified below).
- plus the existing `ai_handoff_completed == true` flag (semantics unchanged).

No new persisted attribute, no migration, no write-side instrumentation — every assignment path (manual, API, auto-assign, action service, voice, enterprise overlays) is covered automatically by the derived `assignee_id` check. The predicate lives in one new module, `AiAgents::HumanTakeover` (DRY across its two call sites) — and is the only place that encodes "stopped", giving future Enterprise overlays a single seam.

For the user's follow-up requirement (handoff completes but **no human can be assigned**): the handoff attempt now tries once to assign an available human via existing round-robin infrastructure; if none is found, the bot **stays stopped** and `HumanHandoffService` appends one private note for the team. Never auto-resume.

## Success Criteria

- [ ] After a human is assigned (any path), the next incoming customer message produces **no** AI reply (both assignee-bot path and inbox-level bot path).
- [ ] After a human writes their first message on an **unassigned** conversation, the next incoming customer message produces no AI reply.
- [ ] With neither assignee nor human reply, the bot still replies exactly as today.
- [ ] Handoffs remain terminal and idempotent; `human_handoff` tool semantics, usage limiter, options/catalog flow, and webhook (non-AI) agent bots unchanged.
- [ ] Failed handoff (no assignable human) keeps the bot stopped and appends one private note; successful handoff assigns an available human when possible.
- [ ] `docs/ai-agent-catalog-runtime.md` updated (component boundary note) and the drift vs `docs/ai-agents-rebuild-plan.md:112-113` documented.
- [ ] All existing `spec/services/ai_agents/live_processor_spec.rb` and `spec/listeners/agent_bot_listener_spec.rb` tests plus the new specs pass; `bundle exec rubocop -a` clean.

---

## Verified facts (evidence)

| Fact | Evidence |
|---|---|
| `AgentBotListener#message_created` → AI branch gates only on incoming/private/activity/template + `ai_handoff_completed` + `agent_bot.ai_agent&.enabled?` | `app/listeners/agent_bot_listener.rb:36-43,79-92,94-106` |
| `agent_bots_for` collects BOTH `conversation.assignee_agent_bot` AND `active_inbox_agent_bot` | `app/listeners/agent_bot_listener.rb:65-77` |
| `AiAgents::LiveProcessor` gates: `eligible_message?` (bot + account enabled) → `handoff_completed?` → duplicate-reply guard | `app/services/ai_agents/live_processor.rb:12-15,42-61,144-151` |
| `ai_agent` resolution: `conversation.assignee_agent_bot&.ai_agent \|\| conversation.inbox.agent_bot&.ai_agent` | `app/services/ai_agents/live_processor.rb:42-44` |
| Human assignment clears ONLY `assignee_agent_bot_id` (no stop flag); bot assignment clears human `assignee_id` | `app/services/conversations/assignment_service.rb:16-30`; `app/models/conversation.rb:75` registers `before_validation :reset_agent_bot_when_assignee_present` (`:270-274`) |
| All human-assignment paths funnel to `assignee_id` column: Assignments API → `Conversations::AssignmentService` (`app/controllers/api/v1/accounts/conversations/assignments_controller.rb:16`); dashboard self-assign (`conversations_controller.rb:187`); action service (`app/services/action_service.rb:44-75`); auto-assign (`AutoAssignment::AgentAssignmentService#perform` writes `conversation.update(assignee: …)` at `app/services/auto_assignment/agent_assignment_service.rb:11-14`); Voice calls (`enterprise/app/services/voice/**` → `Conversations::AssignmentService`) | verified via search |
| Human replies set `first_reply_created_at` only for `human_response?` messages (User sender, no automation/campaign IDs; `Captain::Assistant`/`AgentBot` excluded); bot replies never set it; never cleared after set | `app/models/message.rb:249-258,364-408` |
| Handoff marks `ai_handoff_completed=true` + metadata + `bot_handoff!` (open + `waiting_since`), guarded idempotent by `handoff_completed? → error` | `app/services/ai_agents/tools/human_handoff_service.rb:63-126`; `app/models/conversation.rb:172-176` |
| Fail-open safety handoff and usage-exhausted handoff both exist and must keep working unchanged | `app/services/ai_agents/orchestrator.rb:731-767`; `app/services/ai_agents/usage/limiter.rb:74-81,150-160` |
| Reusable assignment helper: `AutoAssignment::AgentAssignmentService` (round-robin over online inbox agents) + `inbox.available_agents` | `app/services/auto_assignment/agent_assignment_service.rb:1-38`; `app/models/concerns/inbox_agent_availability.rb` |
| Enterprise overlay check: **no** overlay for `LiveProcessor`, `AgentBotListener`, `Conversations::AssignmentService` (searched `enterprise/`); EE overlays only `AutoAssignment::AssignmentService` (a different scheduling class we do NOT touch) | search over `enterprise/**/*.rb` |
| `waiting_since` couples to bot handoff + auto-resolve; must NOT be used by the new gate | `app/models/conversation.rb:87,172-176,239-248,262-265`; `app/models/message.rb:364-385` |
| OSS never had a `pending`-status AI gate (that was Enterprise Captain `.pending?` at 374d2258c) — do not introduce one | verified in history |

---

## Design (gate predicate: `AiAgents::HumanTakeover`)

```ruby
module AiAgents::HumanTakeover
  HANDOFF_KEY = 'ai_handoff_completed'.freeze

  module_function

  def stopped?(conversation)
    handoff_completed?(conversation) ||
      conversation.assignee_id.present? ||
      conversation.first_reply_created_at.present?
  end

  def handoff_completed?(conversation)
    attrs = conversation.additional_attributes
    attrs.is_a?(Hash) && attrs[HANDOFF_KEY] == true
  end
end
```

**Why this shape (vs. alternatives):**
- *vs. extending `ai_handoff_completed` semantics when a human assigns/replies:* breaks consumers that treat that flag as "AI handed off" — `AiAgents::AutomaticLearningCapture` (`app/services/ai_agents/automatic_learning_capture.rb:31`) and `QualitySummary` (`quality_summary.rb:85`); needs write-site changes at every assignment path (races, drift).
- *vs. a new `ai_agent_handed_to_human` attribute:* same write-site problem + migration + deploy order. YAGNI — the derived state already exists.
- *vs. a `pending`-status gate:* that existed only in Enterprise Captain (`enterprise/app/jobs/captain/…/response_builder_job.rb#pending?`). Not needed for (B); not reintroduced.

**Both layers** read the gate:
1. `AiAgents::LiveProcessor#perform` — execution time; the ultimate stop (covers a re-enqueue/schedule that races an assignment).
2. `AgentBotListener#process_ai_bot_event` — schedule time; avoids queue/LLM work and keeps `ResponseBuffer` clean.

**Stop modes ("permanent vs session"):**
- Stopped by a **human's first reply** (`first_reply_created_at` set) → **permanent** for the conversation (field is never cleared).
- Stopped by **assignment only** → while assigned; if the human is later unassigned (`assignee_id = nil`, e.g. `action_service.rb:44/75`) **before replying**, the bot resumes — deliberate: matches "bot stands down while a human holds it", and allows a conversation to return to the bot if the human never engaged.
- Stopped by the **handoff flag** → permanent (existing).

---

## Phase 1: `AiAgents::HumanTakeover` predicate + unit spec

**Owner**: @implementer (backend) | **Deps**: none | **Complexity**: LOW

Files: `app/services/ai_agents/human_takeover.rb` (new), `spec/services/ai_agents/human_takeover_spec.rb` (new)

Tasks:
- 1.1 Create the module exactly as above (only place that encodes "stopped").
- 1.2 **Assumption check** (15 min): `rg -n "first_reply_created_at" app/` — confirm no non-human path sets it outside `message.rb:406-412` (templates, campaigns, email hooks). If any found (ASSUMED-FALSE), fall back to `conversation.messages.outgoing.where(sender_type: 'User').any?` and document in the plan update.
- 1.3 Spec `it` blocks:
  - `'is stopped when a human agent is assigned (assignee_id present)'`
  - `'is stopped after a human wrote the first reply on an unassigned conversation'`
  - `'is stopped when the ai_handoff_completed flag is set'`
  - `'is not stopped when only an agent bot is assigned (assignee_id blank, assignee_agent_bot present)'`
  - `'is not stopped when neither assignee nor reply nor handoff flag exists'`
  - `'recovers when the assignee is removed before any human reply'` (session semantics)

**Acceptance:** module + spec green; `bundle exec rubocop -a` on both files.

---

## Phase 2 — Gate `AiAgents::LiveProcessor`

**Owner**: @implementer | **Deps**: Phase 1 | **Complexity**: LOW

Files: `app/services/ai_agents/live_processor.rb`; `spec/services/ai_agents/live_processor_spec.rb`

Tasks:
- 2.1 In `perform` (line 12-15) replace the single handoff guard with the full gate:
  ```ruby
  def perform
    return unless eligible_message?
    return if AiAgents::HumanTakeover.stopped?(conversation)
    return false if response_already_persisted?
    ...
  ```
- 2.2 Delete `HANDOFF_COMPLETED_KEY` constant and `handoff_completed?` private method from this class (no other usage — checked; the module is the single home for the key).
- 2.3 Spec additions (file already has fixtures at `spec/services/ai_agents/live_processor_spec.rb:3-13`; follow the existing `it` style, new cases placed after the "does not re-enter after handoff is completed" block):
  - `'does not reply when a human agent is assigned'` — `conversation.update!(assignee: user)` (+ needed `user` factory), incoming customer message, `expect(adapter).not_to receive(:perform)`, `described_class.new(message: message, adapter: adapter).perform` → falsy.
  - `'does not reply when a human replied first on an unassigned conversation'` — create conversation (no assignee), create an outgoing `User` message (sets `first_reply_created_at`), then incoming customer message → `adapter` not called, perform falsy.
  - `'returns false for duplicate delivery when a human is assigned'` — same message twice → falsy both times, adapter never called.
  - Existing `'persists one outgoing AgentBot response for a text assistant result'` (line 48) doubles as regression for "no assignee + no reply → still replies".

**Acceptance**: new cases green; the full `live_processor_spec.rb` file (606 lines today) stays green.

## Phase 3 — Gate `AgentBotListener` (schedule time)

**Owner**: @implementer | **Deps**: Phase 1 | **Complexity**: LOW-MED

Files: `app/listeners/agent_bot_listener.rb`; `spec/listeners/agent_bot_listener_spec.rb`

Tasks:
- 3.1 In `process_ai_bot_event` (line 86-92) replace `return if ai_handoff_completed?(message.conversation)` with `return if AiAgents::HumanTakeover.stopped?(message.conversation)`; remove the now-unused private `ai_handoff_completed?` (lines 103-106).
- 3.2 **Do not touch** `agent_bots_for` / `active_inbox_agent_bot` / webhook paths — non-AI webhook bots must keep firing for conversations with human assignees (existing spec `spec/listeners/agent_bot_listener_spec.rb:31-69` must stay green).
- 3.3 Add under `describe '#message_created'`:
  - `context 'when a human agent is assigned'` — AI agent inbox binding active + `conversation.update!(assignee: user)`; stub `expect(AiAgents::ResponseBuffer).not_to receive(:schedule!)`; assert result false (per `message_created` returning `schedule!` result or nil) — assert no AI reply scheduled.
  - `context 'when the human wrote the first message (unassigned)'` — human outgoing message first, then incoming: same no-schedule assertion.
  - `context 'webhook bots still receive events when a human is assigned'` — webhook-type agent bot + assignee: `AgentBots::WebhookJob.perform_later` still expected once (behavior preservation).

**Acceptance**: new contexts green + previously listed webhook cases untouched/green.

## Phase 4 — Handoff assignment attempt + "cannot assign" note

**Owner**: @implementer | **Deps**: Phase 3 | **Complexity**: MED

Files: `app/services/ai_agents/tools/human_handoff_service.rb`; `config/locales/en.yml` + `config/locales/tr.yml`; `spec/services/ai_agents/tools/human_handoff_service_spec.rb`

**Decision (explicit pick):**
- **Cannot-assign** → keep bot **stopped** (handoff flag already terminal) + append **one private note** ("no available human"). Alternative **rejected**: resume the bot — contradicts the customer-facing "transferring you to a human" promise the model just made, burns usage, breaks "handoff is terminal".
- **Can-assign** → attempt **one** best-effort assignment to a human via existing `AutoAssignment::AgentAssignmentService` (round-robin over online agents of the inbox). If assigned, the bot stays stopped through the Phase 2/3 gate. Whole attempt wrapped in `rescue StandardError` + warn log so assignment infrastructure failure never blocks handoff completion.

Tasks:
- 4.1 In `HumanHandoffService#execute_live_handoff!` (line 63-75), after `conversation.bot_handoff!` (line 72) call the new `attempt_human_assignment!`; the existing `return live_error_result('handoff_already_completed')` guard (line 66) keeps the whole block idempotent (no double note on retry; test_mode returns earlier at line 35, so the attempt never runs in test/simulator mode).
- 4.2 Add private method (mirroring the bounded-rescue style of `Orchestrator#log_safety_handoff`):
```ruby
def attempt_human_assignment!
  return if conversation.assignee.present? || conversation.assignee_agent_bot_id.present?

  AutoAssignment::AgentAssignmentService.new(
    conversation: conversation, allowed_agent_ids: conversation.inbox.available_agents.map(&:id)
  ).perform
  return if conversation.assignee_id.present?

  add_private_note! I18n.t('ai_agents.handoff_not_assigned_note')
rescue StandardError => e
  Rails.logger.warn("[AiAgents::HumanHandoffService] assignment attempt failed conversation_id=#{conversation.id} error=#{e.class.name}: #{e.message}")
end
```
- 4.3 i18n (both maintained locales, AGENTS rule): `ai_agents.handoff_not_assigned_note` — en: "Human handoff completed, but no available agent could be assigned automatically. Please follow up with this conversation as soon as possible." + matching `tr` string (find existing `ai_agents:` block in `config/locales/en.yml` and mirror it; do NOT touch other locales).
- 4.4 Specs in `spec/services/ai_agents/tools/human_handoff_service_spec.rb` (existing file covers live handoff, test_mode, id) — add:
  - `context 'when no available human agent exists'`: let `AutoAssignment::AgentAssignmentService` run/produce no assignee (dev Default redis has no online users, or stub `.new(...).perform` to no-op); assert: `ai_handoff_completed` true, status open, exactly **one additional private message** containing the note, assignee unchanged.
  - `context 'when an available agent exists'`: stub `perform` to assign a user; assert assignee set to that user; **no** note added (assignee branch returns early).
  - `context 'when retried after completion'`: existing `handoff_already_completed` error result stays; **no** second note is appended (idempotency).

**Acceptance**: handoff suite green incl. new contexts; unique-note count assertions pass.

---

## Phase 5 — Docs + full validation

**Files**: `docs/ai-agent-catalog-runtime.md`, `docs/ai-agents-rebuild-plan.md` (drift note). No code.

- Update `docs/ai-agent-catalog-runtime.md` §Component boundaries, the `AiAgents::LiveProcessor` row: note the human-takeover gate (assignee / first reply / handoff terminal states).
- Add note beside `docs/ai-agents-rebuild-plan.rb:111-115` (v1 design decision #2): code drifted from "assignee-only" to allowing the inbox-level bot path; this plan **keeps** the inbox path and adds the human-takeover gate; restoring the assignee-only intent is a separate product decision.
- State in the runtime doc that "stopped" is now a recognized runtime concept with a single derivation point.

---

## Deliverables

| Phase | Files created/modified |
|---|---|
| 1 | `app/services/ai_agents/human_takeover.rb` (new), `spec/services/ai_agents/human_takeover_spec.rb` (new) |
| 2 | `app/services/ai_agents/live_processor.rb`, `spec/services/ai_agents/live_processor_spec.rb` |
| 3 | `app/listeners/agent_bot_listener.rb`, `spec/listeners/agent_bot_listener_spec.rb` |
| 4 | `app/services/ai_agents/tools/human_handoff_service.rb`, `config/locales/en.yml`, `config/locales/tr.yml`, `spec/services/ai_agents/tools/human_handoff_service_spec.rb` |
| 5 | `docs/ai-agent-catalog-runtime.md`, `docs/ai-agents-rebuild-plan.md` |

Explicitly NOT changed: `Conversations::AssignmentService`, `Usage::Limiter`, `Orchestrator`, `Message` model, `Conversation` model (code reads existing columns only), any migration/schema, any JS.

## Blast radius

| Entry point | Effect |
|---|---|
| `AgentBotListener#message_created` AI branch | early return when human takeover state → no `ResponseBuffer.schedule!` |
| `AgentBots::AiResponseJob` → `LiveProcessor#perform` | returns false when human takeover state → no LLM call, no usage reserve, no reply |
| `HumanHandoffService` (live mode) | best-effort assignment attempt + at most one extra private note; still terminal + idempotent; test_mode unchanged |
| Safety handoff (`Orchestrator#safety_handoff_result`) & usage-exhausted handoff (`Limiter#exhausted_handoff!`) | both end with the flag set; safety path gets the same assignment-attempt + note; limiter's own params branch untouched (writes its flag directly, not via service) and deliberately stays as-is |
| Pre-existing conversations with `first_reply_created_at` already set | immediately stop (desired; also locks in the new contract) |
| Enterprise | no EE overlays on the 3 touched classes; EE auto-assignment agents are covered by the `assignee_id` gate automatically (parity preserved; no EE spec needed) |
| i18n | `en`/`tr` keys only; no other locales in scope (AGENTS rule) |

**Rollback**: per-phase commits → `git revert` each phase commit (or single revert of the feature branch); no migration, no cleanup; old behavior returns instantly from the first reverted commit. Phase 5 docs revert trivially.

## Feature flag decision

**Unconditional** — no env flag. Justifications: (1) derived-state gate is migration-free and trivially reversible; (2) the current silence is a live trust bug for every enabled account; (3) a data-path env gate would need parallel reads in listener + processor and generate split configs. If product ever wants an escape hatch, add `ENV['CHATWOOT_AI_DISABLE_HUMAN_TAKEOVER_STOP']` inside `HumanTakeover.stopped?` only (a single read point).

---

## Verified Facts vs Assumptions

| # | Statement | Status |
|---|---|---|
| 1 | Human assignment never leaves an `assignee` that is the bot; bot sets `assignee_id: nil` | VERIFIED (`assignment_service.rb:16-30`, `conversation.rb:270-274`) |
| 2 | `first_reply_created_at` only ever set by human messages; never cleared | Verified (message.rb:249-258,406-408; no reset path) |
| 3 | No EE overlay on the 3 touched classes | Verified (grep `enterprise/`) |
| 4 | Auto-assign writes the same `assignee` column | Verified (`agent_assignment_service.rb:11-13`) |
| 5 | `assignee_id` travels through Assign API | Verified (assignments_controller.rb:16) |
| 6 | Local dev has zero "online" agents (redis tracker) → cannot-assign branch dominates demos | Verified (`agent_assignment_service.rb:18-29` reads `OnlineStatusTracker`) |
| 7 | No non-human path sets `first_reply_created_at` (templates, campaigns, email) | **ASSUMED** — phase 1 gate check; if disproven, switch predicate to a `User`-sender scope |
| 8 | The round-robin assignment `find_assignee` respects inbox team/capacity limits as existing auto-assign does | Assumed (uses same service as production) |

**Gate:** No CRITICAL/HIGH assumptions remain unresolved: item 7 is verified in Phase 1 before anything else depends on it (`grep` + one spec flip is enough).

---

## Invariants (must not change)

| Invariant | Why | How to verify |
|---|---|---|
| Webhook non-AI agent bots still receive events (incl. human-assigned convs; incl. both bots when both configured) | public contract; existing spec `listeners/agent_bot_listener_spec.rb:31-69` | preserved by Phase 3 spec + full listener suite |
| `ai_handoff_completed` flag semantics unchanged for its consumers (`AutomaticLearningCapture:31`, `QualitySummary:85`, `Usage::Limiter:163`) | learning/analytics treat it as "AI handed off" | no writer touched except HumanHandoff + usage limiter (existing ones); no new writer |
| `human_handoff` tool: result shape, `error_code`, terminal `handoff_already_completed`, exactly-once effects | customer promise + orchestrator idempotency | `spec/services/ai_agents/tools/human_handoff_service_spec.rb` (existing + new) |
| Duplicate-delivery idempotency: `ResponseBuffer.claim!` + `response_already_persisted?` unchanged | double-trunk delivery | existing specs still green (both delivery, same-message-twice) |
| No use of `waiting_since` or status fields in the gate | auto-resolve scopes; separation from Captain semantics | grep in final diff |
| `test_mode` (simulator) handoff returns before any assignment attempt | simulator must not mutate conversations | existing `test_mode?` early return stays first |
| `first_reply_created_at` remains set after handoff / assignment | - | no code path writes it besides message creation; unchanged |

---

## Validation matrix

| Check | Command | Proves |
|---|---|---|
| Gate unit | `bundle exec rspec spec/services/ai_agents/human_takeover_spec.rb` | predicate truth table + session semantics |
| LiveProcessor | `bundle exec rspec spec/services/ai_agents/live_processor_spec.rb` | stop on assignee/reply; still replies otherwise; duplicate-safety |
| Listener | `bundle exec rspec spec/listeners/agent_bot_listener_spec.rb` | schedule gate + webhook preservation |
| Handoff | `bundle exec rspec spec/services/ai_agents/tools/human_handoff_service_spec.rb` | assign + cannot-assign + no double note + test_mode |
| Full AiAgents | `bundle exec rspec spec/services/ai_agents spec/services/ai_agents/usage spec/listeners` | no regressions |
| Style | `bundle exec rubocop -a app/services/ai_agents/human_takeover.rb app/services/ai_agents/live_processor.rb app/listeners/agent_bot_listener.rb app/services/ai_agents/tools/human_handoff_service.rb` (+ the four touched spec files) | lint |

**Manual/API verification recipe** (dev runtime per AGENTS.md — `pnpm dev` or PM2 host; docker PG/Redis):
1. Seed an account with an AI-enabled inbox; via `web widget` send "Hello" → expect AI reply.
2. **Assign**: `POST /api/v1/accounts/{id}/conversations/{id}/assignments?assignee_id=USER&assignee_type=User` (controller at `assignments_controller.rb`). Customer sends "follow up" → assert no new `AgentBot`-sender outgoing row (`conversation.messages.reload.where(sender_type: 'AgentBot').count` unchanged) and no new `AiAgentLlmCall` row.
3. **Unassigned + human reply**: fresh conversation; an agent replies once (never assigned); customer replies again → same no-AI assertions as step 2.
4. **Handoff**: trigger message forces `human_handoff`; with no online agent in dev, expect `ai_handoff_completed=true`, status "open", and exactly one new private note containing `handoff_not_assigned_note`; subsequent customer message → no reply.
5. **Sanity**: brand-new conversation, no human actions → AI replies and catalog/options flow still works (`AiAgentToolExecution` rows for ikas tools appear).

---

## Evidence Owners

| Item | Owner | Proof |
|---|---|---|
| Gate truth table + assumption #7 verified | @implementer (Phase 1) | grep output + `human_takeover_spec` green |
| Processor/listener silence + reply-when-free | @implementer (Phases 2-3) | specs + API recipe steps 2/3 |
| Webhook bots unaffected | @implementer (Phase 3) | listener spec suite |
| Handoff terminal + cannot-assign note + one-note idempotency | @implementer (Phase 4) | handoff spec suite |
| Docs parity | @implementer (Phase 5) | diff review by @planner |

## Review Gates

| Gate | After | Focus |
|---|---|---|
| G1 | Phase 1 | predicate truth table; unassign/resume semantics; assumption #7 evidence shown |
| G2 | Phases 2-3 | both layers consistent; zero regressions in existing suites |
| G3 | Phase 4 | no contract change for handoff; note added at most once; rescue keeps handoff non-failing |
| G4 | Phase 5 | full targeted suite green; docs drift note correct |

## Failure signals

- Any pre-existing handoff spec regresses (idempotency/assignment ordering) → stop Phase 4, recheck.
- LiveProcessor replies while `assignee_id` is set (spec red) → Phase 2 gate placement defect.
- Assumption #7 disproven → predicate swap documented before release.
- Webhook bots stop on assigned convs (spec red) → revert Phase 3 gate only.

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Non-human path sets `first_reply_created_at` (item 7) | LOW | MED — bot silently mute | Phase-1 verify; fallback predicate listed |
| Round-robin auto-assign at handoff picks suboptimal agent vs. manual assist | MED | LOW | best-effort once; rescue guarded; skip when already assigned |
| Dev-local cannot-assign dominance | HIGH | LOW | note is the proof; specs stub both lanes; production has online agents |
| Race: assignment between enqueue and job execution | MED | LOW | execution-time gate in LiveProcessor; buffer idempotency kept |
| Future EE overlay reformats "stopped" logic | LOW | MED | single module documented as THE seam |
| Voice conference auto-assign (EE) after handoff — assignment attempt inside quests | LOW | LOW | guard `assignee.present?` + `assignee_agent_bot_id.present?` skips |

## Notes / Scope control

- NO new DB columns, NO migration, NO schema change; existing columns only.
- NO `waiting_since` or status coupling — pending gate remains an EE/Captain concept.
- Keep the inbox-level bot path + new gate (drift note); restoring "assignee-only" AI is out of scope (documented decision).
- `ai_handoff_completed` semantics + key name preserved; not merged with anything new.
- Only `config/locales/en.yml` + `tr.yml` edited (AGENTS rule; other locales via Crowdin).
- `HumanHandoffService` is the single writer of the cannot-assign note (listener/orchestrator never writes notes).
- Docs authority: `docs/ai-agent-catalog-runtime.md` stays the runtime authority; this plan is its design record until shipped (per its line 3).

## Decision Log

| Decision | Chosen | Rejected | Rationale |
|---|---|---|---|
| Gate mechanism | Derived check on `assignee_id`, `last first_reply_created_at`, `ai_handoff_completed`; single `AiAgents::HumanTakeover` module | new attribute / `ai_handoff` reuse / pending-status | no write-path races; covers every assignment route; zero migration; EE-neutral |
| Gate locations | Listener (schedule) AND LiveProcessor (execute) | only one layer | job/assignment race + enqueue hygiene |
| Stop mode | reply ⇒ permanent; assign-only ⇒ session; handoff ⇒ permanent | always-permanent on assignee | unassign-without-reply must return to bot (only coherent semantic) |
| Cannot-assign | stay stopped + single private note | resume bot; retry loop | customer promise + idempotency + cost |
| Assignment attempt | `AutoAssignment::AgentAssignmentService` on `inbox.available_agents` | new picker | existing infra, one call, guard rescue |
| Feature gate | unconditional | env flag | migration-free, reversible, single code path |
| Drift note | keep inbox path + new gate now; restore-only note | restore-assignee-in-this-plan | unrelated product decision (YAGNI) |