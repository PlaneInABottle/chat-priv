# ikas Account Integration — Implementation Plan

## Title / goal

Add a proper account-level ikas integration to Chatwoot OSS so an account administrator can connect ikas from **Settings → Integrations**, store credentials safely, validate the connection, see connection status, and disconnect later. This plan covers only ikas account setup; any later AI-agent/tool usage is a downstream consumer and stays out of scope.

## Problem Statement

Chatwoot already has two relevant patterns: a dedicated account-level Shopify integration flow and a generic `Integrations::Hook` / `Integrations::App` integration framework. ikas needs a Shopify-style account integration entry in Settings, but unlike Shopify there is no verified evidence of a browser OAuth redirect requirement for Chatwoot OSS. Verified ikas docs now show that private apps use OAuth `client_credentials`, but token acquisition is **store-specific**, so the safest v1 is a manual credential form backed by the existing hook model with `client_id`, `client_secret`, and `store_name`/normalized `store_url`, plus explicit validation before persistence and no AI-agent runtime work.

## Approach

Use a **single account-scoped `Integrations::Hook` record with `app_id: 'ikas'`**, a **dedicated ikas settings page/controller** patterned after Shopify, and a **manual credential form** that asks for `client_id`, `client_secret`, and `store_name`/normalized `store_url`. Reuse existing app catalog, hooks table, integrations store/module, and settings routes; treat the GraphQL API URL as Chatwoot internal configuration, keep `sales_channel_id` out of connection setup, and avoid new tables, OAuth redirect assumptions, or broad framework refactors.

## Success Criteria

- [ ] ikas appears in Settings → Integrations only when the feature is enabled and secret storage is safe enough for manual credentials.
- [ ] An administrator can connect ikas with a manual form that asks for `client_id`, `client_secret`, and `store_name`/normalized `store_url`, and Chatwoot keeps the secret out of serialized JSON responses.
- [ ] Failed validation does not create or mutate a working ikas hook.
- [ ] The settings page shows a stable connected/disconnected status, key non-secret credential metadata including the connected store identifier, and a disconnect action.
- [ ] Disconnect removes the account’s ikas hook without affecting Shopify or generic hook-based integrations.
- [ ] No AI-agent runtime behavior is added in this plan.

## Scope / out of scope

### In scope

- Account-level ikas entry in the integrations catalog
- ikas settings page in dashboard settings
- Manual connect / update / status / disconnect flow
- Hook-backed storage design for the entered auth fields
- Validation service for submitted credentials
- Feature-flag gating
- OSS test coverage for backend and dashboard integration state management

### Out of scope

- AI-agent tool runtime or ikas query execution
- Product/order/customer sync jobs
- Periodic background revalidation or token refresh daemons
- Webhooks from ikas
- Super-admin global ikas credentials
- New database tables or new encrypted columns
- Enterprise-only behavior changes

## Current state (evidence)

- Account-scoped integrations already persist through `Account has_many :hooks` (`app/models/account.rb:123-130`).
- `Integrations::Hook` already stores `access_token`, `settings`, `status`, and `reference_id`, validates per-app JSON schema, and encrypts `access_token` only when `Chatwoot.encryption_configured?` is true (`app/models/integrations/hook.rb:24-31`, `app/models/integrations/hook.rb:36-45`, `app/models/integrations/hook.rb:92-95`).
- The integrations catalog is driven by `config/integration/apps.yml`, surfaced via `Integrations::App`, and returned from `Api::V1::Accounts::Integrations::AppsController#index` (`config/integration/apps.yml:1-11`, `app/models/integrations/app.rb:51-66`, `app/controllers/api/v1/accounts/integrations/apps_controller.rb:12-17`).
- Shopify uses a dedicated controller and dedicated settings page instead of the generic `NewHook.vue` form (`app/controllers/api/v1/accounts/integrations/shopify_controller.rb:1-39`, `app/javascript/dashboard/routes/dashboard/settings/integrations/Shopify.vue:23-145`).
- Generic hook integrations use `settings_form_schema` / `visible_properties` in `apps.yml` and the generic `IntegrationHooks` + `NewHook.vue` flow (`config/integration/apps.yml:32-58`, `app/javascript/dashboard/routes/dashboard/settings/integrations/NewHook.vue:60-97`, `app/javascript/dashboard/routes/dashboard/settings/integrations/MultipleIntegrationHooks.vue:32-47`).
- Shopify currently stores its account connection in `Integrations::Hook` with `access_token`, `reference_id`, `status`, and `settings[:scope]` (`app/controllers/shopify/callbacks_controller.rb:25-34`).
- No Shopify-specific Enterprise overlay exists, but super-admin app config controllers do have Enterprise prepend hooks (`enterprise/app/controllers/enterprise/super_admin/app_configs_controller.rb:1-18`, `config/initializers/01_inject_enterprise_edition_module.rb:23-28`).
- Verified ikas docs / Context7 facts provided by the user: private apps use OAuth `client_credentials`; token endpoint is store-specific (`https://<your_store_name>.myikas.com/api/admin/oauth/token`); token request requires `client_id` and `client_secret`; verified v1 GraphQL endpoint is `https://api.myikas.com/api/v1/admin/graphql`; `sales_channel_id` is not part of auth; docs recommend evaluating v2 later, but the verified auth/API details available for this plan are v1.

## Verified facts vs assumptions table

