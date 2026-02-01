# Hybrid Setup: IMAP + Webhooks

## Table of Contents

1. [Why Run Both?](#why-run-both)
2. [How It Works Together](#how-it-works-together)
3. [Configuration Steps](#configuration-steps)
4. [Deduplication Mechanism](#deduplication-mechanism)
5. [Email Flow Diagrams](#email-flow-diagrams)
6. [Best Practices](#best-practices)
7. [Monitoring Hybrid Setup](#monitoring-hybrid-setup)

---

## Why Run Both?

Running IMAP polling and webhook ingress simultaneously provides:

### 1. Maximum Coverage

- **Webhooks**: Handle `reply+uuid@yourdomain.com` with 100% threading
- **IMAP**: Handle direct emails to `support@company.com`

### 2. Graceful Fallback

- If webhook endpoint is temporarily down, IMAP still fetches emails
- If IMAP server is slow, webhooks provide instant delivery

### 3. Migration Path

- Start with IMAP (quick setup)
- Add webhooks incrementally
- No disruption during transition

### 4. Different Use Cases

- Organization A uses webhook-enabled domain
- Organization B uses legacy email without webhooks
- Both work in the same Chatwoot instance

---

## How It Works Together

### Email Routing Summary

| Email Type | Handled By | Threading |
|------------|------------|-----------|
| `reply+uuid@yourdomain.com` | Webhook | 100% |
| `support@company.com` (if configured) | IMAP or Webhook | ~70-90%* |
| Direct inbox email | IMAP | ~70-90%* |

*Threading percentages are estimates based on typical email client behavior; actual reliability depends on implementation and environment.

### No Conflicts by Design

IMAP and webhooks use **different ingress paths**:

```
Webhook Path:
  Provider → POST /rails/action_mailbox/... → ApplicationMailbox → ReplyMailbox

IMAP Path:
  Sidekiq Job → IMAP Server → Imap::FetchEmailService → Imap::ImapMailbox
```

These paths:
- Have separate entry points
- Use the same deduplication mechanism
- Can run simultaneously without interference

---

## Configuration Steps

### Step 1: Configure Webhooks (Primary for Reply Threading)

Set up webhook ingress as your primary method for reply emails:

```env
# .env
RAILS_INBOUND_EMAIL_SERVICE=sendgrid  # or mailgun, amazon
RAILS_INBOUND_EMAIL_PASSWORD=your_secure_password
MAILGUN_INGRESS_SIGNING_KEY=your_key  # if using Mailgun
```

Configure your email provider to forward to:
```
https://actionmailbox:PASSWORD@yourdomain.com/rails/action_mailbox/{provider}/inbound_emails
```

Set Inbound Email Domain in Super Admin:
```
Inbound Email Domain: yourdomain.com
```

### Step 2: Configure IMAP (Per-Inbox Fallback)

For each inbox that needs direct email support:

1. Navigate to **Settings → Inboxes → [Email Inbox] → Email Settings**
2. Enable IMAP:
   - **IMAP Address**: `imap.gmail.com` (or your provider)
   - **IMAP Port**: `993`
   - **IMAP Login**: `support@company.com`
   - **IMAP Password**: App password or regular password
   - **IMAP Enable SSL**: `true`
   - **IMAP Enable**: `ON`

### Step 3: Verify Both Are Working

**Check webhook routes:**
```bash
curl -I https://yourdomain.com/rails/action_mailbox/relay/inbound_emails
# Expect: 401 Unauthorized
```

**Check IMAP jobs:**
```ruby
# Rails console
Sidekiq::Queue.new('scheduled_jobs').select { |j| j.klass.include?('FetchImap') }.count
```

---

## Deduplication Mechanism

### How Duplicates Are Prevented

Every email has a unique `Message-ID` header:
```
Message-ID: <abc123@mail.gmail.com>
```

Chatwoot stores this as `source_id` on the Message model:

```ruby
# Application-level deduplication (not a model validation)
# In Imap::ImapMailbox:
return if @conversation.messages.find_by(source_id: message_id).present?
```

### Deduplication Flow

```
Email arrives via Webhook:
  1. Parse Message-ID from email headers
  2. Check: Message.exists?(source_id: message_id, account_id: account_id)
  3. If exists → Skip (duplicate)
  4. If not → Create message

Email arrives via IMAP (same email):
  1. Parse Message-ID from email headers
  2. Check: Message.exists?(source_id: message_id, account_id: account_id)
  3. Already exists → Skip (duplicate)
```

### Race Condition Handling

If both webhook and IMAP try to create simultaneously:

```ruby
# Database unique constraint catches this
rescue ActiveRecord::RecordNotUnique
  # Already created by other method - safe to ignore
end
```

### What Gets Deduplicated

| Field | Uniqueness Scope |
|-------|------------------|
| `source_id` (Message-ID) | Per account |
| Email content | Not checked (Message-ID is sufficient) |

---

## Email Flow Diagrams

### Flow 1: Reply to Conversation (Webhook Primary)

```
Agent sends email to customer
  └─ Reply-To: reply+abc123@yourdomain.com
     │
Customer clicks Reply
  └─ Email goes to: reply+abc123@yourdomain.com
     │
Email provider receives it
  ├─ POST to webhook endpoint
  │    └─ ✅ Message created instantly
  │
  └─ (IMAP fetch runs later)
       └─ Message-ID already exists → Skipped
```

### Flow 2: Customer Emails Direct (IMAP Handles)

```
Customer emails: support@company.com
  │
Email delivered to company mailbox
  │
IMAP fetch job runs
  └─ ✅ Message created, conversation linked (heuristic)
     │
(Webhook not involved - email not to reply+uuid@ address)
```

### Flow 3: Same Email, Both Methods Try

```
Email to: reply+abc123@yourdomain.com
  │
  ├─ Webhook receives it first (usually)
  │    └─ ✅ Message created
  │
  └─ IMAP also fetches it (configured for same mailbox)
       └─ Duplicate detected → Skipped
```

---

## Best Practices

### 1. Prioritize Webhooks for Reply Threading

Webhooks should handle `reply+uuid@` addresses because they guarantee 100% threading. Configure:

```env
RAILS_INBOUND_EMAIL_SERVICE=sendgrid
```

And set the Inbound Email Domain in Super Admin.

### 2. Use IMAP for Fallback Only

IMAP should catch:
- Direct emails that bypass webhooks
- Emails during webhook downtime
- Legacy email configurations

### 3. Monitor Both Paths

Track metrics for both:
```ruby
# Webhook ingress count
ActionMailbox::InboundEmail.where(created_at: 1.hour.ago..).count

# IMAP processed count (check Sidekiq metrics or logs)
```

### 4. Set Appropriate IMAP Interval

Don't poll too frequently (wastes resources) or too slowly (defeats fallback purpose):

```ruby
# Recommended: 5 minutes
# This is configured in the codebase, not user-configurable
```

### 5. Configure Both for Same Domain Carefully

If `@yourdomain.com` is handled by both:
- Webhooks get `reply+uuid@yourdomain.com`
- IMAP can get `support@yourdomain.com`
- Same email could hit both → Deduplication handles it

### 6. Use Separate Subdomains (Cleaner)

```
Webhooks: reply+uuid@mail.yourdomain.com
IMAP:     support@yourdomain.com
```

This avoids any overlap entirely.

---

## Monitoring Hybrid Setup

### Health Checks

**Webhook endpoint health:**
```bash
# Should return 401 (not 404)
curl -I https://yourdomain.com/rails/action_mailbox/relay/inbound_emails
```

**IMAP connection health:**
```ruby
# Rails console - check for recent successful fetches
Channel::Email.where(imap_enabled: true).each do |channel|
  puts "#{channel.email}: Last fetch at #{channel.imap_last_sync_at}"
end
```

### Metrics to Track

| Metric | Healthy Range | Warning |
|--------|---------------|---------|
| Webhook success rate | >99% | <95% |
| IMAP fetch success | >95% | <90% |
| Duplicate rate | <10% | >20% |
| Message creation latency | <1s | >5s |

### Alert Conditions

1. **Webhook 404s** - Route unmounted
2. **IMAP failures** - Credential or network issues
3. **High duplicate rate** - Both methods racing
4. **No messages created** - Both methods failing

### Debugging Commands

```ruby
# Rails console

# Recent webhook emails
ActionMailbox::InboundEmail.order(created_at: :desc).limit(10)

# Check for duplicates (same source_id, different message_id - shouldn't happen)
Message.group(:source_id).having('count(*) > 1').count

# Check IMAP job status
Sidekiq::Queue.new('scheduled_jobs').size

# Recent IMAP sync times
Channel::Email.where(imap_enabled: true).pluck(:email, :imap_last_sync_at)
```

---

## Troubleshooting Hybrid Issues

### Issue: Same Email Creates Two Conversations

**Cause:** IMAP and webhook found different conversation matches

**Solution:** Webhooks should always win for `reply+uuid@` addresses. Check:
1. Reply-To header is set correctly on outbound emails
2. Customer's client honors Reply-To
3. UUID in address matches existing conversation

### Issue: IMAP Gets Emails That Should Go to Webhook

**Cause:** Email provider not forwarding to webhook

**Solution:** 
1. Check provider's inbound parse settings
2. Verify MX records point to provider
3. Confirm webhook URL is correct

### Issue: High Duplicate Count

**Cause:** Both methods processing before dedup can catch it

**Solution:** This is actually fine - deduplication handles it. If causing performance issues:
1. Increase IMAP polling interval
2. Ensure webhook is responding quickly
3. Consider disabling IMAP for webhook-enabled domains

### Issue: Missed Emails

**Cause:** Neither method catching emails

**Solution:**
1. For webhooks: Check provider logs, verify route is mounted
2. For IMAP: Check connection, credentials, folder configuration
3. Check email wasn't spam-filtered before reaching Chatwoot
