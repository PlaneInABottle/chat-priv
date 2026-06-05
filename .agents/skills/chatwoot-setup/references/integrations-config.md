# Account Integrations Visibility

Use this reference when changing which integrations account admins can see under account settings.

## Source of truth

- Account integration definitions live in `config/integration/apps.yml`.
- The runtime model is `Integrations::App` in `app/models/integrations/app.rb`.
- The account integrations API uses `Integrations::App#active?` from `Api::V1::Accounts::Integrations::AppsController#fetch_apps`.
- The dashboard settings page renders records from the integrations Vuex store in `app/javascript/dashboard/routes/dashboard/settings/integrations/Index.vue`.

## Default visibility

- Hide an integration from the account integrations index with:

```yaml
openai:
  id: openai
  visible: false
```

- `Integrations::App#active?` treats `visible: false` as hidden.
- Current product default is to show only `ikas` in the account integrations index. The dashboard index also filters to `ikas` as a defensive UI guard.

## Feature flags vs visibility

- Use `feature_flag` when an integration should be conditionally available by account feature state.
- Use `visible: false` when an integration should be globally hidden from account integration settings by default.
- Do not add feature flags only to hide an integration globally; that creates redundant configuration and stale account flag edge cases.

## Runtime reload

- `APPS_CONFIG` is loaded from `config/integration/apps.yml` in `config/initializers/00_init.rb` at boot.
- After changing `config/integration/apps.yml` or `app/models/integrations/app.rb`, restart the Rails backend process.
- In local PM2 development, check processes with `pm2 list` and restart the Chatwoot processes, for example:

```bash
pm2 restart chatwoot-backend chatwoot-vite chatwoot-worker
```

- If the browser still shows old integrations after a restart, hard refresh the dashboard so the Vue store and Vite bundle reload.
