# Account Integrations Visibility

Use this reference when changing which integrations account admins can see under account settings.

## Source of truth

- Account integration definitions live in `config/integration/apps.yml`.
- The runtime model is `Integrations::App` in `app/models/integrations/app.rb`.
- The account integrations API uses `Integrations::App#active?` from `Api::V1::Accounts::Integrations::AppsController#fetch_apps`.
- The dashboard settings page renders records from the integrations Vuex store in `app/javascript/dashboard/routes/dashboard/settings/integrations/Index.vue`.

## Default visibility

- This Kozmopath deployment intentionally exposes only `ikas` among the account integrations shown to users.
- The six integrations intentionally hidden in this deployment are marked with `visible: false` in `config/integration/apps.yml`.
- The dashboard renders every integration returned by the account integrations API; it does not maintain a second static allowlist.
- `Integrations::App#active?` treats an explicit `visible: false` as hidden before applying optional feature or provider gates.
- `Integrations::App#active?` is the single availability gate for both the index and direct integration detail routes, as well as generic hook creation.
- `ikas` remains conditional on the account's `ikas_integration` feature because its catalog and AI tools depend on the same gate.
- Hiding an app affects discovery and new generic hook creation only; it does not delete existing hooks or disable their runtime processing.

## Feature flags vs visibility

- Use `feature_flag` only when the integration has a real account-scoped capability gate shared with its backend behavior.
- Do not add feature flags or frontend allowlists only to hide an integration globally; those create redundant configuration and can silently hide useful upstream integrations.
- Preserve released feature definitions, columns, and order because account feature bits are persisted by position. Moving a released functional flag requires an explicit data migration that preserves its account state.

## Runtime reload

- `APPS_CONFIG` is loaded from `config/integration/apps.yml` in `config/initializers/00_init.rb` at boot.
- After changing `config/integration/apps.yml` or `app/models/integrations/app.rb`, restart the Rails backend process.
- In local PM2 development, check processes with `pm2 list` and restart the Chatwoot processes, for example:

```bash
pm2 restart chatwoot-backend chatwoot-vite chatwoot-worker
```

- If the browser still shows old integrations after a restart, hard refresh the dashboard so the Vue store and Vite bundle reload.
