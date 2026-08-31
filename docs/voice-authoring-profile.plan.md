# Voice Authoring Profile Persistence - Implementation Plan

## Problem and Success Criteria
- Saved Voice assistants expose the same optional tone, business-context, and boundaries helper as new assistants; saving and reopening preserves the values.
- Create/update accept only a top-level `authoring_profile` object with `tone`, `business_context`, and `boundaries`; clients cannot mass-assign `config`.
- `tone` accepts only `friendly`, `professional`, or `concise`; both text fields accept strings up to 2,000 characters. Invalid writes return the repository-standard `422` validation response and do not partially update the assistant.
- Existing or malformed stored metadata reads as `{ tone: 'friendly', business_context: '', boundaries: '' }` field-by-field without a migration.
- Editing helper fields marks the form dirty and persists them, but never changes `prompt`. Only the explicit “build/reset suggested guidance” action may replace the prompt and must retain the current confirmation, focus, scroll, feedback, editability, and 16-row/min-height behavior.
- Authoring metadata is excluded from release snapshots, release API snapshot responses, and fingerprints; it does not clear successful draft-test state, create draft changes or a release revision, or reach runtime, and the current canonical profile survives publish and rollback.
- English and Turkish source locales remain key-aligned; no Primary goal field or copy returns.

## Current State Evidence
- `app/javascript/dashboard/routes/dashboard/settings/voiceAi/VoiceAiSettings.vue:134-138` initializes a transient `voiceSetupProfile`; `:512-553` uses it only when the user explicitly builds a draft.
- `app/javascript/dashboard/routes/dashboard/settings/voiceAi/VoiceAiSettings.vue:596-625` omits the profile from save/dirty-state payloads; `:656-679` does not hydrate it from a saved agent.
- `app/javascript/dashboard/routes/dashboard/settings/voiceAi/VoiceAiSettings.vue:1292-1353` hides the helper whenever `editingVoiceAgentId` exists; `:1355-1377` contains the preserved prompt textarea and feedback behavior.
- `app/javascript/dashboard/routes/dashboard/settings/voiceAi/specs/VoiceAiSettings.spec.js:139-242` covers field order/no goal, localized generation, confirmation, focus/scroll/feedback, editability, and create/update payloads.
- `app/controllers/api/v1/accounts/voice/agents_controller.rb:77-109` permits a narrow set of fields and currently permits neither `config` nor a profile; create/update both use these params at `:16-38`.
- `app/models/voice_agent.rb:7,171-174` confirms non-null JSONB `config` already exists and is normalized to a hash, so no schema change is required.
- `app/services/voice_agents/serializer.rb:4-6,32-34` currently returns the complete `config` attribute.
- `app/services/voice_agents/release_snapshot.rb:4-9` snapshots complete `config`; `app/models/voice_agent.rb:81-95,138-147` uses that snapshot for releases, fingerprints, draft-test state, and draft-change state.
- `app/models/voice_agent.rb:99-117,162-164` restores all snapshot attributes on rollback, including `config`; profile preservation therefore needs an explicit merge rule after profile metadata is excluded from snapshots.
- `app/controllers/api/v1/accounts/voice/agent_releases_controller.rb:10-19` serializes release index/show/rollback responses through the generic release serializer; show and rollback currently expose the persisted snapshot and therefore need Voice-specific response sanitation for historical releases.
- `app/services/voice_agents/runtime_context.rb:93` passes release/draft `config` to runtime, while searches under `app/services/voice_agents` found no other runtime interpretation of general `config`.
- `spec/requests/api/v1/accounts/voice/agents_spec.rb:50-265` is the existing behavioral request-contract suite; `spec/models/voice_agent_spec.rb:44-121` owns lifecycle/fingerprint/rollback behavior.
- Searches for the affected controller, serializer, and model symbols under `enterprise/` returned no overlay; parity remains through the OSS implementation.
- `app/javascript/dashboard/api/voice.js:21-35` is a pass-through API client, so the contract needs no client method or store change.
- At planning start, `git status --short` reported only the four stated uncommitted UX/locale files; those pre-existing changes remain implementation-owned preservation evidence, while this plan file is the only added planning artifact.

