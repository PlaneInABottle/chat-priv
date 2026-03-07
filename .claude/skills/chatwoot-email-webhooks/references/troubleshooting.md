# Troubleshooting Email Webhooks

## Table of Contents

1. [Fast triage](#fast-triage)
2. [Missing-route symptoms](#missing-route-symptoms)
3. [Authentication symptoms](#authentication-symptoms)
4. [Provider-delivery symptoms](#provider-delivery-symptoms)
5. [Mailbox-routing symptoms](#mailbox-routing-symptoms)
6. [Useful repo checks](#useful-repo-checks)

## Fast triage

Run these checks first:

```bash
bundle exec rails routes | grep action_mailbox
curl -I https://<chatwoot-host>/rails/action_mailbox/relay/inbound_emails
```

Then inspect mailbox-side evidence:

```ruby
ActionMailbox::InboundEmail.last
```

## Missing-route symptoms

Symptoms:

- `404` from `/rails/action_mailbox/...`
- no `action_mailbox` routes in `rails routes`

Next step:

- verify the mount in `config/routes.rb`
- review [action-mailbox-bug.md](action-mailbox-bug.md)

## Authentication symptoms

Symptoms:

- `401` from the ingress endpoint
- provider says delivery reached the URL but the app rejected it

Next step:

- confirm `RAILS_INBOUND_EMAIL_PASSWORD`
- confirm the provider is calling the same service path configured in `RAILS_INBOUND_EMAIL_SERVICE`
- re-check any provider-specific signing key variables from `.env.example`

## Provider-delivery symptoms

Symptoms:

- provider never shows a successful delivery attempt
- Action Mailbox rows are not being created

Next step:

- verify DNS and provider routing outside the app
- verify the endpoint URL matches the repo-documented Action Mailbox shape
- keep provider-dashboard wording generic unless you have current provider docs in hand

## Mailbox-routing symptoms

Symptoms:

- inbound email reaches Action Mailbox but ends up in the wrong place
- a reply-address or channel-address message does not land in `ReplyMailbox`

Next step:

- inspect `app/mailboxes/application_mailbox.rb`
- compare the inbound addresses with the UUID regex and channel-address expectations
- use `spec/mailboxes/application_mailbox_spec.rb` as the current routing example set

## Useful repo checks

```ruby
ApplicationMailbox::REPLY_EMAIL_UUID_PATTERN
ActionMailbox::InboundEmail.count
```

```bash
rg -n "ActionMailbox|reply\\+|FetchImapEmailsJob" app spec config
```