| Type | Item | Evidence / notes |
|---|---|---|
| Verified fact | Chatwoot stores account integrations in `integrations_hooks` via `Account#hooks` | `app/models/account.rb:129` |
| Verified fact | `Integrations::Hook.access_token` is conditionally encrypted, not always encrypted | `app/models/integrations/hook.rb:24-26` |
| Verified fact | `settings` can be schema-validated per app via `settings_json_schema` | `app/models/integrations/hook.rb:92-95`, `config/integration/apps.yml:9-10` |
| Verified fact | Generic hook JSON shown to admins includes `settings` and `reference_id`, but not `access_token` | `app/views/api/v1/models/_hook.json.jbuilder:8-9` |
| Verified fact | Shopify is a single account-level integration (`hook_type: account`, `allow_multiple_hooks: false`) | `config/integration/apps.yml:204-209` |
| Verified fact | Shopify connect/disconnect is handled by dedicated endpoints, not by generic hooks CRUD | `config/routes.rb:326-330`, `app/controllers/api/v1/accounts/integrations/shopify_controller.rb:7-39` |
| Verified fact | The integrations dashboard already has a dedicated Shopify settings route/component | `app/javascript/dashboard/routes/dashboard/settings/integrations/integrations.routes.js:103-112`, `app/javascript/dashboard/routes/dashboard/settings/integrations/Shopify.vue:23-145` |
| Verified fact | Generic manual integrations already rely on `settings_form_schema` and `visible_properties` | `app/javascript/dashboard/routes/dashboard/settings/integrations/NewHook.vue:60-97`, `app/javascript/dashboard/routes/dashboard/settings/integrations/MultipleIntegrationHooks.vue:32-47` |
| Verified fact | `Integrations::App#enabled?` is based on hook existence, not hook `status` | `app/models/integrations/app.rb:81-89` |
| Verified fact | Shopify-specific Enterprise overlay files were not found under `enterprise/` | explore evidence; no matching enterprise Shopify controller/module |
| Verified fact | ikas private apps use OAuth2 `client_credentials` | official ikas docs / Context7 fact provided by user |
| Verified fact | ikas token endpoint is store-specific: `https://<your_store_name>.myikas.com/api/admin/oauth/token` | official ikas docs / Context7 fact provided by user |
| Verified fact | token request requires `client_id` and `client_secret` | official ikas docs / Context7 fact provided by user |
| Verified fact | verified v1 GraphQL endpoint is `https://api.myikas.com/api/v1/admin/graphql` | official ikas docs / Context7 fact provided by user |
| Verified fact | `sales_channel_id` is not part of authentication | official ikas docs / Context7 fact provided by user |
| Verified fact | docs recommend newer API users evaluate v2, but the verified auth path available to this plan is v1 | official ikas docs / Context7 fact provided by user |
| Superseded assumption | a two-field (`client_id` + `client_secret`) onboarding form might be sufficient | superseded by verified store-specific token endpoint requirement |
| Assumption | `sales_channel_id` may later be required by specific ikas tools, but not by base account authentication | still downstream-only; no verified Chatwoot consumer yet |
| Assumption | Future ikas tool-context should live in structured Chatwoot config rather than prompt text | planning recommendation to avoid hidden, non-auditable runtime dependencies |

## Locked decisions from planning

| Topic | Decision |
|---|---|
| Accepted store input | Full URL entered in UI |
| Canonical stored store value | normalized host only, stored in `reference_id` |
| Example canonical value | `mystore.myikas.com` |
| API URL | internal default only: `https://api.myikas.com/api/v1/admin/graphql` |
| Malformed/invalid existing hook | show `reconnect_required` state, not connected |
| Encryption unavailable | show ikas in integrations list/detail, but disabled with explanation |
| Validation probe | token acquisition + lightweight GraphQL `me` query |
| Base auth version | v1 verified path today; v2 is later follow-up |

## Shopify reference pattern summary

1. **Catalog presence**: Shopify is defined as a single account integration in `config/integration/apps.yml` (`config/integration/apps.yml:204-209`).
2. **Visibility gating**: `Integrations::App#active?` has an explicit Shopify branch gated by feature flag + global config presence (`app/models/integrations/app.rb:57-59`, `122-124`).
3. **Dedicated controller**: Shopify does not use generic hooks CRUD for connect; it uses `Api::V1::Accounts::Integrations::ShopifyController` plus a separate callback controller (`app/controllers/api/v1/accounts/integrations/shopify_controller.rb:7-39`, `app/controllers/shopify/callbacks_controller.rb:4-36`).
4. **Storage**: The final account connection is still persisted as `Current.account.hooks.create!(app_id: 'shopify', access_token:, reference_id:, settings:, status: 'enabled')` (`app/controllers/shopify/callbacks_controller.rb:25-34`).
5. **Frontend UX**: Shopify has a dedicated route and component for connect/disconnect UX instead of `IntegrationHooks.vue` (`app/javascript/dashboard/routes/dashboard/settings/integrations/integrations.routes.js:103-112`, `app/javascript/dashboard/routes/dashboard/settings/integrations/Shopify.vue:90-145`).
6. **Disconnect**: Shopify disconnect is a dedicated `DELETE` endpoint that destroys the hook (`app/controllers/api/v1/accounts/integrations/shopify_controller.rb:34-39`).

**What to reuse for ikas**: app catalog entry, single-hook model, dedicated settings page, dedicated controller, and destroy semantics.

**What not to reuse blindly**: Shopify’s OAuth redirect/callback flow, because ikas browser redirect is not verified.

## Recommended ikas integration model

Use a **Shopify-style dedicated integration surface** with a **manual credential form** and **single hook per account**.

### Recommended v1 model

- `app_id: 'ikas'`
- `hook_type: account`
- `allow_multiple_hooks: false`
- dedicated `Api::V1::Accounts::Integrations::IkasController`
- dedicated dashboard page `settings/integrations/ikas`
- user-entered fields: `client_id`, `client_secret`, and `store_name` or normalized `store_url`
- internal/default GraphQL API base: `https://api.myikas.com/api/v1/admin/graphql`; not user-editable in v1
- verified auth path for v1: store-specific `client_credentials` token acquisition
- `create` and `update` perform live validation before persistence
- `destroy` only disconnects locally (no remote revoke unless official docs later justify it)
- integrations list/detail must render `reconnect_required` for malformed or no-longer-valid hooks

### Why this is the simplest correct v1

- Reuses Chatwoot’s existing account integration storage (`Integrations::Hook`)
- Matches the established “special integration gets a dedicated page” Shopify pattern
- Avoids inventing a new persistence model or config store
- Avoids unverified OAuth browser redirect assumptions
- Keeps onboarding minimal while still satisfying verified store-specific auth requirements
- Keeps AI-agent consumption as a later read-only consumer of the hook

## Required vs optional account-level fields

### Fields required to connect / authenticate in v1

| Field | v1 recommendation | Secret? | Why |
|---|---|---:|---|
| `client_id` | Required | No (but sensitive-ish) | Required by verified client-credentials auth flow |
| `client_secret` | Required | Yes | Required by verified client-credentials auth flow; must not be returned in serialized JSON |
| full `store_url` | Required | No | Required because the verified token endpoint is store-specific, and product chose full URL input |

