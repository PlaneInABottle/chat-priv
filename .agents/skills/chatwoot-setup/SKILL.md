---
name: chatwoot-setup
description: High-level guide for Chatwoot instance setup and administrator configuration. Use when the task is about Google OAuth, SMTP and inbound email domain configuration, setup checklists, or understanding the super admin → organization → agent hierarchy. For Action Mailbox provider webhooks, IMAP-versus-webhook decisions, hybrid ingress, or webhook troubleshooting, use chatwoot-email-webhooks.
---

# Chatwoot Setup Guide

Use this skill for instance-level setup and configuration questions. Keep webhook ingress details at a high level here and defer deep webhook work to [chatwoot-email-webhooks](../chatwoot-email-webhooks/SKILL.md).

## Quick navigation

- **Google OAuth**: Read [references/google-oauth.md](references/google-oauth.md).
- **Email configuration overview**: Read [references/email-config.md](references/email-config.md).
- **Setup sequencing and ownership**: Read [references/setup-checklist.md](references/setup-checklist.md).
- **Message flow examples**: Read [references/email-flows.md](references/email-flows.md).

## Core boundaries

- Keep this skill focused on admin-owned setup: OAuth, SMTP, inbound domain, and account hierarchy.
- Treat provider-specific Action Mailbox webhooks, ingress debugging, and IMAP-versus-webhook tradeoffs as webhook deep-dive topics.
- When a request turns into provider setup or `/rails/action_mailbox` debugging, switch to [chatwoot-email-webhooks](../chatwoot-email-webhooks/SKILL.md).

## Configuration map

| Concern | Primary owner | Primary evidence |
| --- | --- | --- |
| Google OAuth | Super admin | `.env.example`, `references/google-oauth.md` |
| Global outbound mail | Super admin | `.env.example`, `references/email-config.md` |
| Inbound email domain | Super admin | `.env.example`, `references/email-config.md` |
| Inbox channel credentials | Account or inbox admin | `references/email-flows.md` |

## Working model

- Chatwoot has a super-admin layer for instance-wide configuration.
- Organizations and inboxes consume those instance-level defaults and add channel-specific credentials.
- `MAILER_INBOUND_EMAIL_DOMAIN` and `RAILS_INBOUND_EMAIL_*` settings enable reply-address generation and webhook ingress, but this skill only covers the setup framing.
- For actual provider routing, webhook URLs, hybrid operation, or 401/404 debugging, defer to the webhook skill.
