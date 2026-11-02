---
name: chatwoot-dev-runbook
description: Operator runbook for working in this Chatwoot repository. Use when the task is to install dependencies, start the dev or test stack, run frontend or backend test and lint commands, or understand the repo's Procfile and worktree process conventions.
---

# Chatwoot Dev Runbook

Use this skill for repo operation questions rather than product configuration or feature-specific behavior.

## Quick navigation

- **Current command entrypoints**: Read [references/dev-commands.md](references/dev-commands.md).
- **Docker development runtime**: `scripts/dev/compose.sh <core|frontend|mail|voice|all>` starts only the services a job needs; see [references/dev-commands.md](references/dev-commands.md#docker-development-runtime) for the job/service matrix, ports, hot-reload and isolation rules.
- **Procfile and worktree notes**: Read [references/worktree-procfile.md](references/worktree-procfile.md).

## Boundaries

- Keep this skill focused on running the repo.
- Use `chatwoot-setup` for instance configuration and `chatwoot-email-webhooks` for inbound email behavior.