### Internal/non-user-entered connection config in v1

| Field | v1 recommendation | Secret? | Why |
|---|---|---:|---|
| `api_url` | Internal Chatwoot constant/config, not user-entered | No | Verified v1 GraphQL endpoint is shared and can be defaulted internally |

### Deferred downstream tool-context fields

| Field | v1 status | Why deferred |
|---|---|---|
| `store_url` | Not part of account connection form | appears more relevant to store-scoped token resolution or later tool execution than to basic credential capture |
| `sales_channel_id` | Not part of account connection form | likely tool-specific filtering/routing metadata, not core account credential input |

**Recommendation**: Implement the v1 UI with full `store_url`, `client_id`, and `client_secret`. Treat `api_url` as internal Chatwoot configuration. Treat `sales_channel_id` as a **deferred downstream requirement** for specific ikas tools, not as part of basic account connection.

### Superseded two-field idea

The earlier two-field (`client_id` + `client_secret`) idea is now superseded by verified docs. It is insufficient because Chatwoot cannot acquire an ikas token without a store-specific token URL.

### Tradeoff introduced by the verified three-field approach

This adds one more user-entered field, but it is the smallest form that satisfies the verified auth contract while preserving Shopify-style account setup. It keeps `sales_channel_id` and other tool-specific metadata out of base connection.

## Secret vs non-secret storage design

### Recommended storage mapping

| Data | Storage location | Reason |
|---|---|---|
| `client_secret` | `Integrations::Hook.access_token` | Existing dedicated secret-ish field; not serialized by `_hook.json.jbuilder`; can be encrypted when Chatwoot encryption is configured |
| `client_id` | `settings['client_id']` | Non-secret form field; needed for later downstream token requests |
| normalized store host | `reference_id` (canonical) | Verified auth requires a store-specific token URL; canonical store identifier should be stored explicitly and reused for reconnect/status |
| `api_url` | internal constant/config, not per-account user data | Keeps endpoint behavior consistent and avoids unnecessary account-level config |
| `sales_channel_id` | not stored by v1 account integration | deferred until a concrete tool requires it |

### Specific recommendation

- Do **not** store `client_secret` inside `settings`, because admin hook responses include `settings` (`app/views/api/v1/models/_hook.json.jbuilder:8-9`).
- Do **not** store short-lived ikas bearer tokens in the database in v1; validate on save, then discard the temporary token.
- Prefer `reference_id` for the canonical normalized store identifier because Chatwoot already uses it for external-store/domain identity in Shopify (`app/controllers/shopify/callbacks_controller.rb:30`).

### Canonical normalization rule for store input

- **Accepted input**: full URL only, for example `https://mystore.myikas.com`, `http://mystore.myikas.com/`, or `mystore.myikas.com`
- **Normalization algorithm**:
  1. trim whitespace
  2. add `https://` temporarily if scheme is missing so URL parsing is deterministic
  3. parse URL and extract host
  4. lowercase host
  5. strip trailing dot
  6. reject if host does not match `*.myikas.com`
  7. store canonical host only
- **Canonical stored value**: `mystore.myikas.com`
- **`reference_id` population**: always set to the canonical normalized host; this is the single source of truth for the account’s connected ikas store
- **Token URL derivation**: `https://#{reference_id}/api/admin/oauth/token`

### Future structured config recommendation

If later ikas tools concretely require `sales_channel_id` or other tool-only metadata beyond the connected store identifier, store them in a **structured Chatwoot-owned config location** rather than prompt text. The most natural future home is a namespaced block under the ikas hook settings, such as `hook.settings['tool_context']` or a similarly explicit account-level integration metadata object.

### Why prompt-only store context is risky

- prompts are not a reliable source of truth for backend-auth requirements
- prompt text is hard to audit, validate, or migrate
- hidden prompt dependencies make connect-status misleading because the account may look “connected” while required tool context is missing
- prompt changes can silently break tool execution without a visible settings diff
- backend services cannot safely depend on prompt parsing for auth-critical routing

### Security gate

Because `access_token` encryption is conditional (`app/models/integrations/hook.rb:24-26`), v1 should treat **manual ikas connection as unavailable unless `Chatwoot.encryption_configured?` is true**. Otherwise a long-lived ikas `client_secret` would be stored in plaintext. This is stricter than existing Shopify behavior, but it is the safer design for a manual-secret integration.

## Integration app catalog/config changes

### Likely OSS files

- `config/integration/apps.yml`
- `config/features.yml`
- `app/models/integrations/app.rb`

### Recommended changes

1. Add a new `ikas` app entry to `config/integration/apps.yml` with:
   - `id: ikas`
   - `i18n_key: ikas`
   - `hook_type: account`
   - `allow_multiple_hooks: false`
   - `feature_flag: ikas_integration`
   - `logo: ikas.png` (plus dark asset if product provides it)
   - `settings_json_schema` for non-secret keys only, including `client_id` and optional non-secret validation metadata
2. Add `ikas_integration` to `config/features.yml`, disabled by default.
3. Add an explicit `when 'ikas'` branch to `Integrations::App#active?` so the app is only listed when:
   - account feature `ikas_integration` is enabled, and
   - no super-admin/global config is required.

   Encryption availability affects ikas connectability/state (`disabled` vs connectable), not catalog visibility.

### Why not use `settings_form_schema`?

The generic form flow serializes everything into `settings` through generic hooks CRUD (`app/controllers/api/v1/accounts/integrations/hooks_controller.rb:5-10`, `42-43`). That is the wrong fit for `client_secret`, so ikas should have a dedicated page/controller rather than `NewHook.vue`.

## Backend design (models/controllers/routes/services)

### Reused model

- Reuse `Integrations::Hook`; no new table and no new ActiveRecord model.

### Recommended routes

Add a dedicated account-scoped singular resource next to Shopify in `config/routes.rb`:

- `GET /api/v1/accounts/:account_id/integrations/ikas` → current connection state
- `POST /api/v1/accounts/:account_id/integrations/ikas` → connect
- `PATCH /api/v1/accounts/:account_id/integrations/ikas` → update/revalidate
- `DELETE /api/v1/accounts/:account_id/integrations/ikas` → disconnect

### Recommended controller

`Api::V1::Accounts::Integrations::IkasController`

