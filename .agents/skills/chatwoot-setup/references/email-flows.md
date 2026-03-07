# Email Flows

## Scenario 1: Organization Receives Email (Basic)

```
Customer sends email to: support@company.com
  ↓
Organization configured IMAP in their inbox settings
  ↓
Chatwoot fetches via IMAP (polls periodically)
  ↓
Agent sees conversation in Chatwoot dashboard
  ↓
Agent clicks "Reply"
  ↓
Chatwoot uses your SMTP to send email
  ↓
Email headers:
  FROM: support@company.com
  TO: customer@email.com
  Reply-To: reply+[uuid-123]@your-domain.com
  ↓
Email delivered to customer ✅
```

---

## Scenario 2: Customer Replies (WITH Inbound Domain)

```
Customer receives email from agent
  ↓
Customer clicks "Reply"
  ↓
Email client sees Reply-To header:
  reply+[uuid-123]@your-domain.com
  ↓
Customer's reply goes to: reply+[uuid-123]@your-domain.com
  ↓
Your email provider (webhook) receives it
  ↓
Webhook sends to: https://actionmailbox:PASSWORD@your-domain/rails/action_mailbox/mailgun/inbound_emails
  ↓
Chatwoot parses UUID-123
  ↓
✅ Posts reply in conversation-123 (SAME conversation, not new one)
```

---

## Scenario 3: Customer Replies (WITHOUT Inbound Domain)

```
Customer receives email from agent
  ↓
Customer clicks "Reply"
  ↓
Email goes back to: support@company.com (just the inbox)
  ↓
Chatwoot fetches via IMAP (no UUID to link)
  ↓
⚠️ Appears as NEW CONVERSATION (not a reply)
  ↓
Agent gets confused (no history linked)
```

---

## What's the Difference?

| Aspect | With Inbound Domain | Without Inbound Domain |
|--------|---------------------|----------------------|
| Customer replies to | `reply+[uuid]@domain` | `support@company.com` |
| Processing | Real-time via webhook | Polling via IMAP |
| Result | Continues same conversation ✅ | New conversation ❌ |
| User experience | Seamless threaded support | Broken conversation history |
