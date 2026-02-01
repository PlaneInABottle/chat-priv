---
name: chatwoot-email-webhooks
description: "Technical deep-dive on Chatwoot email ingress via webhooks (Action Mailbox). Use when asking about: (1) Email webhook setup for SendGrid, Mailgun, or Amazon SES, (2) The 5-year Action Mailbox mount bug and fix, (3) IMAP polling vs webhook ingress comparison, (4) Email threading reliability (100% vs 70-90%), (5) Hybrid IMAP+webhook configurations, (6) Troubleshooting 404 errors on /rails/action_mailbox endpoints, (7) Sidekiq job conflicts with email processing."
---

# Chatwoot Email Webhooks Guide

## Overview

This skill covers the **webhook-based email ingress** system in Chatwoot, powered by Rails Action Mailbox. It explains how inbound emails are routed to conversations, the critical bug that prevented webhooks from working for 5 years, and how to configure providers like SendGrid, Mailgun, and Amazon SES.

## Quick Navigation

**Choose your topic:**

- **Setting up webhooks?** → See [webhook-setup.md](references/webhook-setup.md)
  - DNS/MX record configuration
  - Provider-specific setup (SendGrid, Mailgun, SES)
  - Super Admin settings
  - Verification and testing procedures

- **Understanding the Action Mailbox bug?** → See [action-mailbox-bug.md](references/action-mailbox-bug.md)
  - What the bug was (missing route mount)
  - Why it existed for 5 years undetected
  - The one-line fix
  - How to verify your instance has the fix

- **Deciding between IMAP and webhooks?** → See [imap-vs-webhook-decision.md](references/imap-vs-webhook-decision.md)
  - Side-by-side feature comparison
  - Reliability metrics (100% vs 70-90% threading)
  - Response time analysis
  - Cost and complexity trade-offs
  - Decision tree

- **Running both IMAP and webhooks?** → See [hybrid-setup.md](references/hybrid-setup.md)
  - Why hybrid setups exist
  - Configuration without conflicts
  - Deduplication mechanisms
  - Best practices

- **Troubleshooting issues?** → See [troubleshooting.md](references/troubleshooting.md)
  - 404 errors on webhook endpoint
  - MX record issues
  - DNS propagation problems
  - Threading failures
  - Sidekiq job issues

---

## Key Concepts

### Two Email Ingress Methods

| Method | Mechanism | Threading | Latency | Complexity |
|--------|-----------|-----------|---------|------------|
| **IMAP Polling** | Sidekiq job fetches emails every 1 min | ~70-90%* (heuristic) | Minutes | Low |
| **Webhook Ingress** | Provider POSTs to Action Mailbox | 100% (UUID-based) | Seconds | Medium |

### How Webhook Ingress Works

```
Customer replies to: reply+6bdc3f4d-0bec-4515-a284-5d916fdde489@yourdomain.com
    ↓
Email provider (Mailgun/SendGrid/SES) receives email
    ↓
Provider POSTs to: /rails/action_mailbox/{provider}/inbound_emails
    ↓
Action Mailbox parses email, extracts UUID from address
    ↓
ApplicationMailbox routes to ReplyMailbox
    ↓
Reply is added to conversation 6bdc3f4d-... instantly ✅
```

### Why 100% Threading Reliability?

Webhooks use **UUID-based addressing**:
- Outbound emails include: `Reply-To: reply+{conversation_uuid}@yourdomain.com`
- Customer's reply goes to that address
- UUID is **deterministic** - no guessing needed

IMAP polling uses **heuristic matching**:
- Searches for `In-Reply-To` and `References` headers
- Falls back to subject line matching
- May create new conversation instead of threading

### Sidekiq and Webhooks: No Conflicts

Webhooks and IMAP Sidekiq jobs **do not conflict**:
- Webhooks are synchronous HTTP requests → Action Mailbox
- IMAP polling is async Sidekiq job → `Inboxes::FetchImapEmailsJob`
- Each email type has its own deduplication via `source_id` (Message-ID)
- Running both is safe; duplicates are caught by database uniqueness

