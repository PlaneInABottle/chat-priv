# Setup Checklist

## Minimum Setup (Basic Email Support)

- [ ] **SMTP configured** (at least for testing)
  - SMTP_ADDRESS
  - SMTP_PORT
  - SMTP_USERNAME
  - SMTP_PASSWORD
  - MAILER_SENDER_EMAIL
  
- [ ] **Organizations add Email Inboxes**
  - Dashboard → Settings → Inboxes → Add Email
  - Configure IMAP settings

**Result:** 
- ✅ Agents can receive customer emails
- ✅ Agents can send replies
- ❌ Customer replies appear as NEW conversations (not threaded)

---

## Complete Setup (Production Ready)

- [ ] **SMTP configured** (Gmail, SendGrid, etc.)
  ```env
  SMTP_ADDRESS=smtp.gmail.com
  SMTP_PORT=587
  SMTP_USERNAME=your-email@gmail.com
  SMTP_PASSWORD=your_app_password
  MAILER_SENDER_EMAIL=noreply@your-domain.com
  ```

- [ ] **Inbound Email Domain configured**
  - Super Admin Console: `/super_admin/app_config?config=email`
  - Value: `your-domain.com`

- [ ] **Webhook provider configured** (`.env`)
  ```env
  RAILS_INBOUND_EMAIL_SERVICE=mailgun  # or your provider
  RAILS_INBOUND_EMAIL_PASSWORD=secure_password
  MAILGUN_INGRESS_SIGNING_KEY=your_key
  ```

- [ ] **Email provider webhook set up**
  - Point to: `https://actionmailbox:PASSWORD@your-domain/rails/action_mailbox/mailgun/inbound_emails`
  - Configure in your email provider (Mailgun, SendGrid, etc.)

- [ ] **Organizations add Email Inboxes**
  - Dashboard → Settings → Inboxes → Add Email
  - Configure IMAP settings

- [ ] **Optional: Google OAuth**
  - Super Admin Console: `/super_admin/app_config?config=google`
  - Set client ID, secret, redirect URI

**Result:**
- ✅ Agents can receive/send customer emails
- ✅ Customer replies automatically continue in same conversation
- ✅ Agents can log in with Google (if configured)
- ✅ Organizations can use Gmail as email channel (if Google OAuth configured)

---

## Who Sets What?

| What | Who Sets | Where |
|------|----------|-------|
| Global SMTP | You (Super Admin) | `.env` |
| Inbound Email Domain | You (Super Admin) | Super Admin Console |
| Webhook Provider | You (Super Admin) | `.env` |
| Per-Inbox IMAP | Organizations | Dashboard UI |
| Google OAuth | You (Super Admin) | Super Admin Console |

---

## Common Troubleshooting

### Q: Can organizations set up email without me configuring SMTP?
**A:** They can set up IMAP (receiving), but they can't send replies. SMTP must be configured by you (super admin) globally.

### Q: Do I need Inbound Email Domain for email to work?
**A:** No, but customer replies will appear as new conversations instead of continuing the thread. Recommended for production use.

### Q: Can I use Gmail for both SMTP and Inbound Email Domain?
**A:** 
- **SMTP:** Yes ✅
- **Inbound Email Domain:** No ❌ (You need your own domain)

**Recommended setup:** Gmail SMTP + Your own domain for inbound

### Q: What happens if I don't set SMTP?
**A:** All emails fail silently. Notifications, replies, transcripts won't be sent. Core functionality (chat) still works.

### Q: What happens if I don't set Inbound Email Domain?
**A:** 
- Email still works (can send/receive)
- Customer replies appear as NEW conversations (bad UX)
- Not recommended for production
