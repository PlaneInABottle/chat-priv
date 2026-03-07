# Hybrid Setup: IMAP + Webhooks

## Table of Contents

1. [When hybrid makes sense](#when-hybrid-makes-sense)
2. [Repo-backed split of responsibilities](#repo-backed-split-of-responsibilities)
3. [Practical rollout](#practical-rollout)
4. [Checks after enabling both](#checks-after-enabling-both)

## When hybrid makes sense

Use a hybrid setup when the instance needs both:

- provider-routed inbound mail through `/rails/action_mailbox/...`
- existing inbox polling through `Inboxes::FetchImapEmailsJob`

Typical cases:

- staged migration from IMAP-only to provider-routed ingress
- mixed inbox estate where not every mailbox can move at once
- separate handling for generated reply addresses versus legacy direct inbox addresses

## Repo-backed split of responsibilities

| Path | Repo evidence | Typical use |
| --- | --- | --- |
| Webhook ingress | `config/routes.rb`, `app/mailboxes/application_mailbox.rb`, `app/mailboxes/reply_mailbox.rb` | Provider-routed inbound mail |
| IMAP polling | `app/jobs/inboxes/fetch_imap_emails_job.rb` | Scheduled mailbox fetches |

These are distinct entry paths. Validate behavior with current logs and database state instead of relying on old reliability percentages.

## Practical rollout

1. Keep the existing IMAP path working.
2. Add `MAILER_INBOUND_EMAIL_DOMAIN` plus the `RAILS_INBOUND_EMAIL_*` settings.
3. Configure provider routing for the webhook path.
4. Send one test message through each path and inspect the resulting mailbox activity.

## Checks after enabling both

- confirm Action Mailbox inbound rows are being created for webhook-delivered mail
- confirm scheduled IMAP jobs still run for the inboxes that should poll
- inspect resulting conversations and messages instead of assuming deduplication or threading behavior