Responsibilities only:

- authorize administrator access (same model as other integration controllers)
- load existing ikas hook for current account
- normalize input params
- call validator service
- upsert hook only on validation success
- return sanitized connection payload
- destroy hook on disconnect

### Existing-hook state classification

The controller/page should classify ikas state into exactly these buckets:

- `not_connected`: no ikas hook exists
- `connected`: one ikas hook exists and latest validation succeeds
- `reconnect_required`: hook exists but required fields are missing, duplicated, malformed, or live validation fails
- `disabled`: ikas is visible but connect actions are unavailable because encryption is not configured

### Recommended service

`Integrations::Ikas::ConnectionValidator`

Responsibilities:

- validate presence/shape of submitted fields
- use the internal/default ikas API URL configuration
- normalize submitted full `store_url` into a canonical host identifier
- attempt auth against `https://<store>.myikas.com/api/admin/oauth/token` with `client_id` and `client_secret`
- perform one lightweight API ping against the internal/default API URL
- return structured success/error result without persisting anything

Optional helper if implementation wants cleaner separation:

- `Integrations::Ikas::ConnectionParams` for normalization only

### Upsert behavior

- `POST create`: create a new hook only after validation success.
- `PATCH update`: validate first; on success update the existing hook in place.
- If update validation fails, keep the existing working hook untouched.

### Suggested stored shape

```text
Integrations::Hook
  app_id: 'ikas'
  account_id: <account>
  hook_type: 'account'
  access_token: <client_secret>
  reference_id: <normalized store host>
  status: 'enabled'
  settings:
    client_id: <string>
    validation_state: 'connected' | 'reconnect_required'
    last_validated_at: <timestamp|null>
    last_validation_error_code: <string|null>
```

### Sanitized response contract

Return a dedicated sanitized JSON payload rather than raw generic hook JSON. The implementer should use this exact contract for `GET/POST/PATCH /integrations/ikas` responses:

```json
{
  "app_id": "ikas",
  "state": "not_connected | connected | reconnect_required | disabled",
  "enabled": true,
  "can_connect": true,
  "can_disconnect": false,
  "status_message": "string_or_i18n_key",
  "store_url": "https://mystore.myikas.com",
  "store_host": "mystore.myikas.com",
  "client_id_masked": "clie••••1234",
  "last_validated_at": "2026-05-07T12:34:56Z",
  "last_validation_error_code": null,
  "encryption_available": true,
  "uses_api_version": "v1"
}
```

Contract rules:

- `enabled` means the integration is listed for the account feature-wise; it does **not** imply successful connection
- `state` drives rendering
- `can_connect` is false when encryption is unavailable
- `can_disconnect` is true only when a hook exists
- `store_url` is reconstructed as `https://#{store_host}` when a hook exists
- `client_id_masked` is the only client-id representation returned
- `last_validation_error_code` is one of a fixed set such as `invalid_store_url`, `auth_failed`, `probe_failed`, `timeout`, `duplicate_hook`, `malformed_hook`, `encryption_unavailable`
- no secret, bearer token, or raw validation response body is ever returned

## Frontend settings UX design

### Likely OSS files

- `app/javascript/dashboard/routes/dashboard/settings/integrations/integrations.routes.js`
- `app/javascript/dashboard/routes/dashboard/settings/integrations/Ikas.vue`
- `app/javascript/dashboard/api/integrations.js`
- `app/javascript/dashboard/store/modules/integrations.js`
- `app/javascript/dashboard/i18n/locale/en/integrationApps.json`
- `app/javascript/dashboard/i18n/locale/en/integrations.json`

### UX recommendation

Follow the Shopify pattern: a dedicated integration page, not `IntegrationHooks.vue`.

#### List page

- ikas appears as a normal integration card in `Index.vue` / `IntegrationItem.vue` through the app catalog.
- Clicking Configure opens `/settings/integrations/ikas`.

#### ikas settings page

- Header card reused from `Integration.vue`-style presentation.
- Primary states:
  1. **Disconnected**: empty/manual form, Connect button
  2. **Connected**: non-secret summary + Edit/Revalidate + Disconnect
  3. **Validation error on submit**: inline error, no saved state mutation
  4. **Reconnect required**: existing hook summary + warning banner + Reconnect + Disconnect
  5. **Encryption unavailable**: disabled form with explanatory message
- Form fields:
  - store name or store URL
  - client ID
  - client secret
- Editing connected config should not force re-entry of `client_secret` unless the admin changes it; blank secret on update means “keep existing secret”.
- A small read-only note should explain that `sales_channel_id` and other tool-specific metadata are not part of v1 connection and may be required later by specific ikas tools.

### Integrations list behavior

- ikas card should always be visible when the account feature `ikas_integration` is enabled, even if encryption is unavailable
- list badge/status mapping:
  - `connected` → connected badge
  - `reconnect_required` → reconnect badge / warning badge
  - `not_connected` → disconnected badge
  - `disabled` → disabled badge with tooltip/explanation
- the list must not collapse malformed or invalid hooks into “connected” just because a hook row exists

### UI behavior details

- Use existing integrations Vuex module instead of creating a new store module.
- Add ikas-specific API/store actions similar in style to Slack/Shopify handling.
- Use a delete confirmation dialog identical in concept to Shopify/Integration delete confirmation.
- Use explicit copy that separates **account connection** from **future AI-agent use** (example: “This connection can be used later by other Chatwoot features”).

## Connection validation flow

1. Admin opens ikas settings page.
2. Frontend loads `GET /integrations/ikas`.
3. Admin submits credentials through `POST` (new) or `PATCH` (edit).
4. Controller normalizes params and checks authorization.
5. `Integrations::Ikas::ConnectionValidator` performs:
   - local field validation
   - normalize the submitted full URL to canonical host
   - token request to the store-specific ikas OAuth endpoint using `client_id` and `client_secret`
   - lightweight GraphQL probe against Chatwoot’s internal/default v1 API URL using the acquired bearer token
6. On success:
   - create or update the ikas hook
   - persist only non-secret config in `settings`
   - persist `client_secret` in `access_token`
   - return sanitized connected payload
7. On failure:
   - return `422` with a user-safe error code/message
   - do not create a new hook
   - do not overwrite an existing working hook

### Validation target recommendation

