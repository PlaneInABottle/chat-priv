# Email Configuration

## Contents

- [Three email surfaces](#three-email-surfaces)
- [Instance-level settings](#instance-level-settings)
- [Inbound domain framing](#inbound-domain-framing)
- [Boundary with the webhook skill](#boundary-with-the-webhook-skill)

## Three email surfaces

1. **Global outbound mail**: instance-wide delivery for notifications and agent replies.
2. **Inbox channel credentials**: per-channel IMAP/SMTP credentials owned closer to the inbox.
3. **Inbound email domain**: the instance domain used to generate reply addresses such as `reply+UUID@domain`.

## Instance-level settings

Repo evidence in `.env.example` shows these setup entrypoints:

```env
MAILER_SENDER_EMAIL=
SMTP_DOMAIN=
SMTP_ADDRESS=
SMTP_PORT=
SMTP_USERNAME=
SMTP_PASSWORD=
SMTP_AUTHENTICATION=
SMTP_ENABLE_STARTTLS_AUTO=
SMTP_OPENSSL_VERIFY_MODE=
MAILER_INBOUND_EMAIL_DOMAIN=
RAILS_INBOUND_EMAIL_SERVICE=
RAILS_INBOUND_EMAIL_PASSWORD=
```

Use them for high-level setup guidance only:

- Configure SMTP first so the instance can send mail.
- Add `MAILER_INBOUND_EMAIL_DOMAIN` when you want generated reply addresses on your own domain.
- Treat `RAILS_INBOUND_EMAIL_SERVICE` and `RAILS_INBOUND_EMAIL_PASSWORD` as the hand-off point into webhook ingress configuration.

## Inbound domain framing

`MAILER_INBOUND_EMAIL_DOMAIN` answers the question, “what domain should reply addresses use?”

Example pattern described by the mailbox layer:

```text
reply+<conversation-uuid>@your-domain.example
```

This is enough for setup conversations. Do not duplicate provider routing details here.

## Boundary with the webhook skill

Move to [chatwoot-email-webhooks](../../chatwoot-email-webhooks/SKILL.md) when the request needs any of the following:

- provider-specific inbound routing for SendGrid, Mailgun, or SES
- `/rails/action_mailbox/...` endpoint construction or verification
- IMAP-versus-webhook tradeoff discussion
- hybrid ingress or troubleshooting `401` / `404` webhook responses
