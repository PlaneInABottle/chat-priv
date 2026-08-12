# AI Agent Live Response Context Limits — Implementation Plan (v2: two-level config + customer UX)

## Problem Statement

The existing fixed 24-hour per-contact AI usage window (`AiAgentUsageEvent`) bounds *conversations* for the monthly freemium quota but places no per-window limit on how many customer-visible AI responses one contact can consume, and the live LLM history projection is unbounded in characters (up to 150,000 chars per message × messages). This plan adds a **50 successfully customer-visible AI responses per 24h window** cap (global Super Admin default, per-account Super Admin override), a one-time deterministic customer warning after the 45th counted response, a deterministic terminal handoff on the would-be 51st trigger (no LLM call), raises live history from 12 → 20 logical messages, and adds a deterministic, UTF-8/grapheme-safe character budget projection for LLM history. DB message content is never modified. Normal account owners/admins get no view or write access to the override.

## Approach

Three coupled changes:
1. **Two-level configuration**: global `InstallationConfig` key `AI_AGENT_RESPONSE_LIMIT_PER_WINDOW` (default 50, editable in Super Admin `ai_agents` app config group, applies dynamically to all accounts without override) + per-account override `ai_agent_response_limit_per_window` (nullable: blank = inherit global, 0 = unlimited override, positive = exact override; editable only in the Super Admin Account dashboard). Resolution: override → global → hard fallback 50; malformed/negative values never resolve to unlimited.
2. **Counted-response state machine**: dedicated reservation table `ai_agent_response_slots` keyed uniquely by `(ai_agent_usage_event_id, trigger_message_id)` with statuses reserved/consumed/released/handed_off, all transitions serialized under the existing usage-event row lock. `AiAgents::ResponseWindow` owns reserve/consume/release/warning/terminal-handoff; `AiAgents::Usage::Limiter` is extended only to create/reuse the window event when the effective limit is active (including monthly-unlimited accounts).
3. **History projection**: `AiAgents::ConversationHistoryProjector` applies conservative character budgets after compaction, before the orchestrator (12 → 20 messages, 8,000 chars/message, 40,000 total).

Counters alone cannot prove idempotency under duplicate/overlapping jobs — evidence below; hence the dedicated model. The warning and terminal messages are deterministic backend messages via `Messages::MessageBuilder` (no LLM/tool, never counted), with internal metadata under `content_attributes.ai_agent.system_notice` that is stripped from every public serializer.

## Success Criteria

- [ ] A contact in one 24h window receives at most 50 normal public AgentBot responses; the 50th is the last; the next eligible trigger yields exactly one deterministic public handoff message + one private note, `ai_handoff_reason: ai_response_limit_exhausted`, `bot_handoff!`, and **zero LLM/tool calls**. Terminal delivery is exactly-once **per trigger** (marker) and exactly-once **per conversation** (in-lock `handoff_completed?` re-check) under concurrency.
- [ ] Exactly one deterministic public warning (user-approved copy, no quota/token language) is delivered after the 45th counted response persists; warning/terminal messages never count toward the 50.
- [ ] Global default 50 applies to **all** accounts without override, immediately and dynamically (no signup-time write); per-account override (blank = inherit, 0 = unlimited, positive = exact) wins; malformed/negative values fall back to global; global 0 disables the limit.
- [ ] Normal account owners/admins cannot view or change the override: no API write path (existing permitted-settings list), no API read exposure (filtered from account serializer), no dashboard UI outside Super Admin.
- [ ] Counter is shared across all conversations of the contact in the active window; a new 24h event resets the counter; sticky per-conversation `ai_handoff_completed` behavior preserved.
- [ ] Duplicate/retried jobs never produce a second response, warning, or terminal delivery; slot release is decided by the **slot row's own state** (`slot&.reserved?`) — including `:reused` slots whose job then fails — never by result/limiter status; a trigger with an existing `handed_off` marker is never sent to the LLM again (`reserve!` → `:exhausted`) and `consume!` never transitions `handed_off`.
- [ ] `HISTORY_MESSAGE_LIMIT` = 20, `RAW_HISTORY_MESSAGE_LIMIT` = 60; oversized history projection truncated deterministically (8,000/40,000 chars, marker in budget, grapheme-safe); DB content untouched.
- [ ] Migration expand-only (standalone `trigger_message_id` index included); clean apply, upgrade-path, repeat-run, rollback verified on a disposable DB; `db/schema.rb` + annotations aligned; OSS + Enterprise Super Admin app-config pages expose the global key with loader/controller specs.

---

## Configuration Architecture (decisions)

**Global key**: `AI_AGENT_RESPONSE_LIMIT_PER_WINDOW`
- `config/installation_config.yml` entry in the "Kozmopath AI Agent Config" block (after `AI_AGENT_RESPONSE_BUFFER_SECONDS`, verified pattern at `installation_config.yml:184-189`): `display_title: 'AI Agent Response Limit Per Window'`, `description: 'Maximum AI responses a customer can receive within one reuse window. Set to 0 to disable the limit for all accounts; accounts with a per-account override are unaffected.'`, `value: 50`, `locked: false`. No `type` → generic text field with description paragraph in the Super Admin view (`show.html.erb:57-64` renders description; default branch renders `form.text_field`).
- Added to the OSS `ai_agents` allowlist (`app/controllers/super_admin/app_configs_controller.rb:53`). Enterprise falls through to `super` for the `ai_agents` group (`enterprise/app/controllers/enterprise/super_admin/app_configs_controller.rb:4-19` — no `when 'ai_agents'` case), so no Enterprise code change; the Enterprise spec must assert exposure. The key is NOT added to `InstallationConfig::RESTART_REQUIRED_CONFIG_KEYS` (`installation_config.rb:24-29`) → `after_commit :clear_cache` (`installation_config.rb:46,64-66`) makes the new value apply on the next request without restart.
- Reader: `AiAgents::Settings.response_limit_per_window` — `Integer(GlobalConfig.get_value(KEY), exception: false)`; nil/negative/garbage → 50; explicit `0` → 0 (documented disable). Malformed can never accidentally produce unlimited.
- ConfigLoader creates the row on boot with value 50 (`spec/lib/config_loader_spec.rb:19-25` pattern); before the row exists, `GlobalConfig.get_value` → nil → hard fallback 50 (consistent default).

**Account override**: `ai_agent_response_limit_per_window` (JSON settings key, nullable integer/string)
- Raw reader `Account#ai_agent_response_limit_per_window` (overrides the `store_accessor` method, mirroring `ai_agent_conversation_limit` at `account.rb:234-236`): blank/`""`/negative/non-integer → nil (inherit); explicit `0` → 0 (unlimited override); positive → int.
- Effective reader `Account#effective_ai_agent_response_limit_per_window`: `ai_agent_response_limit_per_window || AiAgents::Settings.response_limit_per_window`. Used by `ResponseWindow` and `Limiter`.
- Settings schema: `'ai_agent_response_limit_per_window': { 'type': %w[integer string null] }` (`account_settings_schema.rb:21` block pattern).
- **No signup-time write** (AccountBuilder unchanged; prior freemium-default design removed — inheritance makes global apply to everyone). Existing freemium accounts are affected by the global default automatically; the earlier fingerprint-backfill runner is **removed**.
- **Visibility control**: `app/views/api/v1/models/_account.json.jbuilder:1` currently dumps `json.settings resource.settings` (account show/update responses) — change to `json.settings resource.settings.except('ai_agent_response_limit_per_window')` so account owners cannot read the override via API. Write path is already closed: `Api::V1::AccountsController#permitted_settings_attributes` (`accounts_controller.rb:116-124`) never includes AI settings keys — add a negative spec. Enterprise account partial (`enterprise/app/views/enterprise/api/v1/accounts/partials/_account.json.jbuilder`) only adds `subscribed_features` — no settings dump, no change needed.
- Super Admin surfaces (only): `AccountDashboard` permitted `ai_agent_settings` keys (`account_dashboard.rb:140`) + `AccountAiAgentSettingsField` partials (`_form.html.erb`, `_show.html.erb`), all under `SuperAdmin::ApplicationController` (`before_action :authenticate_super_admin!`, `application_controller.rb:14`).

**Warning threshold**: derived from the **effective** limit: `limit > 5 ? limit - 5 : 0`; warning fires exactly when consumed count == threshold (> 0). No warning for limits 1–5 (avoids immediate noise; simplest). No separate global warning config (YAGNI). Remaining is always 5 by construction → user-approved copy hardcodes "5", no interpolation.

---

## Milestone 1: Configuration, Schema, and Slot Model
**Owner**: @implementer (backend)
**Dependencies**: None
**Complexity**: MEDIUM
**Milestone Gate**: `MILESTONE` — config loader/controller specs (OSS + Enterprise), account resolution specs, Super Admin field specs, account-API negative specs, migration matrix, model specs all green.

### Subphase 1.1: Global config key
- [ ] `config/installation_config.yml`: add `AI_AGENT_RESPONSE_LIMIT_PER_WINDOW` entry (display_title, description with "0 disables", value 50, locked false) after line 189.
- [ ] `app/controllers/super_admin/app_configs_controller.rb:53`: add `AI_AGENT_RESPONSE_LIMIT_PER_WINDOW` to the `ai_agents` allowlist.
- [ ] `app/services/ai_agents/settings.rb`: add `RESPONSE_LIMIT_PER_WINDOW_KEY = 'AI_AGENT_RESPONSE_LIMIT_PER_WINDOW'`, `DEFAULT_RESPONSE_LIMIT_PER_WINDOW = 50`, and `response_limit_per_window` reader (nil/negative/garbage → 50; 0 → 0).
- [ ] Specs:
  - `spec/lib/config_loader_spec.rb`: new assertion (pattern lines 19-25) — loader creates `AI_AGENT_RESPONSE_LIMIT_PER_WINDOW` with value 50, locked false.
  - `spec/controllers/super_admin/app_config_controller_spec.rb`: extend "shows AI Agent settings on the ai_agents app_config page" (lines ~30-39) to include the new key; add POST update test (pattern of the Enterprise POST test) asserting a changed value persists; assert the key is absent on the `captain` page (pattern lines 40-46).
  - `spec/enterprise/controllers/super_admin/app_config_controller_spec.rb`: add "shows the AI response limit on the ai_agents app_config page" + POST update (mirror of the buffer tests at lines 8-25); `ChatwootHub.pricing_plan == 'premium'` stub already present.
  - `spec/services/ai_agents/settings_spec.rb`: resolution cases (nil → 50, 50 → 50, 0 → 0, -5 → 50, 'abc' → 50, '0' → 0).

