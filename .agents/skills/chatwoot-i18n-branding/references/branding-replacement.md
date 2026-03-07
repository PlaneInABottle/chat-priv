# Branding Replacement

## Contents

- [Primary helper](#primary-helper)
- [What the helper does](#what-the-helper-does)
- [When to apply it](#when-to-apply-it)
- [Verification points](#verification-points)

## Primary helper

Use the UI-layer helper documented in `AGENTS.md`:

- `app/javascript/shared/composables/useBranding.js`
- `app/javascript/shared/composables/specs/useBranding.spec.js`

## What the helper does

`useBranding.js` exports `replaceInstallationName`, which:

- returns the original text when there is no installation name
- replaces exact `Chatwoot` occurrences with `globalConfig.value.installationName`

## When to apply it

Apply `replaceInstallationName` in the UI layer when a user-facing string contains `Chatwoot` and should adapt to branded or self-hosted installs.

Prefer this helper over hardcoded branded copy.

## Verification points

Check the spec file for current expected behavior, including:

- multiple replacements in one string
- no-op behavior when branding config is absent
- case-sensitive replacement of `Chatwoot`
