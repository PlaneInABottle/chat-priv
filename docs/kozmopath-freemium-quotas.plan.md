# Kozmopath Indefinite Freemium Quotas — Implementation Plan

Status: READY (all HIGH/CRITICAL facts verified against code)
Branch baseline: `develop` @ `db4bf69dac` (clean tree at discovery)
Plan file: `docs/kozmopath-freemium-quotas.plan.md` (this file)

## Problem Statement

Kozmopath advertises a 14-day trial on the marketing homepage and signup page, but the runtime has no trial-expiry machinery — AI quotas are controlled by per-account settings that default to unlimited (`ai_agent_conversation_limit` absent → `0` = unlimited) or a generic 1000-credit fallback. The product decision is: **replace the advertised 14-day trial with an indefinite freemium** where newly eligible accounts start with **100 monthly AI conversations** and **600 monthly shared AI workspace credits**, existing accounts stay unchanged, and SuperAdmin retains independent control of both limits (`0` = unlimited, changes apply immediately).

## Approach

Add **explicit opt-in freemium defaults at the single account-creation funnel (`AccountBuilder`)** — never by mutating the `Account` readers/fallbacks that existing accounts depend on. Wire the opt-in only at the three new-account entry points (v1 unauth signup, v2 unauth signup, new-user Google OAuth). Prove limiter behavior, SuperAdmin immediacy, and dashboard/manual-reply decoupling with focused regression specs (no limiter logic changes). Then rename the marketing/signup trial copy, keys, and selectors to freemium language in the maintained `en`/`tr` locales. No DB migration, no schema change, no public API/schema change, no new routes, no payment/expiry state.

## Success Criteria

- [ ] New unauthenticated password signups (v1 AND v2) and new Google OAuth signups create accounts with `settings['ai_agent_conversation_limit'] == 100` and `settings['ai_improvement_monthly_credit_limit'] == 600`; installation onboarding, authenticated add-workspace (v1/v2), platform API, and SuperAdmin creation do NOT (defaults unchanged).
- [ ] `AccountBuilder` opt-in `apply_freemium_limits` defaults to `false`; existing `Account` readers/fallbacks are byte-identical (absent conversation limit → `0`/unlimited; absent/malformed/negative improvement credit → `1000`; explicit `0` preserved).
- [ ] SuperAdmin can independently set both limits, `0` = unlimited, and changes take effect on the next request without usage rewrites (proven by specs; no implementation change).
- [ ] Limiter behavior preserved: `>=` boundary (100th ok / 101st exhausted; 600th ok / 601st exhausted across ≥2 shared operations), 24-hour reuse window, silent handoff with no LLM call, `with_lock` atomicity, reporting-timezone month reset.
- [ ] Marketing homepage and signup page render freemium copy with exact strings `100 AI conversations every month.` and `600 monthly AI workspace credits.` in the `en` source locale; no trial/14-day/credit-card/autobilling claims anywhere in the touched surfaces; en/tr key parity retained.
- [ ] Signup operational gate `ENABLE_ACCOUNT_SIGNUP` remains default-off and untouched in its disabled behavior (404/RoutingError for v1/v2, no-account-found for OAuth).
- [ ] Full targeted suites green: Ruby (builders, v1/v2/omniauth/super_admin controllers, limiters, live processor, marketing), Vitest (signup components), ESLint, RuboCop.

---

## Verified Facts vs Assumptions