### Subphase 1.2: Account override + Super Admin field + API hiding
- [ ] `app/models/account.rb`:
  - Add `:ai_agent_response_limit_per_window` to the `store_accessor` (line 76 block).
  - Raw override reader `ai_agent_response_limit_per_window` (nil/blank/negative/garbage → nil; 0 → 0; positive → int) — mirrors `ai_agent_conversation_limit` pattern (lines 234-236).
  - `effective_ai_agent_response_limit_per_window` = override || `AiAgents::Settings.response_limit_per_window`.
  - Add `response_limit_per_window` to `ai_agent_settings` hash (line ~201) and setter (line ~211).
- [ ] `app/models/concerns/account_settings_schema.rb`: add the key (integer/string/null).
- [ ] `app/views/api/v1/models/_account.json.jbuilder:1`: `json.settings resource.settings.except('ai_agent_response_limit_per_window')`.
- [ ] Super Admin dashboard (field conventions verified: `app/fields/account_ai_agent_settings_field.rb`, `app/views/fields/account_ai_agent_settings_field/_form.html.erb` with `.ai-agent-settings-control__hint` hint spans at lines 33/42/53, `_show.html.erb` with "Unlimited" convention at line 13):
  - `app/dashboards/account_dashboard.rb:140`: add `response_limit_per_window` to permitted `ai_agent_settings` keys.
  - `_form.html.erb`: number control after the `conversation_limit` control — `number_field_tag "#{field.html_name}[response_limit_per_window]"`, value `field.resource.ai_agent_response_limit_per_window` (nil → blank input = inherit), `min: 0`, `step: 1`; hint span: locale key `response_limit_hint` ("Blank = inherit the global default. 0 = unlimited.").
  - `_show.html.erb`: new row after "Monthly conversation limit": raw override (blank → "Inherit (global default: %{global})" using `field.resource.effective_ai_agent_response_limit_per_window`; 0 → "Unlimited"; else number).
  - Locale keys in `config/locales/{en,tr}.yml` under `super_admin.account_ai_agent_settings`: `response_limit_per_window` ("AI responses per 24-hour window" / TR), `response_limit_hint`, `response_limit_inherit` ("Inherit (global default: %{global})" / TR). The label includes no global value; the hint covers blank semantics.
- [ ] Specs:
  - `spec/models/account_spec.rb`: raw reader cases (absent → nil, `''` → nil, 0 → 0, 30 → 30, -5 → nil, 'abc' → nil); effective reader (no override + global 50 → 50; override 30 → 30; override 0 → 0; global nil → 50; global garbage/negative → 50); `ai_agent_settings` round-trip includes the key.
  - `spec/controllers/super_admin/accounts_controller_spec.rb`: permitted params persist the override (pattern lines 474-510); blank value → inherit (nil in settings).
  - `spec/controllers/api/v1/accounts_controller_spec.rb` (negative tests): `GET /api/v1/accounts/:id` response `settings` does **not** include `ai_agent_response_limit_per_window`; `PATCH/POST` with `settings[ai_agent_response_limit_per_window] = 30` is ignored (existing permitted-settings list unchanged; assert settings hash unchanged).
- [ ] Remove stale items from the previous plan: NO AccountBuilder change, NO `FREEMIUM_AI_AGENT_RESPONSE_LIMIT_PER_WINDOW` constant, NO backfill runner, NO `spec/builders/account_builder_spec.rb` change (it must stay exactly as-is; its assertions at lines 91-93/110-115 remain valid untouched).

### Subphase 1.3: Migration + slot model
- [ ] Create `db/migrate/20260812120000_create_ai_agent_response_slots.rb` (timestamp > latest baseline `20260809010000` — verified via `ls db/migrate | sort | tail`; expand-only, additive):
  - `create_table :ai_agent_response_slots` with `t.references :ai_agent_usage_event, null: false, foreign_key: { on_delete: :cascade }`; `t.references :trigger_message, null: false, foreign_key: { to_table: :messages, on_delete: :cascade }`; `t.integer :status, null: false, default: 0`; `t.timestamps`.
  - Unique index `idx_ai_agent_response_slots_on_event_trigger (ai_agent_usage_event_id, trigger_message_id)` (idempotency boundary); index `idx_ai_agent_response_slots_on_event_status (ai_agent_usage_event_id, status)`; **standalone index `index_ai_agent_response_slots_on_trigger_message_id (trigger_message_id)`** (FK lookup + trigger-scoped queries).
  - `add_column :ai_agent_usage_events, :response_limit_warning_sent, :boolean, null: false, default: false`.
- [ ] `app/models/ai_agent_response_slot.rb`: belongs_to event + trigger_message (Message); `enum status: { reserved: 0, consumed: 1, released: 2, handed_off: 3 }`; scopes `active` (reserved|consumed), `consumed`, `for_trigger`; status presence; trigger-account validation (event pattern `ai_agent_usage_event.rb:49-78`).
- [ ] `app/models/ai_agent_usage_event.rb`: `has_many :response_slots, dependent: :destroy`.
- [ ] `rbenv exec bundle exec annotaterb --models` (verify CLI first via `--help`) — schema.rb + annotation headers aligned.
- [ ] Disposable-DB migration matrix (load `database-migration-testing`; never shared DB): clean apply; upgrade path (move migration out → `db:migrate` baseline → restore → `db:migrate`); repeat-run no-op; `db:rollback STEP=1` then re-migrate; psql verification of **all three indexes** (unique `(event, trigger)`, `(event, status)`, standalone `trigger_message_id`), FKs (`ON DELETE CASCADE`), column default.
- [ ] `spec/models/ai_agent_response_slot_spec.rb`: unique index enforced; status enum; FK cascade; trigger-account validation.

### Acceptance Criteria
- [ ] Global config visible/editable in OSS + Enterprise Super Admin, loader default 50, dynamic application without restart.
- [ ] Override resolution exact (inherit/0/positive/malformed), API read+write hidden from account owners, Super Admin-only surfaces.
- [ ] Migration verified on disposable DB; no production data altered; no AccountBuilder/freemium changes anywhere.

---

## Milestone 2: Response Window State Machine + Customer UX Integration
**Owner**: @implementer (backend)
**Dependencies**: Milestone 1
**Complexity**: HIGH
**Milestone Gate**: `MILESTONE` — state machine + LiveProcessor suites green incl. 45/50/51, warning-once, terminal-once (per trigger + per conversation), reused-slot release, handed_off semantics, cross-conversation, monthly precedence, channel notice shape; **FULL @analyzer review (Gate 1)** (customer-visible contract + concurrency).

