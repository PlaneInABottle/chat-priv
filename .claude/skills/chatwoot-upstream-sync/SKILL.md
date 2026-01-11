---
name: chatwoot-upstream-sync
description: Keep a forked Chatwoot repo up-to-date with upstream (chatwoot-origin/master) using a rebase-first workflow. Use when you need to fetch new updates from chatwoot-origin, rebase your origin/develop onto chatwoot-origin/master, resolve conflicts, force-push with lease safely, then sync origin/master from the updated develop. Also configures git to avoid pushing to chatwoot-origin by default.
---

# Chatwoot Upstream Sync

## Rebase upstream into develop (recommended)

1) Ensure a clean working tree

```bash
git status -sb
```

2) Create safety backups

```bash
DEV_SHA=$(git rev-parse --short develop)
MASTER_SHA=$(git rev-parse --short master)

git branch backup/develop-pre-upstream-$DEV_SHA develop
git branch backup/master-pre-upstream-$MASTER_SHA master
```

3) Fetch upstream and your fork

```bash
git fetch chatwoot-origin --prune
git fetch origin --prune
```

4) Rebase develop onto upstream (avoid interactive editor)

```bash
git checkout develop
GIT_EDITOR=: VISUAL=: EDITOR=: git rebase chatwoot-origin/master
```

### Conflict handling notes

- Prefer `git status` + `git diff` to understand conflicts.
- If a file is generated (lockfiles, schema dumps), prefer regenerating via the project toolchain instead of hand-editing.
- If an editor pops up:

```bash
GIT_EDITOR=: VISUAL=: EDITOR=: git rebase --continue
```

Abort safely:

```bash
git rebase --abort
```

5) Force-push rebased develop to your fork

```bash
git push --force-with-lease origin develop
```

## Sync master from develop (make master match develop)

```bash
git checkout master
git reset --hard develop

git push --force-with-lease origin master
```

## Prevent accidental pushes to chatwoot-origin

```bash
git config push.default current

git config branch.develop.pushRemote origin
# Optional: make status/ahead-behind compare to your fork branch
# git branch --set-upstream-to=origin/develop develop
```

## Bundled automation

```bash
.claude/skills/chatwoot-upstream-sync/scripts/rebase_upstream.sh \
  --upstream chatwoot-origin --upstream-branch master \
  --fork origin --develop develop --main master
```