- **Required**: token exchange succeeds against the store-specific token endpoint.
- **Preferred**: token exchange succeeds and one trivial authenticated GraphQL call succeeds against `https://api.myikas.com/api/v1/admin/graphql`.

### Concrete lightweight validation probe

- Preferred probe query:

```graphql
query ValidateIkasConnection {
  me
}
```

- Rationale: `me` is listed in the verified query inventory, appears lighter than product/order lookups, and does not require extra business identifiers.
- Success condition: HTTP success, no GraphQL `errors`, and non-null `data.me`
- Exact fallback if `me` proves incompatible at implementation time: switch to `query { getMerchant }` behind the same validator interface, record `probe_failed` on error, and keep the response/state contract unchanged.

The verified auth path for this plan is v1. ikas docs recommend evaluating v2 for new API users, but v2 endpoint/auth migration is a later product/implementation decision and out of scope for this v1 account integration plan.

## Disconnect flow

1. Admin clicks Disconnect on the ikas settings page.
2. Frontend confirms with a destructive dialog.
3. `DELETE /integrations/ikas` destroys the account’s ikas hook.
4. Frontend updates the integrations store so the ikas app becomes disconnected.
5. No remote revoke call is attempted in v1 unless official ikas docs explicitly support and require it.

**Why local-only disconnect is recommended**: Chatwoot already uses simple local hook destruction for Shopify and Notion (`app/controllers/api/v1/accounts/integrations/shopify_controller.rb:34-39`, `app/controllers/api/v1/accounts/integrations/notion_controller.rb:4-13`). That is the smallest reliable v1.

## Error states / edge cases

| Case | Recommended behavior |
|---|---|
| Missing required field | Client-side and server-side validation; return `422` |
| Encryption not configured | Hide or disable ikas integration; controller also hard-blocks save |
| Missing/invalid store name or store URL | Reject before token request |
| Token endpoint/network timeout | Return retryable validation error; do not persist |
| Auth rejected (`401`/`403`) | Return “invalid credentials” style error; do not persist |
| Rate-limited (`429`) | Return retry-later message; do not mutate existing connection |
| Existing hook + failed update | Keep existing hook unchanged |
| Existing malformed hook from manual DB edits | Show `reconnect_required` state on list/detail; allow disconnect or reconnect |
| Duplicate ikas hooks from bad legacy data | Show `reconnect_required`, return `duplicate_hook` error code, and block connect/update until cleanup or deterministic cleanup path is executed |
| Blank secret on edit | Interpret as “keep existing secret” unless admin toggles replace-secret action |
| Encryption unavailable | ikas remains visible in list/detail but action controls are disabled and explanation is shown |

## Security considerations

1. **Do not store `client_secret` in `settings`** because admin hook JSON exposes settings.
2. **Require encryption configuration** before allowing a manual-secret ikas integration.
3. **Filter params/logs** so `client_secret` never appears in request logs or Rails error messages.
4. **Mask secret in UI**; never echo saved `client_secret` back to the browser.
5. **Avoid persistent bearer tokens**; use them transiently inside the validator only.
6. **Authorize only account administrators** using the same policy standard as other integration controllers (`app/policies/hook_policy.rb:2-16`).
7. **Do not let generic hooks CRUD accept ikas secret payloads**; dedicated controller only.

## Auditability / observability

### Recommended v1 observability

- Structured Rails logs for:
  - ikas connection attempt started
  - ikas validation succeeded
  - ikas validation failed
  - ikas disconnected
- Include only non-secret fields in logs:
  - `account_id`
  - `app_id`
  - normalized store identifier
  - masked `client_id` if logged at all
  - result/error code
- Do not add a new audit table in v1.
- If Enterprise audit features exist elsewhere, do not couple v1 OSS ikas setup to them.

### Suggested proof points

- validation failure logs show error class/code but not response bodies containing secrets
- disconnect logs prove local cleanup happened

## Blast radius / affected files / entry points

| Area | Likely files / entry points | Why affected |
|---|---|---|
| App catalog | `config/integration/apps.yml`, `app/models/integrations/app.rb`, `config/features.yml` | Adds ikas catalog entry and gating |
| API routes | `config/routes.rb` | New ikas resource endpoints |
| Backend controller/service | `app/controllers/api/v1/accounts/integrations/ikas_controller.rb`, `app/services/integrations/ikas/connection_validator.rb` | Connect/show/update/disconnect logic |
| Existing persistence | `app/models/integrations/hook.rb` (read-only reuse, maybe no code change) | Existing storage semantics must remain compatible |
| Settings UX | `app/javascript/dashboard/routes/dashboard/settings/integrations/integrations.routes.js`, `Ikas.vue` | Dedicated settings screen |
| Dashboard integration API/store | `app/javascript/dashboard/api/integrations.js`, `app/javascript/dashboard/store/modules/integrations.js` | Fetch/save/delete state |
| App serializer / state derivation | `app/models/integrations/app.rb` and/or dedicated ikas controller serializer logic | list/detail must distinguish connected vs reconnect-required vs disabled |
| Copy | `app/javascript/dashboard/i18n/locale/en/integrationApps.json`, `app/javascript/dashboard/i18n/locale/en/integrations.json` | New labels/messages |
| Tests | `spec/controllers/api/v1/accounts/integrations/ikas_controller_spec.rb`, `spec/services/integrations/ikas/connection_validator_spec.rb`, `app/javascript/dashboard/store/modules/specs/integrations/actions.spec.js` | Regression coverage |

### Affected entry points

- `GET /api/v1/accounts/:account_id/integrations/apps`
- `GET/POST/PATCH/DELETE /api/v1/accounts/:account_id/integrations/ikas`
- `Settings → Integrations` index
- `Settings → Integrations → ikas`

### Enterprise note

No direct `enterprise/` mirror file is expected for the recommended v1 because this plan avoids super-admin/global config work and no existing Shopify-specific overlay exists. Re-check `enterprise/` only if implementation later chooses a super-admin ikas config path.

## Allowed scope / forbidden scope

- **Allowed**: app registry, account-scoped ikas CRUD endpoints, validation service, dedicated settings page, Vuex integration actions, English i18n, request/service/store tests.
- **Forbidden**: AI-agent runtime, product/order sync, new tables, super-admin credential setup, background workers, webhook ingestion, enterprise-only flows, unverified remote revoke logic.

