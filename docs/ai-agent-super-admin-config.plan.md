# AI Agent Super Admin Configuration — Implementation Plan

## Problem Statement

The AI Asistan feature exists in Chatwoot OSS but lacks per-account configuration for the LLM model and conversation usage limits. Super admins cannot control which OpenRouter model an account uses or cap how many AI conversations that account may consume. This plan adds model and limit fields to the super admin panel (Administrate) and wires them through to the AI agent dashboard and runtime.

## Approach

Store per-account AI configuration in `account.settings` (JSONB), expose it through a custom Administrate field on `AccountDashboard`, and surface the model name read-only in the dashboard AI agent page. Keep the change minimal, follow existing `limits` field patterns, and do not touch Enterprise schema or Captain paths.

## Success Criteria

- [ ] Super admin can edit AI model (dropdown) and conversation limit (integer, 0 = unlimited) on any account
- [ ] AI Asistan dashboard page shows the configured model name read-only
- [ ] AI response service reads the model from account config
- [ ] Conversation usage counter respects the configured limit
- [ ] Default model: `deepseek/deepseek-v4-flash`; default limit: `0` (unlimited)
- [ ] No new `accounts` columns; only existing JSONB `settings` is used
- [ ] Only English i18n source files are updated

---

## Product Decisions Locked In

| Topic | Decision |
|---|---|
| Storage | `account.settings` JSONB — not `limits`, not new columns |
| Settings keys | `ai_agent_model` (string), `ai_agent_conversation_limit` (integer) |
| Default model | `deepseek/deepseek-v4-flash` |
| Default limit | `0` meaning unlimited |
| Model selection | Static dropdown of common OpenRouter models; not customer-editable |
| Super admin surface | Custom Administrate field on `AccountDashboard` edit/show pages |
| Dashboard surface | Read-only model name display only; no model selector for customers |
| Scope | OSS-only; no Enterprise or Captain code touched |

---

## Current State (evidence)

- `Account.settings` is JSONB with a JSON Schema validator that sets `additionalProperties: true`, so adding new keys is safe (`app/models/account.rb:34-75`).
- `Account` already uses `store_accessor` for settings fields (`app/models/account.rb:88-92`).
- Super admin persists `limits` as hash data via `resource_params` (`app/controllers/super_admin/accounts_controller.rb:36-40`), but `settings` is not currently exposed in super admin forms.
- `AccountDashboard` defines `ATTRIBUTE_TYPES`, `FORM_ATTRIBUTES`, `SHOW_PAGE_ATTRIBUTES`, and `permitted_attributes` (`app/dashboards/account_dashboard.rb:27-126`).
- Enterprise adds `AccountLimitsField` to the dashboard via `enterprise_attribute_types`/`enterprise_form_attributes` (`app/dashboards/account_dashboard.rb:11-25`, `78-85`).
- `AccountLimitsField` renders key/value number inputs and is backed by `account.limits` (`enterprise/app/fields/account_limits_field.rb`, `enterprise/app/views/fields/account_limits_field/_form.html.erb`).
- The AI agent API returns `id`, `prompt`, `enabled`, `config`, and `agent_bot` metadata, but no model information (`app/views/api/v1/accounts/ai_agents/show.json.jbuilder:1-17`).
- The dashboard AI agent page (`Index.vue`) references `conversation_count` and `conversation_limit` in computed properties, but these fields do not exist on the backend (`app/javascript/dashboard/routes/dashboard/settings/aiAgent/Index.vue:57-63`).
- The `AiAgent` model stores `prompt`, `enabled`, and `config` JSONB, and auto-creates a shadow `AgentBot` (`app/models/ai_agent.rb`).
- Feature flag `ai_agent` exists and is enabled by default (`config/features.yml:248-251`).
- No OSS AI response service currently reads `ai_agent.prompt` or generates replies; this is a known gap documented in the v1 rebuild plan.

---

## Verified Facts vs Assumptions