## Approach
Store the profile under one reserved JSONB key, `config['authoring_profile']`, but expose and accept it only as the top-level API field `authoring_profile`. Add a small `VoiceAgents::AuthoringProfile` value object as the single source of defaults, permitted tones, 2,000-character limits, read normalization, and strict write validation. The controller will strongly permit only the three nested keys and merge the validated normalized profile into the existing `config`, preserving all unrelated runtime config keys; arbitrary `config` remains ignored.

The serializer will return normalized `authoring_profile` and return `config` with the reserved key removed. `VoiceAgents::ReleaseSnapshot.sanitize` will be the one sanitation path for both newly built and arbitrary historical snapshots: deep-stringify a hash input, retain only `ATTRIBUTES` plus `knowledge_sources`, coerce a non-hash `config` to `{}`, and remove the reserved profile key from config. A non-hash snapshot sanitizes to the same safe allowed-key shape rather than being trusted. `ReleaseSnapshot.for` must pass its output through this sanitizer, and Voice release show/rollback responses must serialize the sanitized snapshot rather than historical raw JSONB.

Rollback must sanitize the selected historical snapshot before any new release is created, compute the fingerprint from that exact sanitized object, persist that exact object as the rollback release snapshot, and restore runtime fields/knowledge assignments from that same object. Only after runtime restoration may the model merge the pre-rollback canonical authoring profile into its draft `config`; that profile is never added to the rollback release. This separation is smaller than a new column/table, avoids leaking authoring data into runtime or release identity, and keeps one JSONB document without opening mass assignment.

Do not derive helper fields from an existing prompt and do not regenerate the prompt on hydration, field edits, save, publish, or rollback. Older assistants therefore receive safe helper defaults while their existing prompt remains untouched.

## Verified Facts vs Assumptions
| Item | Evidence | Status |
|------|----------|--------|
| JSONB can hold metadata without migration | `app/models/voice_agent.rb:7,171-174` | VERIFIED |
| Voice create/update is the relevant narrow write boundary | `app/controllers/api/v1/accounts/voice/agents_controller.rb:16-38,77-109` | VERIFIED |
| Full config currently affects release identity/readiness | `app/services/voice_agents/release_snapshot.rb:4-9`; `app/models/voice_agent.rb:138-147` | VERIFIED |
| Runtime consumes config from a release/draft snapshot | `app/services/voice_agents/runtime_context.rb:93` | VERIFIED |
| Release show/rollback responses can expose persisted snapshots | `app/controllers/api/v1/accounts/voice/agent_releases_controller.rb:10-19`; `app/services/assistant_releases/serializer.rb` | VERIFIED |
| No Enterprise overlay mirrors affected symbols | repository search under `enterprise/` | VERIFIED |
| No frontend store adapter is involved | `app/javascript/dashboard/api/voice.js:21-35`; component direct calls at `VoiceAiSettings.vue:723-739,748-776` | VERIFIED |
| Text limits should be 2,000 characters each | Product asks for “reasonable existing-style lengths”; the repository uses 2,000 for bounded operational text at `app/models/voice_tool_event.rb:42` | VERIFIED design decision (new contract) |
| Standard exception rendering will shape invalid profile errors | Not required to assume: request specs must lock the actual status/body, and implementation may render a local `422` profile error if shared rescue does not provide a stable body | VERIFIED implementation boundary |

## Scope
- Allowed: `VoiceAgent` profile/runtime-config accessors; focused `VoiceAgents::AuthoringProfile` and release-snapshot sanitation; Voice agents and Voice agent-releases controllers plus agent serializer; release snapshot/rollback separation; focused model/service/agent-request/release-request specs; `VoiceAiSettings.vue` and its focused spec; maintained EN/TR Voice helper copy if needed.
- Forbidden: migrations, new tables/columns, arbitrary `config` request permission, runtime prompt composition changes, release schema backfills, OpenAPI/client generation, Primary goal fields, password/auth changes, unrelated Voice UI refactors, generated Histoire assets, or edits outside the listed behavior.
- Preserve: all pre-existing uncommitted changes in the four UX/locale files. Before implementation, capture `git diff --` for those paths; after each edit and final review, compare the resulting diff to ensure confirmation/focus/feedback/layout/height changes remain.

