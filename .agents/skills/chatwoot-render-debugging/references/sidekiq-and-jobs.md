# Sidekiq and Job-State Checks

## Goal

Determine whether work is still queued, actively executing, retried, dead, or already completed.

## Quick process check

Use SSH on the worker service.

```bash
ps aux | grep [s]idekiq
```

Healthy worker examples often show:

- `sidekiq ... [0 of N busy]`
- `/gems/ruby/.../bin/sidekiq -C config/sidekiq.yml`

## Queue health snapshot

```ruby
require 'sidekiq/api'
puts({
  queues: Sidekiq::Queue.all.map { |q| [q.name, q.size] }.to_h,
  retry_size: Sidekiq::RetrySet.new.size,
  dead_size: Sidekiq::DeadSet.new.size
}.inspect)
```

Interpretation:

- queue size growing: jobs are enqueued faster than processed
- retry size growing: current failures are being retried
- dead size nonzero: historical failures exist; inspect recency and job class before blaming them

## Search for a job identifier

When the UI shows an ActiveJob UUID-like id, search the full Sidekiq payloads instead of only `jid`.

Check:

- `Sidekiq::Workers`
- all live queues
- `RetrySet`
- `DeadSet`
- `ScheduledSet`

If the identifier is absent everywhere, the job is not currently running or queued. It may already have completed, been discarded, or belong to a different tracking surface.

## Interpreting absence

If a UUID is not in workers, queues, retry, dead, or scheduled sets:

- do not call it "stuck" from backend evidence alone
- suspect stale UI state or a finished job with outdated frontend status

## Current-incident vs background noise

Old dead jobs are often unrelated. Filter by:

- recent failure time
- matching job class
- matching error message
- matching target record or payload id

Do not treat unrelated `ActionMailer::MailDeliveryJob` failures as proof of a WhatsApp incident unless the payload or timing matches.