| Type | Item | Evidence / Notes |
|---|---|---|
| Verified fact | `account.settings` JSONB schema allows additional properties | `app/models/account.rb:34-75` — `additionalProperties: true` |
| Verified fact | `Account` uses `store_accessor` for settings sub-fields | `app/models/account.rb:88-92` |
| Verified fact | Super admin `resource_params` already intercepts and transforms `limits` | `app/controllers/super_admin/accounts_controller.rb:36-40` |
| Verified fact | `AccountDashboard` supports custom fields via `ATTRIBUTE_TYPES` and `permitted_attributes` | `app/dashboards/account_dashboard.rb:27-126` |
| Verified fact | Enterprise `AccountLimitsField` is the established pattern for JSONB hash editing in super admin | `enterprise/app/fields/account_limits_field.rb`, `_form.html.erb` |
| Verified fact | AI agent API response does not include model name today | `app/views/api/v1/accounts/ai_agents/show.json.jbuilder:1-17` |
| Verified fact | Dashboard AI page references `conversation_count`/`conversation_limit` that do not exist on backend | `app/javascript/dashboard/routes/dashboard/settings/aiAgent/Index.vue:57-63` |
| Verified fact | `AiAgent` belongs to exactly one account and auto-creates an `AgentBot` | `app/models/ai_agent.rb` |
| Verified fact | No OSS AI response generation service exists yet | `app/listeners/agent_bot_listener.rb:18-25` — only webhook bots |
| Assumption | A single custom Administrate field can render both a model dropdown and a limit number input | Consistent with `AccountLimitsField` pattern; form view will contain both inputs |
| Assumption | `store_accessor` with overridden getter can provide default values cleanly | Standard Rails pattern; verified by existing `support_email` override in Account |
| Assumption | Conversation counting for limit enforcement can reuse bot-assignment tracking or a lightweight join table | Not yet implemented; deferred to Phase 4 with explicit atomicity requirement |

---

## Scope Boundary

### In scope

- Per-account AI model configuration in super admin (dropdown)
- Per-account AI conversation limit configuration in super admin (integer, 0 = unlimited)
- Read-only model display on the dashboard AI Asistan page
- Backend API surfacing model and limit to the dashboard
- Account-level default values for model and limit
- Static, configurable list of OpenRouter model options

### Explicitly out of scope

- Customer-facing model selector (dashboard users cannot change the model)
- OpenRouter API integration or key management
- AI response generation service (covered by v1 rebuild plan, not this plan)
- Enterprise/Captain overlay changes
- Billing or plan-tier logic
- Analytics beyond usage count/limit display
- Simulator connection to real AI

### Deferred scope

- Conversation counting table/schema (needed for limit enforcement but separate from configuration UI)
- Automatic handoff when limit is reached
- Model-specific pricing or token limit metadata

---

## Design Decisions

1. **Config storage: `account.settings`**
   - Keys: `ai_agent_model` (string) and `ai_agent_conversation_limit` (integer).
   - Rationale: `settings` schema allows additional properties without modifying validation. `limits` is validated in Enterprise with `additionalProperties: false`, so adding a new key there would require Enterprise code changes, which is out of scope.

2. **Super admin field pattern**
   - Create a single custom `AccountAiAgentSettingsField` (OSS, not Enterprise) that renders a model `<select>` and a limit `<input type="number">`.
   - Rationale: Matches the existing `AccountLimitsField` pattern while keeping both related inputs in one visual unit.

3. **Form param naming**
    - Submit as `account[ai_agent_settings][model]` and `account[ai_agent_settings][conversation_limit]`.
    - `Account` defines `ai_agent_settings` getter/setter virtual attribute that reads/writes the two store accessors as a hash. No controller transformation needed — the model handles it.
    - Rationale: Virtual attribute is simpler than controller param merging and avoids accidentally wiping existing `settings` keys.

4. **Default values**
   - Model default: `deepseek/deepseek-v4-flash` via overridden getter on Account.
   - Limit default: `0` (unlimited) via overridden getter on Account.
   - Rationale: Zero is a conventional "unset/unlimited" sentinel for limits in this codebase; the frontend already treats `null`/`0` as unlimited in `usageDisplay`.

5. **Dashboard read-only display**
   - The AI agent `show` API response will include `model` read-only.
   - The dashboard `Index.vue` will show the model name in a non-editable field.
   - Rationale: Product requirement that model selection is super-admin only.

6. **Model dropdown options**
   - Define a constant `AI_AGENT_MODELS` on `AccountAiAgentSettingsField` (or Account) containing common OpenRouter model IDs.
   - Rationale: Keeps the list in one place; easy to extend later via env/config if needed.

---

## Implementation Plan

### Phase 1: Data contract — Account settings + defaults
**Owner**: @implementer (backend)
**Dependencies**: None
**Complexity**: LOW

#### Tasks
- [ ] Add `store_accessor :settings, :ai_agent_model, :ai_agent_conversation_limit` to `Account`.
- [ ] Add `attr_accessor :ai_agent_settings` virtual attribute for Administrate binding.
- [ ] Add `ai_agent_settings` getter/setter that surfaces the two store accessors as a hash.
- [ ] Override `ai_agent_model` getter to return `'deepseek/deepseek-v4-flash'` when blank.
- [ ] Override `ai_agent_conversation_limit` getter to return `0` when blank and cast strings to integers.
- [ ] Add `AI_AGENT_MODELS` constant with static OpenRouter model list.
- [ ] Write/update `spec/models/account_spec.rb` for default behavior and virtual attribute round-trip.