## Blast Radius and Invariants
- API entry points: Voice agent index/show/create/update responses gain top-level `authoring_profile`; create/update accept only its three keys. Existing callers omitting it retain config and behavior.
- Persistence: only `config['authoring_profile']` is changed by this contract; all sibling runtime-config keys survive create/update and publish, and rollback restores sibling runtime keys from the selected sanitized release while retaining the current profile only on the model. Missing/non-hash profile data is read-normalized, not backfilled eagerly.
- Runtime/release: one sanitizer removes the reserved key from newly built snapshots, arbitrary historical snapshots used for rollback, and release API snapshot responses. Profile-only updates leave `draft_fingerprint`, `draft_changes?`, `draft_tested?`, `last_tested_at`, release revision, and live release values unchanged.
- Prompt authority: helper and prompt are independent persisted form fields. Generation remains an explicit destructive action protected by the existing confirmation when the prompt diverged from `lastSafePrompt`.
- UI composition: within the existing editor card the reading order remains name/greeting → optional helper → authoritative instructions textarea → remaining capabilities/assignments. The helper remains adjacent to the prompt for both new and saved agents, uses the existing bordered section and controls, honors Voice-access disabled state, and introduces no new loading/empty/error surface beyond existing page/save handling.
- Authorization/account isolation remains inherited from `BaseController`, admin authorization, feature gate, and account-scoped lookup at `agents_controller.rb:1-5,73-75`; negative account/feature tests must remain green.

## Milestone 1: Separate Authoring Metadata from Runtime and Release Identity
- Dependencies: None.
- Subphases:
  1. Add `VoiceAgents::AuthoringProfile` with constants for the reserved key, defaults, tones, and 2,000-character limits. Provide strict write validation (object/hash shape and exact permitted values/types/lengths; unknown nested keys are filtered by strong params and ignored) and tolerant field-by-field read normalization (invalid/missing tone → `friendly`; non-string/oversized context or boundaries → empty string; valid sibling fields retained).
  2. Add focused `VoiceAgent` methods to read normalized profile, merge a validated profile into existing config, and return runtime config without the reserved key. Do not expose a general config writer.
  3. Add `VoiceAgents::ReleaseSnapshot.sanitize(snapshot)` as the only release sanitation function. `for(agent)` passes the freshly built snapshot through it. It accepts arbitrary historical input, keeps only runtime snapshot keys plus `knowledge_sources`, converts malformed/non-hash config to `{}`, and strips `authoring_profile` without mutating the caller’s object.
  4. Change `rollback_to!` ordering: capture the current canonical profile; sanitize the selected release snapshot; fingerprint that exact sanitized object; create the rollback release with that fingerprint and snapshot; restore runtime attributes and knowledge assignments from the same object; merge the captured profile only into the model’s restored config; save/current-release bookkeeping remains inside the existing lock/transaction.
- Files/behavior boundary: add `app/services/voice_agents/authoring_profile.rb` and its focused spec; modify `app/models/voice_agent.rb`, `app/services/voice_agents/release_snapshot.rb`, and `spec/models/voice_agent_spec.rb`; add `spec/services/voice_agents/release_snapshot_spec.rb` for arbitrary-input sanitation.
- INNER/CHECKPOINT: `bundle exec rspec spec/services/voice_agents/authoring_profile_spec.rb spec/services/voice_agents/release_snapshot_spec.rb spec/models/voice_agent_spec.rb`.
- Milestone gate: demonstrate that changing only profile metadata does not change fingerprint/test/readiness/release revision; a deliberately contaminated historical release rolls back to a newly persisted sanitized snapshot whose fingerprint equals `AssistantReleases::Snapshot.fingerprint(restored.snapshot)`; the new release and the model’s runtime-only config view contain no profile; the model’s persisted config retains its pre-rollback canonical profile; and runtime config/prompt/knowledge restoration all come from the sanitized object.
- Evidence invalidation: any later edit to profile normalization, `ReleaseSnapshot`, fingerprinting, or rollback requires rerunning this gate.
- Stop conditions: stop if any runtime consumer demonstrably requires the reserved authoring key, existing persisted config uses `authoring_profile` for another meaning, the sanitizer cannot safely preserve the existing allowed snapshot/knowledge-source contract, or snapshot creation/fingerprinting/restoration cannot share one exact sanitized object atomically under the current lock.
- Acceptance: normalized backward-compatible profile access exists without schema work; all newly built and rollback-created snapshots contain no reserved key; rollback release fingerprint exactly matches its stored sanitized snapshot; model-only profile preservation and lifecycle semantics are proven.