| # | Claim | Evidence (path:line) | Impact | Verification status |
|---|-------|----------------------|--------|---------------------|
| F1 | `AccountBuilder` uses `pattr_initialize` and sets exactly `ai_agent_enabled: true`, `voice_ai_enabled: false` at creation | `app/builders/account_builder.rb:5`, `:46-54` | Opt-in default + settings merge point | VERIFIED (read) |
| F2 | Repo pattr_initialize default syntax is `[... , { key: default }]` | `lib/captain/base_task_service.rb:22`, `lib/captain/rewrite_service.rb:2` | `{ apply_freemium_limits: false }` is valid | VERIFIED (read) |
| F3 | v1 `create` is unauthenticated for signup (`user: current_user` decides add-workspace vs signup) | `app/controllers/api/v1/accounts_controller.rb:5-12`, `:24-39` | `apply_freemium_limits: current_user.nil?` | VERIFIED (read) |
| F4 | v2 `create` is an unauthenticated password signup (skips auth, gated by signup flag + hCaptcha, builder `user: current_user`) | `app/controllers/api/v2/accounts_controller.rb:4-9`, `:16-33`, `:60-66` | v2 IS eligible → decision D1 | VERIFIED (read) |
| F5 | OAuth calls AccountBuilder only for NEW users (`sign_up_user`); existing-user login never reaches builder | `app/controllers/devise_overrides/omniauth_callbacks_controller.rb:4-8`, `:43-52`, `:82-91` | OAuth opt-in true only on signup | VERIFIED (read) |
| F6 | Installation onboarding uses builder without `user:`; platform API and SuperAdmin bypass builder entirely | `app/controllers/installation/onboarding_controller.rb:6-21`; `app/controllers/platform/api/v1/accounts_controller.rb:11-16`; Administrate default create | Stays default-false, no change | VERIFIED (read) |
| F7 | `Account#ai_agent_conversation_limit` = `(super \|\| 0).to_i` (absent → 0 = unlimited); `ai_improvement_monthly_credit_limit` falls back to `DEFAULT_AI_IMPROVEMENT_MONTHLY_CREDIT_LIMIT = 1000` for nil/malformed/negative; explicit `0` preserved; `DEFAULT_...` at :46 | `app/models/account.rb:46`, `:231-233`, `:259-267` | Existing-account semantics must NOT change → constants must be opt-in values | VERIFIED (read) |
| F8 | Conversation limiter: `account.with_lock`, `>=` boundary, unlimited `limit.zero?`, reuse window = `now + reuse_window_hours`, silent handoff on exhaustion, no LLM call | `app/services/ai_agents/usage/limiter.rb:27,30,32,74-81,91-93,95-109`; `spec/services/ai_agents/usage/limiter_spec.rb:49-72,100-114`; `spec/services/ai_agents/live_processor_spec.rb:377-408` | No limiter logic change needed | VERIFIED (read + spec names) |
| F9 | Shared-credit limiter: `account.with_lock`, `enough_credits?` `>=` on floored remaining, idempotency by `(period_start_at, idempotency_key)` + DB unique index, stale TTL 1h, unlimited branch, operations enum | `app/services/ai_improvements/usage/limiter.rb:4-12,35-45,113-123`; `app/models/ai_improvement_usage_event.rb:29,45,61` | No limiter logic change; operations available: `text_test`, `website_import`, ... | VERIFIED (read) |
| F10 | Monthly period from `account.reporting_timezone` (fallback `Time.zone`), UTC boundaries, used by both limiters/summaries | `app/services/ai_agents/usage/period.rb:9-27`; `spec/services/ai_agents/usage/limiter_spec.rb:25-26` | Reporting-timezone month reset preserved | VERIFIED (read) |
| F11 | SuperAdmin independently writes both limits via dashboard fields; setter preserves other keys; form `min: 0`; explicit 0 passes normalization | `app/dashboards/account_dashboard.rb:40-41,140-141`; `app/views/fields/account_ai_agent_settings_field/_form.html.erb:28-33`; `app/views/fields/account_ai_improvement_settings_field/_form.html.erb:13-18`; `app/models/account.rb:208-221,248-257`; `spec/controllers/super_admin/accounts_controller_spec.rb:194-241` | No SuperAdmin implementation change; add regression specs | VERIFIED (read) |
| F12 | No limit caching across requests (`@limit \|\|=` only inside one per-request Summary instance); SuperAdmin PATCH applies on next request | `app/services/ai_agents/usage/summary.rb:38`; `app/services/ai_improvements/usage/summary.rb` | "Changes apply immediately" needs no code | VERIFIED (read) |
| F13 | Enterprise has zero references to both quota keys/limiters and no AccountBuilder overlay; only enterprise specs assert builder args (v2 ×2 sites) | `rg` in `enterprise/` → 0 hits; `spec/enterprise/controllers/enterprise/api/v2/accounts_controller_spec.rb:41,80` | Enterprise parity = update 2 arg assertions + verify 3 enterprise specs | VERIFIED (grep) |
| F14 | Exact `AccountBuilder.new` arg assertions that break when a key is added: **7 sites across 4 spec files** — v1 spec `:27-29` (1 site), v2 spec `:26,:76,:135` (3 sites), omniauth spec `:44-50` (1 site), enterprise v2 spec `:41,:80` (2 sites). Enterprise v1 + google_oauth_attribution use loose `allow` → no change | `spec/controllers/api/v1/accounts_controller_spec.rb:27-29`; `spec/controllers/api/v2/accounts_controller_spec.rb:26,76,135`; `spec/controllers/devise/omniauth_callbacks_controller_spec.rb:44-50`; `spec/enterprise/controllers/api/v1/accounts_controller_spec.rb:26-28`; `spec/enterprise/controllers/enterprise/devise_overrides/google_oauth_attribution_spec.rb:17-20` | Update 7 assertion sites across 4 spec files | VERIFIED (read) |
| F15 | Marketing trial keys live only in `config/locales/{en,tr}.yml` (`marketing.trial.*`, 5 keys) and render only in `app/views/marketing/home.html.erb`; tr homepage is the tested locale | `config/locales/en.yml:799-804`, `config/locales/tr.yml:656-661`; `app/views/marketing/home.html.erb:7-13,27,41,59,66,390,396` | Key rename surface is bounded | VERIFIED (read) |
| F16 | Design-contract fingerprint: **single source is `MarketingController::DESIGN_CONTRACT_SHA`** (controller constant). The request spec verifies `SHA256` of the final response body AFTER replacing the design-contract meta content's 64-hex value with empty (meta-neutralized body — the body embeds the constant via the layout, so a full-body hash would be self-referential and infeasible), AND verifies the rendered meta content equals the controller constant. **No spec-local duplicated literal is authoritative.** The currently stored constant is a full-body hash computed over a body embedding the previous constant — invalid under this method; see "Plan correction" note | `app/controllers/marketing_controller.rb:3`; `app/views/layouts/marketing.html.erb:10`; `spec/requests/marketing_homepage_spec.rb:18,34` | Canonical method: neutralized-body digest + meta-sync assertion; regenerate in Phases 9 and 10 | VERIFIED (read + analyzer-verified digest) |
| F17 | Marketing SCSS trial selectors: `.trial-announcement`, `.hero-trial-truth`, `.final-trial-button`, `a[data-trial-cta]`, responsive block; asserted in `spec/lib/marketing_controller_spec.rb:26-28` | `app/javascript/entrypoints/marketing.scss:782-785,845,847-848` | Selector rename phase scope | VERIFIED (read) |
| F18 | Signup trial keys: `REGISTER.TRIAL.*` in `app/javascript/dashboard/i18n/locale/{en,tr}/signup.json` (values at en `:5-13`), used in `app/javascript/v3/views/auth/signup/Index.vue` (12+ sites) and `components/Signup/Form.vue` (`:128`, `:193`); testids `trial-signup-form`, `trial-sequence-step`; en/tr parity asserted in `Index.spec.js:56-69`, submit/testid in `Form.spec.js:122-152` | explore citations above; `app/javascript/v3/views/auth/signup/Index.vue:25-242` | Atomic rename phase (locale + both components + both specs) | VERIFIED (read) |
| F19 | `pnpm sync:i18n` only copies `en/index.js` import manifests when that file is staged; content-only locale edits do not trigger it; `en/index.js:37,85` already imports/spreads signup.json | `bin/sync_i18n_file_change` (pre-commit helper, staged-file check); `app/javascript/dashboard/i18n/locale/en/index.js:37,85` | NO sync run needed | VERIFIED (read) |
| F20 | `ChatwootCaptcha#valid?` returns `true` when `HCAPTCHA_SERVER_KEY` is blank; signup gate default `false` via `GlobalConfigService.account_signup_enabled?`; v1/v2 raise RoutingError 404; `REQUIRE_EMAIL_CONFIRMATION` defaults true | `lib/chatwoot_captcha.rb:7-12`; `lib/global_config_service.rb:18-20`; `config/installation_config.yml:61-66`; `app/controllers/api/v1/accounts_controller.rb:126-141`; `app/controllers/api/v2/accounts_controller.rb:60-62` | Runtime matrix can enable signup locally with blank hCaptcha key + `REQUIRE_EMAIL_CONFIRMATION=false`; gate stays off by default | VERIFIED (read) |
| F21 | Conversation-event factory `:ai_agent_usage_event` exists (`spec/factories/ai_agent_usage_events.rb` — requires account + optional ai_agent/contact/conversation/message, defaults monthly period to `Time.current`); **NO `ai_improvement_usage_event` factory exists** — shared-credit tests must create events through the limiter (`reserve_or_raise!`) or direct `AiImprovementUsageEvent.create!` with required `account`, `operation`, `unit_type`, `units` (≥0), `credits` (>0), `period_start_at`, `period_end_at`, unique `idempotency_key` (uniqueness scoped `[:account_id, :period_start_at]`); no thread-based concurrency spec exists (atomicity via `with_lock` + unique index) | `spec/factories/ai_agent_usage_events.rb:1-15`; `app/models/ai_improvement_usage_event.rb:42-53,61`; `spec/services/ai_agents/usage/limiter_spec.rb:31-57`; `spec/services/ai_improvements/usage/limiter_spec.rb:31-47` | Conversation boundary tests reuse the factory; shared-credit tests use limiter/direct-create; new deterministic thread test | VERIFIED (read) |
| F22 | `text_test` and `website_import` endpoints enforce shared credits via `ensure_ai_improvement_credits!` → `ensure_available!` → 402 `ai_improvement_credits_exhausted` | `app/controllers/api/v1/accounts/ai_agent_test_conversations_controller.rb:39-48`; `app/controllers/api/v1/accounts/ai_agent_website_imports_controller.rb:14`; `app/controllers/api/v1/accounts/base_controller.rb:28-44` | Request-level 599/600/601 tests target these endpoints | VERIFIED (read) |
| F23 | Agent/manual message replies (`conversations/messages_controller.rb`) do NOT invoke either limiter (shared limiter only in `suggest_learning` rescue) | `app/controllers/api/v1/accounts/conversations/messages_controller.rb:68-69`; limiter callers inventory | Dashboard/manual replies are decoupled; prove with request spec | VERIFIED (read) |
| F24 | `TRIAL_PERIOD_DAYS`/`isTrialAccount` in `app/javascript/dashboard/store/modules/accounts.js:13,43-50` and a local 15-day computed in `UpgradePage.vue:35-43,90` are dashboard billing/enterprise-cloud surfaces, NOT marketing/signup copy | files cited | Out of scope (see Forbidden Scope) | VERIFIED (read) |
| A1 | Enabling signup locally with `ENABLE_ACCOUNT_SIGNUP=true` + blank hCaptcha + `REQUIRE_EMAIL_CONFIRMATION=false` yields confirmed users and full auth responses on v1/v2 (no SMTP needed) | derived from F20 + `app/controllers/api/v1/accounts_controller.rb:139-153` | Runtime matrix assumption | LOW (safe; spec behavior matches `:85-110`) |
| A2 | Community (non-en/tr) dashboard locale folders keep stale `TRIAL` keys after the rename; no repo check validates cross-locale key parity (only en↔tr) | `rg flattenKeys` → only `Index.spec.js` + `marketing_controller_spec.rb` | Accepted; Crowdin flow | LOW (verified no parity check) |
| A3 | Live Google OAuth E2E requires real Google credentials → may remain UNVERIFIED; automated specs cover the wiring | F5/F14 | Runtime matrix marks it UNVERIFIED if credentials absent | LOW (explicitly reported) |

No CRITICAL or HIGH unverified assumptions remain.

---

## Constants / Inputs / Schema / API / Route Contract Inventory

**New constants (implementation):**
- `Account::FREEMIUM_AI_AGENT_CONVERSATION_MONTHLY_LIMIT = 100` (placed next to `DEFAULT_AI_IMPROVEMENT_MONTHLY_CREDIT_LIMIT`, `app/models/account.rb:46`).
- `Account::FREEMIUM_AI_IMPROVEMENT_MONTHLY_CREDIT_LIMIT = 600` (same location).
- `AccountBuilder` pattr option `{ apply_freemium_limits: false }` (repo default syntax per F2).

**Inputs (no API/schema change):** eligibility is decided by the call site:
- v1 unauth signup (`current_user.nil?`) → `true`; v1 authenticated add-workspace → `false`.
- v2 unauth signup (`current_user.nil?`) → `true`; v2 authenticated → `false`.
- OAuth new-user (`sign_up_user` path) → `true`; existing-user login → builder not called.
- Installation onboarding, platform API, SuperAdmin create → builder not opted in / not used.
- Settings keys written when opted in (string keys, matching `store_accessor` + `account_settings_schema.rb:21,24`): `'ai_agent_conversation_limit'` (integer 100), `'ai_improvement_monthly_credit_limit'` (integer 600).

**No schema change:** no migration; `db/schema.rb` untouched; no columns, indexes, or jsonb shape changes (both keys already valid per `app/models/concerns/account_settings_schema.rb:21,24`).

**No public API change:** no new response fields, headers, or status codes; `spec/controllers/api/v1/accounts/ai_agents_controller_spec.rb:68,135` already pin `conversation_limit` absence from public payloads — they stay untouched and green.

**Routes — all changes map existing routes:** `POST /api/v1/accounts` (`config/routes.rb:74`), `POST /api/v2/accounts` (`config/routes.rb:618`), `GET /auth/google_oauth2/callback` (devise omniauth mount, `config/routes.rb:3-9`), `POST /installation/onboarding` (unchanged), `PATCH /super_admin/accounts/:id` (unchanged), marketing `GET /` (unchanged). Zero route edits.