#### Likely files / areas
- `app/models/account.rb`
- `spec/models/account_spec.rb`

#### Acceptance Criteria
- [ ] `account.ai_agent_model` returns default when settings key is absent
- [ ] `account.ai_agent_conversation_limit` returns `0` when settings key is absent
- [ ] `account.settings` JSON schema validation still passes after adding new keys
- [ ] Model spec covers both default and explicit value cases

---

### Phase 2: Super admin integration — Custom field + dashboard + controller
**Owner**: @implementer (backend)
**Dependencies**: Phase 1
**Complexity**: MEDIUM

#### Tasks
- [ ] Create `AccountAiAgentSettingsField < Administrate::Field::Base` in `app/fields/`.
- [ ] Create `_form.html.erb` for the field: label + model `<select>` + limit number input.
- [ ] Create `_show.html.erb` for the field: display model name and limit value.
- [ ] Add `ai_agent_settings: AccountAiAgentSettingsField` to `AccountDashboard::ATTRIBUTE_TYPES`.
- [ ] Add `:ai_agent_settings` to `AccountDashboard::FORM_ATTRIBUTES` and `SHOW_PAGE_ATTRIBUTES`.
- [ ] Update `AccountDashboard#permitted_attributes` to permit `{ ai_agent_settings: %i[model conversation_limit] }`.
- [ ] Add exact i18n keys to `config/locales/en.yml` for Administrate labels (`helpers.label.account.ai_agent_settings`, `helpers.label.account.ai_agent_settings.model`, `helpers.label.account.ai_agent_settings.conversation_limit`).
- [ ] Write request spec in `spec/controllers/super_admin/accounts_controller_spec.rb` verifying: (a) new keys persist into settings, (b) existing settings keys are NOT wiped.
- [ ] Write request spec in `spec/controllers/super_admin/accounts_controller_spec.rb` verifying that updating an account persists model and limit into settings.

#### Likely files / areas
- `app/fields/account_ai_agent_settings_field.rb`
- `app/views/fields/account_ai_agent_settings_field/_form.html.erb`
- `app/views/fields/account_ai_agent_settings_field/_show.html.erb`
- `app/dashboards/account_dashboard.rb`
- `app/controllers/super_admin/accounts_controller.rb`
- `config/locales/en.yml`
- `spec/controllers/super_admin/accounts_controller_spec.rb`

#### Acceptance Criteria
- [ ] Super admin account edit page renders model dropdown and limit input
- [ ] Saving the form persists `ai_agent_model` and `ai_agent_conversation_limit` into `account.settings`
- [ ] Show page displays the persisted values
- [ ] Empty limit submits as `0` (or is compacted safely)
- [ ] Controller spec proves round-trip persistence

---

### Phase 3: Dashboard read-only model display
**Owner**: @implementer (backend + frontend)
**Dependencies**: Phase 2
**Complexity**: LOW

#### Tasks
- [ ] Update `app/views/api/v1/accounts/ai_agents/show.json.jbuilder` to include `json.model @ai_agent.account.ai_agent_model`.
- [ ] Update `app/javascript/dashboard/routes/dashboard/settings/aiAgent/Index.vue` to display the model name in a read-only section.
- [ ] Add i18n keys to `app/javascript/dashboard/i18n/locale/en/aiAgent.json` for model label/help text.
- [ ] Update `spec/controllers/api/v1/accounts/ai_agents_controller_spec.rb` to assert `model` is present in the response.

#### Likely files / areas
- `app/views/api/v1/accounts/ai_agents/show.json.jbuilder`
- `app/javascript/dashboard/routes/dashboard/settings/aiAgent/Index.vue`
- `app/javascript/dashboard/i18n/locale/en/aiAgent.json`
- `spec/controllers/api/v1/accounts/ai_agents_controller_spec.rb`

#### Acceptance Criteria
- [ ] `GET /api/v1/accounts/:id/ai_agent` response includes `model`
- [ ] Dashboard AI page shows the model name in a non-editable field
- [ ] If model is not configured, the default `deepseek/deepseek-v4-flash` is shown
- [ ] API spec asserts model presence

---

### Phase 4: Conversation limit backend enforcement (deferred core)
**Owner**: @implementer (backend)
**Dependencies**: Phase 3 (and future AI response service)
**Complexity**: MEDIUM

