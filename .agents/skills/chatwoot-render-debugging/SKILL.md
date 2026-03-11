---
name: chatwoot-render-debugging
description: Debug Chatwoot production/runtime issues on Render using SSH, Rails runner, Sidekiq inspection, and safe read-mostly checks. Use when a task involves connecting to Render services, checking web or worker state, validating WhatsApp channel health, tracing webhook-to-job-to-database flow, inspecting reauthorization state, or separating UI symptoms from backend/job failures.
---

# Chatwoot Render Debugging

Use this skill for production-style investigation on Render-hosted Chatwoot services. Prefer SSH, Rails runner, Redis/Sidekiq inspection, and targeted database reads before suggesting fixes.

## Quick navigation

- **SSH and app-root discovery**: Read [references/ssh-and-runtime.md](references/ssh-and-runtime.md).
- **Render CLI usage**: Read [references/render-cli.md](references/render-cli.md).
- **Sidekiq and job-state checks**: Read [references/sidekiq-and-jobs.md](references/sidekiq-and-jobs.md).
- **WhatsApp-specific debugging**: Read [references/whatsapp-debugging.md](references/whatsapp-debugging.md).

## Core workflow

1. Confirm which Render service is the web app and which is the worker.
2. Verify Render CLI auth and prefer `render ssh`, `render logs`, and `render psql` when they fit the task.
3. Verify SSH access with a non-interactive command before running any deeper checks.
4. Locate the Chatwoot app root dynamically instead of assuming a single path.
5. Use `bundle exec rails runner` for inspection and one-shot fixes; avoid interactive console when Render Ruby/IRB is unstable.
6. Trace the failure across boundaries in order: incoming webhook or request -> enqueue -> Sidekiq execution -> DB state -> UI visibility.
7. Prefer read-only checks first. Only mutate state after confirming the exact failing flag or stale credential.

## Boundaries

- Keep this skill focused on Render-hosted runtime debugging and production-safe investigation.
- Use `chatwoot-dev-runbook` for local repo setup, test, and Procfile workflows.
- Use `chatwoot-setup` for high-level instance configuration questions.
- Use `chatwoot-email-webhooks` for Action Mailbox and inbound email routing details.

## Proven patterns from this repo/runtime

- Chatwoot WhatsApp webhook intake can succeed even when the inbox is blocked by `reauthorization_required?`; inspect both webhook logs and channel state.
- `Channel::Whatsapp#setup_webhooks` calls `prompt_reauthorization!` when webhook setup fails, which can make the UI show an expired inbox while webhooks still arrive.
- `Webhooks::WhatsappEventsJob` drops inbound events when the channel is blank, inactive, or reauthorization is required.
- The reauthorization flag for channels is stored in Redis via `Reauthorizable`, not directly in Postgres.
- On Render, web and worker services are often separate; Sidekiq may be absent on the web service and healthy on the worker.
- Render CLI is available in this environment and supports `render ssh`, `render logs`, `render psql`, and workspace-scoped non-interactive flows.
- Old dead jobs in Sidekiq do not prove the current incident. Always inspect retry/queue/dead sets for the current signal, not just any failures.