**New copy keys (en + tr, key renames only — no layout changes):**
- `marketing.freemium.{announcement, cta, final_cta, start_note, final_note}` (replaces `marketing.trial.*`).
- `REGISTER.FREEMIUM.*` (replaces `REGISTER.TRIAL.*`): `EYEBROW`, `MONTHLY_CONVERSATIONS` (was `DAY_COUNT`), `CONVERSATION_HEADLINE` (was `STARTS_WHEN_CREATED`), `WORKSPACE_CREDITS` (was `NO_CARD_OR_AUTO_CHARGE`), `TITLE`, `DESCRIPTION`, `SUBMIT`, `REFERENCE`, `BACK_HOME`, `PROOF_*`, `SEQUENCE_*`, `CONVERSATION_LABEL`, `CONTACT_*`, `ASSISTANT_*`, `FIXTURE_DISCLOSURE`, `CUSTOMER_QUESTION`, `ASSISTANT_ANSWER`, `PRODUCT_*` (PROOF/SEQUENCE/product values unchanged).

**Selector renames:** `data-trial-cta` → `data-freemium-cta` (4 CTAs); `data-testid="trial-signup-form"` → `freemium-signup-form`; `data-testid="trial-sequence-step"` → `freemium-sequence-step`; CSS classes `.trial-announcement`, `.hero-trial-truth`, `.final-trial-button` → `.freemium-announcement`, `.hero-freemium-truth`, `.final-freemium-button`.

**Exact copy mapping (authoritative — asserted in specs):**

| Key | en value | tr value |
|-----|----------|----------|
| `marketing.freemium.announcement` | `100 AI conversations every month.` (exact headline) | `Her ay 100 yapay zekâ sohbeti.` |
| `marketing.freemium.cta` | `Start for free` | `Ücretsiz başla` |
| `marketing.freemium.final_cta` | `Create your free account` | `Ücretsiz hesabını oluştur` |
| `marketing.freemium.start_note` | `600 monthly AI workspace credits.` (exact supporting copy) | `Ayda 600 yapay zekâ çalışma alanı kredisi.` |
| `marketing.freemium.final_note` | `Free forever. 100 AI conversations and 600 monthly AI workspace credits, renewed every month.` | `Süresiz ücretsiz. Her ay 100 yapay zekâ sohbeti ve ayda 600 yapay zekâ çalışma alanı kredisi.` |
| `REGISTER.FREEMIUM.EYEBROW` | `FREE FOREVER PLAN` | `SÜRESİZ ÜCRETSİZ PLAN` |
| `REGISTER.FREEMIUM.MONTHLY_CONVERSATIONS` (badge, `aria-hidden`) | `100` | `100` |
| `REGISTER.FREEMIUM.CONVERSATION_HEADLINE` (card `<strong>`) | `100 AI conversations every month.` | `Her ay 100 yapay zekâ sohbeti.` |
| `REGISTER.FREEMIUM.WORKSPACE_CREDITS` (card `<small>`) | `600 monthly AI workspace credits.` | `Ayda 600 yapay zekâ çalışma alanı kredisi.` |
| `REGISTER.FREEMIUM.TITLE` | `Kozmopath for your own store.` | `Kozmopath kendi mağazan için.` |
| `REGISTER.FREEMIUM.DESCRIPTION` | `Your work email and password are enough to begin.` | `İş e-postan ve şifren başlangıç için yeterli.` |
| `REGISTER.FREEMIUM.SUBMIT` | `Create your free account` | `Ücretsiz hesabını oluştur` |
| `REGISTER.FREEMIUM.REFERENCE` | `FREEMIUM / 001` | `FREEMIUM / 001` |

All other keys under the renamed blocks keep their existing values. No card/autobilling claims anywhere (the old "no credit card required" / "no automatic charge" strings are removed).

---

## Architecture & Design Rationale (YAGNI / KISS / DRY)

- **KISS — one funnel:** every eligible signup already funnels through `AccountBuilder`. One opt-in option + one settings merge covers all three entry points; no new service, no flags plumbing.
- **YAGNI — no persistence changes:** no new columns, no trial-expiry state, no job, no backfill. Existing readers are the single source of truth; "immediate apply" is already the behavior (F12).
- **DRY — no parallel system:** SuperAdmin already writes both limits; limiters already enforce `0`=unlimited, reuse, handoff, and timezone month reset (F8-F11). We add regression coverage instead of touching established behavior.
- **Safety of existing accounts:** freemium values are *opt-in builder settings*, not changes to `Account` fallbacks — an existing account's readers are byte-identical (F7). This is the core correctness constraint of the plan.
- **No new feature flag:** eligibility is derivable at call time (`current_user.nil?`, new-OAuth-user), and the existing operational gate `ENABLE_ACCOUNT_SIGNUP` already protects every signup entry (F20). A new persistent flag would be a parallel gate with no additional safety.

---

## Feature / Behavior Gates

1. **Internal gate:** `apply_freemium_limits` defaults to `false`. Every non-wired caller (installation onboarding, future callers, specs) gets existing behavior unless it explicitly opts in.
2. **Operational gate (unchanged):** `ENABLE_ACCOUNT_SIGNUP` (via `GlobalConfigService.account_signup_enabled?`, default `false`, `lib/global_config_service.rb:18-20` + `config/installation_config.yml:61-66`) keeps signup disabled until SMTP/email-confirmation and hCaptcha E2E are verified. v1/v2 `check_signup_enabled` still raise 404 RoutingError; OAuth still redirects with `no-account-found`. Runtime verification uses a disposable local stack only.
3. **No new persistent feature flag** — rationale above.

---

## Blast Radius — Affected Callers / Entry Points

| Entry point / caller | Effect | Must remain |
|---|---|---|
| `POST /api/v1/accounts` unauth (signup) | +`apply_freemium_limits: true` | 404 when gate off; captcha; confirmation flow |
| `POST /api/v1/accounts` auth (add-workspace) | +`apply_freemium_limits: false` | full response with account_id; no quota settings |
| `POST /api/v2/accounts` unauth (API-only/mobile signup) | +`apply_freemium_limits: true` | 404 when gate off; captcha; onboarding_step profile_update |
| `GET /auth/google_oauth2/callback` new user | +`apply_freemium_limits: true` | business-domain check; password-reset redirect; attribution (enterprise) |
| `POST /installation/onboarding` | unchanged (default false) | SuperAdmin bootstrap |
| Platform API `POST /platform/api/v1/accounts` | unchanged (bypasses builder) | `limits:` param passthrough |
| SuperAdmin create/PATCH | unchanged | Administrate form incl. both AI settings fields |
| `AiAgents::Usage::Limiter` / `Summary` | unchanged code | 0=unlimited, `>=`, reuse 24h, handoff, timezone reset |
| `AiImprovements::Usage::Limiter` / `Summary` + all consumers (`text_test`, `evaluation`, `website_import`, `learning`, `voice_test`, suggestion creator, adapter) | unchanged code | idempotency, stale TTL, 402 contract |
| Marketing homepage + signup page | copy/keys/selectors renamed | disabled-signup fallback; section order; proof layout |
| `MarketingController::DESIGN_CONTRACT_SHA` | meta-neutralized-body digest regenerated twice (Phase 9 copy change AND Phase 10 selector/class change — both alter the rendered body); controller constant is the single source; spec reads the constant | layout meta tag mirrors the constant; neutralized-body digest + meta-sync assertions green after EACH of Phases 9/10 |
| Enterprise overlays | none touch builder/quotas (F13) | enterprise v1/v2/oauth specs green after arg updates |

---

## Invariants (with verification method)

| Invariant | Why it matters | How to verify |
|---|---|---|
| Existing accounts' quota values never change | Core product requirement | `spec/models/account_spec.rb` reader-default tests (existing, unchanged) + Phase 1/5 assertions |
| `Account` readers/fallbacks byte-identical | F7 | diff of `account.rb` must be constants-only additions |
| Explicit `0` = unlimited for both limits | SuperAdmin contract | existing limiter `unlimited?` tests + Phase 5 PATCH-0 tests |
| Boundary `>=`: 100th ok/101st exhausted; 600th ok/601st exhausted | Product behavior | Phase 6/7/8 specs |
| 24h reuse window, silent handoff, no LLM call | Existing UX | existing limiter/live_processor tests + Phase 6 context |
| Reporting-timezone month reset | Existing UX | `AiAgents::Usage::Period` specs + Phase 6/7 month-reset contexts |
| en/tr key parity after rename | Both maintained locales | `spec/lib/marketing_controller_spec.rb:97-109` + `Index.spec.js:56-69` |
| Exact freemium strings in `en` source locale | Requirement | new en.yml / en signup.json equality assertions (Phase 9/11) |
| Signup gate default-off behavior | Operational safety | existing 404/`no-account-found` specs + runtime gate probe |
| No card/autobilling claims in touched copy | Requirement | exact-string assertions + selector guard (Phase 9) |

---