#### Tasks
- [ ] Define conversation counting mechanism (e.g., `AiAgentConversation` join table with unique index on `[ai_agent_id, conversation_id]` or a counter on `conversations`).
- [ ] Add `conversation_count` to the AI agent API response (computed from counting mechanism).
- [ ] Add `conversation_limit` to the AI agent API response (read from account settings).
- [ ] Implement limit check before enqueueing an AI response job: skip if limit > 0 and count >= limit.
- [ ] Ensure counting is atomic (use `create_or_find_by` or `upsert` with unique index to prevent double-count under concurrency).
- [ ] Write specs for limit enforcement and race-condition safety.

#### Likely files / areas
- Future AI response service / job (not yet in OSS)
- `app/views/api/v1/accounts/ai_agents/show.json.jbuilder`
- `app/models/ai_agent.rb` (helper for count/limit)
- New migration for `ai_agent_conversations` table (if join-table approach chosen)
- `spec/models/ai_agent_spec.rb`

#### Acceptance Criteria
- [ ] API response includes `conversation_count` and `conversation_limit`
- [ ] AI response is not generated when the account has reached its limit
- [ ] First-response counting is idempotent under concurrent jobs
- [ ] Limit of `0` is treated as unlimited

---

## Deliverables

| Phase | Files Created/Modified |
|---|---|
| Phase 1 | `app/models/account.rb`, `spec/models/account_spec.rb` |
| Phase 2 | `app/fields/account_ai_agent_settings_field.rb`, `app/views/fields/account_ai_agent_settings_field/_form.html.erb`, `app/views/fields/account_ai_agent_settings_field/_show.html.erb`, `app/dashboards/account_dashboard.rb`, `app/controllers/super_admin/accounts_controller.rb`, `config/locales/en.yml`, `spec/controllers/super_admin/accounts_controller_spec.rb` |
| Phase 3 | `app/views/api/v1/accounts/ai_agents/show.json.jbuilder`, `app/javascript/dashboard/routes/dashboard/settings/aiAgent/Index.vue`, `app/javascript/dashboard/i18n/locale/en/aiAgent.json`, `spec/controllers/api/v1/accounts/ai_agents_controller_spec.rb` |
| Phase 4 | Future AI service, `app/models/ai_agent.rb`, `app/views/api/v1/accounts/ai_agents/show.json.jbuilder`, new migration, specs |

---

## Blast Radius / Affected Entry Points

- `app/models/account.rb` — new store accessors and default getters for AI settings
- `app/dashboards/account_dashboard.rb` — new custom field in ATTRIBUTE_TYPES, FORM_ATTRIBUTES, SHOW_PAGE_ATTRIBUTES, and permitted_attributes
- `app/controllers/super_admin/accounts_controller.rb` — `permitted_attributes` must allow nested `ai_agent_settings` params
- `app/views/api/v1/accounts/ai_agents/show.json.jbuilder` — adds `model` (and later `conversation_count`/`conversation_limit`)
- `app/javascript/dashboard/routes/dashboard/settings/aiAgent/Index.vue` — read-only model display
- `app/javascript/dashboard/i18n/locale/en/aiAgent.json` — new UI strings
- `config/locales/en.yml` — super admin field labels
- Future AI response service — will read `account.ai_agent_model` and `account.ai_agent_conversation_limit`

---

## Allowed Scope / Forbidden Scope

- **Allowed**: OSS `account.settings` extension, custom Administrate field, dashboard read-only display, API response augmentation, atomic conversation counting
- **Forbidden**: Changes to Enterprise `limits` schema or `validate_limit_keys`, Captain-specific paths, customer-facing model selector, new `accounts` columns, billing/plan logic, auto-reply behavior

---

## Invariants

| Invariant | Why it matters | How to verify |
|---|---|---|
| `account.settings` JSON schema remains valid | Prevents account save failures | `account.valid?` passes after setting/unsetting AI keys |
| Existing webhook agent bots keep working | Super admin change must not regress bot delivery | Existing bot specs pass unchanged |
| Enterprise `limits` schema is untouched | Avoids Enterprise validation breakage | Enterprise `validate_limit_keys` still only allows its 5 keys |
| Model selection is super-admin only | Product requirement | Dashboard page has no model `<select>`; API does not accept `model` param |
| Default model is `deepseek/deepseek-v4-flash` | Consistent baseline for all accounts | Getter returns default when settings key is absent |
| Limit of `0` means unlimited | Matches frontend expectation and avoids accidental lockout | Getter returns `0`; enforcement logic treats `0` as no-op |

---

## Behavior That Must Not Change

