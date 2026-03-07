#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_REMOTE="chatwoot-origin"
UPSTREAM_BRANCH="master"
FORK_REMOTE="origin"
DEVELOP_BRANCH="develop"
MAIN_BRANCH="master"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --upstream) UPSTREAM_REMOTE="$2"; shift 2 ;;
    --upstream-branch) UPSTREAM_BRANCH="$2"; shift 2 ;;
    --fork) FORK_REMOTE="$2"; shift 2 ;;
    --develop) DEVELOP_BRANCH="$2"; shift 2 ;;
    --main) MAIN_BRANCH="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree not clean; commit/stash first." >&2
  exit 1
fi

DEV_SHA=$(git rev-parse --short "$DEVELOP_BRANCH")
MAIN_SHA=$(git rev-parse --short "$MAIN_BRANCH")

git branch "backup/${DEVELOP_BRANCH}-pre-upstream-${DEV_SHA}" "$DEVELOP_BRANCH" || true
git branch "backup/${MAIN_BRANCH}-pre-upstream-${MAIN_SHA}" "$MAIN_BRANCH" || true

git fetch "$UPSTREAM_REMOTE" --prune
git fetch "$FORK_REMOTE" --prune

git config push.default current
git config "branch.${DEVELOP_BRANCH}.pushRemote" "$FORK_REMOTE"

git checkout "$DEVELOP_BRANCH"

export GIT_EDITOR=:
export VISUAL=:
export EDITOR=:

if ! git rebase "${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}"; then
  echo "Rebase stopped (likely conflicts)." >&2
  echo "Resolve conflicts, then run: GIT_EDITOR=: VISUAL=: EDITOR=: git rebase --continue" >&2
  exit 1
fi

git push --force-with-lease "$FORK_REMOTE" "$DEVELOP_BRANCH"

git checkout "$MAIN_BRANCH"
git reset --hard "$DEVELOP_BRANCH"

git push --force-with-lease "$FORK_REMOTE" "$MAIN_BRANCH"
