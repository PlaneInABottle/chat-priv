---
name: chatwoot-upstream-sync
description: Keep a forked Chatwoot repository aligned with upstream using a rebase-first workflow. Use when the task is to fetch chatwoot-origin and origin, create backup branches, rebase the fork's develop branch onto upstream master, push develop and master with force-with-lease, and set git push safety so pushes default to the fork remote.
---

# Chatwoot Upstream Sync

Use the bundled script when you want the documented rebase-first sync flow and matching git safety configuration.

## What the script does

1. Require a clean working tree.
2. Create backup branches for the develop and master branches.
3. Fetch both the upstream remote and the fork remote.
4. Configure git so normal pushes stay on the current branch and the develop branch pushes to the fork remote.
5. Rebase the develop branch onto the upstream branch with editors disabled.
6. Force-push the rebased develop branch to the fork with lease protection.
7. Reset the master branch to the updated develop branch and force-push that branch to the fork.

## Bundled automation

```bash
.claude/skills/chatwoot-upstream-sync/scripts/rebase_upstream.sh \
  --upstream chatwoot-origin \
  --upstream-branch master \
  --fork origin \
  --develop develop \
  --main master
```

## Conflict handling

If the rebase stops for conflicts:

- inspect the conflicting files with normal git tools
- resolve them manually
- continue with `GIT_EDITOR=: VISUAL=: EDITOR=: git rebase --continue`
- or abort with `git rebase --abort`