## Milestone 2: Add the Narrow Voice API Contract
- Dependencies: Milestone 1.
- Subphases:
  1. Strong-permit `authoring_profile: [:tone, :business_context, :boundaries]` separately from ordinary assignable attributes. Validate it only when the top-level key is supplied, merge it through the model’s narrow method inside the existing create/update transaction, and return `422` with field-addressable errors on invalid object/type/tone/length. Omission on update must preserve the stored profile; explicit empty strings clear the two text fields.
  2. Extend `VoiceAgents::Serializer` with normalized top-level `authoring_profile` and serialize runtime-only `config`, preventing duplication/leakage of the reserved key.
  3. In the Voice release controller response path, sanitize snapshots before including them in show/rollback payloads; keep the generic release serializer unchanged for AI-agent releases. Index remains snapshot-free, and tests lock that property.
  4. Add agent request coverage for create/update persistence and response shape, omitted-update preservation, valid clearing, unknown/arbitrary `config` rejection/ignoring, invalid tone/type/oversize atomic rejection, existing malformed/missing metadata defaults, account ownership, and unchanged profile-only test/readiness state.
  5. Extend `spec/requests/api/v1/accounts/voice/agent_releases_spec.rb` for index/show/rollback: seed a deliberately contaminated historical release snapshot; assert index never includes snapshots, show returns a sanitized snapshot, rollback response and newly persisted rollback release contain the same sanitized snapshot with no profile, its fingerprint equals the fingerprint recomputed from that stored snapshot, and the assistant retains its current canonical profile only in model config.
- Files/behavior boundary: `app/controllers/api/v1/accounts/voice/agents_controller.rb`, `app/controllers/api/v1/accounts/voice/agent_releases_controller.rb`, `app/services/voice_agents/serializer.rb`, `spec/requests/api/v1/accounts/voice/agents_spec.rb`, and `spec/requests/api/v1/accounts/voice/agent_releases_spec.rb`; no API client or generic release serializer change.
- INNER/CHECKPOINT: `bundle exec rspec spec/requests/api/v1/accounts/voice/agents_spec.rb spec/requests/api/v1/accounts/voice/agent_releases_spec.rb` and focused profile/snapshot/model specs from Milestone 1.
- Milestone gate: create and update round-trip the exact top-level contract while persisted JSONB changes only the reserved subtree, sibling config survives, normal responses omit the profile from `config`, and invalid updates leave the complete record unchanged. Release index/show/rollback additionally prove contaminated history cannot leak the reserved key through API responses or newly created rollback releases and that rollback fingerprint equals the exact stored sanitized snapshot.
- Evidence invalidation: either Voice controller, serializer, model, release sanitizer, release response shaping, or shared exception rendering invalidates this gate.
- Stop conditions: stop if API error semantics require a public contract decision beyond the existing `422` pattern, strong parameters cannot distinguish omission from explicit clearing without changing unrelated behavior, or Voice release snapshots cannot be sanitized in responses without changing the generic AI release contract.
- Acceptance: the API is additive, account-scoped, strictly bounded, backward compatible for omitted fields, cannot overwrite arbitrary config, and never exposes authoring metadata through Voice release snapshots even when historical rows are contaminated.

## Milestone 3: Hydrate, Edit, and Persist the Helper Without Rewriting Instructions
- Dependencies: Milestone 2 response/request shape.
- Subphases:
  1. Define one frontend default/normalization helper matching server defaults. On new-agent reset use defaults; on saved-agent sync hydrate `agent.authoring_profile`; include the profile in dirty-state and save payloads using snake_case API keys.
  2. Remove only the `!editingVoiceAgentId` visibility condition so the existing optional helper section stays adjacent to the prompt for saved agents. Disable its select/textareas/build action when Voice access is disabled and apply matching `maxlength="2000"` attributes; retain the existing hierarchy, field order, and no-goal copy.
  3. Extend focused Vitest coverage for saved hydration/rendering, create/update payloads, dirty-state changes, defaults for absent/malformed responses, profile-only edits leaving `agentForm.prompt` byte-for-byte unchanged, explicit build behavior, disabled controls, max lengths, and all existing confirmation/focus/scroll/feedback/textarea-height assertions.