- Existing `AccountLimitsField` (Enterprise) behavior and allowed keys must not change.
- `SuperAdmin::AccountsController#resource_params` compaction of `limits` must continue to work.
- AI agent API update endpoint must not accept `model` or `conversation_limit` from customers.
- Dashboard AI agent page must continue to allow editing prompt, enabled state, and inbox bindings.
- Existing `AgentBot` webhook dispatch must remain unchanged.
- `account.settings` validation must not reject the new keys.

---

## Validation Matrix

| Check | Command / Method | Proves |
|---|---|---|
| Account settings default | `bundle exec rspec spec/models/account_spec.rb` | Default model and limit return correct fallback values |
| Super admin form renders | Log in as super admin, visit `/super_admin/accounts/{id}/edit` | Model dropdown and limit input are visible |
| Super admin persistence | Submit form with model=`anthropic/claude-3.5-sonnet`, limit=`100` | `account.reload.settings` contains both keys |
| API model inclusion | `GET /api/v1/accounts/{id}/ai_agent` with admin token | Response JSON contains `model` with expected value |
| Dashboard model display | Open dashboard AI Asistan settings page | Read-only model name is shown matching API response |
| Settings schema safety | `account.update(settings: { ai_agent_model: 'x', ai_agent_conversation_limit: 5 })` | `account.valid?` is true |
| Enterprise limits untouched | `bundle exec rspec` including Enterprise specs (if available) | No `limits` validation regressions |
| Param rejection | `PATCH /api/v1/accounts/{id}/ai_agent` with `{ model: 'x' }` | Model is ignored (not mass-assignable through AI agent API) |

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `account.settings` schema ever changes to `additionalProperties: false` | LOW | HIGH | Use `store_accessor` and rely on current `additionalProperties: true`; if schema is tightened later, add explicit properties for these keys |
| Administrate custom field breaks on upgrade | LOW | MEDIUM | Follow official `Administrate::Field::Base` subclass pattern; keep view ERB minimal |
| Virtual attribute `ai_agent_settings` not defined on Account | LOW | HIGH | Phase 1 now includes `attr_accessor` and getter/setter; verify Administrate binds correctly |
| Frontend `usageDisplay` treats `0` incorrectly | LOW | MEDIUM | Verify frontend logic: `usageLimit.value` is `null`/`0`/falsy → unlimited; `0` from backend must match this |
| Conversation limit enforcement races under concurrent jobs | MEDIUM | HIGH | Phase 4 requires atomic counting (unique index + `create_or_find_by` or `upsert`) |
| Scope drift into building full AI response service | MEDIUM | HIGH | Keep Phase 4 scoped to counting/limit plumbing only; defer generation service to v1 rebuild plan |
| Default model `deepseek/deepseek-v4-flash` is an external OpenRouter ID | LOW | MEDIUM | Not in `config/llm.yml` (Captain-only); AI Agent uses OpenRouter directly; document as external ID |

---

## Decision Log

| Decision | Chosen | Rejected | Rationale | Evidence |
|---|---|---|---|---|
| Storage location | `account.settings` | `account.limits` | `limits` has Enterprise `additionalProperties: false` validation; modifying it requires Enterprise code changes | `enterprise/app/models/enterprise/account/plan_usage_and_limits.rb:133-151` |
| Super admin field pattern | Single custom `AccountAiAgentSettingsField` | Two separate fields or exposing all `settings` | Keeps related AI config together; follows `AccountLimitsField` precedent | `enterprise/app/fields/account_limits_field.rb` |
| Default model | `deepseek/deepseek-v4-flash` | `openai/gpt-4o` or `anthropic/claude-3.5-sonnet` | External OpenRouter ID selected by product team; not in `config/llm.yml` because AI Agent uses OpenRouter directly, not Captain's `Llm::Models` | Product requirement |
| Default limit | `0` (unlimited) | `nil` or a fixed number | `0` is unambiguous and matches existing frontend unlimited logic | `app/javascript/dashboard/routes/dashboard/settings/aiAgent/Index.vue:65-73` |
| Customer model access | Read-only display | Editable dropdown | Product requirement: model selection is super-admin only | Requirement #6 |
| Model list source | Static constant in field/account class | Database table or env var | Simplest viable; easy to make dynamic later if needed | YAGNI |
| Param handling | Virtual attribute on Account (`ai_agent_settings`) | Controller `resource_params` merge | Virtual attribute is simpler, safer, and avoids settings-wipe risk | Analyzer review |

---

## Remaining Open Questions

None that block planning. Implementation-time choices:
- Exact OpenRouter model IDs to include in the static list (can be adjusted during Phase 2).
- Whether Phase 4 counting uses a join table vs. a column on `conversations` (decision deferred to when AI response service is designed).

(End of plan)
