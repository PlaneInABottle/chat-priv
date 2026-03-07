# Worktree and Procfile Notes

## Contents

- [Current repo files](#current-repo-files)
- [Worktree guidance from AGENTS](#worktree-guidance-from-agents)
- [How to interpret the gap](#how-to-interpret-the-gap)

## Current repo files

The checked-in process files in this repository are:

- `Procfile.dev`
- `Procfile.test`

No checked-in `Procfile.worktree` was found in the current repo snapshot.

## Worktree guidance from AGENTS

`AGENTS.md` recommends:

- a separate git worktree and branch per task
- Codex-specific setup under `.codex/`
- a `Procfile.worktree`
- `.codex/environments/environment.toml` for per-worktree ports and database values

## How to interpret the gap

Treat the worktree guidance as a repository convention, not as a currently available checked-in run target.

That means:

- use `Procfile.dev` and `Procfile.test` for current checked-in process orchestration
- if a task explicitly references `Procfile.worktree` or `.codex/environments/environment.toml`, verify whether those files are created in the working copy before relying on them
- avoid documenting nonexistent command entrypoints as if they already exist in the repo