- Files/behavior boundary: the already-dirty `app/javascript/dashboard/routes/dashboard/settings/voiceAi/VoiceAiSettings.vue`, its existing focused spec, and matching `app/javascript/dashboard/i18n/locale/{en,tr}/aiAgent.json` only if persisted-edit wording needs adjustment. Preserve every current UX change rather than replacing the files wholesale.
- INNER/CHECKPOINT: use Node from `.nvmrc` and Corepack pnpm; run the repository’s focused Vitest invocation for `VoiceAiSettings.spec.js`, then `pnpm eslint app/javascript/dashboard/routes/dashboard/settings/voiceAi/VoiceAiSettings.vue app/javascript/dashboard/routes/dashboard/settings/voiceAi/specs/VoiceAiSettings.spec.js` (or the repository-supported equivalent if ESLint script does not accept paths), and compare EN/TR key paths.
- Milestone gate: all focused component tests pass, targeted ESLint has zero errors, and diff inspection confirms the pre-existing overwrite confirmation, prompt focus/scroll/feedback, optional-helper copy/location, and rows=16/min-h-80 changes remain.
- Evidence invalidation: any later component, spec, or locale edit invalidates focused Vitest/lint/locale evidence; generated Histoire output is never edited.
- Stop conditions: stop if the saved-agent response lacks the agreed profile shape after Milestone 2, or if making the helper visible conflicts with an existing editor state/accessibility contract not represented in the current component.
- Acceptance: saved and new assistants show the same optional helper, save/reopen round-trips values, helper-only changes enable Save but do not alter prompt, and explicit generation retains all current safeguards.

## Conditional Surface Contracts

### API Contract
```json
{
  "authoring_profile": {
    "tone": "friendly | professional | concise",
    "business_context": "string, 0..2000",
    "boundaries": "string, 0..2000"
  }
}
```
- Field is optional on create/update. Create omission and legacy reads return defaults; update omission preserves existing metadata.
- When supplied, require an object and return a complete normalized response. Merge supplied nested keys over defaults on create and over the current normalized profile on update, so `{ "tone": "concise" }` does not clear text fields.
- `null`, arrays, non-string values, unsupported tones, or over-limit text return `422`; no truncation and no partial persistence.
- Unknown top-level `config` remains unpermitted. Unknown nested profile keys follow existing strong-parameter behavior and are not persisted; request coverage locks this behavior.
- Responses from index/show/create/update/publish/activate/pause include normalized top-level profile because all use the same agent serializer. `config` remains present for compatibility but excludes the reserved authoring subtree. Voice release index remains snapshot-free; release show/rollback include only sanitized snapshots and do not add the top-level authoring profile.

### Persistence and Release Contract
- Physical shape: `voice_agents.config.authoring_profile`; no migration/backfill.
- Read normalization is non-destructive and field-by-field. A later valid profile save replaces only the reserved subtree with canonical keys/values.
- Sanitizer contract: `ReleaseSnapshot.sanitize` deep-stringifies hash input, retains only `ATTRIBUTES` and `knowledge_sources`, normalizes malformed config to `{}`, removes `config.authoring_profile`, and returns a new object. Fresh publish snapshots, historical rollback input, and Voice release API snapshot output all use this function.
- Snapshot config equals persisted config minus `authoring_profile`; fingerprints and release payloads therefore remain runtime-only.
- Rollback algorithm: capture the current canonical authoring profile; sanitize the selected historical snapshot once; compute fingerprint from that object; persist it unchanged in the new rollback release; restore runtime attributes/knowledge assignments from it; then merge the captured profile only into the model config. The rollback release snapshot, rollback response snapshot, and fingerprint input must be equal in content.
- Profile-only controller updates compare the same runtime-only draft fingerprint before/after, so `last_tested_at` and `last_tested_draft_fingerprint` remain intact under the existing clearing logic at `agents_controller.rb:30-33`.