## Behavior That Must Not Change

- `Account#ai_agent_conversation_limit` absent → `0` (unlimited) — pinned by `account_spec.rb:421-423` (unchanged).
- `Account#ai_improvement_monthly_credit_limit` nil/malformed/negative → `1000`; explicit `0` → `0` — pinned by `account_spec.rb:548-572` (unchanged).
- Installation onboarding, platform API, SuperAdmin-created accounts: no quota settings.
- OAuth **existing-user login** (`sign_in_user`): never calls builder, never gets quotas.
- Limiter semantics: `>=` exhaustion, reservation idempotency, stale TTL 1h, voice-call-linked reservation retention, summary payload shapes, 402 `ai_improvement_credits_exhausted` contract.
- Public API payloads: no `conversation_limit`/credit fields added (`ai_agents_controller_spec.rb:68,135` stay green).
- Marketing disabled-signup fallback (`marketing.announcement.*` + `.demo-availability`), section ids/order, meta/canonical/robots, proof fixtures — untouched.
- Signup form behavior: validation, hCaptcha widget, terms links, Google OAuth button, submit disable states — only copy/keys/testids change.
- `ENABLE_ACCOUNT_SIGNUP` default and disabled behavior; `REQUIRE_EMAIL_CONFIRMATION` default.
- Dashboard `accounts.js` (`TRIAL_PERIOD_DAYS`/`isTrialAccount`) and `UpgradePage.vue` — untouched (see Forbidden Scope).

## Legacy / Malformed Persisted-State Handling

- Accounts created before this change (settings absent or explicit values): readers unchanged → no behavior delta. No backfill, no migration.
- Accounts with malformed/negative credit settings: existing fallback `1000` continues (reader untouched).
- Accounts with explicit `0`: remain unlimited.
- No new persisted state is written except the two settings keys on *new* eligible accounts.
- Because `ENABLE_ACCOUNT_SIGNUP` is off by default, no "new eligible account" can be created in production until the gate is deliberately enabled — zero risk of accidental quota writes.

---

## Phases

Each phase is one implementer dispatch; each leaves the tree green and is independently committable. All RSpec runs use the repo test-env wrapper (see Validation Matrix). Rollback for every phase: `git revert <commit>` of that phase (all changes are additive; no data migration to undo).

### Phase 1: Freemium constants + `AccountBuilder` opt-in (backend core)
**Files (3):** `app/models/account.rb`, `app/builders/account_builder.rb`, `spec/builders/account_builder_spec.rb`
**Edit intent:** Add `FREEMIUM_AI_AGENT_CONVERSATION_MONTHLY_LIMIT = 100` and `FREEMIUM_AI_IMPROVEMENT_MONTHLY_CREDIT_LIMIT = 600` next to `DEFAULT_AI_IMPROVEMENT_MONTHLY_CREDIT_LIMIT` (`account.rb:46`). Add `{ apply_freemium_limits: false }` to `pattr_initialize` (`account_builder.rb:5`). In `create_account` (`:46-54`) build the settings hash and merge the two string keys when opted in. Do NOT touch readers.
**Tests (add to builder spec):** (1) default (no option) → `settings` excludes both keys, `account.ai_agent_conversation_limit == 0`, `account.ai_improvement_monthly_credit_limit == 1000`; (2) `apply_freemium_limits: true` → `settings` include `'ai_agent_conversation_limit' => 100` and `'ai_improvement_monthly_credit_limit' => 600`, readers return `100`/`600`; (3) constants exist with values 100/600 (or in Phase 5 account_spec). Existing builder tests untouched and green.
**Rollback:** revert commit. **Gate:** `rspec spec/builders/account_builder_spec.rb spec/models/account_spec.rb` green; `git diff app/models/account.rb` shows constants-only additions.

### Phase 2: Wire v1 controller (unauth signup opt-in; authenticated unchanged)
**Files (2):** `app/controllers/api/v1/accounts_controller.rb`, `spec/controllers/api/v1/accounts_controller_spec.rb`
**Edit intent:** Pass `apply_freemium_limits: current_user.nil?` in the builder call (`:26-34`).
**Tests:** (1) update arg assertion `:27-29` → `params.except(:password).merge(user_password: ..., confirmed: false, apply_freemium_limits: true)`; (2) extend the real-signup test "when email confirmation is disabled" (`:85-110`) with `expect(account.ai_agent_conversation_limit).to eq(100)`, `expect(account.ai_improvement_monthly_credit_limit).to eq(600)`, and `settings` key presence; (3) extend "when an authenticated user creates a second account" (`:155-169`) to fetch the created account from the response `account_id` and assert `ai_agent_conversation_limit == 0` and `ai_improvement_monthly_credit_limit == 1000` (existing behavior pinned); (4) keep all gate/captcha/confirmation tests unchanged.
**Rollback:** revert. **Gate:** `rspec spec/controllers/api/v1/accounts_controller_spec.rb spec/enterprise/controllers/api/v1/accounts_controller_spec.rb` green (enterprise spec needs no edits — loose `allow`).

### Phase 3: Wire v2 controller (API-only/mobile signup opt-in)
**Files (3):** `app/controllers/api/v2/accounts_controller.rb`, `spec/controllers/api/v2/accounts_controller_spec.rb`, `spec/enterprise/controllers/enterprise/api/v2/accounts_controller_spec.rb`
**Edit intent:** Pass `apply_freemium_limits: current_user.nil?` in the builder call (`:17-22`).
**Tests:** (1) update v2 arg assertions `:26` and `:135` → `merge(user_password: ..., apply_freemium_limits: true)`; `:76` (invalid-params context) → same; (2) enterprise v2 arg assertions `:41` and `:80` → same addition; (3) **real persistence path (new context, no builder stub):** with `ENABLE_ACCOUNT_SIGNUP: 'true'` env and NO `allow(AccountBuilder)`, POST unauth with a random business email (pattern used by the v1 real signup: `"Signup-#{SecureRandom.hex(8)}@Example.COM"`), `password: 'Password1!'`, `locale: nil` → expect 200, then `account = User.find_by!(email: ...).accounts.first` → `account.settings` include `'ai_agent_conversation_limit' => 100` and `'ai_improvement_monthly_credit_limit' => 600`, readers return 100/600. (The existing stub contexts prove the builder receives the option; this new context proves the created account actually persists the freemium settings. v2 does not pass `confirmed:`, so the created user is unconfirmed — assert on the account, not auth headers.)
**Rollback:** revert. **Gate:** `rspec spec/controllers/api/v2/accounts_controller_spec.rb spec/enterprise/controllers/enterprise/api/v2/accounts_controller_spec.rb` green.

### Phase 4: Wire Google OAuth new-user signup
**Files (2):** `app/controllers/devise_overrides/omniauth_callbacks_controller.rb`, `spec/controllers/devise/omniauth_callbacks_controller_spec.rb`
**Edit intent:** Add `apply_freemium_limits: true` in `create_account_for_user` (`:82-91`). Existing-user path (`sign_in_user`) untouched.
**Tests:** (1) update "allows signup" arg assertion (`:44-50`) → hash includes `apply_freemium_limits: true`; (2) verify "allows login" and other tests unchanged.
**Rollback:** revert. **Gate:** `rspec spec/controllers/devise/omniauth_callbacks_controller_spec.rb spec/enterprise/controllers/enterprise/devise_overrides/google_oauth_attribution_spec.rb spec/controllers/installation/onboarding_controller_spec.rb` green (last two need no edits).

### Phase 5: SuperAdmin independence + `0`-unlimited + immediate-apply regression specs (spec-only)
**Files (2):** `spec/controllers/super_admin/accounts_controller_spec.rb`, `spec/models/account_spec.rb`
**Edit intent:** No implementation change. Add specs proving existing behavior.
**Tests:** (1) PATCH `conversation_limit: 0` → `account.ai_agent_conversation_limit == 0`; (2) PATCH `ai_improvement_settings: { monthly_credit_limit: 0 }` → `== 0`; (3) independent writes: PATCH `conversation_limit: 100` on an account with `monthly_credit_limit: 600` → credit unchanged; then PATCH `monthly_credit_limit: 300` → conversation unchanged (extends the "does not wipe" pattern at `:218-241` to the credit side); (4) immediate apply: PATCH then `account.reload` readers reflect new values without touching usage events (assert an existing `ai_agent_usage_event` row count is unchanged after PATCH); (5) `account_spec.rb`: assert the two new constants' values and that reader defaults are still 0/1000 for a settings-less account (extends existing `:409-511`, `:548-572`).
**Rollback:** revert. **Gate:** `rspec spec/controllers/super_admin/accounts_controller_spec.rb spec/models/account_spec.rb` green.

