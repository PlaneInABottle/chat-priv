# Dev Commands

## Contents

- [Install and environment basics](#install-and-environment-basics)
- [Start the repo](#start-the-repo)
- [Test and lint entrypoints](#test-and-lint-entrypoints)
- [Build and storybook-style entrypoints](#build-and-storybook-style-entrypoints)

## Install and environment basics

Repo-backed command entrypoints from `AGENTS.md` and `package.json`:

```bash
bundle install && pnpm install
eval "$(rbenv init -)"
```

Use `bundle exec` for Ruby CLI commands.

## Start the repo

Current repo entrypoints:

```bash
pnpm dev
pnpm start:dev
pnpm start:test
overmind start -f ./Procfile.dev
```

Current Procfiles show:

- `Procfile.dev`: Rails on port `3000`, Sidekiq, and Vite
- `Procfile.test`: Rails on port `5050`, Vite, and Sidekiq under `RAILS_ENV=test`

## Test and lint entrypoints

```bash
pnpm test
pnpm test:watch
pnpm test:coverage
pnpm eslint
pnpm eslint:fix
bundle exec rspec spec/path/to/file_spec.rb
bundle exec rspec spec/path/to/file_spec.rb:LINE
pnpm ruby:prettier
```

## Build and storybook-style entrypoints

```bash
pnpm build:sdk
pnpm story:dev
pnpm story:build
pnpm story:preview
pnpm sync:i18n
```
