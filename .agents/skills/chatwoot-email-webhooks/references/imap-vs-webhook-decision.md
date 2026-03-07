# IMAP vs Webhook Decision Guide

## Table of Contents

1. [Repo-backed ingress paths](#repo-backed-ingress-paths)
2. [Operational tradeoffs](#operational-tradeoffs)
3. [Decision prompts](#decision-prompts)
4. [When hybrid helps](#when-hybrid-helps)

## Repo-backed ingress paths

### Webhook ingress

Repo evidence:

- `config/routes.rb` mounts Action Mailbox.
- `app/mailboxes/application_mailbox.rb` routes `reply+UUID@...` mail and verified channel-address mail into `ReplyMailbox`.
- `app/mailboxes/reply_mailbox.rb` uses `Mailbox::ConversationFinder` inside the mailbox processing transaction.

Operationally, webhook ingress is the path to choose when you need immediate provider push into `/rails/action_mailbox/...` and want the mailbox layer to see the original inbound request directly.

### IMAP polling

Repo evidence:

- `app/jobs/inboxes/fetch_imap_emails_job.rb` enqueues scheduled polling work on `scheduled_jobs`.
- The job fans out through the IMAP fetch services and then into `Imap::ImapMailbox`.

Operationally, IMAP is the path to choose when the inbox is already accessible over IMAP and provider webhook configuration is not available or not desired.

## Operational tradeoffs

| Concern | IMAP polling | Webhook ingress |
| --- | --- | --- |
| Trigger path | Scheduled Sidekiq job | HTTP request into Action Mailbox |
| External dependency | IMAP-capable mailbox | Provider inbound routing |
| Setup surface | Channel credentials | Channel credentials plus provider/domain routing |
| Debug surface | Worker logs and IMAP auth | Route mount, endpoint auth, provider delivery |
| Reply-address handling | Indirect mailbox fetch path | Direct mailbox ingress path |

Keep claims qualitative unless you can re-verify them from current code or session evidence.

## Decision prompts

Choose **webhooks** when:

- the task is about `/rails/action_mailbox` delivery or reply-address routing
- you control the inbound provider and domain routing
- you need to debug route/auth/provider delivery directly

Choose **IMAP** when:

- the mailbox already exists and inbound provider routing is out of scope
- you only need inbox polling and mailbox credential setup
- the operational model is centered on Sidekiq polling rather than provider callbacks

## When hybrid helps

Read [hybrid-setup.md](hybrid-setup.md) when both of these are true:

- some mail should continue to arrive through inbox polling
- reply-address or provider-routed mail should also enter through Action Mailbox
