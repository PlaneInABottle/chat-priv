# IMAP vs Webhook: Decision Guide

## Table of Contents

1. [Quick Comparison](#quick-comparison)
2. [Feature-by-Feature Analysis](#feature-by-feature-analysis)
3. [Reliability Metrics](#reliability-metrics)
4. [Response Time Analysis](#response-time-analysis)
5. [Cost and Complexity](#cost-and-complexity)
6. [Decision Tree](#decision-tree)
7. [Recommendations by Use Case](#recommendations-by-use-case)

---

## Quick Comparison

| Aspect | IMAP Polling | Webhook Ingress |
|--------|--------------|-----------------|
| **Mechanism** | Pull (Chatwoot fetches) | Push (Provider sends) |
| **Latency** | ~1 minute (cron: `*/1 * * * *`) | Seconds |
| **Threading Reliability** | ~70-90%* | ~100%* |
| **Setup Complexity** | Low | Medium |
| **External Dependencies** | Email account | Email provider + DNS |
| **Cost** | Free (just email account) | May have costs |
| **Works Offline** | Yes (queues emails) | No (needs internet) |

---

## Feature-by-Feature Analysis

### Email Ingress Method

**IMAP Polling:**
```
Every 1 minute (cron: `*/1 * * * *`):
  → Sidekiq job runs: Inboxes::FetchImapEmailsJob
  → Connects to email server via IMAP
  → Fetches new emails since last check
  → Processes and creates messages
```

**Webhook Ingress:**
```
When email arrives at provider:
  → Provider immediately POSTs to Chatwoot
  → ActionMailbox processes synchronously
  → Message created instantly
```

### Email Threading

**IMAP Polling (Heuristic Matching):**
- Looks for `In-Reply-To` header (email client dependent)
- Checks `References` header chain
- Falls back to subject line matching
- May match incorrectly or not at all

```ruby
# Simplified threading logic for IMAP
def find_conversation(mail)
  # Try In-Reply-To header
  if mail.in_reply_to
    msg = Message.find_by(source_id: mail.in_reply_to)
    return msg.conversation if msg
  end
  
  # Try References header
  mail.references&.each do |ref|
    msg = Message.find_by(source_id: ref)
    return msg.conversation if msg
  end
  
  # Fall back to subject matching (unreliable)
  # ... or create new conversation
end
```

**Webhook Ingress (UUID Matching):**
- Outbound emails include `Reply-To: reply+{uuid}@domain.com`
- Customer's reply goes to that exact address
- UUID is extracted from address
- 100% deterministic matching

```ruby
# UUID-based threading - no guessing
def find_conversation(mail)
  to_address = mail.to.first  # reply+abc123...@domain.com
  uuid = extract_uuid(to_address)
  Conversation.find_by!(uuid: uuid)  # Direct lookup
end
```

### Processing Architecture

**IMAP Polling:**
- Uses Sidekiq background jobs
- Configurable polling interval
- Batch processing (all new emails at once)
- Retries on failure

**Webhook Ingress:**
- Synchronous HTTP request handling
- Rails ActionMailbox framework
- Per-email processing
- Provider handles retries

---

## Reliability Metrics

### Threading Success Rate

| Scenario | IMAP | Webhook |
|----------|------|---------|
| Reply from same client | 95% | 100% |
| Reply from different client | 70% | 100% |
| Reply after client restart | 60% | 100% |
| Reply to forwarded email | 40% | 100% |
| Reply from mobile | 80% | 100% |
| **Overall Average** | **~70-90%*** | **~100%*** |

*These percentages are estimates based on typical email client behavior; actual reliability depends on implementation and environment.

### Why IMAP Threading Fails

1. **Client strips headers**: Some email clients don't preserve `In-Reply-To`
2. **Forwarded emails**: New headers, broken chain
3. **Different client**: Switching from desktop to mobile
4. **Subject line changes**: Client modifies subject
5. **Long threads**: `References` header gets truncated

### Why Webhook Threading Succeeds

The customer has no choice but to reply to the UUID address:
- `Reply-To` header is honored by all email clients
- UUID is in the address, not headers that can be stripped
- Works regardless of client, forwarding, or thread length

---

## Response Time Analysis

### IMAP Polling Latency

```
Best case:  Email arrives right before poll → ~30 seconds
Average:    Email arrives mid-cycle        → 1-5 minutes
Worst case: Email arrives right after poll → 10+ minutes

Variables affecting latency:
- Poll interval (configurable, default ~2 minutes)
- IMAP server response time
- Number of emails to process
- Sidekiq queue depth
```

### Webhook Latency

```
Typical:    100-500ms from email receipt to message creation

Variables affecting latency:
- Provider processing time (~50-200ms)
- Network latency to Chatwoot
- Chatwoot processing time (~50-100ms)
```

### User Experience Impact

| Scenario | IMAP | Webhook |
|----------|------|---------|
| Customer sends reply | Agent sees it in ~1 min | Agent sees it in <5 sec |
| Time-sensitive support | Frustrating delays | Real-time response |
| High-volume inbox | Delays compound | Consistent latency |

---

## Cost and Complexity

### IMAP Polling

**Costs:**
- ✅ Free - uses existing email account
- ✅ No additional services needed

**Complexity:**
- ✅ Simple setup - just IMAP credentials
- ✅ Works with any email provider (Gmail, Outlook, etc.)
- ⚠️ Firewall must allow outbound IMAP connections

**Operational:**
- ⚠️ Depends on email server availability
- ⚠️ IMAP connections can be rate-limited
- ⚠️ Password changes require updating credentials

### Webhook Ingress

**Costs:**
- ⚠️ Email provider costs (varies by volume)
  - SendGrid: Free tier available, then $20-90/month
  - Mailgun: Free tier (100 emails/day), then $35+/month
  - Amazon SES: $0.10 per 1000 emails
- ⚠️ Domain costs if not already owned

**Complexity:**
- ⚠️ DNS configuration required (MX records)
- ⚠️ Provider-specific setup
- ⚠️ SSL certificate required
- ⚠️ More debugging when issues arise

**Operational:**
- ✅ No polling overhead
- ✅ No IMAP connection management
- ⚠️ Depends on provider availability
- ⚠️ Webhook URL must be stable

### Total Cost of Ownership (Monthly)

| Volume | IMAP | Webhook (SendGrid) | Webhook (SES) |
|--------|------|-------------------|---------------|
| 100 emails | $0 | $0 | $0.01 |
| 1,000 emails | $0 | $0 | $0.10 |
| 10,000 emails | $0 | $20 | $1.00 |
| 100,000 emails | $0 | $90 | $10.00 |

---

## Decision Tree

```
Start: Do you need real-time email delivery?
  │
  ├─ No → Do you need 100% threading reliability?
  │         │
  │         ├─ No → ✅ Use IMAP (simplest)
  │         │
  │         └─ Yes → Do you control a domain?
  │                   │
  │                   ├─ No → ⚠️ Consider acquiring domain
  │                   │       or accept IMAP limitations
  │                   │
  │                   └─ Yes → ✅ Use Webhooks
  │
  └─ Yes → Do you control a domain?
            │
            ├─ No → ❌ Cannot use webhooks
            │       Consider IMAP + expectations
            │
            └─ Yes → Can you configure DNS?
                      │
                      ├─ No → ⚠️ Work with DNS admin
                      │       or use IMAP temporarily
                      │
                      └─ Yes → ✅ Use Webhooks
```

### Quick Decision Matrix

| Priority | Recommendation |
|----------|----------------|
| Simplicity | IMAP |
| Speed | Webhook |
| Reliability | Webhook |
| Cost | IMAP |
| No domain access | IMAP |
| High volume | Webhook (SES) |

---

## Recommendations by Use Case

### Startup / Small Team

**Recommended: IMAP**
- Low email volume
- Budget-conscious
- Quick setup needed
- Threading issues manageable

### Growing Business

**Recommended: Webhook**
- Customer experience matters
- Volume increasing
- Worth the setup investment
- Threading reliability important

### Enterprise

**Recommended: Webhook (SES)**
- High volume
- Cost-effective at scale
- Full control needed
- Reliability non-negotiable

### Development / Testing

**Recommended: IMAP or Relay**
- IMAP for production-like testing
- Relay ingress for local development
- No external dependencies

### Migrating from Another System

**Recommended: Hybrid**
- Start with IMAP (immediate functionality)
- Add webhooks after stabilization
- Gradual migration with fallback

---

## Hybrid Approach

You can run both IMAP and webhooks simultaneously:

**Benefits:**
- Webhooks for `reply+uuid@` addresses (100% threading)
- IMAP for direct inbox emails (fallback)
- Maximum coverage

**How deduplication works:**
- Each email has a unique `Message-ID` header
- Stored as `source_id` in messages table
- Second ingress method is rejected as duplicate

See [hybrid-setup.md](hybrid-setup.md) for configuration details.
