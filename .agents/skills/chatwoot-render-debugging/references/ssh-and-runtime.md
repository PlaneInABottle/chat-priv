# SSH and Runtime Checks

## Goal

Confirm connectivity, identify the correct Render service role, and find the Chatwoot app root without assuming a fixed path.

## Baseline SSH pattern

Use non-interactive SSH with an explicit identity file and fast failure options.

```bash
ssh -i "$HOME/.ssh/<key-name>" \
  -o IdentitiesOnly=yes \
  -o BatchMode=yes \
  -o StrictHostKeyChecking=accept-new \
  -o UpdateHostKeys=no \
  -o ConnectTimeout=12 \
  <render-service>@ssh.<region>.render.com \
  'printf "connected=yes\nhost=%s\nuser=%s\npwd=%s\n" "$(hostname)" "$(whoami)" "$(pwd)"'
```

## App root discovery

Do not hardcode a single root. Probe a small ordered list and stop at the first `Gemfile`.

```bash
APP=""
for d in /opt/render/project/src /app /home/chatwoot; do
  if [ -f "$d/Gemfile" ]; then
    APP="$d"
    break
  fi
done
[ -n "$APP" ] || { echo app_root_not_found; exit 1; }
```

## Rails runner over console

Prefer `bundle exec rails runner` for Render investigation and one-shot fixes.

Reasons:

- avoids IRB/reline/prism issues seen in production shells
- makes output deterministic
- keeps the operation scriptable and auditable

Example:

```bash
cd "$APP" && bundle exec rails runner 'puts Channel::Whatsapp.order(:id).pluck(:id, :phone_number).inspect'
```

## Safe environment checks

Inspect presence of runtime markers without printing raw secrets.

```bash
env | sort | grep -E "^(RAILS_ENV|FRONTEND_URL|DATABASE_URL|REDIS_URL|WHATSAPP_|FB_|FACEBOOK_)=" | sed -E 's/=(.*)$/=<set>/'
```

## Role expectations on Render

- Web service: receives HTTP/webhook traffic; Sidekiq may be absent.
- Worker service: runs Sidekiq; queues and dead/retry sets should be inspected here.
- If both SSH endpoints are reachable, compare their runtime role before assuming a bug.
