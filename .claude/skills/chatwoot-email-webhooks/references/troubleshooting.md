# Troubleshooting Email Webhooks

## Table of Contents

1. [Quick Diagnostic Checklist](#quick-diagnostic-checklist)
2. [404 Error on Webhook Endpoint](#404-error-on-webhook-endpoint)
3. [401 Unauthorized Errors](#401-unauthorized-errors)
4. [MX Record Issues](#mx-record-issues)
5. [DNS Propagation Problems](#dns-propagation-problems)
6. [Webhook Not Receiving Emails](#webhook-not-receiving-emails)
7. [Threading Failures](#threading-failures)
8. [Sidekiq Job Issues](#sidekiq-job-issues)
9. [Provider-Specific Issues](#provider-specific-issues)
10. [Debug Commands Reference](#debug-commands-reference)

---

## Quick Diagnostic Checklist

Run through this checklist before deep debugging:

```bash
# 1. Is the route mounted?
bundle exec rails routes | grep action_mailbox
# Expected: Shows /rails/action_mailbox routes

# 2. Does the endpoint respond?
curl -I https://yourdomain.com/rails/action_mailbox/relay/inbound_emails
# Expected: 401 Unauthorized (not 404)

# 3. Are environment variables set?
echo $RAILS_INBOUND_EMAIL_SERVICE
echo $RAILS_INBOUND_EMAIL_PASSWORD

# 4. Can you reach your domain?
curl -I https://yourdomain.com
# Expected: 200 OK

# 5. Are MX records set?
dig MX yourdomain.com +short
# Expected: Points to your email provider
```

---

## 404 Error on Webhook Endpoint

### Symptom
```
POST /rails/action_mailbox/sendgrid/inbound_emails → 404 Not Found
```

### Cause
ActionMailbox engine is not mounted in `config/routes.rb`.

### Diagnosis
```bash
bundle exec rails routes | grep action_mailbox
# If empty output → Bug present
```

### Solution
Add to `config/routes.rb` (before the final `end`):

```ruby
# Action Mailbox routes for inbound email webhooks
mount ActionMailbox::Engine => '/rails/action_mailbox'
```

Then restart Rails:
```bash
# Docker
docker-compose restart rails

# Systemd
sudo systemctl restart chatwoot.target

# Manual
bundle exec rails restart
```

### Verification
```bash
curl -I https://yourdomain.com/rails/action_mailbox/relay/inbound_emails
# Now returns 401 Unauthorized
```

See [action-mailbox-bug.md](action-mailbox-bug.md) for full details on this issue.

---

## 401 Unauthorized Errors

### Symptom
```
POST /rails/action_mailbox/sendgrid/inbound_emails → 401 Unauthorized
```

### Cause
Authentication credentials don't match.

### Diagnosis
Check your provider's webhook URL configuration:
```
https://actionmailbox:YOUR_PASSWORD@yourdomain.com/rails/action_mailbox/{provider}/inbound_emails
```

The password in the URL must match `RAILS_INBOUND_EMAIL_PASSWORD` in `.env`.

### Solution

1. **Check `.env` password:**
   ```bash
   grep RAILS_INBOUND_EMAIL_PASSWORD .env
   ```

2. **Verify URL encoding:** Special characters in password need URL encoding:
   - `@` → `%40`
   - `:` → `%3A`
   - `#` → `%23`

3. **Update provider webhook URL** to match `.env` password exactly.

4. **Restart to apply changes:**
   ```bash
   docker-compose restart
   ```

### Testing
```bash
# With correct password
curl -u "actionmailbox:YOUR_PASSWORD" \
  -I https://yourdomain.com/rails/action_mailbox/relay/inbound_emails
# Should return 4xx (not 401)
```

---

## MX Record Issues

### Symptom
- Emails sent to your domain bounce
- Provider never receives emails to forward

### Diagnosis
```bash
# Check MX records
dig MX yourdomain.com +short

# Check from external DNS
dig @8.8.8.8 MX yourdomain.com +short
dig @1.1.1.1 MX yourdomain.com +short
```

### Common Problems

**Wrong MX record:**
```
# Wrong - pointing to web server
MX 10 yourdomain.com

# Correct - pointing to email provider
MX 10 mxa.mailgun.org
MX 10 mxb.mailgun.org
```

**Missing MX record:**
```bash
dig MX yourdomain.com +short
# Empty output = no MX records
```

**Conflicting records:**
```
MX 10 mail.yourdomain.com    # Old record
MX 10 mxa.mailgun.org        # New record
# Both exist = unpredictable delivery
```

### Solution

1. **Log into your DNS provider** (Cloudflare, Route53, GoDaddy, etc.)

2. **Remove old MX records**

3. **Add correct MX records for your email provider:**

   **Mailgun:**
   ```
   Type: MX, Host: @, Points to: mxa.mailgun.org, Priority: 10
   Type: MX, Host: @, Points to: mxb.mailgun.org, Priority: 10
   ```

   **SendGrid:**
   ```
   Type: MX, Host: @, Points to: mx.sendgrid.net, Priority: 10
   ```

   **Amazon SES:**
   ```
   Type: MX, Host: @, Points to: inbound-smtp.{region}.amazonaws.com, Priority: 10
   ```

4. **Wait for propagation** (up to 48 hours, usually faster)

5. **Verify:**
   ```bash
   dig MX yourdomain.com +short
   ```

---

## DNS Propagation Problems

### Symptom
- MX records look correct in DNS console
- But `dig` shows old/wrong records
- Some locations can send email, others can't

### Diagnosis
```bash
# Check multiple DNS servers
dig @8.8.8.8 MX yourdomain.com +short   # Google
dig @1.1.1.1 MX yourdomain.com +short   # Cloudflare
dig @208.67.222.222 MX yourdomain.com +short  # OpenDNS

# Check propagation status
# Use: https://www.whatsmydns.net/#MX/yourdomain.com
```

### Solution

**Wait:** DNS propagation can take up to 48 hours. Most changes propagate within 1-4 hours.

**Lower TTL before making changes:**
1. Set TTL to 300 (5 minutes) 24 hours before changing MX
2. Make the change
3. Propagation is much faster with low TTL
4. Raise TTL back to 3600+ after verification

**Flush local DNS:**
```bash
# macOS
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder

# Linux
sudo systemctl restart systemd-resolved
# or
sudo /etc/init.d/nscd restart

# Windows
ipconfig /flushdns
```

---

## Webhook Not Receiving Emails

### Symptom
- Webhook endpoint is accessible (returns 401 without auth)
- MX records are correct
- But emails don't arrive

### Diagnosis Steps

1. **Check email provider logs:**
   - SendGrid: Activity → Inbound Parse Activity
   - Mailgun: Logs → Receiving
   - SES: CloudWatch logs

2. **Send test email and trace:**
   ```bash
   # Send from command line
   echo "Test" | mail -s "Test Subject" test@yourdomain.com
   ```

3. **Check Action Mailbox records:**
   ```ruby
   # Rails console
   ActionMailbox::InboundEmail.order(created_at: :desc).limit(5)
   ```

### Common Causes

**Provider not configured to forward:**
- Inbound Parse not enabled
- Route not created (Mailgun)
- Receipt rule not active (SES)

**Webhook URL incorrect:**
- Typo in URL
- Wrong provider path (`/sendgrid/` vs `/mailgun/`)
- HTTP instead of HTTPS

**Domain not verified in provider:**
- Mailgun: Domain must be verified
- SES: Domain must be verified
- SendGrid: Domain authentication recommended

### Solution

1. **Verify provider inbound parse is configured** (see [webhook-setup.md](webhook-setup.md))

2. **Test with provider's test tools:**
   - SendGrid: Use "Test Inbound Parse" feature
   - Mailgun: Send email and check logs immediately

3. **Check for provider errors** in their dashboard logs

---

## Threading Failures

### Symptom
- Emails arrive but create new conversations
- Should have been replies to existing conversations

### Diagnosis

**For webhook emails:**
```ruby
# Check the email address
ActionMailbox::InboundEmail.last.mail.to
# Should be: ["reply+{uuid}@yourdomain.com"]
```

**For IMAP emails:**
```ruby
# Check headers
mail = ActionMailbox::InboundEmail.last.mail
mail.in_reply_to
mail.references
```

### Common Causes

**UUID not in address:**
- Customer replied to wrong address
- Outbound email didn't have Reply-To header
- Customer's client ignored Reply-To

**UUID doesn't match conversation:**
- Conversation was deleted
- UUID was corrupted

**IMAP heuristic failure:**
- Email client stripped In-Reply-To header
- Subject line changed

### Solutions

1. **Verify outbound emails have Reply-To:**
   ```ruby
   # Check a sent message
   message = Message.where(message_type: :outgoing).last
   puts message.content_attributes
   # Should include reply-to address
   ```

2. **Check Inbound Email Domain is set:**
   - Super Admin → `/super_admin/app_config?config=email`
   - Must be set for UUID addresses to work

3. **For IMAP:** Accept some threading failures or switch to webhooks

---

## Sidekiq Job Issues

### Symptom
- IMAP polling not running
- Emails not being fetched
- Jobs stuck or failing

### Diagnosis

```ruby
# Rails console

# Check queue status
Sidekiq::Queue.all.map { |q| [q.name, q.size] }

# Check for IMAP jobs
Sidekiq::Queue.new('scheduled_jobs').select { |j| j.klass.include?('Imap') }

# Check failed jobs
Sidekiq::DeadSet.new.select { |j| j.klass.include?('Imap') }

# Check retry queue
Sidekiq::RetrySet.new.select { |j| j.klass.include?('Imap') }
```

### Common Causes

**Sidekiq not running:**
```bash
# Check process
ps aux | grep sidekiq

# Check Docker
docker-compose ps sidekiq
```

**IMAP credentials wrong:**
```ruby
# Check channel configuration
Channel::Email.where(imap_enabled: true).each do |c|
  puts "#{c.email}: #{c.imap_address}"
end
```

**IMAP server blocking:**
- Rate limiting
- IP blocklist
- Firewall rules

### Solutions

1. **Restart Sidekiq:**
   ```bash
   docker-compose restart sidekiq
   ```

2. **Clear dead jobs:**
   ```ruby
   Sidekiq::DeadSet.new.clear
   ```

3. **Retry failed jobs:**
   ```ruby
   Sidekiq::RetrySet.new.each(&:retry)
   ```

4. **Check IMAP credentials** in inbox settings

---

## Provider-Specific Issues

### SendGrid

**Issue: Emails not forwarded**
- Check Inbound Parse is enabled for your domain
- Verify domain ownership in SendGrid

**Issue: POST fails with encoding error**
- Known issue with special characters
- Check Rack::Attack configuration for exceptions

### Mailgun

**Issue: Signature verification fails**
- `MAILGUN_INGRESS_SIGNING_KEY` must match dashboard
- Key rotates - check for updates

**Issue: Routes not matching**
- Check route expression syntax
- Verify priority (lower = higher priority)

### Amazon SES

**Issue: SNS subscription pending**
- Confirm subscription in SNS console
- Check endpoint is HTTPS

**Issue: Domain not verified**
- Add DKIM records
- Add verification TXT record

---

## Debug Commands Reference

### Rails Console

```ruby
# Recent inbound emails
ActionMailbox::InboundEmail.order(created_at: :desc).limit(10)

# Check specific email
email = ActionMailbox::InboundEmail.find(id)
email.mail.to
email.mail.from
email.mail.subject
email.status

# Check routing
ApplicationMailbox.route(email.mail)

# Find conversation by UUID
uuid = "6bdc3f4d-0bec-4515-a284-5d916fdde489"
Conversation.find_by(uuid: uuid)

# Check for message duplicates
Message.where(source_id: "message-id-here")
```

### Shell Commands

```bash
# Check routes
bundle exec rails routes | grep action_mailbox

# Check environment
env | grep -i mail
env | grep -i inbound

# Test endpoint
curl -u "actionmailbox:password" \
  -X POST \
  -H "Content-Type: application/json" \
  https://yourdomain.com/rails/action_mailbox/relay/inbound_emails

# Check DNS
dig MX yourdomain.com +short
dig TXT yourdomain.com +short

# Check SSL
openssl s_client -connect yourdomain.com:443 -servername yourdomain.com
```

### Sidekiq

```ruby
# Queue sizes
Sidekiq::Queue.all.map { |q| [q.name, q.size] }.to_h

# Clear a queue
Sidekiq::Queue.new('queue_name').clear

# Find specific jobs
Sidekiq::Queue.new('default').select { |j| j.klass == 'SomeJob' }

# Dead jobs
Sidekiq::DeadSet.new.size
Sidekiq::DeadSet.new.first

# Scheduled jobs
Sidekiq::ScheduledSet.new.size
```

### Logs

```bash
# Rails logs
tail -f log/production.log | grep -i mail

# Sidekiq logs
tail -f log/sidekiq.log | grep -i imap

# Docker logs
docker-compose logs -f rails
docker-compose logs -f sidekiq
```
