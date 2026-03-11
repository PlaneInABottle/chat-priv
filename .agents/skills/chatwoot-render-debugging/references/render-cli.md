# Render CLI

## Verified local state

In this environment:

- `render` is installed at `/opt/homebrew/bin/render`
- version observed: `Render CLI v2.13.0`
- `render whoami` succeeds, so CLI auth is already configured

## When to prefer Render CLI

Prefer the CLI when you need:

- service selection without manually copying SSH commands
- workspace-aware service or database operations
- direct `psql` access through Render-managed connection flow
- log access without opening the dashboard

Prefer raw `ssh` when you already have the exact host and key workflow verified and want deterministic shell options.

## Core commands

### Identity and workspace

```bash
render whoami
render workspaces -o text --confirm
```

### SSH

Interactive service selection:

```bash
render ssh
```

Direct service selection by id, service name, or instance id:

```bash
render ssh <service-id>
render ssh <service-name>
render ssh <instance-id>
```

Ephemeral shell:

```bash
render ssh <service-id> --ephemeral
```

Pass raw SSH args through `--`:

```bash
render ssh <service-id> -- -v
```

Notes:

- Use this when you do not want to manage the raw `ssh <service>@ssh.<region>.render.com` form yourself.
- For long-running investigation, remember SSH sessions can be closed by deploys, restarts, or platform maintenance.

### Logs

Use the logs command to inspect current service output from the CLI. Start from help if syntax is needed locally:

```bash
render logs --help
```

For incident work, align the log window with:

- request timestamp
- webhook arrival time
- Sidekiq enqueue time
- known job ids or conversation creation time

### Postgres

Interactive psql:

```bash
render psql <database-id>
```

One-shot query:

```bash
render psql <database-id> -c "SELECT NOW();" -o text --confirm
```

Structured output for scripts:

```bash
render psql <database-id> -c "SELECT id, name FROM accounts LIMIT 5;" -o json --confirm
```

## Non-interactive usage

For scripting or automation:

```bash
render services --output json --confirm
```

Docs-verified options:

- `--output json|yaml|text`
- `--confirm`

Environment variables:

- `RENDER_API_KEY` for API-key auth in automation
- `RENDER_OUTPUT` for default output mode

## Practical Chatwoot flow

1. `render whoami`
2. `render services -o text --confirm` or interactive `render ssh`
3. connect to web or worker service
4. discover app root and run `bundle exec rails runner` checks
5. if DB inspection is needed, use `render psql` when the DB id is known

## When CLI and raw SSH differ

- `render ssh` is great for operator ergonomics
- raw SSH is better when you need exact hostnames, specific identity files, or reproducible shell flags in a documented runbook
- both approaches can coexist in the same investigation
