# Action Mailbox Route Failure Mode

## Table of Contents

1. [Current repo state](#current-repo-state)
2. [Historical failure mode](#historical-failure-mode)
3. [How to verify the mount](#how-to-verify-the-mount)
4. [Why this matters](#why-this-matters)

## Current repo state

`config/routes.rb` currently includes:

```ruby
mount ActionMailbox::Engine => '/rails/action_mailbox'
```

That means the current repository expects Action Mailbox ingress routes to exist.

## Historical failure mode

The failure mode to remember is simple: if the mount line is missing, inbound webhook URLs under `/rails/action_mailbox/...` behave like missing routes rather than authenticated ingress endpoints.

Keep the guidance focused on the failure mode itself unless you have separate evidence for timeline or incident-history claims.

## How to verify the mount

```bash
bundle exec rails routes | grep action_mailbox
curl -I https://<chatwoot-host>/rails/action_mailbox/relay/inbound_emails
```

Interpretation:

- no route output usually means the mount is missing or not loaded
- `404` suggests route wiring is broken
- `401` suggests the route exists and auth is now the next thing to verify

## Why this matters

The mailbox classes and job paths can exist in the repo while webhook ingress still fails if the routes are not mounted. Always check the mount before investigating provider dashboards.