### Phase 6: Conversation-limiter freemium boundaries (spec-only)
**Files (2):** `spec/services/ai_agents/usage/limiter_spec.rb`, `spec/services/ai_agents/live_processor_spec.rb`
**Edit intent:** Add contexts using the existing factory pattern (`create(:ai_agent_usage_event, ...)`, explicit `period_start_at`, `status: :consumed`).
**Tests (limiter_spec):** (1) **99/100/101:** account `ai_agent_conversation_limit: 100` (reporting tz `America/New_York`), `create_list` 99 consumed events in the June window → `reserve!` on a fresh contact returns `:reserved` (100th); a second fresh contact → `:exhausted`, `summary[:remaining] == 0` (101st); (2) **month reset:** 100 consumed in June → with `now` in July → `reserve!` returns `:reserved`, `period_start_at == 2026-07-01 04:00:00 UTC`; (3) **immediate lower/raise:** limit 100 with 50 consumed → update limit to 10 → `reserve!` → `:exhausted`; update to 200 → `reserve!` → `:reserved`, then `summary[:remaining] == 149` (remaining = limit − used − reserved = 200 − 50 − 1; the new reservation itself counts — no usage rewrites).
**Tests (live_processor_spec):** **handoff/no LLM:** freemium-limited account (limit 100) with 100 consumed events → incoming message → processor hands off silently: no LLM adapter invocation (same mock pattern as existing `:377-408` context), `conversation.additional_attributes['ai_usage_limit_exhausted'] == true`, private note present, no public outgoing message.
**Rollback:** revert. **Gate:** `rspec spec/services/ai_agents/usage/limiter_spec.rb spec/services/ai_agents/usage/summary_spec.rb spec/services/ai_agents/live_processor_spec.rb` green.

### Phase 7: Shared-credit limiter freemium boundaries (spec-only)
**Files (1):** `spec/services/ai_improvements/usage/limiter_spec.rb`
**Edit intent:** New context with `ai_improvement_monthly_credit_limit: 600`, `reporting_timezone: 'Etc/UTC'`, `now` fixed.
**Tests:** (1) **599/600/601:** `reserve_or_raise!` for 599 unique idempotency keys (operation `text_test`) → 600th `reserve_or_raise!` succeeds; 601st raises `AiImprovements::Usage::Exhausted`, `summary[:remaining_credits] == 0`; (2) **across a second operation:** 300 reserved as `text_test` + 299 as `website_import` → next `website_import` succeeds (600th) → next raises (601st) — proves the shared balance across operations; (3) **concurrency (deterministic):** 4 threads × 200 `reserve_or_raise!` with unique keys at limit 600 → after joins: exactly 600 reserved (`AiImprovementUsageEvent.reserved.sum(:credits) == 600`), exactly 200 raise `Exhausted`, no negative remaining (invariant is interleaving-independent thanks to `account.with_lock`; existing "atomically rejects" pattern at `:39-47`); (4) **month reset:** 600 consumed in July → `now` in August → new reservation succeeds; (5) **immediate lower/raise:** 300 consumed → limit 100 → next raises; limit 500 → next succeeds, then summary `remaining_credits == 199` (remaining = 500 − 300 used − 1 reserved; the new reservation itself counts — no usage rewrites).
**Rollback:** revert. **Gate:** `rspec spec/services/ai_improvements/usage/limiter_spec.rb spec/services/ai_improvements/usage/summary_spec.rb spec/services/ai_improvements/usage/meter_spec.rb` green.

