---
name: chatwoot-email-webhooks
description: Technical deep-dive for Chatwoot inbound email over Action Mailbox. Use when the task involves provider webhook setup for SendGrid, Mailgun, or Amazon SES; `/rails/action_mailbox` routing and authentication; IMAP-versus-webhook or hybrid ingress decisions; or troubleshooting inbound email processing and conversation threading.
---

# Chatwoot Email Webhooks Guide

Use this skill when the question is specifically about inbound email ingress through Action Mailbox and the surrounding operational choices. Keep generic Chatwoot setup questions in [chatwoot-setup](../chatwoot-setup/SKILL.md).

## Quick navigation

- **Provider routing and endpoint shape**: Read [references/webhook-setup.md](references/webhook-setup.md).
- **Choosing IMAP, webhooks, or both**: Read [references/imap-vs-webhook-decision.md](references/imap-vs-webhook-decision.md).
- **Historical mounted-route failure mode**: Read [references/action-mailbox-bug.md](references/action-mailbox-bug.md).
- **Hybrid operation details**: Read [references/hybrid-setup.md](references/hybrid-setup.md).
- **Operational debugging paths**: Read [references/troubleshooting.md](references/troubleshooting.md).

## Repo-backed model

- `config/routes.rb` currently mounts `ActionMailbox::Engine` at `/rails/action_mailbox`.
- `app/mailboxes/application_mailbox.rb` routes `reply+UUID@domain` mail and verified channel addresses into `ReplyMailbox`.
- `app/jobs/inboxes/fetch_imap_emails_job.rb` shows IMAP polling remains a separate scheduled Sidekiq path.
- `spec/mailboxes/application_mailbox_spec.rb` confirms both UUID reply mail and channel-address mail are routed into `ReplyMailbox`.

## Boundaries

- Use this skill for inbound transport, routing, and debugging details.
- Use [chatwoot-setup](../chatwoot-setup/SKILL.md) for high-level SMTP, OAuth, and admin configuration questions.
- Keep unsupported reliability percentages out of the entrypoint unless they are re-verified from current evidence.
