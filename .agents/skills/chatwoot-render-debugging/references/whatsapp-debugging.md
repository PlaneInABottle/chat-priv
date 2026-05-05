# WhatsApp Debugging on Render

## Contents

- [Goal](#goal)
- [The actual inbound path in this repo](#the-actual-inbound-path-in-this-repo)
- [Critical gating behavior](#critical-gating-behavior)
- [Fast checks](#fast-checks)
  - [Check live channel state](#check-live-channel-state)
  - [Check whether webhook delivery actually arrived](#check-whether-webhook-delivery-actually-arrived)
  - [Check whether DB side effects happened](#check-whether-db-side-effects-happened)
- [Common Meta error meanings](#common-meta-error-meanings)
  - [`(#100) Before override the current callback uri...`](#100-before-override-the-current-callback-uri)
  - [`(#200) You do not have the necessary permissions to send messages...`](#200-you-do-not-have-the-necessary-permissions-to-send-messages)
  - [`OAuthException code 190 subcode 460`](#oauthexception-code-190-subcode-460)
- [Direct Meta probes](#direct-meta-probes)
- [Reauthorization handling](#reauthorization-handling)

## Goal

Trace WhatsApp incidents across channel config, webhook delivery, Sidekiq execution, Meta permissions, and database side effects.

## The actual inbound path in this repo

Use these files as the mental model:

- `app/controllers/webhooks/whatsapp_controller.rb` receives verification and payload POSTs.
- `app/jobs/webhooks/whatsapp_events_job.rb` matches the channel and dispatches processing.
- `app/models/channel/whatsapp.rb` auto-sets up webhooks on create and prompts reauthorization on setup failure.
- `app/models/concerns/reauthorizable.rb` stores reauthorization state in Redis.

## Critical gating behavior

`Webhooks::WhatsappEventsJob` returns early when:

- channel is blank
- `channel.reauthorization_required?` is true
- account is inactive

So a payload can reach the web app and still never create a conversation.

## Fast checks

### Check live channel state

```ruby
channel = Channel::Whatsapp.find_by(phone_number: '+<number>')
puts({
  id: channel.id,
  inbox_id: channel.inbox&.id,
  inbox_name: channel.inbox&.name,
  provider: channel.provider,
  reauthorization_required: channel.reauthorization_required?,
  phone_number_id: channel.provider_config['phone_number_id'],
  business_account_id: channel.provider_config['business_account_id']
}.inspect)
```

### Check whether webhook delivery actually arrived

Look for these signals in logs or incident evidence:

- `Started POST "/webhooks/whatsapp/+<number>"`
- payload contains expected `phone_number_id` and WABA id
- `Enqueued Webhooks::WhatsappEventsJob`

If these appear, webhook delivery is working.

### Check whether DB side effects happened

Inspect for:

- contact creation by phone/identifier
- new conversation in the target inbox
- saved message with the inbound `wamid`

If the message exists in the DB but not in the UI, the next suspect is UI visibility, filters, stale cache, or inbox membership.

## Common Meta error meanings

### `(#100) Before override the current callback uri...`

Meaning:

- Chatwoot tried to override the WABA callback URL
- Meta says the app is not properly subscribed to receive messages for that WABA first

Impact in this repo:

- `Channel::Whatsapp#setup_webhooks` rescues the failure and calls `prompt_reauthorization!`
- the inbox can show as expired afterward

### `(#200) You do not have the necessary permissions to send messages...`

Meaning:

- token/app can reach Meta but is not authorized to send on behalf of that WABA

Likely causes:

- wrong app
- wrong token
- missing send permission
- token not linked to the WABA/phone pair used by the inbox

### `OAuthException code 190 subcode 460`

Meaning:

- token/session is invalidated, expired, revoked, or rotated

Impact:

- read checks fail
- send checks fail
- metadata checks fail

## Direct Meta probes

Use the channel's stored token only for targeted debugging and avoid printing the raw token.

Recommended checks:

- GET `/<phone_number_id>?fields=id,display_phone_number,verified_name,code_verification_status`
- GET `/<business_account_id>?fields=id,name`
- POST `/<phone_number_id>/messages` with a minimal text body only when explicitly verifying send permission

Interpretation:

- phone lookup `200` + WABA lookup `200` + send `403/#200` -> token can read but cannot send
- all three `401` with `190/460` -> token is invalidated

## Reauthorization handling

If Meta/auth is fixed and the inbox remains blocked only because of stale reauthorization state, clearing it can restore processing:

```ruby
channel.reauthorized!
```

Only do this after confirming the underlying credential/config problem is fixed or intentionally accepted for short-term recovery.
