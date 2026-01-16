# Chatwoot Development Guidelines

## Build / Test / Lint
- **[Both] Setup**: `bundle install && pnpm install` because dependencies span Ruby gems and pnpm packages.
- **[Frontend] Run Dev**: `pnpm dev` or `overmind start -f ./Procfile.dev` because the frontend relies on the Procfile.dev stack.
- **[Both] Run Project (foreman)**: `pnpm start:dev` or `pnpm start:test` because these scripts map to the current `package.json` Procfile runners.
- **[Backend] Seed Local Test Data**: `bundle exec rails db:seed` (quickly populates minimal data for standard feature verification).
- **[Backend] Seed Search Test Data**: `bundle exec rails search:setup_test_data` (bulk fixture generation for search/performance/manual load scenarios).
- **[Backend] Seed Account Sample Data (richer test data)**: `Seeders::AccountSeeder` is available as an internal utility and is exposed through Super Admin `Accounts#seed`, but can be used directly in dev workflows too:
  - UI path: Super Admin → Accounts → Seed (enqueues `Internal::SeedAccountJob`).
  - CLI path: `bundle exec rails runner "Internal::SeedAccountJob.perform_now(Account.find(<id>))"` (or call `Seeders::AccountSeeder.new(account: Account.find(<id>)).perform!` directly).
- **[Frontend] Lint JS/Vue**: `pnpm eslint` / `pnpm eslint:fix` because the script targets `app/**/*.{js,vue}`.
- **[Backend] Lint Ruby**: `pnpm ruby:prettier` or `bundle exec rubocop -a` because RuboCop is the configured formatter.
- **[Frontend] Test JS**: `pnpm test`, `pnpm test:watch`, or `pnpm test:coverage` because these are the Vitest scripts in `package.json`.
- **[Backend] Test Ruby**: `bundle exec rspec spec/path/to/file_spec.rb` because there is no npm wrapper for RSpec.
- **[Backend] Single Test**: `bundle exec rspec spec/path/to/file_spec.rb:LINE_NUMBER` because RSpec supports line targeting.
- **[Frontend] Build**: `pnpm build:sdk` and `pnpm story:build` because those are the only build scripts defined.
- **[Frontend] Histoire**: `pnpm story:dev` / `pnpm story:preview` because Histoire is the component explorer.
- **[Both] Ruby Version**: manage Ruby via `rbenv` and `.ruby-version` because Bundler must match the project Ruby.
- **[Both] rbenv setup**: run `eval "$(rbenv init -)"` before `bundle` or `rspec` because shell init selects the correct Ruby/Bundler.
- **[Both] Bundle exec**: always prefer `bundle exec` for Ruby CLI tasks because the gemset is locked in `Gemfile.lock`.

## Code Style
- **[Backend] Ruby**: follow RuboCop rules (150 character max line length) because `.rubocop.yml` enforces the style.
- **[Frontend] Vue/JS**: follow ESLint (Airbnb base + Vue 3 recommended) because `.eslintrc.js` is the single source of truth.
- **[Frontend] Vue Components**: use PascalCase because Vue tooling and imports assume that casing.
- **[Frontend] Events**: use camelCase because event listeners are case-sensitive in templates.
- **[Both] I18n**: avoid bare strings in templates because UI text must remain localized.
- **[Backend] Error Handling**: use custom exceptions (`lib/custom_exceptions/`) because shared rescue logic expects them.
- **[Backend] Models**: validate presence/uniqueness and add DB indexes because data integrity must be enforced at the database level.
- **[Frontend] Type Safety**: define prop types (`defineProps` or typed `props`) because PropTypes are not used and contracts still need validation.
- **[Backend] Params**: keep strong params strict because controller security depends on it.
- **[Both] Naming**: use clear, descriptive names with consistent casing because reviews prioritize readability.
- **[Frontend] Vue API**: prefer Composition API with `<script setup>` for new or migrated components because Vue 3 is the standard API.

## Styling (Frontend only)
- **[Frontend] Tailwind first**: use Tailwind utility classes in templates because the design system is Tailwind-first.
- **[Frontend] SCSS entrypoints**: place shared styles in existing SCSS entrypoints (`app/javascript/dashboard/assets/scss/`, `app/javascript/widget/assets/scss/`, `app/javascript/survey/assets/scss/`, `app/javascript/portal/application.scss`) because Tailwind is wired through those files.
- **[Frontend] `@apply` usage**: use `@apply` in SCSS when utilities are reused because it matches current styling patterns.
- **[Frontend] Scoped styles**: add scoped CSS only when utilities cannot express the UI because scoped CSS is harder to maintain.
- **[Frontend] Colors**: pull tokens from `tailwind.config.js` because it is the canonical palette.

## General Guidelines
- **[Both] MVP focus**: keep changes minimal and happy-path only because the surface area is large.
- **[Both] Avoid unnecessary defensive programming** because it slows iteration and obscures intent.
- **[Both] Ship the happy path first** because production feedback should drive guardrails.
- **[Both] Prefer minimal, readable code** because clarity beats cleverness in reviews.
- **[Both] Break down complex tasks** into small, testable units because CI and review cycles are faster.
- **[Both] Iterate after confirmation** because the project favors incremental delivery.
- **[Both] Avoid writing specs unless asked** because scope is usually change-only.
- **[Both] Remove dead/unreachable/unused code** when touched because it reduces maintenance load.
- **[Both] Avoid duplicate implementations** because multiple versions drift quickly.
- **[Both] Prefer `with_modified_env` in specs** because it is the repo helper for env isolation.
- **[Both] In reloading/parallel specs, compare `error.class.name`** because class equality can break with reloading.