### Phase 8: Request-level integration — text_test/website_import boundaries + manual-reply decoupling (spec-only)
**Files (3):** `spec/controllers/api/v1/accounts/ai_agent_test_conversations_controller_spec.rb`, `spec/controllers/api/v1/accounts/ai_agent_website_imports_controller_spec.rb`, `spec/controllers/api/v1/accounts/conversations/messages_controller_spec.rb`
**Edit intent:** Add request-level boundary and decoupling tests (no implementation change; follow each spec's existing auth/stub patterns — the LLM orchestrator/adapter stubs as in the current test-conversations spec).
**Tests:** (1) **text_test 599/600/601:** account `ai_improvement_monthly_credit_limit: 600`; pre-fill 599 consumed credits via a **local helper/loop using direct `AiImprovementUsageEvent.create!`** (NO factory exists — F21; inside the spec file define a private helper, e.g. `fill_improvement_credits(account, count)` looping `create!(account: account, operation: 'text_test', unit_type: 'tokens', units: 1_000, credits: 1, status: :consumed, period_start_at: <current reporting month start via `AiAgents::Usage::Period.new(account: account, now: Time.current).start_at`>, period_end_at: <same Period end_at>, idempotency_key: "seed-text-test-#{index}")` — keys unique per account+period per the model's uniqueness scope) → `POST .../test_conversations/:id/send_message` succeeds (200, orchestrator stubbed); fill to 600 → same POST → 402 with `code: 'ai_improvement_credits_exhausted'`; (2) **website_import boundary:** same helper with `operation: 'website_import'` (unique key prefix per operation); account limit 600; 599 consumed → `POST .../ai_agent_website_imports` succeeds; 600 → 402 (mirror the endpoint's existing rescue assertions); (3) **manual-reply decoupling:** exhausted account (limit 100 with 100 consumed conversation events via the EXISTING `:ai_agent_usage_event` factory, `spec/factories/ai_agent_usage_events.rb`) → agent `POST .../conversations/:id/messages` with a reply → 200, message persisted, `AiAgentUsageEvent`/`AiImprovementUsageEvent` counts unchanged — proves dashboard/manual replies are not gated by AI quotas.
**Rollback:** revert. **Gate:** `rspec spec/controllers/api/v1/accounts/ai_agent_test_conversations_controller_spec.rb spec/controllers/api/v1/accounts/ai_agent_website_imports_controller_spec.rb spec/controllers/api/v1/accounts/conversations/messages_controller_spec.rb` green.

### Phase 9: Marketing copy + design-contract SHA (backend copy)
**Files (5):** `config/locales/en.yml`, `config/locales/tr.yml`, `app/views/marketing/home.html.erb`, `app/controllers/marketing_controller.rb`, `spec/requests/marketing_homepage_spec.rb`
*(Atomicity note: copy, rendered HTML, and the fingerprint constant are one unit — the spec's digest assertion fails unless the constant and copy change together; exceeds the 3-file guideline for this single reason. The spec holds NO local digest literal: `MarketingController::DESIGN_CONTRACT_SHA` is the single source, verified via the meta-neutralized-body method below.)*
**Edit intent:** Rename `marketing.trial.*` → `marketing.freemium.*` (both locales) with the exact values from the copy table; update `home.html.erb:10,27,41,59,66,390,396` key references; switch the SHA verification to the canonical meta-neutralized-body method and set `DESIGN_CONTRACT_SHA` per the procedure below. Keep `data-trial-cta` attributes and CSS classes untouched in this phase (renamed in Phase 10).
**Canonical digest method (replaces the old, infeasible full-body method — see "Plan correction" note):**
1. **Rewrite the spec's SHA verification** (`spec/requests/marketing_homepage_spec.rb`): delete the local `contract_html_sha` literal at `:18`; replace the assertion at `:34` with the meta-sync assertion `expect(document.at_css('meta[name="kozmopath-design-contract"]')['content']).to eq(MarketingController::DESIGN_CONTRACT_SHA)`; add the neutralized-body digest assertion. Hash the RAW `response.body` after a string replacement — do NOT re-serialize via Nokogiri (serializer differences would change the digest). Exact snippet:
   ```ruby
   # Scoped to the design-contract meta only: anchored meta-name literal + [0-9a-f]{64}
   # (the constant is always a 64-hex SHA256), leaving content="" in place.
   neutralized_body = response.body.gsub(
     %r{(<meta name="kozmopath-design-contract" content=")[0-9a-f]{64}(")},
     '\1\2'
   )
   # Guard: proves the replacement actually fired (no silent no-op if the meta is missing/malformed).
   expect(neutralized_body).to include('<meta name="kozmopath-design-contract" content="">')
   expect(Digest::SHA256.hexdigest(neutralized_body)).to eq(MarketingController::DESIGN_CONTRACT_SHA)
   ```
   No fixed-point problem: the neutralized body does NOT contain the constant, so `constant == sha256(neutralized_body)` is an ordinary hash verification.
2. **Set the controller constant to the analyzer-verified anchor** `DESIGN_CONTRACT_SHA = '1e66cb7dec356e70de58def01e8aa0feb5e2e2124801a2a0cd8a50eaa3899a56'` (`marketing_controller.rb:3`) — the verified neutralized-body digest of the current signup-enabled `www.kozmopath.com` Turkish render. Run the request spec → green confirms the method end-to-end against the current body.
3. **Apply the copy edits** (key rename + copy-table values in `en.yml`/`tr.yml`, key references in `home.html.erb`).
4. **Re-capture once:** temporarily print `Digest::SHA256.hexdigest(neutralized_body)` inside the spec example (signup-enabled stub, `www.kozmopath.com`, Turkish render), run it, capture the digest, remove the temporary code, and update **`marketing_controller.rb:3` ONLY** (no spec literal to update). If the working-tree body already matches the anchor (copy already applied), the re-capture yields the same value — verify and proceed.
5. **Remove temporary output; run the request + lib specs** → green.
**Tests (spec updates):** (1) exact-string source assertions: `I18n.t('marketing.freemium.announcement', locale: :en) == '100 AI conversations every month.'` and `I18n.t('marketing.freemium.start_note', locale: :en) == '600 monthly AI workspace credits.'`; (2) rendered Turkish assertions at `:83-92`: CTA texts `['Ücretsiz başla', 'Ücretsiz başla', 'Ücretsiz başla', 'Ücretsiz hesabını oluştur']`; `.announcement` squish `== '✦ Her ay 100 yapay zekâ sohbeti.'`; `.hero-trial-truth` (class still named so until Phase 10) includes `'Ayda 600 yapay zekâ çalışma alanı kredisi.'`; `.final-cta` includes `'Süresiz ücretsiz.'`; (3) no-card/autobilling guard (selector absence guard comes in Phase 10, since `data-trial-cta` attributes still exist here): `expect(response.body).not_to match(/(kredi kartı|otomatik ücretlendirme|14 gün|deneme süren)/i)` and `expect(document.text).not_to include('No credit card')`; (4) disabled-signup fallback test (`:143`) unchanged (still `data-trial-cta` until Phase 10); (5) the SHA rewrites from step 1 (meta-sync + neutralized-body digest + `content=""` guard).
**Rollback:** revert (fingerprint returns with the revert). **Gate:** `rspec spec/requests/marketing_homepage_spec.rb spec/lib/marketing_controller_spec.rb` green.

### Phase 10: Marketing selector/class renames + design-contract SHA (frontend)
**Files (5):** `app/views/marketing/home.html.erb`, `app/javascript/entrypoints/marketing.scss`, `app/controllers/marketing_controller.rb`, `spec/lib/marketing_controller_spec.rb`, `spec/requests/marketing_homepage_spec.rb`
*(Atomicity note: the selector/class renames change the rendered HTML body, so the neutralized-body digest changes — the controller constant must be updated in the SAME phase. No spec-local literal exists (removed in Phase 9); the spec's meta-sync and digest assertions both read `MarketingController::DESIGN_CONTRACT_SHA`, so updating the controller constant alone keeps the spec green. Exceeds the 3-file guideline for this single reason, mirroring Phase 9.)*
**Edit intent:** Rename `data-trial-cta` → `data-freemium-cta` (`home.html.erb:27,41,59,390`; `marketing.scss:845`); classes `.trial-announcement`/`.hero-trial-truth`/`.final-trial-button` → `.freemium-announcement`/`.hero-freemium-truth`/`.final-freemium-button` (`home.html.erb:7,66,390`; `marketing.scss:782-785,847-848`). **Regenerate the neutralized-body digest ONCE** — the rendered body changed since Phase 9 (data attributes + class names appear in the HTML): repeat Phase 9's canonical capture (temporarily print `Digest::SHA256.hexdigest(neutralized_body)` inside the spec example with the signup-enabled stub on `www.kozmopath.com`, Turkish render; run, capture, remove temporary output) and update **`marketing_controller.rb:3` ONLY**. **No fixed-point iteration** — the neutralized body does not contain the constant, so a single capture yields the final digest directly.
**Tests:** (1) `marketing_controller_spec.rb:26-28` → `include('.marketing-home.variant-a .hero-freemium-truth')`, `include('.marketing-home.variant-a .final-freemium-button')`, keep `not_to include('.trial-runway', '.guided-trial')`, and add `expect(stylesheet).not_to match(/\.trial-|\[data-trial-/)`; (2) `marketing_homepage_spec.rb`: NO `contract_html_sha` literal exists (removed in Phase 9) — the meta-sync assertion and the neutralized-body digest assertion follow the updated controller constant automatically; selectors at `:80-84` → `a[data-freemium-cta][href='#{signup_url}']`, attribute values `%w[header mobile-menu hero-primary final]`; `:105` → `a[data-freemium-cta='mobile-menu']`; `:143` → `[data-freemium-cta]` empty in the disabled fallback; update the `.hero-trial-truth` class reference from Phase 9 to `.hero-freemium-truth`; keep the copy assertions from Phase 9; (3) add the selector-absence guard deferred from Phase 9: `expect(document.css('[data-trial-cta], .trial-announcement, .hero-trial-truth, .final-trial-button')).to be_empty`.
**Rollback:** revert (fingerprint returns with the revert). **Gate:** `rspec spec/requests/marketing_homepage_spec.rb spec/lib/marketing_controller_spec.rb` green — Phase 10 is independently green without Phase 9/11 changes.

### Phase 11: Signup copy rename (atomic — locale + components + specs)
**Files (6):** `app/javascript/dashboard/i18n/locale/en/signup.json`, `app/javascript/dashboard/i18n/locale/tr/signup.json`, `app/javascript/v3/views/auth/signup/Index.vue`, `app/javascript/v3/views/auth/signup/components/Signup/Form.vue`, `app/javascript/v3/views/auth/signup/Index.spec.js`, `app/javascript/v3/views/auth/signup/components/Signup/Form.spec.js`
*(Atomicity note: a key-namespace rename cannot be split — any intermediate state renders missing-key strings; exceeds the 3-file guideline for this single reason.)*
**Edit intent:** Rename block `TRIAL` → `FREEMIUM` and the four semantically-trial keys per the copy table; update every `REGISTER.TRIAL.*` reference in `Index.vue` (sites at `:25,40,46,51,60,64,67,108,116,122,127,133,142,146,149,160,164,167,178,182,185,193,201,204,211,217,223,225,234,239,242`) and `Form.vue` (`:193`); rename testids `trial-signup-form` → `freemium-signup-form` (`Form.vue:128`) and `trial-sequence-step` → `freemium-sequence-step` (`Index.vue:136,154,172`). Card structure: badge `MONTHLY_CONVERSATIONS` (keep `aria-hidden`), `<strong>` `CONVERSATION_HEADLINE`, `<small>` `WORKSPACE_CREDITS` (`Index.vue:56-70`).
**Tests:** (1) `Index.spec.js`: key-name assertions `:39-43` → `REGISTER.FREEMIUM.*`; testid assertion → `freemium-sequence-step`; **add exact-string source assertions** reading the JSON: `enSignup.REGISTER.FREEMIUM.CONVERSATION_HEADLINE === '100 AI conversations every month.'`, `WORKSPACE_CREDITS === '600 monthly AI workspace credits.'`, and `not.toMatch(/trial|deneme|14 gün/)` across `enSignup.REGISTER.FREEMIUM` values; en/tr flatten parity test (`:56-69`) unchanged (still passes); (2) `Form.spec.js`: `:147-149` → `freemium-signup-form`; `:150-152` → `REGISTER.FREEMIUM.SUBMIT`; (3) no `pnpm sync:i18n` needed (F19).
**Rollback:** revert. **Gate:** `pnpm test app/javascript/v3/views/auth/signup` + `pnpm exec eslint app/javascript/v3/views/auth/signup/` green.

### Phase 12: Final sweep + full-suite validation
**Files:** none (fixes only if the sweep finds stragglers, restricted to the surfaces listed below).
**Edit intent:** Sweep and validate.
**Checks:** (1) `rg -n "trial|TRIAL|deneme|14 gün|kredi kartı|otomatik ücret" config/locales/en.yml config/locales/tr.yml app/views/marketing/ app/javascript/entrypoints/marketing.scss app/javascript/dashboard/i18n/locale/en/signup.json app/javascript/dashboard/i18n/locale/tr/signup.json app/javascript/v3/views/auth/signup/ spec/requests/marketing_homepage_spec.rb spec/lib/marketing_controller_spec.rb` → zero hits (touching only these surfaces; hits in `app/javascript/dashboard/store/modules/accounts.js`, `UpgradePage.vue`, `design-prototypes/` are expected and out of scope); (2) run the full Validation Matrix; (3) confirm `git status` shows only intended files.
**Gate:** matrix green; `rg` sweep clean.

---

## Test Strategy Summary (by concern)

| Concern | Phase | Exact files |
|---|---|---|
| Builder opt-in default/on + constants | 1 | `spec/builders/account_builder_spec.rb` |
| Password signup eligible (100/600) | 2, 3 | v1 + v2 accounts controller specs (real-path + arg assertions) |
| OAuth signup eligible (100/600) | 4 | omniauth controller spec |
| Installation/manual/platform/existing unchanged | 1, 2, 4, 5 | builder default test; v1 authenticated-account test; onboarding + platform + super_admin specs stay green; account_spec reader defaults |
| SuperAdmin independent + 0 + immediate | 5 | `spec/controllers/super_admin/accounts_controller_spec.rb` + `spec/models/account_spec.rb` |
| 99/100/101, handoff/no LLM, month reset, immediate change | 6 | `ai_agents/usage/limiter_spec.rb`, `live_processor_spec.rb` |
| 599/600/601 across text_test + second op, concurrency, month reset | 7 | `ai_improvements/usage/limiter_spec.rb` |
| Endpoint-level 599/600/601 (text_test, website_import) + manual-reply decoupling | 8 | test_conversations, website_imports, messages controller specs |
| Marketing request/Vitest/i18n/lint/build | 9, 10, 11 | marketing_homepage_spec, marketing_controller_spec, signup specs, `pnpm eslint`, `pnpm test`, `pnpm build:sdk` smoke |

---

## Validation Matrix (exact commands)

All backend runs via the repo-native test env (Node 24/.nvmrc, Corepack pnpm 10, rbenv Ruby 3.4.4):

```bash
# Phase 1
RAILS_ENV=test POSTGRES_DATABASE=chatwoot_test .agents/skills/chatwoot-ai-native-test/scripts/with-chatwoot-env.sh rbenv exec bundle exec rspec spec/builders/account_builder_spec.rb spec/models/account_spec.rb
# Phase 2
... rbenv exec bundle exec rspec spec/controllers/api/v1/accounts_controller_spec.rb spec/enterprise/controllers/api/v1/accounts_controller_spec.rb
# Phase 3
... rbenv exec bundle exec rspec spec/controllers/api/v2/accounts_controller_spec.rb spec/enterprise/controllers/enterprise/api/v2/accounts_controller_spec.rb
# Phase 4
... rbenv exec bundle exec rspec spec/controllers/devise/omniauth_callbacks_controller_spec.rb spec/enterprise/controllers/enterprise/devise_overrides/google_oauth_attribution_spec.rb spec/controllers/installation/onboarding_controller_spec.rb
# Phase 5
... rbenv exec bundle exec rspec spec/controllers/super_admin/accounts_controller_spec.rb spec/models/account_spec.rb
# Phase 6
... rbenv exec bundle exec rspec spec/services/ai_agents/usage/limiter_spec.rb spec/services/ai_agents/usage/summary_spec.rb spec/services/ai_agents/live_processor_spec.rb
# Phase 7
... rbenv exec bundle exec rspec spec/services/ai_improvements/usage/limiter_spec.rb spec/services/ai_improvements/usage/summary_spec.rb spec/services/ai_improvements/usage/meter_spec.rb
# Phase 8
... rbenv exec bundle exec rspec spec/controllers/api/v1/accounts/ai_agent_test_conversations_controller_spec.rb spec/controllers/api/v1/accounts/ai_agent_website_imports_controller_spec.rb spec/controllers/api/v1/accounts/conversations/messages_controller_spec.rb
# Phases 9-10
... rbenv exec bundle exec rspec spec/requests/marketing_homepage_spec.rb spec/lib/marketing_controller_spec.rb
# Phase 11
pnpm test app/javascript/v3/views/auth/signup
pnpm exec eslint app/javascript/v3/views/auth/signup/ app/javascript/dashboard/i18n/locale/en/signup.json 2>/dev/null || pnpm exec eslint app/javascript/v3/views/auth/signup/
# Phase 12 full
pnpm ruby:prettier    # rubocop -a on changed ruby files
pnpm eslint           # full frontend lint
pnpm test             # full vitest
pnpm build:sdk        # build smoke
bundle exec rubocop --force-exclusion app/models/account.rb app/builders/account_builder.rb app/controllers/api/v1/accounts_controller.rb app/controllers/api/v2/accounts_controller.rb app/controllers/devise_overrides/omniauth_callbacks_controller.rb
```

| Check | Command / Method | Proves |
|------|------------------|--------|
| Exact regression path (new signup → 100/600) | Phase 2/3 specs + runtime Scenario A/B | Freemium defaults applied |
| Edge: existing/authenticated unchanged | Phase 2 authenticated test + builder default test | No quota mutation |
| Edge: explicit 0 / malformed legacy settings | Phase 5 tests + existing `account_spec.rb:548-572` | Readers untouched |
| Behavior preservation: limiter boundaries, handoff, month reset | Phases 6-8 + existing limiter specs | No limiter regression |
| Preservation: public API payloads | existing `ai_agents_controller_spec.rb:68,135` | No API drift |
| Preservation: signup gate off | existing 404 + `no-account-found` specs + runtime probe | Gate intact |
| i18n parity en↔tr | `marketing_controller_spec.rb:97-109`, `Index.spec.js:56-69` | Both locales aligned |

---

## Runtime Evidence Matrix (post-implementation; disposable local stack)

Signup gate safety: production signup stays **off** — runtime evidence uses a disposable local DB only; no SMTP/hCaptcha production enabling.

| Criterion | Surface | Action | Expected | Cleanup | Status |
|---|---|---|---|---|---|
| Stack up | runtime | `docker compose up -d postgres redis`; PM2 `chatwoot-backend`/`chatwoot-worker`/`chatwoot-vite` via `with-chatwoot-env.sh` + Node 24; `curl -sSf http://localhost:3000/health` → `{"status":"woot"}` | health woot | stop PM2 processes; keep DB/redis running | VERIFIED |
| Gate still off by default | API | unauth `POST /api/v1/accounts` before enabling | 404 (RoutingError) | — | VERIFIED |
| Enable signup on disposable DB | datastore | `rbenv exec bundle exec rails runner "InstallationConfig.find_or_create_by(name: 'ENABLE_ACCOUNT_SIGNUP').update!(value: true); InstallationConfig.find_or_create_by(name: 'REQUIRE_EMAIL_CONFIRMATION').update!(value: false); GlobalConfig.clear_cache"` | no error | delete both InstallationConfig rows + `GlobalConfig.clear_cache` at teardown | VERIFIED |
| v1 password signup → freemium | API | unauth `POST /api/v1/accounts` (`email` random, `password`, `h_captcha_client_response: 'x'`; hCaptcha passes because server key blank — F20) | 200; `Account.find(...).settings` include `ai_agent_conversation_limit: 100`, `ai_improvement_monthly_credit_limit: 600`; user confirmed | destroy created user/account | VERIFIED |
| v2 signup → freemium | API | unauth `POST /api/v2/accounts` | 200 + same settings | destroy created user/account | VERIFIED |
| Live smoke: reservation lifecycle without LLM provider | API/datastore | create AI agent on the v1 account; drive one `send_message` on a test conversation WITHOUT an LLM provider configured | a shared-credit reservation event is created for the account (`AiImprovementUsageEvent` with operation `text_test`); after the failed provider call it is **released** (or remains reserved until stale-TTL release); assert reservation/release behavior and that the summary reflects the transient decrease | destroy records | VERIFIED for reservation/release; **consumed-status proof (1 credit consumed) requires an LLM provider → report UNVERIFIED without one** (100-message live drive stays in specs) |
| SuperAdmin immediate change | UI/API | sign in seeded super admin; PATCH `conversation_limit: 0` then `150` via `/super_admin/accounts/:id` | readers reflect immediately; summary remaining changes without usage rewrites | revert to seed state | VERIFIED |
| Google OAuth live signup | browser | real Google login → new account settings 100/600 | 100/600 | destroy created user/account | **UNVERIFIED without Google credentials** (specs cover wiring; report explicitly) |
| Production gate | config | confirm `.env.server.local`/InstallationConfig leave `ENABLE_ACCOUNT_SIGNUP` false | gate off | none | VERIFIED (do not enable) |

Teardown: delete only records created for these scenarios (`User.where(email: <random emails>)` → cascades to account/usage fixtures), delete the two `InstallationConfig` rows, `GlobalConfig.clear_cache`, stop PM2 processes. Never touch other records, and never run these steps on the home-server host.

---

## Risks & Rollback

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Regressing existing-account quota semantics | LOW | HIGH | Constants-only additions to `account.rb`; Phase 1 gate diff-check; existing reader specs must stay green |
| Missing a builder-arg assertion → CI break | LOW | MEDIUM | Exact site list (F14) pre-verified; Phase 2-4 gates run full affected spec files |
| Community locale stale `TRIAL` keys after rename | MEDIUM | LOW | Only en/tr are maintained; no cross-locale parity check exists (A2); Crowdin flow |
| Thread-based concurrency spec flakes | LOW | MEDIUM | Invariant is interleaving-independent (sum of credits = 600, exactly 200 Exhausted) due to `with_lock` |
| Fingerprint regeneration error | LOW | MEDIUM | Canonical meta-neutralized-body method documented in Phases 9 and 10 (rendered body changes twice); analyzer-verified anchor digest `1e66cb…` confirms the method; ONE capture per phase, controller constant only (single source — no spec literal) |
| Accidental production signup enablement during runtime checks | LOW | HIGH | Runtime matrix explicitly restricted to disposable local DB; teardown restores gate |
| Live Google OAuth unverifiable | MEDIUM | LOW | Marked UNVERIFIED in evidence matrix; automated specs cover the path |

Rollback: every phase is a single revertible commit; no migration, no data rewrite, no schema — global rollback = `git revert` of the phase commits in reverse order. Copy phases additionally restore the controller fingerprint constant automatically with the revert.

---

## Allowed Scope / Forbidden Scope

- **Allowed:** the files listed per phase (Account model constants, AccountBuilder, v1/v2/omniauth controllers, their specs, super_admin/limiter/live_processor/messages/test-conversations/website-imports specs, en/tr marketing locales + home.html.erb + marketing.scss + marketing specs + fingerprint constant, en/tr signup.json + signup components + their specs), plus this plan file.
- **Forbidden:** `Account` reader/fallback semantics (`account.rb:231-233`, `:259-267`), limiter logic (`ai_agents/usage/*`, `ai_improvements/usage/*`), settings schema, routes, migrations/schema, public API serializers/payloads, `ENABLE_ACCOUNT_SIGNUP`/`REQUIRE_EMAIL_CONFIRMATION` defaults or gate code, devise/user/confirmation flows, hCaptcha behavior, `app/javascript/dashboard/store/modules/accounts.js` (`TRIAL_PERIOD_DAYS`/`isTrialAccount`), `UpgradePage.vue`, enterprise overlay modules (no new hooks; enterprise specs only get the arg updates), `design-prototypes/kozmopath-trial-conversion/*`, any new feature flag, payment/expiry state, and any production/home-server runtime change.

---

## Docs / Skill Freshness Assessment

- `docs/marketing-homepage-assets.md`: asset SHAs unchanged → no update required (fingerprint is not documented there; optional note out of scope).
- `docs/ai-agent-catalog-runtime.md`: untouched (no catalog/orchestrator change).
- Skills: `chatwoot-i18n-branding`, `chatwoot-enterprise-overlays`, `chatwoot-ai-agent-local-testing`, `chatwoot-dev-runbook` contain no trial/quota references and no commands that change → no skill updates needed.
- `AGENTS.md`: no change needed (no new commands; `pnpm sync:i18n` explicitly NOT needed — import manifests unchanged, F19).
- Optionally note in the plan file itself once implemented; no other doc churn.

---

## Evidence Owners

| Item | Owner | Proof required |
|---|---|---|
| Builder opt-in default false + constants | @implementer (Phases 1-4) | rspec run output; `git diff` of account.rb |
| Existing-account semantics untouched | @implementer (Phase 5) + @analyzer | green `account_spec.rb` + super_admin spec; diff review |
| Limiter boundaries/handoff/month reset | @implementer (Phases 6-7) | rspec output with counts 99/100/101, 599/600/601 |
| Endpoint + decoupling proofs | @implementer (Phase 8) | rspec output (402 codes, message persisted) |
| Copy exact strings + parity + fingerprint | @implementer (Phases 9-10) + @analyzer | rspec/vitest output; meta-neutralized SHAs (Phase 9 copy, Phase 10 selectors); en/tr parity; meta-sync assertion green |
| Gate safety + runtime evidence | @implementer (runtime matrix) | evidence rows with cleanup status |
| Full-suite green + sweep | @implementer (Phase 12) | matrix output; `rg` sweep output |

## Review Gates

| Gate | After Phase | Focus for @analyzer |
|---|---|---|
| 1 | Phase 1 | Constants-only `account.rb` diff; default-false semantics; builder settings merge |
| 2 | Phase 4 | All 7 arg-assertion sites updated; enterprise specs green; onboarding untouched |
| 3 | Phase 5 | SuperAdmin independence/0/immediacy proofs; no implementation drift |
| 4 | Phase 8 | Boundary counts and decoupling assertions; no limiter logic changes |
| 5 | Phase 11 | Exact mandated strings in en source; no card/autobilling; parity tests; selectors renamed |
| 6 | Phase 12 | Full matrix; sweep; scope compliance |

## Failure Signals

- Any phase gate fails in an untouched spec (signal of an unplanned coupling not listed in Blast Radius) → stop, investigate, do not proceed.
- `account.rb` diff contains reader/fallback edits → plan violated; revert Phase 1.
- New signup produces quotas while `ENABLE_ACCOUNT_SIGNUP=false` in a runtime probe → gate regression; stop.
- `rg` sweep still finds trial vocabulary in the touched surfaces after Phase 11 → Phase 12 blocks.
- Community-locale key mismatch breaks a build/test unexpectedly → re-check A2 (currently no such check exists).

---

## Decision Log

| Decision | Chosen | Rejected | Rationale | Evidence |
|----------|--------|----------|-----------|----------|
| D1: v2 eligibility | Include v2 (`current_user.nil?`) | Exclude v2 | v2 is an unauthenticated password signup (skips auth, gated, captcha, builder) — same class as v1 signup | `api/v2/accounts_controller.rb:4-9,16-33` |
| D2: Constants location | `Account::FREEMIUM_*` constants | In-builder literals / renaming `DEFAULT_AI_IMPROVEMENT_...` | Single home next to the existing quota constant; generic fallback untouched | `account.rb:46,259-267` |
| D3: Option shape | `{ apply_freemium_limits: false }` | Env flag / new feature flag | Explicit internal opt-in default false; eligibility derivable at call sites; repo pattr default syntax | `account_builder.rb:5`; `lib/captain/base_task_service.rb:22` |
| D4: Limiter logic | No changes; regression specs only | Touching boundaries/reset | Established, spec-pinned behavior already meets requirements | F8-F12 |
| D5: Key renames | `marketing.trial.*`→`marketing.freemium.*`; `REGISTER.TRIAL.*`→`REGISTER.FREEMIUM.*` | Keep keys, change values | Requirement mandates freemium keys/selectors; parity tests cover en↔tr | F15, F18 |
| D6: Selector renames | `data-trial-cta`, `trial-signup-form`, `trial-sequence-step`, 3 CSS classes → freemium equivalents | Keep selectors | Requirement mandates selector rename; all usages/assertions enumerated | F17, F18 |
| D7: Sync | No `pnpm sync:i18n` | Run it | Script only mirrors `en/index.js` when staged; content-only edits | F19 |
| D8: Signup rename atomicity | One 6-file phase | Split json/components | No working intermediate (missing-key render); tests stub `t` so CI alone can't catch it | F18 |
| D9: Out-of-scope trial traces | Leave `accounts.js` `TRIAL_PERIOD_DAYS`/`isTrialAccount` + `UpgradePage.vue` untouched | Remove/rename | Not homepage/signup copy; cloud/enterprise-gated dashboard surface; no global billing banner added/removed | F24 |
| D10: Runtime signup enablement | Disposable local stack only; gate restored at teardown | Production enablement | Operational gate stays off until SMTP/hCaptcha E2E verified | F20, A1 |
| D11: Fingerprint verification method (discovered plan correction, NOT a requirement change) | Meta-neutralized-body SHA256: spec hashes the final response body after replacing the design-contract meta's 64-hex value with empty (scoped anchored regex), asserts it equals the single source `MarketingController::DESIGN_CONTRACT_SHA`, and asserts the rendered meta mirrors the constant | Full-body `sha256(response.body)` with a duplicated spec literal | The body embeds the constant via the layout, so `constant == sha256(full body)` requires an infeasible SHA fixed point; neutralizing the meta makes the digest body-independent and stable; single source avoids drift | `app/views/layouts/marketing.html.erb:10`; `app/controllers/marketing_controller.rb:3`; analyzer-verified canonical digest `1e66cb7dec356e70de58def01e8aa0feb5e2e2124801a2a0cd8a50eaa3899a56` for the current signup-enabled `www.kozmopath.com` Turkish render |

## Notes

- Turkish homepage is the tested marketing locale (`around_action :use_turkish_locale`); English exact-string mandates are enforced at the `en` source-locale level (en.yml / en signup.json) and the rendered EN dashboard bundle.
- The mandated exact strings appear: marketing homepage announcement node (en source) and signup card `<strong>`/`<small>` (en source; rendered in the en dashboard).
- SuperAdmin `0` remains the unlimited sentinel for both limits (`limit.zero?` branches) — no new sentinel introduced.
- No usage-rewrite, backfill, or data migration exists in any phase; "immediate apply" is inherent (F12).

## Plan Correction (discovered during analyzer review — not a user requirement change)

**The originally documented fingerprint method was invalid and is superseded.** The previous instructions hashed the full rendered `response.body` (`Digest::SHA256.hexdigest(response.body)`) and set both `MarketingController::DESIGN_CONTRACT_SHA` and a duplicated spec literal (`contract_html_sha`) to that digest. Because `app/views/layouts/marketing.html.erb:10` embeds the constant into the body, `constant == sha256(body containing constant)` demands a SHA-256 fixed point — infeasible. The previously stored full-body hash is therefore invalid under the canonical method and must NOT be used.

**Canonical method (current and only):** neutralize the design-contract meta before hashing — replace its 64-hex content with empty via the anchored regex in Phase 9, hash the raw `response.body`, and assert against the single source `MarketingController::DESIGN_CONTRACT_SHA`; the spec additionally asserts the rendered meta mirrors the constant. The analyzer-verified canonical digest of the current signup-enabled `www.kozmopath.com` Turkish render is `1e66cb7dec356e70de58def01e8aa0feb5e2e2124801a2a0cd8a50eaa3899a56` (used as the Phase 9 anchor). Historical references to the old full-body method in this file, if any, are invalid by definition of this note.
