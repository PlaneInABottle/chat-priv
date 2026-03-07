# Webhook Setup Guide

## Table of Contents

1. [What the repo already proves](#what-the-repo-already-proves)
2. [Required instance settings](#required-instance-settings)
3. [Inbound endpoint pattern](#inbound-endpoint-pattern)
4. [Provider-specific handoff](#provider-specific-handoff)
5. [Verification steps](#verification-steps)

## What the repo already proves

- `config/routes.rb` mounts `ActionMailbox::Engine` at `/rails/action_mailbox`.
- `.env.example` documents `RAILS_INBOUND_EMAIL_SERVICE`, `RAILS_INBOUND_EMAIL_PASSWORD`, `MAILGUN_INGRESS_SIGNING_KEY`, and `ACTION_MAILBOX_SES_SNS_TOPIC`.
- `app/mailboxes/application_mailbox.rb` accepts both `reply+UUID@...` mail and verified channel addresses.

## Required instance settings

Use `.env.example` as the source of truth for instance-level webhook settings:

```env
MAILER_INBOUND_EMAIL_DOMAIN=
RAILS_INBOUND_EMAIL_SERVICE=
RAILS_INBOUND_EMAIL_PASSWORD=
MAILGUN_INGRESS_SIGNING_KEY=
ACTION_MAILBOX_SES_SNS_TOPIC=
```

Interpret them like this:

- `MAILER_INBOUND_EMAIL_DOMAIN`: domain used in generated reply addresses.
- `RAILS_INBOUND_EMAIL_SERVICE`: Action Mailbox ingress adapter name (`mailgun`, `sendgrid`, `ses`, `relay`, and other Rails-supported adapters documented in `.env.example`).
- `RAILS_INBOUND_EMAIL_PASSWORD`: shared secret used by password-protected ingress URLs.
- Provider-specific variables: set only when the selected ingress service requires them.

## Inbound endpoint pattern

The repo documents this URL shape in `.env.example`:

```text
https://actionmailbox:<RAILS_INBOUND_EMAIL_PASSWORD>@<chatwoot-host>/rails/action_mailbox/<RAILS_INBOUND_EMAIL_SERVICE>/inbound_emails
```

Use the service segment that matches the configured ingress adapter.

## Provider-specific handoff

### SendGrid

- Configure the provider to send inbound mail to the Action Mailbox URL using the `sendgrid` service segment.
- Use the shared password from `RAILS_INBOUND_EMAIL_PASSWORD` in the URL.
- Re-check the provider dashboard labels against current provider documentation before clicking save; those UI labels are outside this repo.

### Mailgun

- Configure the provider to forward or post inbound mail to the Action Mailbox URL using the `mailgun` service segment.
- Set `MAILGUN_INGRESS_SIGNING_KEY` when Mailgun signature validation is required.
- Re-check the provider dashboard labels against current provider documentation before finalizing the route.

### Amazon SES

- Configure the provider to deliver inbound mail into the Action Mailbox `ses` ingress path.
- Set `ACTION_MAILBOX_SES_SNS_TOPIC` when the chosen SES flow uses SNS topic delivery, as documented in `.env.example`.
- Re-check the region-specific SES console flow against current provider documentation before finalizing it.

## Verification steps

1. Confirm the mount exists:
   ```bash
   bundle exec rails routes | grep action_mailbox
   ```
2. Confirm the endpoint responds as an Action Mailbox endpoint rather than a missing route:
   ```bash
   curl -I https://<chatwoot-host>/rails/action_mailbox/relay/inbound_emails
   ```
3. Confirm inbound mail is being created:
   ```ruby
   ActionMailbox::InboundEmail.count
   ```
4. If mail is still not arriving, continue with [troubleshooting.md](troubleshooting.md).
