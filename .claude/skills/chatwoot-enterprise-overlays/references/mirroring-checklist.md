# Mirroring Checklist

## Contents

- [Before coding](#before-coding)
- [During the change](#during-the-change)
- [Before finishing](#before-finishing)

## Before coding

1. Search in both `app` and `enterprise` for the feature area.
2. Inspect `config/initializers/01_inject_enterprise_edition_module.rb` if hooks are involved.
3. Decide whether the behavior belongs in OSS, Enterprise, or both.

## During the change

1. Keep request/response and public API contracts stable unless the change explicitly updates both editions.
2. Prefer overlay hooks when behavior is Enterprise-only.
3. Mirror file renames or structural moves into the Enterprise tree when an overlay exists.

## Before finishing

1. Check whether `spec/enterprise` needs an updated or mirrored example.
2. Re-run your searches to ensure no Enterprise override was missed.
3. Confirm the skill boundary still makes sense: overlay guidance here, general dev workflow elsewhere.