## Invariants + verification method

| Invariant | Why it matters | How to verify |
|---|---|---|
| Exactly one ikas hook per account | Prevents ambiguous credentials and status | request spec: second create updates/rejects rather than adding duplicate row |
| `client_secret` never appears in API response | Prevents secret leakage | request spec asserts response body excludes secret; UI test/store assertions inspect payload |
| Failed validation never overwrites a working connection | Avoids breaking an already-connected account | update request spec with existing hook + simulated validator failure |
| Malformed or invalid ikas hook never renders as connected | Prevents false-positive status in settings list | request spec + frontend store/component assertions for `reconnect_required` |
| Shopify flow remains unchanged | ikas must not break existing integration behavior | existing Shopify request spec still passes |
| Generic hook integrations still use their existing CRUD flow | Prevent regression to dialogflow/webhook/etc. | existing integrations store tests + manual regression on generic pages |
| ikas listing obeys feature/encryption gate while remaining visible when encryption is unavailable | prevents unsafe plaintext secret storage without hiding the feature | app model/spec or request spec on apps index |

## Behavior that must not change

- Shopify OAuth connect/callback/disconnect behavior must remain unchanged (`spec/controllers/api/v1/accounts/integrations/shopify_controller_spec.rb`).
- Generic hook-based integrations (`dialogflow`, `google_translate`, `dyte`, etc.) must continue using `IntegrationHooks.vue` and `NewHook.vue`; ikas should not change their payload contract.
- `GET /integrations/apps` should continue to return existing apps and existing `enabled` semantics for non-ikas entries.
- AI-agent settings/runtime behavior must remain untouched by this plan.

## Legacy / malformed config handling

### Legacy shapes to tolerate

- ikas hook exists but `access_token` missing
- ikas hook exists but `reference_id` / canonical store identifier missing
- ikas hook has extra unknown settings keys from manual edits
- multiple ikas hooks exist for the same account

### Recommended handling

- The ikas page should derive a `needs_reconnect` status when a hook exists but required persisted fields are missing.
- The ikas page and integrations list should derive a `reconnect_required` status when a hook exists but required persisted fields are missing or live validation fails.
- Keep the malformed record visible enough to let an admin disconnect or repair it.
- Do not auto-delete malformed records in page load logic.
- On successful reconnect, rewrite the hook into the normalized v1 shape.
- Keep `settings_json_schema` strict for new writes, but read existing data defensively.

## Feature flag strategy

### Account feature

- Add `ikas_integration` to `config/features.yml`
- Default: `enabled: false`

### Gating recommendation

ikas should be active only when all are true:

1. `account.feature_enabled?('ikas_integration')`

`Chatwoot.encryption_configured?` no longer determines visibility; it determines whether `can_connect` is true.

### Why no frontend feature flag constant is required

The settings routes are already behind the global integrations feature (`app/javascript/dashboard/routes/dashboard/settings/integrations/integrations.routes.js:26-27`, `80`, `108`, `118`). App-level availability is already driven by the backend apps catalog response.

## Test strategy with specific files/assertions

### Backend

1. `spec/controllers/api/v1/accounts/integrations/ikas_controller_spec.rb`
    - `GET show` returns `connected: false` when no hook exists
    - `POST create` with valid credentials creates one ikas hook
    - created hook stores non-secret config in `settings`
    - created hook stores normalized store identifier in `reference_id` (or chosen canonical non-secret location)
    - created hook stores `client_secret` outside `settings`
    - response payload never includes `client_secret`
    - malformed hook returns `state: reconnect_required` and `last_validation_error_code: malformed_hook`
    - duplicate hooks return `state: reconnect_required` and `last_validation_error_code: duplicate_hook`
    - `PATCH update` with blank secret preserves existing secret
    - `PATCH update` with validator failure keeps old hook values unchanged
    - `DELETE destroy` removes the hook
    - encryption unavailable returns `state: disabled`, `can_connect: false`, and explanation message while still listing ikas
    - non-admin / unauthenticated requests are rejected

2. `spec/services/integrations/ikas/connection_validator_spec.rb`
    - normalizes store name/store URL correctly
    - rejects blank/invalid required fields before network I/O
   - maps auth failure, timeout, and 429 into stable error codes
    - succeeds on valid simulated token exchange
    - succeeds on valid simulated GraphQL probe after token acquisition

3. `spec/requests/api/v1/accounts/integrations/apps_spec.rb` or equivalent apps-index coverage
   - ikas appears when feature is enabled and encryption is available
   - ikas appears when feature is enabled and encryption is unavailable
   - ikas list payload reflects `disabled` when encryption is unavailable
   - ikas list payload reflects `reconnect_required` for malformed hook state

### Frontend

1. `app/javascript/dashboard/store/modules/specs/integrations/actions.spec.js`
    - ikas show/connect/update/delete actions toggle the right UI flags
    - delete action updates the ikas record to disconnected state
    - malformed/reconnect payload updates the ikas record to reconnect state
    - disabled payload updates the ikas record to disabled state
2. Optional component spec if the repo already has a pattern for settings route component tests; otherwise rely on store/action tests plus manual browser verification.

### Native workflow verification

- API: use Hurl or direct authenticated HTTP requests against the new ikas endpoints
- UI: open Settings → Integrations → ikas and verify connect / validation error / disconnect using browser automation

## Validation matrix

| Check | Command / method | Proves |
|---|---|---|
| Apps catalog gating | `bundle exec rspec spec/models/integrations/app_spec.rb` or apps-index request spec | ikas only appears when feature + encryption gate pass |
| Disabled-but-visible behavior | apps-index request spec | ikas remains visible when encryption is unavailable |
| Connect success | `bundle exec rspec spec/controllers/api/v1/accounts/integrations/ikas_controller_spec.rb` | valid store-specific connect persists normalized hook |
| Failed update preserves working config | same request spec, update-failure context | no destructive overwrite |
| Reconnect state rendering | same request spec + frontend store tests | malformed/invalid hook does not appear connected |
| Secret not serialized | same request spec, response body assertions | API does not leak `client_secret` |
| Validator mapping | `bundle exec rspec spec/services/integrations/ikas/connection_validator_spec.rb` | timeout/auth/rate-limit handling is stable |
| Dashboard store state | `pnpm test app/javascript/dashboard/store/modules/specs/integrations/actions.spec.js` | ikas actions mutate UI flags/store correctly |
| Manual settings flow | Browser verification on Settings → Integrations → ikas | page states and disconnect UX are correct |
| Shopify regression | `bundle exec rspec spec/controllers/api/v1/accounts/integrations/shopify_controller_spec.rb` | existing Shopify integration path still works |

