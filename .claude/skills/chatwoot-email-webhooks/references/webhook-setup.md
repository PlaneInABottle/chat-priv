# Webhook Setup Guide

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [DNS Configuration](#dns-configuration)
3. [Provider Setup](#provider-setup)
   - [SendGrid](#sendgrid-inbound-parse)
   - [Mailgun](#mailgun-routes)
   - [Amazon SES](#amazon-ses)
4. [Chatwoot Configuration](#chatwoot-configuration)
5. [Verification Steps](#verification-steps)
6. [Test Email Procedures](#test-email-procedures)

---

## Prerequisites

Before configuring webhooks, ensure you have:

1. **A domain you control** - You need to set MX records
2. **Chatwoot instance with Action Mailbox mounted** - Check `config/routes.rb` contains:
   ```ruby
   mount ActionMailbox::Engine => '/rails/action_mailbox'
   ```
3. **HTTPS enabled** - Webhook endpoints must be secure
4. **Email provider account** - SendGrid, Mailgun, or AWS SES

---

## DNS Configuration

### MX Records

Your domain's MX records must point to your email provider. This tells the internet where to deliver emails for `@yourdomain.com`.

**For Mailgun:**
```
Priority  Host            Points To
10        yourdomain.com  mxa.mailgun.org
10        yourdomain.com  mxb.mailgun.org
```

**For SendGrid:**
```
Priority  Host            Points To
10        yourdomain.com  mx.sendgrid.net
```

**For Amazon SES:**
```
Priority  Host            Points To
10        yourdomain.com  inbound-smtp.us-east-1.amazonaws.com
```
(Region-specific - check AWS console for your region)

### SPF Record (Recommended)

Add TXT record for email authentication:
```
v=spf1 include:mailgun.org ~all  # For Mailgun
v=spf1 include:sendgrid.net ~all  # For SendGrid
v=spf1 include:amazonses.com ~all  # For SES
```

### Verification

```bash
# Check MX records
dig MX yourdomain.com +short

# Check propagation (may take up to 48 hours)
nslookup -type=MX yourdomain.com
```

---

## Provider Setup

### SendGrid Inbound Parse

1. **Navigate to Settings → Inbound Parse**
   - URL: https://app.sendgrid.com/settings/parse

2. **Add Host & URL**
   - **Hostname**: `yourdomain.com` (or subdomain like `mail.yourdomain.com`)
   - **Destination URL**:
     ```
     https://actionmailbox:YOUR_PASSWORD@your-chatwoot-domain.com/rails/action_mailbox/sendgrid/inbound_emails
     ```

3. **Options**
   - ✅ POST the raw, full MIME message
   - ✅ Check incoming emails for spam

4. **Authentication**
   - SendGrid uses URL-based auth (username `actionmailbox`, password in URL)
   - Set matching password in Chatwoot `.env`:
     ```env
     RAILS_INBOUND_EMAIL_PASSWORD=YOUR_PASSWORD
     RAILS_INBOUND_EMAIL_SERVICE=sendgrid
     ```

### Mailgun Routes

1. **Navigate to Receiving → Routes**
   - URL: https://app.mailgun.com/app/receiving/routes

2. **Create a New Route**
   - **Expression Type**: Match Recipient
   - **Recipient**: `.*@yourdomain.com` (catch-all)
   - **Actions**:
     - ✅ Forward: `https://actionmailbox:YOUR_PASSWORD@your-chatwoot-domain.com/rails/action_mailbox/mailgun/inbound_emails`
     - ✅ Store and notify

3. **Get Your Signing Key**
   - Navigate to Settings → API Keys → Mailgun Ingress Signing Key
   - Copy the key

4. **Configure Chatwoot `.env`**
   ```env
   RAILS_INBOUND_EMAIL_PASSWORD=YOUR_PASSWORD
   RAILS_INBOUND_EMAIL_SERVICE=mailgun
   MAILGUN_INGRESS_SIGNING_KEY=your_signing_key_here
   ```

### Amazon SES

1. **Enable SES Email Receiving**
   - Navigate to SES Console → Email Receiving → Rule Sets
   - Create a new rule set and set it as active

2. **Create a Receipt Rule**
   - **Recipients**: `yourdomain.com` (or specific addresses)
   - **Actions**: SNS Action
     - Create/select an SNS topic
     - Encoding: UTF-8

3. **Create SNS Subscription**
   - Protocol: HTTPS
   - Endpoint:
     ```
     https://actionmailbox:YOUR_PASSWORD@your-chatwoot-domain.com/rails/action_mailbox/amazon/inbound_emails
     ```

4. **Verify Domain in SES**
   - Add TXT record for domain verification
   - Wait for verification (can take hours)

5. **Configure Chatwoot `.env`**
   ```env
   RAILS_INBOUND_EMAIL_PASSWORD=YOUR_PASSWORD
   RAILS_INBOUND_EMAIL_SERVICE=amazon
   ```

---

## Chatwoot Configuration

### Environment Variables

Add to your `.env` file:

```env
# Required: Select your provider
RAILS_INBOUND_EMAIL_SERVICE=sendgrid  # or: mailgun, amazon, mandrill, postmark, relay

# Required: Webhook authentication password
RAILS_INBOUND_EMAIL_PASSWORD=generate_a_secure_password_here

# Mailgun only: Signing key for request verification
MAILGUN_INGRESS_SIGNING_KEY=your_key_here
```

### Super Admin Configuration

1. **Navigate to Super Admin Console**
   - URL: `https://your-chatwoot-domain.com/super_admin/app_config?config=email`

2. **Set Inbound Email Domain**
   - Enter: `yourdomain.com`
   - This enables `reply+{uuid}@yourdomain.com` addresses in outbound emails

3. **Save and Restart**
   - Restart Chatwoot to apply environment changes:
     ```bash
     # Docker
     docker-compose restart

     # Systemd
     sudo systemctl restart chatwoot.target

     # Manual
     bundle exec rails restart
     ```

---

## Verification Steps

### Step 1: Verify Route is Mounted

```bash
# In Rails console or via shell
bundle exec rails routes | grep action_mailbox
```

Expected output:
```
rails_action_mailbox    /rails/action_mailbox    ActionMailbox::Engine
```

If missing, add to `config/routes.rb`:
```ruby
mount ActionMailbox::Engine => '/rails/action_mailbox'
```

### Step 2: Test Endpoint Accessibility

```bash
# Should return 401 Unauthorized (not 404!)
curl -I https://your-chatwoot-domain.com/rails/action_mailbox/relay/inbound_emails
```

- **401 Unauthorized** = ✅ Route exists, auth required
- **404 Not Found** = ❌ Route not mounted
- **502/503** = ❌ App not running

### Step 3: Test with Correct Auth

```bash
# SendGrid endpoint test
curl -X POST \
  -u "actionmailbox:YOUR_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{}' \
  https://your-chatwoot-domain.com/rails/action_mailbox/sendgrid/inbound_emails
```

Expected: 400 or 422 (bad request due to missing email data, but auth passed)

### Step 4: Verify DNS

```bash
# Check MX records
dig MX yourdomain.com +short

# Check from different DNS (Cloudflare's resolver)
dig @1.1.1.1 MX yourdomain.com +short
```

---

## Test Email Procedures

### Manual Test Email

1. **Get a conversation UUID**
   ```ruby
   # Rails console
   conversation = Conversation.last
   puts "reply+#{conversation.uuid}@yourdomain.com"
   ```

2. **Send test email**
   - From any external email account
   - To: `reply+{uuid}@yourdomain.com`
   - Subject: "Test reply"
   - Body: "This is a test"

3. **Verify receipt**
   ```ruby
   # Check Action Mailbox received it
   ActionMailbox::InboundEmail.last

   # Check message was created
   conversation.messages.last
   ```

### Provider Test Tools

**SendGrid:**
- Use Activity Feed to see incoming emails
- Check Inbound Parse logs for POST attempts

**Mailgun:**
- Check Logs → Accepted/Delivered
- View failed routes in Routes → Logs

**Amazon SES:**
- Check CloudWatch for SNS notifications
- View SES console for receipt rule activity

### Automated Test Script

```ruby
# test_webhook.rb - Run in Rails console
require 'net/http'

def test_webhook(provider, password, domain)
  uri = URI("https://#{domain}/rails/action_mailbox/#{provider}/inbound_emails")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  
  request = Net::HTTP::Get.new(uri)
  request.basic_auth('actionmailbox', password)
  
  response = http.request(request)
  puts "Status: #{response.code}"
  puts response.code == '401' ? "❌ Unauthorized" : "✅ Auth passed"
end

# Usage
test_webhook('sendgrid', 'your_password', 'your-chatwoot-domain.com')
```

---

## Troubleshooting

| Symptom | Likely Cause | Solution |
|---------|--------------|----------|
| 404 on webhook URL | Route not mounted | Add mount line to routes.rb |
| 401 Unauthorized | Password mismatch | Check `.env` matches URL password |
| Email not appearing | UUID not found | Verify conversation exists with that UUID |
| Duplicate emails | Both IMAP and webhook active | Normal - dedup handles it |
| Provider not POSTing | DNS not propagated | Wait 24-48h, verify MX records |

See [troubleshooting.md](troubleshooting.md) for more detailed solutions.
