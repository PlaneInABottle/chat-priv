# Overlay Hooks

## Contents

- [Primary evidence](#primary-evidence)
- [Hook methods](#hook-methods)
- [Search pattern before editing](#search-pattern-before-editing)
- [What to preserve](#what-to-preserve)

## Primary evidence

Start with these repo files:

- `config/initializers/01_inject_enterprise_edition_module.rb`
- `enterprise/`
- `spec/enterprise/`
- `AGENTS.md` enterprise guidance section

## Hook methods

The initializer prepends methods onto `Module` and exposes these entrypoints:

- `prepend_mod_with`
- `include_mod_with`
- `extend_mod_with`

Use that initializer as the authority for how Enterprise modules are injected into OSS classes and modules.

## Search pattern before editing

Run a targeted search across both trees before changing core behavior:

```bash
rg -n "ClassName|ServiceName|prepend_mod_with|include_mod_with" app enterprise spec
```

Check for all of the following:

- the OSS implementation in `app/` or `lib/`
- any Enterprise override module under `enterprise/`
- mirrored or Enterprise-specific specs under `spec/enterprise/`

## What to preserve

- Public contracts must stay aligned across OSS and Enterprise.
- Enterprise-only behavior should prefer overlay modules over hard-forking OSS code.
- File moves or renames in OSS usually require corresponding Enterprise review.