## Codex Worktree Workflow

- Use a separate git worktree + branch per task to keep changes isolated.
- Keep Codex-specific local setup under `.codex/` and use `Procfile.worktree` for worktree process orchestration.
- The setup workflow in `.codex/environments/environment.toml` should dynamically generate per-worktree DB/port values (Rails, Vite, Redis DB index) to avoid collisions.
- Start each worktree with its own Overmind socket/title so multiple instances can run at the same time.

## Commit Messages
- **[Both] Use Conventional Commits** (`type(scope): subject`) because release tooling expects that format.
- **[Both] Example**: `feat(auth): add user authentication` because scopes improve changelog clarity.
- **[Both] Do not reference AI tools** in commit messages because it adds noise to history.

## Project-Specific
- **[Both] Translations**: only update English source files because Crowdin/community handles other locales.
- **[Backend] Backend i18n**: update `config/locales/en.yml` because Rails i18n loads YAML from there.
- **[Frontend] Dashboard i18n**: update `app/javascript/dashboard/i18n/locale/en/**` because the dashboard composes locales from that tree.
- **[Frontend] Widget/Survey i18n**: update `app/javascript/{widget,survey}/i18n/locale/en.json` because those apps import JSON locales directly.
- **[Frontend] Sync i18n**: run `pnpm sync:i18n` after key changes because it syncs locale bundles.
- **[Frontend] Message bubbles**: use `app/javascript/dashboard/components-next/` because legacy message bubbles are being deprecated.

## Ruby Best Practices
- **[Backend] Compact module/class definitions** because the codebase avoids deep nesting for readability.

## Enterprise Edition Notes
- **[Both] Check `enterprise/` overlays** when changing core behavior because Enterprise code can override OSS.
- **[Both] Use `prepend_mod_with`/`include_mod_with`** (see `config/initializers/01_inject_enterprise_edition_module.rb`) because overlays rely on those hooks.
- **[Both] Keep OSS/Enterprise contracts aligned** because both editions ship the same public APIs.
- **[Both] Add Enterprise specs under `spec/enterprise`** because CI expects mirrored spec structure.
- **[Both] Follow the Enterprise handbook** because it documents required patterns: https://chatwoot.help/hc/handbook/articles/developing-enterprise-edition-features-38

Practical checklist for any change impacting core logic or public APIs
- **[Both] Search in `app` and `enterprise`** before editing because overrides may exist (e.g., `rg -n "FooService|ControllerName|ModelName" app enterprise`).
- **[Both] Consider overlays or extension points** (e.g., `prepend_mod_with`, hooks, configuration) because hard forks drift quickly.
- **[Both] Avoid instance/plan hardcoding in OSS** because Enterprise consumes OSS via configuration and feature flags.
- **[Both] Keep request/response contracts stable** because Enterprise expects OSS API parity.
- **[Both] Mirror renames/moves in `enterprise/`** because the overlay must stay aligned.
- **[Both] Add Enterprise-specific specs under `spec/enterprise`** because behavior changes must be validated in both editions.
- **[Both] Prefer Enterprise modules over OSS edits** when behavior is Enterprise-only because `prepend_mod_with`/`include_mod_with` is the intended hook.

## Branding / White-labeling note

- For user-facing strings that currently contain "Chatwoot" but should adapt to branded/self-hosted installs, prefer applying `replaceInstallationName` from `shared/composables/useBranding` in the UI layer (for example tooltip and suggestion labels) instead of adding hardcoded brand-specific copy.

## Legacy / Exceptions to Know
- **[Frontend] Composition API adoption is mixed** because the repo has both `<script setup>` and Options API components.
- **[Frontend] Keep Options API files as-is** unless migration is requested because large rewrites are risky.
- **[Frontend] Vuex is still active** in dashboard/v3/widget/survey; Pinia is used only for new features (e.g., `dashboard/stores/*.js` for voice calls and companies), not as an ongoing migration.
- **[Frontend] Scoped styles and SCSS utilities exist** even though Tailwind is preferred because legacy styling is still in use.
- **[Frontend] Legacy components remain outside `components-next/`** because the migration is incremental.

## References (Repo Sources)
- **[Frontend] Styling**: `tailwind.config.js`, `postcss.config.js`, `app/javascript/dashboard/assets/scss/`, `app/javascript/widget/assets/scss/`, `app/javascript/survey/assets/scss/`, and `app/javascript/portal/application.scss` because they define the Tailwind pipeline.
- **[Frontend] i18n**: `app/javascript/dashboard/i18n/index.js` and `app/javascript/dashboard/i18n/locale/en/**` because they show locale composition.
- **[Frontend] Widget/Survey i18n**: `app/javascript/widget/i18n/locale/en.json` and `app/javascript/survey/i18n/locale/en.json` because those are the app-specific JSON sources.
- **[Backend] i18n**: `config/locales/en.yml` because Rails loads backend strings from YAML.
- **[Both] Enterprise overlays**: `enterprise/` and `config/initializers/01_inject_enterprise_edition_module.rb` because they document override wiring.
- **[Both] Translation process**: README section "Translation process" because it links to Crowdin guidelines.

## Last Verified
- **Date**: 2026-01-16
- **Context**: Verified `package.json` scripts, Tailwind pipeline files, i18n layout under `app/javascript/**/i18n` and `config/locales/en.yml`, and Enterprise overlay hooks in `config/initializers/01_inject_enterprise_edition_module.rb`.
