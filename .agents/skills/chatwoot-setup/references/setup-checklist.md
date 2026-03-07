# Setup Checklist

## Contents

- [Minimum instance setup](#minimum-instance-setup)
- [Expanded email-ready setup](#expanded-email-ready-setup)
- [Ownership guide](#ownership-guide)
- [Escalation points](#escalation-points)

## Minimum instance setup

1. Confirm dependency install and repo boot works before changing application settings.
2. Set outbound mail basics in `.env` using the SMTP variables documented in `.env.example`.
3. Configure Google OAuth values if SSO or Google login is required.
4. Verify the super-admin layer can reach the configuration pages needed for app settings.

## Expanded email-ready setup

1. Set `MAILER_INBOUND_EMAIL_DOMAIN` if reply-address generation should use your domain.
2. Decide whether inbound mail will stay IMAP-only or move to webhook ingress.
3. If webhook ingress is required, hand off to [chatwoot-email-webhooks](../../chatwoot-email-webhooks/SKILL.md) for provider routing and endpoint checks.
4. Confirm inbox-level channel credentials are configured after the instance-level settings are in place.

## Ownership guide

| Task | Typical owner |
| --- | --- |
| `.env` mailer and OAuth values | Super admin / deploy operator |
| Inbound email domain | Super admin / deploy operator |
| Inbox credentials and channel setup | Account or inbox admin |
| Provider webhook routing | Deploy operator with webhook skill |

## Escalation points

Escalate out of this skill when the task becomes:

- debugging `/rails/action_mailbox` routes or auth failures
- choosing between IMAP polling and webhook ingress
- configuring SendGrid, Mailgun, or SES receive pipelines
- validating hybrid IMAP + webhook behavior
