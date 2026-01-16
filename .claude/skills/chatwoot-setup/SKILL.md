---
name: chatwoot-setup
description: "Comprehensive guide for setting up and configuring Chatwoot authentication, email, and integrations. Use when asking about: (1) Google OAuth setup and configuration, (2) Email configuration (SMTP, inbound domains, webhooks), (3) Email flows and routing, (4) Configuration checklists and troubleshooting, (5) User hierarchy and organization setup."
---

# Chatwoot Setup Guide

## Overview

This skill provides comprehensive configuration guidance for Chatwoot, covering authentication (Google OAuth), email systems (SMTP, inbound routing, webhooks), and how the app hierarchy works (super admin → organizations → agents → customers).

## Quick Navigation

**Start with the topic that matches your question:**

- **Setting up Google OAuth?** → See [google-oauth.md](references/google-oauth.md)
  - How to create credentials in Google Cloud Console
  - Configuration steps for Chatwoot
  - OAuth flow explanation

- **Configuring email?** → See [email-config.md](references/email-config.md)
  - SMTP setup (for sending)
  - Inbound Email Domain (for reply routing)
  - Webhook vs IMAP comparison
  - Email provider examples (Gmail, Mailgun, SendGrid)

- **Understanding email flows?** → See [email-flows.md](references/email-flows.md)
  - How emails move through the system
  - Scenarios with and without Inbound Email Domain
  - Why reply routing matters

- **Need a checklist?** → See [setup-checklist.md](references/setup-checklist.md)
  - Minimum setup (basic functionality)
  - Complete setup (production ready)
  - Troubleshooting FAQ

## Key Concepts

### User Hierarchy

```
You (App Owner / Super Admin)
  ↓
Organizations (Teams using your Chatwoot)
  ↓
  Agents (Respond to customers)
  ↓
  Customers (External end users)
```

### Configuration Responsibility

| What | Who Configures | Where |
|------|---|---|
| Global SMTP | You (Super Admin) | `.env` |
| Google OAuth | You (Super Admin) | Super Admin Console |
| Inbound Email Domain | You (Super Admin) | Super Admin Console |
| Webhook Provider | You (Super Admin) | `.env` |
| Per-Inbox Email | Organizations | Dashboard UI |

### The Three Email Systems

1. **System Emails** - Notifications and alerts (uses global SMTP)
2. **Email Inbox Channel** - Customer support emails (per-organization IMAP/SMTP)
3. **Inbound Email Domain** - Reply routing (uses webhooks + your domain)

## Common Questions

**Q: Can organizations use email without me setting up SMTP?**
A: They can receive emails (IMAP), but not send replies. SMTP is required globally.

**Q: Is Inbound Email Domain required?**
A: No, but without it, customer replies appear as new conversations. Recommended for production.

**Q: Can I use Gmail for everything?**
A: SMTP yes, but not for Inbound Email Domain. Use Gmail SMTP + your own domain for inbound.