### UI Composition Contract
- Screen zone: existing assistant editor main column; no new page, modal, sidebar, or step.
- Reading/action order: identity fields → bordered optional guidance helper (tone, context, boundaries, build/reset action) → large authoritative Instructions textarea and its help/feedback/count → existing remaining editor sections/save action.
- The build action is secondary/outlined and remains inside the helper; Save remains the form’s primary persistence action. Helper edits never imply generation.
- Existing loading and save-error behavior remains page-level. Missing profile uses populated defaults, not an empty/error state. Disabled Voice access disables helper inputs/action consistently with name/prompt controls. Existing responsive single-column flow and textarea resize behavior remain.

### Enterprise Parity Contract
- Re-run symbol searches in `app`, `enterprise`, and `spec/enterprise` before final review. If an overlay appears due to branch movement, stop and mirror the contract/spec through the established hook; otherwise no Enterprise-only files are added.

## Final Validation and Review
- After implementation review fixes, run FINAL: `spec/services/voice_agents/authoring_profile_spec.rb`, `spec/services/voice_agents/release_snapshot_spec.rb`, `spec/models/voice_agent_spec.rb`, `spec/requests/api/v1/accounts/voice/agents_spec.rb`, and `spec/requests/api/v1/accounts/voice/agent_releases_spec.rb`; focused `VoiceAiSettings.spec.js`; targeted ESLint; EN/TR profile-key parity; and `git diff --check`.
- Inspect final `git status` and path-scoped diff against the captured starting diff. No migration, generated Histoire asset, password/auth file, or unrelated worktree file may appear.
- Perform a full high-attention review of security (strong params/account scope/atomic rejection), persistence merge symmetry, legacy malformed values, one-path snapshot sanitation, contaminated-history release API behavior, exact snapshot/fingerprint equality, readiness invariants, rollback ordering, prompt non-rewrite, locale parity, and preservation of the uncommitted UX work. Re-run only evidence invalidated by review fixes.
- Only after code/test/review completion: production build and deployment/reload using the existing home-server release procedure, then health/readiness checks and a browser smoke test using the user-set permanent demo password. Browser acceptance: open a saved assistant, observe persisted helper values, edit/save/reload them, confirm prompt is unchanged until explicit build, verify cancellation preserves a manual prompt, and confirm lifecycle/readiness/revision indicators do not change for a profile-only edit. Do not mutate browser/runtime state during implementation milestones.

## Risks and Rollback
- Risk: filtering the reserved key only in ordinary agent serialization or fresh snapshots would erase/resurrect profile metadata during rollback or leak it from historical releases. Mitigation: one runtime-config accessor for agent config plus one release-snapshot sanitizer used by fresh snapshots, rollback, and Voice release snapshot responses, with explicit merge and contaminated-history specs.
- Risk: a historical release created before this feature may already contain `config.authoring_profile`; copying its raw snapshot during rollback or show would reintroduce metadata into release history/API output and produce a fingerprint for different content. Mitigation: the single sanitizer is mandatory at fresh snapshot creation, historical rollback input, and Voice release response output; contaminated-history model/service/request tests assert stored snapshot, response snapshot, and recomputed fingerprint agree.
- Risk: profile-only API updates could clear successful test state if fingerprint input still includes metadata. Mitigation: request and model assertions compare fingerprint, `draft_tested?`, timestamps, draft-change flag, and revision before/after.
- Risk: editing the already-dirty Vue/locales could regress accepted UX. Mitigation: capture and compare the initial path-scoped diff; make surgical edits and retain focused tests.
- Compatibility-preserving application rollback: frontend helper persistence and the API write/exposure of top-level `authoring_profile` may be reverted while preserving the pre-existing four-file UX diff, but runtime-config filtering, tolerant read normalization, snapshot sanitation, sanitized Voice release responses, and sanitized rollback creation/restoration remain deployed as the compatibility floor. This keeps already-written reserved keys inert and prevents historical contamination from reaching runtime or release APIs.
- A full code removal is not a safe rollback once any profile data exists. It requires a separate reviewed data-cleanup/backfill operation that removes reserved keys from model config and historical release snapshots, recomputes affected fingerprints where appropriate, proves release/runtime compatibility, and only then removes the compatibility floor. That cleanup/migration is explicitly outside this mission.
- No database cleanup, backfill, or migration is performed by this change or its normal rollback.
