---
name: chatwoot-ai-native-test
description: Chatwoot-specific native dev/test setup, PM2 plus Docker runtime split, seeded login verification, and post-phase health/browser validation for OSS development. Use when preparing or verifying local Chatwoot runtime without intentionally powering Captain or Copilot.
---

# Chatwoot AI-Native Test

Use this skill for Chatwoot-local runtime prep and verification only.

## Quick navigation

- **Runtime and verification sequence**: Read [references/runtime-and-verification.md](references/runtime-and-verification.md).
- **Reusable helper scripts**: Use files under `scripts/` when following this workflow repeatedly.

## Boundaries

- Defer generic runtime/testing guidance to `ai-native-workflow`.
- Defer repo command conventions to `chatwoot-dev-runbook`.
- Defer PM2 lifecycle details to `pm2-runtime-operator`.
- Defer browser interaction mechanics to `agent-browser`.
