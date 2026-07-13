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

`useBranding.js` exports `replacePublicBranding` and
`replaceTranslatedBranding`, while `useBranding()` exposes the existing
`replaceInstallationName` UI helper. Together they:

- return the original text when there is no installation name
- replace product-name occurrences regardless of case with the configured installation name
- replace upstream public domains with the configured brand host
- replace the voice transport provider name with `<installation name> Voice`
- support both raw `window.globalConfig` keys and the camel-cased Vuex global config

## When to apply it

Apply `replaceInstallationName` in a component when hardcoded public product,
domain, or voice-provider copy should adapt to the installation. Use
`replaceTranslatedBranding` as Vue I18n's `postTranslation` hook so community
locale values are branded without editing non-English source files.

Prefer this helper over hardcoded branded copy.

## Verification points

Check the spec file for current expected behavior, including:

- multiple replacements in one string
- no-op behavior when branding config is absent
- case-insensitive product replacement
- public domain replacement using `BRAND_URL`
- voice-provider replacement using the installation name
