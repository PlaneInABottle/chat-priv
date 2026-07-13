# I18n Source Files

## Contents

- [English-only policy](#english-only-policy)
- [Backend source files](#backend-source-files)
- [Frontend source files](#frontend-source-files)
- [Sync step](#sync-step)

## English-only policy

`AGENTS.md` says to update only English source files in-repo because Crowdin and community flows handle other locales.

## Backend source files

Use:

- `config/locales/en.yml`

That is the Rails-backed English source file called out by `AGENTS.md`.

## Frontend source files

Use these repo-backed entrypoints:

- `app/javascript/dashboard/i18n/index.js`
- `app/javascript/dashboard/i18n/locale/en/**`
- `app/javascript/widget/i18n/locale/en.json`
- `app/javascript/survey/i18n/locale/en.json`

`app/javascript/dashboard/i18n/index.js` and `app/javascript/dashboard/i18n/locale/en/index.js` show how the dashboard English bundle is assembled.

## Sync step

After changing locale keys or English source files, run:

```bash
pnpm sync:i18n
```

## Build-time translated branding

`vite.config.ts` defines the `kozmopath-locale-branding` pre-transform for
locale JSON modules. It recursively rewrites string values at build and test
time while preserving translation keys and repo-owned non-English source
files. Keep customer-facing provider/product replacement in that transform
and in the Vue I18n `postTranslation` hook rather than bulk-editing community
locales.
