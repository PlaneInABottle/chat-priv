# Email Configuration

## Three Email Systems

Chatwoot has three separate email systems:

### 1. System Emails (Notifications from Chatwoot)
- **Who sends:** Chatwoot app (using your SMTP)
- **Who receives:** Agents and admins
- **What:** Notifications (assignment, mentions, alerts)
- **Requires:** SMTP configured by super admin

### 2. Email Inbox Channel (Customer Support)
- **Who manages:** Each organization
- **What:** Receive/send customer support emails
- **Requires:** Per-inbox IMAP/SMTP settings
- **Works independently:** Can function without global SMTP

### 3. Inbound Email Domain (Reply Routing)
- **Purpose:** Route customer replies back to correct conversation
- **Format:** `reply+[uuid]@your-domain.com`
- **Requires:** Webhook setup + email provider

## Configuration Locations

| Setting | Who Sets | Location | Purpose |
|---------|----------|----------|---------|
| **SMTP** | Super Admin | `.env` file | Powers all email sending from Chatwoot |
| **MAILER_SENDER_EMAIL** | Super Admin | `.env` file | Email address shown in "From:" field |
| **Inbound Email Domain** | Super Admin | Super Admin Console: `/super_admin/app_config?config=email` | Domain for reply+uuid@... addresses |
| **Webhook Provider** | Super Admin | `.env` file | Where to receive inbound reply emails |
| **Per-Inbox IMAP** | Organizations | Dashboard: Settings → Inboxes → Email Channel | Each org's email account settings |

## SMTP Configuration

SMTP is for **sending emails OUT** from Chatwoot.

### Required `.env` Variables

```env
SMTP_ADDRESS=smtp.gmail.com  # Email provider
SMTP_PORT=587
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your_app_password
SMTP_AUTHENTICATION=plain
SMTP_ENABLE_STARTTLS_AUTO=true
MAILER_SENDER_EMAIL=noreply@your-domain.com
```

**Can use Gmail for SMTP:** ✅ YES

### Gmail SMTP Setup
1. Enable 2-Step Verification: https://myaccount.google.com/security
2. Create App Password: https://myaccount.google.com/apppasswords
3. Use the app password in `SMTP_PASSWORD`

---

## Inbound Email Domain

Inbound Email Domain is for **routing customer replies** back to conversations.

### Format: `reply+[uuid]@your-domain.com`

Example:
```
reply+6bdc3f4d-0bec-4515-a284-5d916fdde489@your-domain.com
```

When customer replies to this address, Chatwoot parses the UUID and routes the reply to the correct conversation.

### Configuration

**Super Admin Console:** `/super_admin/app_config?config=email`

```
Inbound Email Domain: your-domain.com
```

**Requirements:**
1. You own/control the domain
2. Email provider webhook configured (Mailgun, SendGrid, etc.)
3. `.env` variables set for webhook

### `.env` Variables

```env
RAILS_INBOUND_EMAIL_SERVICE=mailgun  # or: sendgrid, mandrill, postmark, ses
RAILS_INBOUND_EMAIL_PASSWORD=your_webhook_password
MAILGUN_INGRESS_SIGNING_KEY=your_key  # Provider-specific
```

**Can use Gmail for Inbound:** ❌ NO
- Gmail doesn't forward emails to your app
- You need your own domain and mail service

---

## Webhook vs IMAP

### Webhook (Push) - For `reply+uuid@` Emails

Email providers (Mailgun, SendGrid) push emails to Chatwoot webhook.

**Flow:**
```
Email arrives at: reply+[uuid]@your-domain.com
  ↓
Email provider receives it
  ↓
Provider POSTs to Chatwoot webhook
  ↓
Chatwoot processes instantly ✅
```

**Characteristics:**
- Real-time processing
- Requires email provider account
- Used for reply routing

---

### IMAP (Pull) - For Regular Email Inboxes

Chatwoot connects to email server and fetches emails periodically.

**Flow:**
```
Organization sets up IMAP in inbox settings
  ↓
Chatwoot connects to their email server
  ↓
Chatwoot periodically fetches emails from inbox
  ↓
Agents see conversations ✅
```

**Organizations configure (per inbox):**
- IMAP server address
- IMAP port
- IMAP login/username
- IMAP password
- Enable IMAP: ON

**Characteristics:**
- Polling-based (every few minutes)
- Organizations manage their own accounts
- Used for receiving customer emails

---

## Email Provider Examples

### Gmail SMTP (Easiest for Testing)

```env
SMTP_ADDRESS=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=[app password from https://myaccount.google.com/apppasswords]
```

### Mailgun (Recommended for Production)

```env
SMTP_ADDRESS=smtp.mailgun.org
SMTP_PORT=587
SMTP_USERNAME=postmaster@your-domain.com
SMTP_PASSWORD=[Mailgun SMTP password]

RAILS_INBOUND_EMAIL_SERVICE=mailgun
RAILS_INBOUND_EMAIL_PASSWORD=your_webhook_password
MAILGUN_INGRESS_SIGNING_KEY=[from Mailgun console]
```

### SendGrid

```env
SMTP_ADDRESS=smtp.sendgrid.net
SMTP_PORT=587
SMTP_USERNAME=apikey
SMTP_PASSWORD=[SendGrid API key]

RAILS_INBOUND_EMAIL_SERVICE=sendgrid
RAILS_INBOUND_EMAIL_PASSWORD=your_webhook_password
```