---

## The Critical Bug (Fixed)

For **5 years**, the Action Mailbox routes were **not mounted** in `config/routes.rb`. This meant:

- Webhook endpoints returned **404 Not Found**
- All documentation about webhooks was **incorrect**
- IMAP polling was the **only working method**
- Nobody noticed because IMAP "just worked" (poorly)

**The fix was one line:**

```ruby
# config/routes.rb (at the end of the file)
mount ActionMailbox::Engine => '/rails/action_mailbox'
```

See [action-mailbox-bug.md](references/action-mailbox-bug.md) for the full story.

---

## Setup Paths

### Path A: Quick Setup (IMAP Only)

If you just need email working quickly:
1. Configure SMTP in `.env` for sending
2. Set up IMAP credentials in each inbox
3. Accept ~70-90% threading reliability (estimate)

### Path B: Production Setup (Webhooks)

For reliable threading and instant delivery:
1. Configure SMTP in `.env`
2. Set up email provider (Mailgun/SendGrid/SES)
3. Configure DNS (MX records for your domain)
4. Configure provider to forward to your webhook
5. Set `RAILS_INBOUND_EMAIL_SERVICE` in `.env`
6. Set Inbound Email Domain in Super Admin

### Path C: Hybrid Setup

For maximum coverage:
1. Complete Path B (webhooks)
2. Also configure IMAP as fallback
3. Deduplication handles overlaps automatically

---

## Configuration Checklist

### Super Admin Settings

| Setting | Location | Purpose |
|---------|----------|---------|
| Inbound Email Domain | `/super_admin/app_config?config=email` | Your domain for `reply+uuid@domain` |

### Environment Variables

```env
# Inbound email service (required for webhooks)
RAILS_INBOUND_EMAIL_SERVICE=sendgrid  # or: mailgun, mandrill, postmark, relay

# Password for webhook authentication
RAILS_INBOUND_EMAIL_PASSWORD=your_secure_password

# Provider-specific keys
MAILGUN_INGRESS_SIGNING_KEY=your_key        # For Mailgun
# SendGrid uses username:password auth in URL
# SES uses IAM authentication
```

### Verification Steps

1. **Check route is mounted:**
   ```bash
   rails routes | grep action_mailbox
   ```
   Should show `/rails/action_mailbox` routes

2. **Test webhook endpoint:**
   ```bash
   curl -I https://yourdomain.com/rails/action_mailbox/relay/inbound_emails
   # Should return 401 Unauthorized (not 404)
   ```

3. **Send test email:**
   - Send to `reply+test@yourdomain.com`
   - Check Sidekiq logs for `ActionMailbox::InboundEmail`
   - Check `action_mailbox_inbound_emails` table

---

## Debugging Tips

### Check if webhooks are working

```ruby
# Rails console
ActionMailbox::InboundEmail.count
ActionMailbox::InboundEmail.last
```

### Check Sidekiq for IMAP jobs

```ruby
# Look for IMAP fetch jobs
Sidekiq::Queue.new('scheduled_jobs').select { |j| j.klass == 'Inboxes::FetchImapEmailsJob' }
```

### Trace email routing

```ruby
# In console, simulate routing
mail = Mail.new(to: 'reply+6bdc3f4d-0bec-4515-a284-5d916fdde489@yourdomain.com')
ApplicationMailbox.route(mail)
```

---

## Common Mistakes

1. **Forgetting to mount Action Mailbox** - Check `config/routes.rb` for the mount line
2. **Wrong webhook URL** - Use exact format: `https://actionmailbox:PASSWORD@domain/rails/action_mailbox/{provider}/inbound_emails`
3. **DNS not propagated** - MX records can take 24-48 hours
4. **Password mismatch** - `.env` password must match URL password
5. **Provider not configured to forward** - Each provider needs explicit inbound parse setup