## Evidence owners

| Item | Owner | Proof required |
|---|---|---|
| ikas hook persistence shape | @implementer | request spec assertions on DB fields |
| secret non-leakage | @implementer | response-body assertions + log review |
| feature/encryption gate and disabled visibility | @implementer | apps-index request spec |
| UI state transitions | @implementer | Vuex action tests + browser verification |
| reconnect-state classification | @implementer | request spec + browser verification |
| blast-radius regression (Shopify/generic integrations) | @analyzer | focused review + existing test run |

## Failure signals

- ikas credentials appear anywhere inside serialized `settings` JSON responses
- creating/updating ikas works when encryption is not configured
- failed validation still creates a hook row or mutates a working hook
- apps list shows ikas for accounts without the feature enabled
- apps list shows malformed/invalid ikas hook as connected instead of reconnect-required
- Shopify or generic hooks tests fail after ikas changes
- implementation requires background refresh jobs or new tables to make connect/disconnect work

## Review gates

| Gate | After phase | Focus area |
|---|---|---|
| Gate 1 | Phase 1 | app catalog, feature gating, disabled-but-visible behavior |
| Gate 2 | Phase 3 | backend storage contract and non-leakage |
| Gate 3 | Phase 5 | reconnect-state UX, disabled UX, regression to other integrations |

## Rollback plan

1. **Immediate safety rollback**: disable `ikas_integration` feature flag to hide the app from accounts.
2. **Code rollback**: revert ikas route/controller/service/UI changes; no schema rollback needed because no new table/column is introduced.
3. **Data cleanup (optional)**: delete `Integrations::Hook.where(app_id: 'ikas')` only if product wants full cleanup after rollback.
4. **Preservation note**: because v1 stores no remote resources and no background jobs, rollback is low-risk and local.

## Risk assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| store normalization is implemented incorrectly | MEDIUM | HIGH | normalize/store canonical host consistently in `reference_id` and cover with validator specs |
| plaintext secret storage if encryption is off | HIGH | HIGH | gate ikas on `Chatwoot.encryption_configured?`; hard-block connect/update |
| overusing generic hooks flow leaks secret into `settings` | MEDIUM | HIGH | dedicated controller/page only; no `settings_form_schema`-driven create |
| updating a working connection with bad input breaks it | MEDIUM | HIGH | validate first, then persist; keep old hook on failure |
| future v2 migration changes endpoint/auth expectations | MEDIUM | MEDIUM | keep v1 endpoint/auth isolated in the validator service so a later v2 follow-up is localized |
| tools later require `sales_channel_id` or extra context not captured at connect time | HIGH | MEDIUM | keep those fields explicitly out of v1 connect status; add future structured tool-context config when requirements become concrete |
| apps-list/status semantics misrepresent malformed ikas hook | MEDIUM | MEDIUM | add explicit `reconnect_required` classification in dedicated ikas payload contract and test it |

## Decision log

| Decision | Chosen | Rejected | Rationale | Evidence |
|---|---|---|---|---|
| ikas connect UX | manual credential form on dedicated page | OAuth redirect callback | browser OAuth not verified; manual form is safer and simpler | Shopify dedicated page exists (`Shopify.vue`), but ikas redirect flow is unverified |
| v1 user-entered auth fields | full `store_url` + `client_id` + `client_secret` | two-field form; collecting `sales_channel_id` at connect time | verified store-specific token endpoint makes store identifier required; product chose full URL input; `sales_channel_id` is not part of auth | official ikas docs / Context7 facts provided by user + user decision |
| Persistence model | reuse `Integrations::Hook` | new `IkasConnection` table | existing account integration storage already fits single-account connection | `app/models/account.rb:129`, `app/models/integrations/hook.rb:17-45` |
| Secret storage | `access_token` only | `settings['client_secret']` | generic hook JSON exposes settings to admins | `_hook.json.jbuilder:8-9` |
| UI path | dedicated `Ikas.vue` | generic `IntegrationHooks.vue` / `NewHook.vue` | generic hooks form would funnel secret into `settings` | `NewHook.vue:71-97`, `HooksController:42-43` |
| `sales_channel_id` handling | future structured config | prompt-only context; auth-time requirement | prompt-only context is hard to validate, audit, and migrate, and `sales_channel_id` is not part of verified auth | planning recommendation + official auth facts |
| GraphQL API version for v1 integration | verified v1 endpoint now, revisit v2 later | speculative immediate v2 migration | verified endpoint/auth details available today are v1; v2 is a follow-up decision | official ikas docs / Context7 facts provided by user |
| encryption unavailable UX | visible but disabled | hidden entirely | user should see feature availability/requirement without being allowed unsafe connect flow | user decision |
| malformed hook UX | `reconnect_required` | render as connected | hook existence alone is not enough to claim working integration | user decision |
| Disconnect semantics | local destroy only | remote revoke in v1 | no verified revoke contract; local destroy matches existing patterns | Shopify/Notion destroy controllers |

## Deliverables

| Phase | Files created / modified |
|---|---|
| Phase 1 | `config/integration/apps.yml`, `config/features.yml`, `app/models/integrations/app.rb` |
| Phase 2 | `config/routes.rb`, `app/controllers/api/v1/accounts/integrations/ikas_controller.rb`, `app/services/integrations/ikas/connection_validator.rb` |
| Phase 3 | `spec/controllers/api/v1/accounts/integrations/ikas_controller_spec.rb`, `spec/services/integrations/ikas/connection_validator_spec.rb`, `spec/models/integrations/app_spec.rb` or apps-index request spec |
| Phase 4 | `app/javascript/dashboard/api/integrations.js`, `app/javascript/dashboard/store/modules/integrations.js`, `app/javascript/dashboard/store/modules/specs/integrations/actions.spec.js` |
| Phase 5 | `app/javascript/dashboard/routes/dashboard/settings/integrations/integrations.routes.js`, `app/javascript/dashboard/routes/dashboard/settings/integrations/Ikas.vue`, `app/javascript/dashboard/i18n/locale/en/integrationApps.json`, `app/javascript/dashboard/i18n/locale/en/integrations.json` |