### Subphase 2.1: `AiAgents::ResponseWindow` service
- [ ] Create `app/services/ai_agents/response_window.rb` (explicit plumbing: every call passes `event:` + `slot:`/`trigger_message_id:`; results carry the slot; no implicit reads of `@message` inside state transitions):
  - `Result = Struct.new(:status, :event, :slot, keyword_init: true)`; statuses `:inactive | :reserved | :reused | :exhausted`; `limit` = `account.effective_ai_agent_response_limit_per_window`; `warning_threshold = limit > 5 ? limit - 5 : 0`.
  - `reserve!(event:, trigger_message_id: message.id)` (only when `event` present and `limit.positive?`): `event.with_lock` → `slot = event.response_slots.find_or_initialize_by(trigger_message_id: trigger_message_id)`;
    - `slot.persisted? && slot.handed_off?` → `Result(:exhausted, event:)` — a trigger whose terminal handoff was already delivered must never run the LLM again (duplicate/retry of a terminal trigger returns to `exhausted_handoff!`, which finds the marker and no-ops);
    - `slot.persisted? && slot.released?` → atomically re-reserve under the event lock: `event.response_slots.active.count >= limit` → `Result(:exhausted, event:, slot:)` (only this exhausted released row stays untouched); else `slot.update!(status: :reserved)` → `Result(:reserved, event:, slot:)` — the row is active again, so two concurrent released retries at 49 can never both pass and later consume beyond the limit;
    - `slot.persisted?` (reserved/consumed) → `Result(:reused, event:, slot:)` (duplicate/retry proceeds; consume/release transition the same row — preserves today's crash-retry robustness);
    - else `active = event.response_slots.active.count`; `active >= limit` → `Result(:exhausted, event:)` (no marker created here — marker is created atomically with terminal delivery); else `slot.update!(status: :reserved)` → `Result(:reserved, event:, slot:)`.
  - `consume!(event:, slot:)`: `event.with_lock`; `slot.reload`; `reserved? || released?` → `consumed`; **`handed_off?` slots are never transitioned by `consume!` (terminal markers are consumed only by `exhausted_handoff!`); no-op otherwise**; then `maybe_send_warning!(event)`: consumed count == `warning_threshold` (> 0) and `!event.response_limit_warning_sent?` → set flag + persist warning message (2.2) — all in the same transaction as the consuming response.
  - `release!(event:, slot:)`: `event.with_lock`; `slot.reload`; `reserved?` → `released`; no-op otherwise (including `handed_off`).
  - `exhausted_handoff!(event:)`: **lock order conversation → event** (invariant; see below): `conversation.with_lock { return false if handoff_completed?(conversation); event.with_lock { event.reload; marker = event.response_slots.find_or_initialize_by(trigger_message_id: message.id); return false if marker.persisted?; marker.update!(status: :handed_off); deliver_terminal! } }` — the in-lock `handoff_completed?` re-check (sticky `ai_handoff_completed` attribute) makes concurrent **same-conversation** triggers at the boundary produce exactly one public terminal delivery (both pass `ReplyPolicy` before either delivers; the conversation row lock serializes them; the loser sees the committed flag and no-ops); the marker makes duplicate/retry jobs of the **same trigger** exactly-once; marker + delivery in ONE transaction.
- [ ] `app/services/ai_agents/usage/limiter.rb` minimal extension:
  - `unlimited?` (line 91) → `limit.zero? && account.effective_ai_agent_response_limit_per_window.zero?`.
  - `monthly_limit_active?` = `limit.positive?`; guard the `active_usage_count >= limit` check (line 32) with it (monthly-unlimited accounts must not always exhaust).
  - Everything else (event creation/reuse, `consume!`, `release!`, `exhausted_handoff!`, summary payload) untouched → monthly contract preserved.
- [ ] **Known spec impact**: with global default 50 effective, monthly-unlimited test accounts now create events and slots. Update `spec/services/ai_agents/usage/limiter_spec.rb` `:unlimited` expectations (e.g., line 66 area) to set `ai_agent_response_limit_per_window: 0` or stub `AiAgents::Settings.response_limit_per_window` to 0; `spec/services/ai_agents/live_processor_spec.rb` default-account cases remain valid (assertions are message/attr-based) but verify event counts where asserted.

### Subphase 2.2: LiveProcessor integration + deterministic notice messages
- [ ] `app/services/ai_agents/live_processor.rb#perform` (lines 11-30) — named plumbing; `response_window` memoized like `usage_limiter` (line 154); `window_result` always carries `event` + `slot` (nil slot only for `:inactive`/`:exhausted`):
  ```ruby
  usage_result  = usage_limiter.reserve!
  return handle_usage_exhausted!(usage_result) if usage_result.exhausted?           # monthly precedence unchanged

  window_result = response_window.reserve!(event: usage_result.event, trigger_message_id: message.id)
  return handle_response_limit_exhausted!(window_result) if window_result.exhausted? # deterministic terminal, no LLM/tools
  # ... orchestrator_result, persist_assistant_response!/consume_usage! as today ...
  rescue StandardError
    response_window.release!(event: usage_result.event, slot: window_result&.slot) if window_result&.slot&.reserved?
    usage_limiter.release!(usage_result&.event) if usage_result&.reserved?
    raise
  end
  ```
  - **Release decision is always `window_result&.slot&.reserved?` (the slot row's own state) — never `window_result&.reserved?` (result status) and never the limiter/usage result status.** A `:reused` result still carries a `reserved` slot from the first attempt; if the reused job then fails (e.g., adapter error), that slot must be released. `ResponseWindow#release!` re-checks `slot.reserved?` under the event lock as its internal guard.
  - `consume_usage!` (line 163): in the `assistant_message.present? || handoff_result?` branch also `response_window.consume!(event: usage_result.event, slot: window_result.slot)` (only when slot present); in the release branch (blank result, not handoff) also `response_window.release!(event: usage_result.event, slot: window_result.slot) if window_result&.slot&.reserved?`. Handoff-tool turns count 1 (matches existing event-consume semantics); catalog presentations count 1 per trigger.
- [ ] **Warning message** (`Messages::MessageBuilder`, public AgentBot message, same conversation/inbox — normal outbound delivery path):
  - Content: `I18n.t('ai_agents.response_limit_warning', locale: conversation.account.locale)` — **user-approved verbatim**:
    - EN: `This conversation has been going for a while. I can provide 5 more responses, then I’ll hand the conversation over to our team.`
    - TR: `Bu görüşme oldukça uzadı. Size 5 yanıt daha verebilirim; ardından konuşmayı ekibimize aktaracağım.`
  - No quota/token/internal language; "5" is hardcoded (remaining is always 5 by construction).
  - `content_attributes: { ai_agent: { system_notice: { type: 'response_limit_warning', limit: effective_limit, remaining: 5 } } }` — **verified safe**: `Message#public_content_attributes` (`message.rb:211-224`) deletes `ai_agent` unless it contains `selection.version`, and the widget/dashboard/webhook serializers all use it (`_widget_message.json.jbuilder:5`, `_message.json.jbuilder:9`, `message.rb:158,194`) → the notice renders as plain text everywhere, metadata is never customer-visible. No usage-event id (minimal shape per requirement).
  - No `ai_agent.trigger_message_id` → `response_already_persisted?` (`live_processor.rb:145-152`) never matches it; no count.
  - Exactly-once logical vs physical: the message insert + `response_limit_warning_sent` flag commit in the same DB transaction as the 45th response's consume; job retry rolls back and redoes; after commit, channel delivery (e.g., WhatsApp provider window) is asynchronous — a physical delivery failure never blocks counting and never retries the job. No duplicates.
- [ ] **Terminal messages** (would-be 51st trigger):
  - Public message (same channel, normal text) — **user-approved verbatim**:
    - EN: `This conversation has reached its AI response limit. Our team will take over from here.`
    - TR: `Bu görüşme için yapay zekâ yanıt sınırına ulaştık. Bundan sonra ekibimiz yardımcı olacak.`
  - `content_attributes: { ai_agent: { system_notice: { type: 'response_limit_handoff', limit: effective_limit } } }` (stripped publicly; no trigger id).
  - Private note (diagnostic, internal; includes window reset but NO customer-facing reset promise): EN `AI response limit reached for this conversation (limit: %{limit}, used: %{used}). Window resets at %{reset_at}. Conversation handed off to a human agent. Reason: ai_response_limit_exhausted.` + TR equivalent (maintained locales).
  - Conversation attributes (mirror `Limiter#exhausted_attributes` at `limiter.rb:150-160`): `ai_handoff_completed`, `ai_handoff_at`, `ai_handoff_by_ai_agent_id`, `ai_handoff_message_id` (trigger), `ai_handoff_reason: 'ai_response_limit_exhausted'`, `ai_response_limit_exhausted: true`; then `conversation.bot_handoff!` (`conversation.rb:183`). No auto-assignment (parity with monthly `exhausted_handoff!`).
  - **Ordering/failure semantics** (single transaction under `conversation.with_lock` then `event.with_lock`: in-lock `handoff_completed?` re-check → marker create (`handed_off`) → public message → private note → conversation attrs → `bot_handoff!`): any DB failure rolls back everything → job retry redoes exactly once (the re-check + marker both roll back); after commit, channel delivery failure (WhatsApp) is out of band — conversation state + private note already committed, human handoff safe, no retry loop.
  - Locale keys in `config/locales/{en,tr}.yml` `ai_agents:` block (maintained sources only, aligned keys; existing block at `en.yml:34-40`, `tr.yml:21-23`): `response_limit_warning`, `response_limit_handoff_message`, `response_limit_handoff_note`.

### Subphase 2.3: State machine + integration specs
- [ ] `spec/services/ai_agents/response_window_spec.rb` (new): reserve/consume/release transitions; threshold rule (limit 50 → warning at 45 with `remaining: 5`; limit 6 → 1; limit 5 and 3 → no warning ever); warning exactly once + flag; `:reused` duplicate single row; released→consumed retry; `:inactive` when effective limit 0; `exhausted_handoff!` exactly-once per trigger (second call false); independent markers per trigger; **existing `handed_off` slot → `reserve!` returns `:exhausted` and `consume!`/`release!` are no-ops (never transition `handed_off`)**; **concurrent same-conversation triggers → second `exhausted_handoff!` no-ops on the in-lock `handoff_completed?` re-check**; `system_notice` shape assertions (type/limit/remaining, no trigger id, no event id); `public_content_attributes` of the notice message strips `ai_agent`.
- [ ] `spec/services/ai_agents/usage/limiter_spec.rb`: update `:unlimited` cases for effective-limit semantics (override 0 / stubbed global 0); monthly 0 + effective 50 → event created/reused, never monthly `:exhausted`.
- [ ] `spec/services/ai_agents/live_processor_spec.rb` (extend): 45th → exactly 1 warning (public, copy assertions EN/TR via account locale), consumed count 45, no LLM for the warning; 51st → no `adapter.perform`, 1 public terminal + 1 private note (with `reset_at`), `ai_handoff_reason == 'ai_response_limit_exhausted'`, conversation open, reused event; **`:reused` slot (duplicate/retry of an in-flight or failed trigger) + failing adapter → slot ends `released`, event `released` (new-event case), no message, retry-safe**; monthly exhausted + window open → existing silent monthly handoff (precedence; no terminal message, no slots); same contact second conversation → shared window, per-conversation terminal delivery; catalog multi-message response counts 1; handoff-tool turn counts 1; warning/terminal messages have no `trigger_message_id`.
- [ ] Run: `rbenv exec bundle exec rspec spec/services/ai_agents/response_window_spec.rb spec/services/ai_agents/live_processor_spec.rb spec/services/ai_agents/usage/limiter_spec.rb` + rubocop on touched services.

### Acceptance Criteria
- [ ] 45/50/51 + warning-once + terminal-once (per trigger + per conversation) + reused-slot release on failure + handed_off no-rerun/no-consume + duplicates/retry/release + cross-conversation + monthly precedence proven; notice shape stripped publicly; copy verbatim; state safe under channel delivery failure.

---

## Milestone 3: History Projection (12 → 20 + Character Budgets)
**Owner**: @implementer (backend)
**Dependencies**: None (independent; may run after M1)
**Complexity**: MEDIUM
**Milestone Gate**: `MILESTONE` — projector + updated history specs green; `docs/ai-agent-catalog-runtime.md` updated.

### Subphase 3.1: `AiAgents::ConversationHistoryProjector`
- [ ] Create `app/services/ai_agents/conversation_history_projector.rb`:
  - Constants (**engineering decisions**): `PER_MESSAGE_CHAR_BUDGET = 8_000`, `TOTAL_HISTORY_CHAR_BUDGET = 40_000`, `SHORTENING_MARKER = '[...message shortened for AI context...]'`, `WHITESPACE_SCAN_GRAPHEMES = 200`, head 2/3 – tail 1/3 split.
  - `call`: input = compacted chronological messages (≤ 20, `{role:, content:}` shape per `conversation_history_compactor.rb:22-33`; orchestrator slices only role/content at `orchestrator.rb:169-170`).
  - `truncate_message(content, budget)`: fit → as-is; else head = first `(budget − marker_length) * 2/3` graphemes, tail = last `(budget − marker_length) * 1/3` graphemes, join with marker (marker counts within budget); grapheme-safe via `String#each_grapheme_cluster` (ActiveSupport, runtime-verified with emoji); cut adjusted to nearest whitespace within 200 graphemes when present, then `.strip`; never splits a grapheme cluster.
  - Packing newest→oldest, keep while `accumulated + len ≤ 40_000`; overflow message truncated to remaining budget (or to the total budget if the newest alone exceeds it — one-huge-latest case; older dropped); output restored to chronological order; latest trigger never dropped.
  - Blank/nil content skipped defensively (compactor already rejects blanks).
- [ ] `app/services/ai_agents/live_processor.rb`: line 2 `HISTORY_MESSAGE_LIMIT = 20` (line 3 stays `* MAX_PRODUCTS` → `RAW_HISTORY_MESSAGE_LIMIT = 60`; `MAX_PRODUCTS = 3` verified at `tools/present_catalog_products_service.rb:8`); line 74 → `AiAgents::ConversationHistoryProjector.new(AiAgents::ConversationHistoryCompactor.new(messages).call.last(HISTORY_MESSAGE_LIMIT)).call` (count limit first, then character projection; 21st message dropped by count rule).
- [ ] Update `docs/ai-agent-catalog-runtime.md` (LiveProcessor row + new projector row) — keeps the skill-referenced doc current.

### Subphase 3.2: Projector specs + history spec updates
- [ ] `spec/services/ai_agents/conversation_history_projector_spec.rb` (new): 20 normal messages unchanged; 21 → 20 (oldest dropped); >8,000-char message → head+marker+tail within budget, no grapheme split (emoji `😀`, combining, Turkish `ğışİ`); one 150,000-char latest (Message max, `message.rb:81`) → truncated to total budget, older dropped; huge old + normal newer → old truncated to remaining; total ≤ 40,000; marker counted; compacted group content passes with role/content only; no DB writes (assert no Message/Event rows created/changed).
- [ ] `spec/services/ai_agents/live_processor_spec.rb`: existing constant-based history spec (line 539) stays green; add 25-message → 20 logical entries; 150k-char old message → truncated projection while `Message.find(...).content` remains full.
- [ ] Run: `rbenv exec bundle exec rspec spec/services/ai_agents/conversation_history_projector_spec.rb spec/services/ai_agents/conversation_history_compactor_spec.rb spec/services/ai_agents/live_processor_spec.rb` + rubocop.

### Acceptance Criteria
- [ ] Limit 20 / raw 60; budgets enforced; DB content unmodified; Turkish/emoji/grapheme-safe truncation proven; compaction semantics preserved.

---

## Milestone 4: Integration, Concurrency, Channel, Runtime Evidence
**Owner**: @implementer (backend) + @analyzer (FULL review)
**Dependencies**: M2, M3
**Complexity**: MEDIUM
**Milestone Gate**: `MILESTONE` + **FINAL**: full focused suite + lint + migration matrix re-run + runtime smoke; **FULL @analyzer review (Gate 2)**.

### Subphase 4.1: Concurrency / duplicate-delivery / channel / exposure specs
- [ ] Threaded specs in `spec/services/ai_agents/response_window_spec.rb` (pattern `limiter_spec.rb:227-285`: `use_transactional_tests = false`, `Concurrent::CyclicBarrier`, `thread.join(30)`, ensure-cleanup):
  - 49 consumed + 3 concurrent reservations from 3 conversations → exactly 1 `:reserved`, 2 `:exhausted`; slot count ≤ 50.
  - Two concurrent duplicate jobs, same trigger → one slot row; second `reserve!` → `:reused`.
  - Two concurrent `exhausted_handoff!` calls, **same trigger** → one public message + one private note + one marker (marker is the trigger-level guard).
  - **Two concurrent triggers in the SAME conversation at the boundary (window exhausted) → exactly one public terminal message + one private note total** (conversation row lock serializes; the loser's in-lock `handoff_completed?` re-check no-ops; event markers may exist for both triggers, but only one conversation-level delivery) — conversation open, `ai_handoff_completed` set once.
  - Deadlock guard: concurrent persist path (conversation→event) vs terminal path (conversation→event) for the same conversation → both complete.
- [ ] Duplicate-delivery/idempotency (`async-worker-testing` guidance — assert durable state): simulated WhatsApp double delivery — `LiveProcessor#perform` twice same trigger → 1 response, 1 consumed slot, count +1; warning/terminal duplicates impossible (transactional flag/marker).
- [ ] Channel notice tests: web widget (text render path via `public_content_attributes`), WhatsApp-style channel, API channel — warning/terminal persist as normal public AgentBot messages with content_type text; metadata stripped in `_widget_message.json.jbuilder`/`_message.json.jbuilder` payloads; no `trigger_message_id`.
- [ ] Exposure negative tests: account API read excludes the override key; account API write ignores it (from M1/S1.2 — re-verified here on final code); SuperAdmin dashboard is the only edit surface (`authenticate_super_admin!`).
- [ ] Run: `rbenv exec bundle exec rspec spec/services/ai_agents/response_window_spec.rb spec/services/ai_agents/live_processor_spec.rb spec/controllers/api/v1/accounts_controller_spec.rb`.

### Subphase 4.2: Runtime smoke + full focused validation (FINAL)
- [ ] Bounded runtime smoke (only if local stack available; `chatwoot-ai-agent-local-testing` + `ai-native-workflow` closed loop): PM2/Docker per `chatwoot-ai-native-test`; readiness `curl -sSf http://localhost:3000/health` → `{"status":"woot"}`; Super Admin `/super_admin/app_config?config=ai_agents` shows the new key; one real local incoming message through an AI-agent inbox with **no paid provider** (simulator endpoint `AI_AGENTS_SIMULATOR_*` from `settings.rb:19-29` or RSpec stubs only); verify 1 public message + slot `consumed` + warning/terminal paths via RSpec (no runtime quota burn). If runtime unavailable → explicit `UNVERIFIED`.
- [ ] Full focused suite (independent jobs):
  - `rbenv exec bundle exec rspec spec/services/ai_agents/response_window_spec.rb spec/services/ai_agents/live_processor_spec.rb spec/services/ai_agents/usage/limiter_spec.rb spec/services/ai_agents/usage/summary_spec.rb spec/services/ai_agents/settings_spec.rb spec/services/ai_agents/conversation_history_projector_spec.rb spec/services/ai_agents/conversation_history_compactor_spec.rb spec/models/ai_agent_response_slot_spec.rb spec/models/account_spec.rb spec/controllers/super_admin/accounts_controller_spec.rb spec/controllers/super_admin/app_config_controller_spec.rb spec/enterprise/controllers/super_admin/app_config_controller_spec.rb spec/controllers/api/v1/accounts_controller_spec.rb spec/lib/config_loader_spec.rb`
  - `rbenv exec bundle exec rubocop` on all touched files; `pnpm ruby:prettier` check.
  - Disposable-DB migration matrix re-run on final code.
- [ ] FULL @analyzer review: config resolution + API hiding, migration safety, concurrency/lock-order, customer contract (45/50/51, copy, notice shape), monthly precedence, Enterprise parity (re-verify `rg -n "AiAgents|ai_agent" enterprise/` — no AiAgents overlay expected), spec completeness.

### Acceptance Criteria
- [ ] Concurrency boundary proven with threads; duplicate delivery + channel notice behavior proven; exposure negatives proven; lint clean; migration matrix green; FULL review sign-off.

---

## Verified Facts vs Assumptions

| Item | Verified at | Evidence / Note |
|------|------------|-----------------|
| `LiveProcessor#perform` flow; `response_already_persisted?` matches outgoing AgentBot messages with `ai_agent.trigger_message_id` | `app/services/ai_agents/live_processor.rb:11-30,145-152` | ✅ confirmed |
| `HISTORY_MESSAGE_LIMIT = 12`; RAW = limit × `MAX_PRODUCTS` (3); `.last(limit)` after compactor | `live_processor.rb:2-3,74`; `tools/present_catalog_products_service.rb:8` | ✅ confirmed |
| Compactor output `{role, content, catalog_presentation_id}`; orchestrator slices role/content only | `conversation_history_compactor.rb:22-33`; `orchestrator.rb:169-170` | ✅ confirmed |
| Message max 150,000 chars; `content_for_llm` fallbacks | `app/models/message.rb:81-82,299-310` | ✅ confirmed |
| Completion token limits 2,048 / 4,096 retry / 8,192 cap | `open_ai_compatible_adapter.rb:6-7`; `orchestrator.rb:48` | ✅ confirmed |
| Fixed window semantics, reuse, `account.with_lock` creation, event `with_lock` transitions; enums; `active_for_contact_window` | `app/services/ai_agents/usage/limiter.rb:26-72`; `app/models/ai_agent_usage_event.rb:40-41,54-58` | ✅ confirmed |
| `Limiter#exhausted_handoff!` per-conversation guard + hardcoded EN note; `exhausted_attributes` keys | `limiter.rb:74-81,136-160` | ✅ confirmed (new terminal path: event-guarded, localized) |
| `ReplyPolicy.can_reply?` sticky handoff; `Conversation#bot_handoff!` | `reply_policy.rb:9-16`; `conversation.rb:183-188` | ✅ confirmed |
| ResponseBuffer claim/complete/release; listener → schedule; job → LiveProcessor | `response_buffer.rb:1-61`; `agent_bot_listener.rb:86-92`; `ai_response_job.rb:4-17` | ✅ confirmed |
| InstallationConfig pattern: `AI_AGENT_RESPONSE_BUFFER_SECONDS` block (title/description/value/locked) | `config/installation_config.yml:184-189` | ✅ confirmed |
| OSS Super Admin `ai_agents` allowlist | `app/controllers/super_admin/app_configs_controller.rb:53` | ✅ confirmed |
| Enterprise `allowed_configs` falls through to `super` for `ai_agents` (no override case); captain group mirrors buffer key at line 50 | `enterprise/app/controllers/enterprise/super_admin/app_configs_controller.rb:4-19,43-52` | ✅ confirmed (no Enterprise code change; spec only) |
| ConfigLoader spec pattern ("creates editable … config with default value") | `spec/lib/config_loader_spec.rb:19-25` | ✅ confirmed |
| OSS + Enterprise app-config controller specs patterns (show on `ai_agents`, POST update) | `spec/controllers/super_admin/app_config_controller_spec.rb:30-46`; `spec/enterprise/controllers/super_admin/app_config_controller_spec.rb:8-25` | ✅ confirmed |
| `InstallationConfig#value`, `after_commit :clear_cache`; new key not in `RESTART_REQUIRED_CONFIG_KEYS` → applies without restart | `app/models/installation_config.rb:24-29,46,48-66` | ✅ confirmed |
| `GlobalConfig.get_value` (Redis cache 1 day, DB fallback, boolean-only typecast) | `lib/global_config.rb` (full file read) | ✅ confirmed — integers pass through raw; reader coerces |
| Super Admin auth boundary | `app/controllers/super_admin/application_controller.rb:14` (`authenticate_super_admin!`) | ✅ confirmed |
| Account settings: `store_accessor` + override-reader pattern (`ai_agent_conversation_limit`), `ai_agent_settings` hash/setter, settings JSON schema | `app/models/account.rb:76,201-245`; `account_settings_schema.rb:19-23` | ✅ confirmed |
| **Account API read exposes full settings**: `_account.json.jbuilder:1` `json.settings resource.settings`; rendered by show/update jbuilders; Enterprise partial adds only `subscribed_features` | `app/views/api/v1/models/_account.json.jbuilder:1`; `app/views/api/v1/accounts/{show,update}.json.jbuilder`; `enterprise/app/views/enterprise/api/v1/accounts/partials/_account.json.jbuilder` | ✅ confirmed — hide via `.except(...)` in the OSS partial |
| **Account API write cannot set AI keys**: `permitted_settings_attributes` list | `app/controllers/api/v1/accounts_controller.rb:112-124` | ✅ confirmed — negative test only |
| Existing accounts controller spec patterns | `spec/controllers/api/v1/accounts_controller_spec.rb:107-176` | ✅ confirmed |
| **Public serializers strip `ai_agent` metadata**: `public_content_attributes` deletes `ai_agent` unless `selection.version`; used by dashboard API, widget API, webhooks, push events | `app/models/message.rb:158,194,211-224`; `app/views/api/v1/models/_message.json.jbuilder:9`; `_widget_message.json.jbuilder:5` | ✅ confirmed — `ai_agent.system_notice` is internal-only; plain-text rendering everywhere else |
| SuperAdmin dashboard field conventions: permitted keys, hint spans, show "Unlimited" pattern | `app/dashboards/account_dashboard.rb:136-143`; `app/views/fields/account_ai_agent_settings_field/_form.html.erb:27-34,42-53`; `_show.html.erb:12-13` | ✅ confirmed |
| `ai_agents` locale block EN/TR maintained; super_admin account_ai_agent_settings block | `config/locales/en.yml:34-40,693`; `config/locales/tr.yml:21-23` | ✅ confirmed |
| ActiveSupport `each_grapheme_cluster` works | runtime: `rbenv exec bundle exec ruby -e "require 'active_support/core_ext/string/multibyte'; …"` → `["a","b","😀","c","d","e"]` | ✅ confirmed |
| Spec patterns: threaded reservations, `with_modified_env` (`spec/spec_helper.rb:16`) | `spec/services/ai_agents/usage/limiter_spec.rb:227-285` | ✅ confirmed |
| No Enterprise AiAgents overlay (re-verify at M4) | `rg "AiAgents|ai_agent" enterprise/` → no matches | ✅ confirmed |
| No Ruby tokenizer/tiktoken dependency | repo grep → no matches | ✅ confirmed |
| Allowlisted model ids (7) + defaults; OpenRouter ≥128k for matched ids (3 absent) | `app/models/account.rb:36-45`; coordinator-supplied external evidence | ✅ confirmed / external |
| 50 global default, 45 threshold, 20 history, copy EN/TR, marker text | human product decisions | ✅ **decisions** |
| 8,000/40,000 budgets, 2/3–1/3 split, 200-grapheme whitespace scan | — | ⚠️ **engineering decisions** (rationale below) |
| Global key name `AI_AGENT_RESPONSE_LIMIT_PER_WINDOW`; override semantics (blank=inherit, 0=unlimited) | — | ⚠️ **decisions** (chosen over alternatives in Decision Log) |
| Threshold rule `limit > 5 ? limit - 5 : 0`; no warning for 1–5 | — | ⚠️ **decision** (simplest; exact for 50 → 45) |

**Zero CRITICAL/HIGH unverified assumptions.** All marked items are explicit decisions or LOW-unknown engineering choices.

---

## Budget Rationale (engineering decisions, unchanged)

Known minimum 128k context for matched allowlisted models; 3 allowlisted ids lack metadata → no universal tokenizer/window claim (no tokenizer dependency). Conservative ≈4 chars/token: 40,000 chars ≈ 10,000 tokens ≈ 8% of 128k (≈16% at 2 chars/token) — headroom for system prompt, in-turn tool results, and 8,192-token output. Per-message 8,000 chars ≈ 2,000–4,000 tokens. 2/3–1/3 head/tail split preserves opening context and recent intent; marker (39 chars) counts within budgets. Newest-first packing with the trigger never dropped, then chronological restore. Residual risk (documented): system prompt + tool results are outside this history budget; model-specific adaptation out of scope.

---

## Deliverables

| Milestone / Subphase | Files Created/Modified |
|----------------------|------------------------|
| M1 / S1.1 | `config/installation_config.yml`, `app/controllers/super_admin/app_configs_controller.rb`, `app/services/ai_agents/settings.rb`, `spec/lib/config_loader_spec.rb`, `spec/controllers/super_admin/app_config_controller_spec.rb`, `spec/enterprise/controllers/super_admin/app_config_controller_spec.rb`, `spec/services/ai_agents/settings_spec.rb` |
| M1 / S1.2 | `app/models/account.rb`, `app/models/concerns/account_settings_schema.rb`, `app/views/api/v1/models/_account.json.jbuilder`, `app/dashboards/account_dashboard.rb`, `app/views/fields/account_ai_agent_settings_field/_form.html.erb`, `_show.html.erb`, `config/locales/{en,tr}.yml`, `spec/models/account_spec.rb`, `spec/controllers/super_admin/accounts_controller_spec.rb`, `spec/controllers/api/v1/accounts_controller_spec.rb` |
| M1 / S1.3 | `db/migrate/20260812120000_create_ai_agent_response_slots.rb` (new), `app/models/ai_agent_response_slot.rb` (new), `app/models/ai_agent_usage_event.rb`, `db/schema.rb`, annotations, `spec/models/ai_agent_response_slot_spec.rb` (new) |
| M2 / S2.1 | `app/services/ai_agents/response_window.rb` (new), `app/services/ai_agents/usage/limiter.rb`, `spec/services/ai_agents/usage/limiter_spec.rb` |
| M2 / S2.2 | `app/services/ai_agents/live_processor.rb`, `config/locales/{en,tr}.yml` |
| M2 / S2.3 | `spec/services/ai_agents/response_window_spec.rb` (new), `spec/services/ai_agents/live_processor_spec.rb` |
| M3 / S3.1 | `app/services/ai_agents/conversation_history_projector.rb` (new), `app/services/ai_agents/live_processor.rb`, `docs/ai-agent-catalog-runtime.md` |
| M3 / S3.2 | `spec/services/ai_agents/conversation_history_projector_spec.rb` (new), `spec/services/ai_agents/live_processor_spec.rb` |
| M4 / S4.1 | `spec/services/ai_agents/response_window_spec.rb`, `spec/services/ai_agents/live_processor_spec.rb`, `spec/controllers/api/v1/accounts_controller_spec.rb` |
| M4 / S4.2 | validation-only (no code changes expected); review artifacts |

**Explicitly removed from v1 plan**: `app/builders/account_builder.rb` change, `FREEMIUM_AI_AGENT_RESPONSE_LIMIT_PER_WINDOW` constant, freemium backfill runner, `spec/builders/account_builder_spec.rb` change.

## Gate Plan

| Subphase / Milestone | Gate | Exact Commands / Methods | Evidence Invalidation Paths | Expected Duration Evidence |
|----------------------|------|--------------------------|-----------------------------|----------------------------|
| M1 / S1.1 | INNER / CHECKPOINT | `rbenv exec bundle exec rspec spec/lib/config_loader_spec.rb spec/controllers/super_admin/app_config_controller_spec.rb spec/enterprise/controllers/super_admin/app_config_controller_spec.rb spec/services/ai_agents/settings_spec.rb` | Any config/allowlist edit | UNKNOWN — collect first observation |
| M1 / S1.2 | INNER / CHECKPOINT | `rbenv exec bundle exec rspec spec/models/account_spec.rb spec/controllers/super_admin/accounts_controller_spec.rb spec/controllers/api/v1/accounts_controller_spec.rb` | Any account/serializer/dashboard edit | UNKNOWN — collect first observation |
| M1 / S1.3 | INNER / CHECKPOINT | `rbenv exec bundle exec rspec spec/models/ai_agent_response_slot_spec.rb` + migration matrix on `RAILS_ENV=test` | Any migration/model edit | UNKNOWN — collect first observation |
| Milestone 1 | MILESTONE | M1 spec set + `git diff --stat` review | Migration/schema drift, exposure change | UNKNOWN — collect first observation |
| M2 / S2.3 | INNER / CHECKPOINT | `rbenv exec bundle exec rspec spec/services/ai_agents/response_window_spec.rb spec/services/ai_agents/live_processor_spec.rb spec/services/ai_agents/usage/limiter_spec.rb` + rubocop | Any state-machine/LiveProcessor edit | UNKNOWN — collect first observation |
| Milestone 2 | MILESTONE | M2 suite green + manual 45/50/51 trace in specs | Contract or lock-order change | UNKNOWN — collect first observation |
| M3 / S3.2 | INNER / CHECKPOINT | `rbenv exec bundle exec rspec spec/services/ai_agents/conversation_history_projector_spec.rb spec/services/ai_agents/conversation_history_compactor_spec.rb spec/services/ai_agents/live_processor_spec.rb` | Any projector/limit edit | UNKNOWN — collect first observation |
| Milestone 3 | MILESTONE | M3 suite green + history doc updated | History constant change | UNKNOWN — collect first observation |
| M4 / S4.1 | CHECKPOINT | Threaded specs + channel/dup + exposure negatives | Concurrency/exposure edit | UNKNOWN — collect first observation |
| Final | FINAL | Independent jobs: full focused RSpec set, rubocop + prettier, migration matrix re-run, optional runtime smoke | Final diff / environment | UNKNOWN — collect first observation |

## Blast Radius / Affected Entry Points

- `AgentBots::AiResponseJob` → `LiveProcessor#perform`: whole limit path (reservation, warning, terminal); job retries idempotent via slot state machine.
- `AgentBotListener#process_ai_bot_event`: unchanged trigger; every eligible incoming message now passes slot accounting.
- `AiAgents::Usage::Limiter#reserve!`: `unlimited?` semantics widened (effective response limit); monthly-unlimited accounts with effective limit > 0 now create window events (intended — event table growth for those accounts is a documented product consequence). Single production caller is LiveProcessor (verified).
- `AiAgentUsageEvent`: new column + association; legacy rows without slots are valid (count 0) — no backfill.
- `AiAgents::Orchestrator` / `ConversationHistoryCompactor`: untouched; projector feeds orchestrator with the same `{role, content}` shape.
- `AiAgents::Settings`: new global reader; existing readers untouched.
- `config/installation_config.yml` + `app_configs_controller` allowlist: new editable global key (OSS + Enterprise via `super`); value applies next request (cache cleared on save; not restart-required).
- `app/views/api/v1/models/_account.json.jbuilder`: settings dump minus the override key — account API read contract changes by one hidden key; existing settings keys unchanged (incl. existing `ai_agent_conversation_limit` exposure, out of scope).
- SuperAdmin account dashboard form/show: one new field; `accounts_controller_spec` permitted-params coverage.
- `Usage::Summary` / monthly quota / `AiImprovements::Usage::Limiter`: logic untouched; **display side effect**: monthly-unlimited accounts now accrue consumed events → `counted_conversations` shows non-zero for them (accepted, see Notes).
- `docs/ai-agent-catalog-runtime.md` + skills referencing it: updated.
- Existing specs with changed expectations: `limiter_spec.rb` `:unlimited` cases (effective-limit semantics); `live_processor_spec.rb` default-account cases verified message/attr-based (event counts re-checked); `account_builder_spec.rb` untouched and stays green.

## Allowed Scope / Forbidden Scope

- Allowed: `app/services/ai_agents/{response_window,conversation_history_projector}.rb` (new), `live_processor.rb`, `usage/limiter.rb`, `settings.rb`, `app/models/{ai_agent_usage_event,ai_agent_response_slot,account}.rb`, `account_settings_schema.rb`, `app/views/api/v1/models/_account.json.jbuilder`, `app/controllers/super_admin/app_configs_controller.rb`, `config/installation_config.yml`, `app/dashboards/account_dashboard.rb`, field partials, `config/locales/{en,tr}.yml` (new keys only), `db/migrate/20260812120000_create_ai_agent_response_slots.rb`, `db/schema.rb`, annotations, specs listed, `docs/ai-agent-catalog-runtime.md`.
- Forbidden: modifying `Orchestrator`, `ResponseBuffer`, `ReplyPolicy`, `Conversation#bot_handoff!`, `Usage::Summary`/`Period`, `AccountBuilder`, option-selection/catalog tool services, message content in DB, monthly quota semantics, `enterprise/` code (specs only), `RESTART_REQUIRED_CONFIG_KEYS`, any provider/tokenizer dependency, job-ordering changes, paid-plan differentiation, test-mode history, `ai_agent_conversation_limit`/`ai_agent_conversation_reuse_window_hours` exposure (existing contract).

## UI/UX Composition Specification

### [Zone: SuperAdmin App Config — `ai_agents` group] (`/super_admin/app_config?config=ai_agents`)
```
#### List of config fields (generic view, app/views/super_admin/app_configs/show.html.erb)
├── AI Agent Response Buffer (existing, text field)
├── NEW: "AI Agent Response Limit Per Window" — generic text field (default branch, show.html.erb:57)
│   └── Description paragraph below (existing .text-xs text-slate-400 pattern, show.html.erb:59-63):
│       "Maximum AI responses a customer can receive within one reuse window. Set to 0 to disable
│        the limit for all accounts; accounts with a per-account override are unaffected."
└── Save button (existing)
```
- Value source: `@app_config['AI_AGENT_RESPONSE_LIMIT_PER_WINDOW']` (current InstallationConfig value); label from `display_title`; description from `description` in `installation_config.yml` (English source, matching every other entry — no locale keys for app config entries).
- Behavior: save → `AppConfigsController#create` → `InstallationConfig` update → cache cleared → effective on next request; not in restart-required list.

### [Zone: SuperAdmin Account Dashboard — "AI agent settings" panel] (`_form.html.erb`)
```
#### Panel (existing ai-agent-settings-panel markup)
├── Header: "Account access" + enabled toggle (unchanged)
├── Body (existing order):
│   ├── Model select
│   ├── Monthly conversation limit (existing)
│   ├── NEW: "AI responses per 24-hour window" — number input (min 0, step 1), value = raw override (blank when inherit)
│   │   └── Hint (existing .ai-agent-settings-control__hint): "Blank = inherit the global default. 0 = unlimited."
│   ├── Same customer reuse window (existing)
│   └── Data retention (existing)
└── Show page (_show.html.erb): NEW row after "Monthly conversation limit":
    raw override → blank: "Inherit (global default: 50)" | 0: "Unlimited" | else number
```
- Action placement: input between the two existing limit controls; no new buttons; blank submit = clear override (inherit).
- Component mapping: reuse `ai-agent-settings-control` + `number_field_tag` + hint span pattern (`_form.html.erb:27-34`); no new components.
- i18n: `super_admin.account_ai_agent_settings.response_limit_per_window` (label), `response_limit_hint`, `response_limit_inherit` in `en.yml` + `tr.yml`; global config title/description live in `installation_config.yml` (existing English-only convention).
- States: blank input → inherit; 0 → unlimited; positive → exact; show page renders effective value for inherit row. No customer-facing UI anywhere.

## Invariants

| Invariant | Why it matters | How to verify |
|-----------|----------------|---------------|
| Global lock order: conversation → usage event; never event → conversation | No deadlock between persist and terminal paths | Threaded deadlock spec (S4.1) |
| At most `limit` slots in reserved/consumed per event at any committed instant | 50-cap exact under overlap; **released retries atomically re-reserve under the event lock** (a released row only stays untouched when exhausted at full capacity), so concurrent released retries cannot both pass at 49 and reach 51 | Threaded 49/50 spec + threaded two-released-retries spec |
| At most one slot row per `(event, trigger_message)` | Duplicate/retry idempotency | Unique index + `:reused` spec |
| Warning exactly once, only when consumed == `limit − 5` for `limit > 5` | Customer contract (45 for 50) | Consume-path + flag assertions |
| Terminal handoff exactly once per trigger (handed_off marker) AND exactly once per conversation (in-lock `handoff_completed?` re-check); marker + delivery in one transaction | No duplicate public handoffs under retries, duplicate jobs, or concurrent same-conversation triggers | `exhausted_handoff!` twice + threaded same-trigger and same-conversation specs |
| Slot release decisions keyed on the slot row's own state (`slot&.reserved?`), never result/limiter status | `:reused` slots must still release when their job fails; no reserved-slot leaks | Reused-slot + failed-adapter spec |
| `handed_off` slots: `reserve!` → `:exhausted` (never re-runs LLM for an already-terminally-handed-off trigger); `consume!`/`release!` no-op | Terminal markers are immutable; no double handoff, no miscount | handed_off reserve/consume/release specs |
| Warning/terminal messages carry no `trigger_message_id`, no count; `system_notice` under `ai_agent` (stripped publicly) | Not counted; not customer-exposed; no idempotency collision | content-attributes + serializer assertions |
| DB message content never modified by projection | Customer data integrity | Projector spec content assertions |
| Marker length included in char budgets | Budget honesty | Projector boundary cases |
| Effective limit never unlimited from malformed/negative input; only explicit 0 | Abuse/drift safety | Account + Settings resolution specs |
| Override invisible to account API (read + write) | Requirement: Super Admin-only | Exposure negative specs |
| 50th response is the last normal AI response; 51st trigger → no LLM/tool | Spend + customer contract | `expect(adapter).not_to receive(:perform)` at 51st |

## Behavior That Must Not Change

- Monthly freemium quota (100 windows) + silent monthly-exhaustion handoff (private note, `ai_usage_limit_exhausted`) — existing limiter/live_processor specs (updated only for `:unlimited` effective-limit semantics).
- `:unlimited` result when effective limits are both 0 (global 0 + no override).
- `Usage::Summary` monthly payload — `summary_spec.rb` untouched.
- Duplicate-trigger response idempotency (`response_already_persisted?` + `conversation.with_lock`) — `live_processor_spec.rb:70-80` pattern.
- Sticky `ai_handoff_completed` (ReplyPolicy) — handed-off conversation stays silent.
- Catalog compaction + `.last(N)` limiting + orchestrator message shape + tool budgets.
- Option-selection contract (version 1, stale rejection, one submission).
- Existing account API settings keys (including `ai_agent_conversation_limit` exposure — pre-existing contract, out of scope).
- AccountBuilder behavior and non-freemium/freemium settings assertions (`account_builder_spec.rb` untouched, green).
- **Acknowledged UX inconsistency (out of scope)**: monthly exhaustion remains private/silent while response-limit exhaustion is customer-visible; precedence kept (monthly first). **Follow-up note**: revisit monthly UX separately — do not alter in this feature.

## Validation Matrix

| Check | Command / Method | Proves |
|------|-------------------|--------|
| Config loader default 50 + OSS/Enterprise exposure + POST persistence | `config_loader_spec.rb`, `app_config_controller_spec.rb` (OSS + enterprise) | Global config contract |
| Dynamic application without restart | `installation_config.rb` cache-clear evidence + controller spec (no restart list) | Instant global change |
| Override resolution (inherit/0/positive/malformed/global fallback) | `account_spec.rb` + `settings_spec.rb` | Exact two-level semantics |
| API read/write hiding | `api/v1/accounts_controller_spec.rb` negatives | Super Admin-only override |
| 45/50/51 + warning/terminal copy + notice shape | `response_window_spec.rb` + `live_processor_spec.rb` | Customer contract exact |
| Duplicate/retry/release | `live_processor_spec.rb` (2× perform → 1 response/1 slot) + `response_window_spec.rb` | Idempotency at side-effect boundary |
| Released retry cannot overfill | `response_window_spec.rb` (threaded: 49 consumed + two released retries → exactly one `:reserved`, one `:exhausted`, active == limit, exhausted row stays released) + `live_processor_spec.rb` (sequential: a released retry takes the 50th response, a second released retry gets no LLM and no 51st consumption, terminal deferred per conversation) | Cap holds even for concurrent retries released below the limit |
| Reused-slot failure release | `live_processor_spec.rb` (2× perform with failing adapter on the reused run → slot `released`, no message) | Slot-state-based release, no leak |
| handed_off semantics | `response_window_spec.rb` (`reserve!` → `:exhausted`; `consume!`/`release!` no-op) | Terminal markers immutable |
| Terminal exactly-once (same trigger + same conversation) | `exhausted_handoff!` twice + threaded same-trigger and same-conversation specs | One public terminal/handoff per trigger and per conversation |
| Concurrency at boundary | Threaded spec: 49 consumed + 3 concurrent → 1 reserved / 2 exhausted | Exact cap under overlap |
| Cross-conversation sharing | Same contact, second conversation, same event | Window semantics |
| Failed adapter | Stub raising → slot `released`, event `released` (new event case) | No leak, retry-safe |
| Monthly precedence | Monthly exhausted + window open → existing silent handoff, zero slots | Contract order |
| Warning/terminal across channels | Widget/WhatsApp/API LiveProcessor cases + serializer strip assertions | Same-channel plain-text notices |
| History 20/21 + truncation + no DB mutation | Projector specs (Turkish/emoji/grapheme, huge latest/old, 20/21) | Projection correctness |
| Migration | Disposable DB clean/upgrade/repeat/rollback + psql | Expand-only, zero-downtime |
| WhatsApp delivery failure | State committed before async delivery; duplicate-delivery spec | State + handoff safe |
| Runtime smoke | `/health` woot + simulator message → 1 public message + consumed slot | End-to-end (or explicit UNVERIFIED) |

## Visual Baseline Policy

No visual-regression baselines in scope (Super Admin administrate form + generic app-config page only; no screenshot suites for them). No baselines may be written in any milestone.

## Evidence Owners

| Item | Owner | Proof Required |
|------|-------|----------------|
| Global config + resolution semantics | @implementer | config/settings/account specs green |
| API exposure negatives | @implementer | accounts controller/request specs green |
| Migration matrix + schema.rb alignment | @implementer | psql catalog output, `db:migrate:status`, schema diff |
| State machine 45/50/51 + idempotency | @implementer | M2/M4 spec files green |
| Concurrency/lock-order | @implementer | Threaded specs green (join timeouts, counts) |
| Notice shape + public stripping | @implementer | Serializer/content-attribute assertions |
| History projection + no DB mutation | @implementer | Projector specs green + content assertions |
| Monthly precedence / behavior preservation | @implementer | Existing specs untouched (minus documented `:unlimited` updates) and green |
| Enterprise parity re-verification | @implementer | `rg -n "AiAgents|ai_agent" enterprise/` → no matches (recorded at M4) |
| FULL review Gate 1 (customer contract, concurrency) | @analyzer | Review findings + sign-off |
| FULL review Gate 2 FINAL (migration, config, security) | @analyzer | Review findings + sign-off |
| Runtime smoke (optional) | @implementer | Health probe + simulator evidence, or explicit UNVERIFIED |

## Failure Signals

- Threaded boundary spec yields 2 reserved at 49/50 → reservation state machine wrong.
- `exhausted_handoff!` double-delivery under retry → marker transaction not atomic.
- Threaded same-conversation terminal spec yields 2 public terminal messages → in-lock `handoff_completed?` re-check missing or not atomic with delivery.
- Reused-slot + failed-adapter spec leaves the slot `reserved` → release decision keyed on the wrong object (result/limiter status instead of `slot&.reserved?`).
- A `handed_off` slot re-runs the LLM (`reserve!` ≠ `:exhausted`) or gets consumed → handed_off branch missing in `reserve!`/`consume!`.
- Warning appears twice or at wrong count → flag/transaction ordering broken.
- `:unlimited` legacy specs fail → effective-limit semantics regression in `Limiter#unlimited?`.
- Account API exposes or accepts the override → exposure negative tests fail; stop and fix.
- Enterprise `ai_agents` page misses the key → allowlist/spec mismatch.
- Projector splits grapheme clusters or mutates DB content → truncation bug.
- Deadlock in threaded spec → lock-order violation.
- Migration matrix fails upgrade path, standalone `trigger_message_id` index, or schema.rb drift → migration incomplete.
- Scope drift: Orchestrator/ReplyPolicy/Selection/Enterprise-code/AccountBuilder edits → stop; out of scope.

## Risk Review Gates

| Gate | After Milestone | Focus Area |
|------|-------------|------------|
| **Gate 1 (FULL)** | Milestone 2 | Customer-visible contract (45/50/51, verbatim copy, notice stripping), concurrency + lock order, monthly precedence, duplicate/retry idempotency, reused-slot release on failure, handed_off immutability, same-conversation terminal-once |
| **Gate 2 (FULL)** | Final (M4) | Migration safety + schema alignment, config resolution + API hiding, security/abuse (spend cap), Enterprise parity, i18n completeness (en+tr) |

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Concurrent duplicates over/under-count | MEDIUM | HIGH | Slot rows + unique index + event row lock; threaded specs |
| Deadlock (event→conversation vs conversation→event) | LOW | HIGH | Enforce conversation→event order; threaded deadlock spec |
| Crash between marker and terminal delivery | LOW | MEDIUM | Marker + delivery in one transaction under event lock |
| False exhaustion from stuck reserved slots | LOW | MEDIUM | Crash-retry completes via `:reused` (same-row transition); release keyed on `slot&.reserved?` so reused-slot failures release too |
| Duplicate terminal in one conversation under concurrency | LOW | MEDIUM | In-lock `handoff_completed?` re-check + per-trigger marker; threaded same-conversation spec |
| Global default surprises existing installs (50 applies everywhere) | MEDIUM | MEDIUM | Explicit product intent; rollback = global 0 or per-account override 0; documented in Notes; no silent per-account writes |
| Malformed override/global → accidental unlimited | LOW | HIGH | Readers: only explicit 0 → 0; everything malformed/negative → global/50; resolution specs |
| 150k-char messages blow context | MEDIUM | HIGH | 40k total / 8k per-message budgets; residual risk documented |
| Migration locking | LOW | LOW | Expand-only additive DDL; fast default; disposable-DB matrix |
| Physical delivery failure (WhatsApp) | MEDIUM | LOW | State commits before async delivery; private note persists; no retry loop |
| Override leaked via account API | LOW | MEDIUM | `.except` in serializer + read/write negative specs |

## Notes

- **Decisions**: global key `AI_AGENT_RESPONSE_LIMIT_PER_WINDOW` (default 50); override `ai_agent_response_limit_per_window` (blank=inherit, 0=unlimited, positive=exact); threshold `limit > 5 ? limit − 5 : 0` (no warning for 1–5; remaining always 5 → copy hardcodes "5"); budgets 8,000/40,000; account-locale for deterministic copy (matches existing note pattern); terminal path does not auto-assign (parity with monthly path); notice metadata `{type, limit, remaining}` under `ai_agent.system_notice` (publicly stripped; no ids).
- **UX limitation (explicit, decision #7)**: the same handed-off conversation never resumes AI automatically — even after the window resets; a new eligible conversation/window is needed. Copy avoids promising auto-reopening; private note's reset time is diagnostic only.
- **Monthly precedence**: monthly exhaustion keeps existing private/silent behavior and runs first. Documented follow-up (out of scope): consider making monthly exhaustion customer-visible in a separate change.
- **Global default impact**: applies to ALL accounts without override immediately after deploy — including existing freemium accounts (intended). This also means monthly-unlimited accounts start creating window events (counter container). Rollback: set global 0 (disable all), or per-account override 0 (disable one); revert code; migration `down` supported.
- **Documented display side effect (no scope expansion)**: `Usage::Summary#metrics.counted_conversations` (`usage/summary.rb:72-79`) counts consumed events — monthly-unlimited accounts now accrue consumed window events, so Super Admin usage displays for those accounts will show non-zero counted conversations where they previously showed none. Monthly quota semantics, `Summary#payload` shape, and the `remaining`/`status` fields are unchanged; the display effect is accepted and covered by the updated `limiter_spec` `:unlimited` cases (override 0 / stubbed global 0 keep the pure-unlimited display contract in specs).
- **Community locale fallback (no scope expansion)**: only `en`/`tr` are maintained; `I18n.t('ai_agents.response_limit_*', locale: account.locale)` for a community locale (e.g., `de`) falls back to the EN default in production; dev/test environments with `I18n.enforce_available_locales`/missing-translation rendering may show `translation missing:` keys for non-en/tr accounts. This matches the existing maintained-locales convention (same as `handoff_not_assigned_note`); no new locale work in this feature.
- **Legacy/malformed persisted state**: pre-existing events have zero slots (valid; no backfill); events with nil `contact_id` cannot reuse a window and the response limit is not enforced for them (rare deleted-contact edge, consistent with existing monthly reuse behavior, documented); settings values may be strings (`'50'`/`'0'`/`''`) — readers coerce; `response_limit_warning_sent` flag absent on old rows → default false; InstallationConfig row absent → fallback 50.
- **Security/abuse**: per-contact spend capped at 50 LLM turns per window (plus retries of failed turns); reservation rows bounded; no new endpoints; malformed config cannot disable the cap accidentally; Super Admin-only control surface.
- **Metrics/observability**: `Rails.logger.info` lines for warning + terminal handoff (event/trigger/conversation ids, pattern `live_processor.rb:59-61`); `Usage::Summary` monthly contract untouched.
- **Skills**: `database-migration-testing` (M1 matrix), `async-worker-testing` (S4.1 idempotency), `chatwoot-i18n-branding` (en/tr maintained sources only; `pnpm sync:i18n` NOT needed — dashboard locale trees untouched), `chatwoot-enterprise-overlays` (specs only, re-verify), `chatwoot-ai-agent-local-testing` + `ai-native-workflow` (M4 runtime smoke, optional). No Context7 — no external dependency proposed.
- **i18n**: global config title/description in `installation_config.yml` (existing English-only convention for app-config entries); account dashboard labels/hints + `ai_agents.response_limit_*` copy in `{en,tr}.yml`, aligned.

## Decision Log

| Decision | Chosen | Rejected | Rationale | Evidence |
|----------|--------|----------|-----------|---------|
| Data model | Dedicated `ai_agent_response_slots` keyed `(event, trigger_message)` | Counter column on events | Counters cannot prove per-trigger idempotency under duplicate/overlapping jobs | `live_processor.rb:11-30,145-152`; async-worker-testing guidance |
| Global default source | InstallationConfig `AI_AGENT_RESPONSE_LIMIT_PER_WINDOW` (default 50, dynamic) | AccountBuilder freemium write / per-account default at signup | Applies to all accounts immediately; inheritance without writes; cache cleared on save → no restart | `installation_config.yml:184-189`; `installation_config.rb:24-29,46,64-66`; `app_configs_controller.rb:53` |
| Override semantics | blank=inherit, 0=unlimited, positive=exact; malformed/negative → inherit | Treating blank as 0 | Never accidentally unlimited; explicit disable only | Requirement + readers design |
| Effective reader location | `Account#effective_ai_agent_response_limit_per_window` + `AiAgents::Settings.response_limit_per_window` | Inline GlobalConfig reads at call sites | Single resolution point, testable, DRY | `account.rb:234-236` pattern |
| Override visibility | Hidden from account API read (`.except` in `_account.json.jbuilder`) + write already impossible | Leave visible like existing AI settings | Explicit user requirement (view+change denied); existing keys out of scope | `_account.json.jbuilder:1`; `accounts_controller.rb:116-124` |
| Warning threshold | Derived `limit > 5 ? limit − 5 : 0` | Separate configurable warning setting | Simplest; exact 45 for 50; no warning noise for tiny limits; YAGNI | Requirement #6 |
| Notice metadata | `ai_agent.system_notice` `{type, limit, remaining}` | Flat content_attributes / event ids | Publicly stripped by existing serializer; minimal shape | `message.rb:211-224`; `_widget_message.json.jbuilder:5` |
| Warning copy | User-approved verbatim, "5" hardcoded | Interpolated remaining | Remaining is always 5 by construction; approved copy exact | Product decision |
| Terminal exactly-once | Per-`(event, trigger)` `handed_off` marker + per-conversation in-lock `handoff_completed?` re-check, delivery in one transaction | Event-level boolean / result-status guards | Duplicates suppressed per trigger AND per conversation; the conversation row lock serializes same-conversation boundary races | Decision #5/#6/#7 + analyzer review |
| Slot release decision | Keyed on the slot row's own state (`slot&.reserved?`) | Keyed on result/limiter status | A `:reused` slot must still release when its job fails; the row is the truth | Analyzer review + reused-slot spec |
| handed_off immutability | `reserve!` → `:exhausted`; `consume!`/`release!` no-op on `handed_off` | Allow re-reservation/re-count of terminal triggers | Terminal triggers must never re-run the LLM or affect counts | Analyzer review |
| Lock order | conversation → event, always | event → conversation | Deadlock-free | Invariants + S4.1 |
| Slot statuses | reserved/consumed/released/handed_off | consumed-only | Handed_off marker enables exactly-once terminal | Product decision #5 |
| Budgets | 8,000/40,000 chars, 2/3–1/3 split, marker in budget | Tokenizer-based | No tokenizer dependency; conservative vs 128k min | Budget Rationale |
| Projector call site | After compactor + `.last(20)`, before orchestrator | Inside orchestrator | Count and char limits separable; orchestrator untouched | Requirement #7 |

---

## Readiness Status

- **PASS** — plan updated in place at `docs/ai-agent-live-response-context-limits.plan.md` (uncommitted; plan-only).
- **Global/override resolution**: `AI_AGENT_RESPONSE_LIMIT_PER_WINDOW` InstallationConfig default 50 (Super Admin `ai_agents` group, OSS + Enterprise, dynamic via cache-clear, 0 = disable all) → per-account override `ai_agent_response_limit_per_window` (blank = inherit, 0 = unlimited, positive = exact; malformed/negative → inherit) → hard fallback 50; `Account#effective_ai_agent_response_limit_per_window` is the single reader.
- **Warning/terminal UX**: deterministic `Messages::MessageBuilder` public messages with user-approved verbatim TR/EN copy (no quota language; warning hardcodes "5"); `ai_agent.system_notice` metadata `{type, limit, remaining}` verified stripped from all public serializers → plain-text rendering everywhere; exactly-once logical delivery via transactional flag/marker; physical channel delivery failure never blocks counting or handoff state; terminal = public message + diagnostic private note (window reset time, no customer promise) + `ai_handoff_reason: ai_response_limit_exhausted` + `bot_handoff!`, all in one transaction under `conversation.with_lock` → `event.with_lock` (conversation→event lock order) with the in-lock `handoff_completed?` re-check making terminal delivery exactly-once per conversation and the `handed_off` marker making it exactly-once per trigger.
- **Slot state machine corrections (analyzer review)**: slot release decisions are keyed on `slot&.reserved?` (never result/limiter status) so `:reused` slots release on failure; an existing `handed_off` slot makes `reserve!` return `:exhausted` (no LLM re-run) while `consume!`/`release!` no-op on it; migration adds a standalone `trigger_message_id` index and the disposable-DB matrix asserts all three indexes.
- **Super Admin surfaces**: global app-config field (display_title/description in `installation_config.yml`, generic view, no restart) + account dashboard field under `ai_agent_settings` (blank = inherit hint; show page renders inherit + effective), both behind `authenticate_super_admin!`; account API read filtered, write closed (verified permitted list + negative specs).
- **Milestones**: M1 config+override+super-admin+API hiding (S1.1 global, S1.2 override, S1.3 migration+slot model) → M2 ResponseWindow + LiveProcessor customer UX → M3 HistoryProjector → M4 concurrency/channel/exposure + FINAL; FULL @analyzer reviews at Gate 1 (M2) and Gate 2 (FINAL).
- **Zero-HIGH-assumption status**: no CRITICAL/HIGH unverified assumptions — every contract carries file:line evidence including the new config/loader/controller/serializer/authorization facts; only explicitly marked decisions/LOW unknowns remain.
- **Remaining LOW unknowns**: exact `annotaterb` CLI flags (verify `--help`); Sidekiq retry schedule (not required — DB-state idempotent); runtime-smoke availability (explicit UNVERIFIED path); `installation_config.yml` placement ordering (after line 189, mechanical); whether `upsert_config`-style specs need `GlobalConfig.clear_cache` cleanup in the config persistence spec (use DB assertions like the existing POST test — verified pattern).