## Phased implementation plan

### Phase 1: Register ikas in the integrations catalog
**Owner**: @implementer (backend)
**Dependencies**: None
**Complexity**: LOW

#### Tasks
- [ ] Add `ikas` app metadata to `config/integration/apps.yml` as a single account-level integration with a strict non-secret settings schema.
- [ ] Add `ikas_integration` to `config/features.yml`, disabled by default.
- [ ] Update `app/models/integrations/app.rb` so ikas appears when the account feature is enabled, while encryption availability controls disabled/connectable state.
- [ ] Add or update minimal model/request coverage proving catalog gating.

#### Acceptance Criteria
- [ ] ikas is hidden when the feature is off
- [ ] ikas remains visible but disabled when encryption is unavailable
- [ ] ikas appears in the integrations catalog when both conditions pass

---

### Phase 2: Build backend connect/show/update/disconnect contract
**Owner**: @implementer (backend)
**Dependencies**: Phase 1
**Complexity**: MEDIUM

#### Tasks
- [ ] Add singular ikas resource routes in `config/routes.rb`.
- [ ] Implement `Api::V1::Accounts::Integrations::IkasController` with `show/create/update/destroy`.
- [ ] Implement `Integrations::Ikas::ConnectionValidator` to normalize input and validate credentials before persistence.
- [ ] Use `client_id`, `client_secret`, and `store_name`/`store_url` as user-entered connection params.
- [ ] Accept full URL input and normalize it to canonical host stored in `reference_id`.
- [ ] Ensure `create/update` never persist secret into `settings` and never overwrite an existing working hook on failed validation.

#### Acceptance Criteria
- [ ] connect succeeds only after validation passes
- [ ] show returns sanitized, UI-ready connection state
- [ ] disconnect deletes the ikas hook and returns success
- [ ] no secret is present in the returned payload
- [ ] token acquisition uses the submitted store-specific endpoint
- [ ] successful validation includes a lightweight GraphQL probe against the internal/default v1 API URL
- [ ] malformed/duplicate hooks return `reconnect_required` instead of `connected`

---

### Phase 3: Lock down backend regressions with request/service specs
**Owner**: @implementer (backend)
**Dependencies**: Phase 2
**Complexity**: MEDIUM

#### Tasks
- [ ] Add request specs for ikas create/show/update/destroy success and failure paths.
- [ ] Add validator specs for normalization, auth failures, timeouts, and rate limits.
- [ ] Add apps-index/model coverage for visibility gating.
- [ ] Run the existing Shopify request spec as a regression gate.

#### Acceptance Criteria
- [ ] failed validation leaves existing config intact
- [ ] response contract never leaks `client_secret`
- [ ] visibility gate is proven by test
- [ ] Shopify regression spec still passes

---

### Phase 4: Add dashboard API/store support
**Owner**: @implementer (frontend)
**Dependencies**: Phase 3
**Complexity**: LOW

#### Tasks
- [ ] Extend `app/javascript/dashboard/api/integrations.js` with ikas `show/create/update/delete` methods.
- [ ] Extend `app/javascript/dashboard/store/modules/integrations.js` with ikas-specific UI flags and actions.
- [ ] Update `app/javascript/dashboard/store/modules/specs/integrations/actions.spec.js` for ikas action flows.

#### Acceptance Criteria
- [ ] dashboard store can load ikas state
- [ ] connect/update/delete actions toggle the correct flags
- [ ] delete updates the integration record back to disconnected state

---

### Phase 5: Ship the dedicated ikas settings page
**Owner**: @implementer (frontend)
**Dependencies**: Phase 4
**Complexity**: MEDIUM

#### Tasks
- [ ] Register `/settings/integrations/ikas` in `integrations.routes.js`.
- [ ] Create `Ikas.vue` using the Shopify dedicated-page pattern, but with a manual credential form and explicit status states.
- [ ] Limit the form to full `store_url`, `client_id`, and `client_secret`; do not expose `api_url` or `sales_channel_id` in v1.
- [ ] Add English copy to `integrationApps.json` and `integrations.json`.
- [ ] Perform browser verification of connect error handling, connected state, and disconnect UX.

#### Acceptance Criteria
- [ ] administrators can connect, edit, and disconnect ikas from a dedicated page
- [ ] disconnected, connected, reconnect-required, validation-error, and encryption-unavailable states are visually distinct
- [ ] the page clearly distinguishes base account credential connection from deferred tool-context requirements such as `sales_channel_id`
- [ ] page copy clearly separates account setup from downstream AI-agent usage

## Open questions

1. What exact mask format should Chatwoot use for `client_id_masked` in UI/API responses?
2. When tool requirements become concrete, should structured `sales_channel_id` / tool context live under ikas hook settings or another account-level config object?
3. If the preferred `me` GraphQL probe behaves unexpectedly in practice, should the implementation switch immediately to `getMerchant` or keep both behind a feature-tested validator fallback?

## Recommendation summary

Implement ikas as a **single-hook, account-level integration** using a **dedicated settings page and dedicated controller**, not the generic hook form. In v1, ask for **full `store_url`, `client_id`, and `client_secret`**, normalize the URL to a canonical host stored in **`reference_id`**, store the **secret in `Integrations::Hook.access_token`**, keep only minimal non-secret credential metadata in `settings`, treat the verified v1 GraphQL endpoint **`https://api.myikas.com/api/v1/admin/graphql`** as internal Chatwoot config, and defer **`sales_channel_id`** into a future structured tool-context layer rather than prompt text. Validation should use the **store-specific OAuth token endpoint** first and then the **`me` GraphQL probe** (falling back to `getMerchant` only inside the validator if needed). The integrations list/detail should distinguish **connected**, **reconnect-required**, **not connected**, and **disabled** states, and ikas should remain visible-but-disabled when encryption is unavailable. This preserves the Shopify-style integration framing, resolves the analyzer blockers, reflects the verified auth requirements, and keeps later ikas tool enablement explicitly downstream. A future v2 migration remains a separate follow-up decision.
