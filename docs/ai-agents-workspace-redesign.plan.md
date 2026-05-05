# AI Agents Workspace Redesign - Implementation Plan

## Problem Statement

The current AI Agent workspace already moved away from the old always-on right rail and now uses in-page tabs, but the latest user preference changes the next UX priority: prompt authoring and testing should happen in one shared workspace view. Today users still have to switch from **Instructions** to **Test & publish**, which creates a mental/context break exactly at the moment they want to save a draft and immediately test it.

There is also a smaller but visible UX quality issue: AI Agent form fields currently mix different focus/error treatments (blue border, blue outline, ruby border) depending on whether the control is an `Input`, `TextArea`, or `ComboBox`, which makes the page feel less polished for non-technical users.

## Approach

Frontend-only IA refinement on top of the current tabbed workspace: keep the existing route, stores, draft/publish semantics, and current backend constraints, but make **Instructions** the primary split workspace on desktop with a large authoring pane on the left and a contextual **Test & publish** pane on the right. Keep **Tools** and **Channels & handoff** as separate tabs. Keep versioning/readiness/publish context supportive rather than competing with authoring.

## Success Criteria

- [ ] Users can write instructions, save draft, and test in one desktop view without switching to a separate step-first screen.
- [ ] The prompt editor remains the dominant surface in the workspace.
- [ ] The test simulator/chat area is available side by side with authoring on desktop, but the page still feels calm and SMB-friendly.
- [ ] Versioning/readiness/publish context remains visible and useful without crowding the page.
- [ ] The redesign stays realistic on the current OSS frontend and does not require new backend runtime semantics.
- [ ] AI Agents form controls use one consistent focus/error language inside this workspace.

## Executive Summary

**Recommendation:** keep the current hybrid workspace shell, but change the IA inside it.

- Keep top-level AI Agents navigation as **Agents** + **Tools**.
- Keep one canonical per-agent route.
- Keep **Instructions** as the default primary tab.
- On desktop, make **Instructions** a **two-column workspace**:
  - **Left:** large prompt/instructions authoring area.
  - **Right:** contextual **Test & publish** column.
- Keep **Tools** and **Channels & handoff** as separate top-level workspace tabs.
- Move detailed versioning/readiness into the right-side support stack under the testing surface, while keeping only compact status hints in the header/summary strip.

This is the simplest viable direction because it uses the current page architecture (`AiAgentEditPage.vue`) and current test/publish support data (`workspace_summary`) without duplicating testing in two places or introducing new routes.

## Current State (evidence)

### Facts observed in code

- The per-agent workspace already uses in-page tabs for `instructions`, `tools`, `channels`, and `testPublish`: `app/javascript/dashboard/routes/dashboard/aiAgents/pages/AiAgentEditPage.vue:47-64`.
- The page currently renders only one heavy panel at a time via `v-if` branches for form, channels, and test/publish: `AiAgentEditPage.vue:211-261`.
- Instructions and Tools currently share the same `AiAgentForm` instance rather than separate route-level pages: `AiAgentEditPage.vue:219-234`, `app/javascript/dashboard/routes/dashboard/aiAgents/pages/AiAgentEditPage.spec.js:439-466`.
- The prompt editor is already implemented with the shared `TextArea` component and is materially larger than a default field (`min-height="26rem"`, `max-height="40rem"`): `app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentForm.vue:230-253`.
- The shared `TextArea` already supports `autoHeight`, `minHeight`, and `maxHeight`, so a larger authoring surface does not require a new editor stack: `app/javascript/dashboard/components-next/textarea/TextArea.vue:19-23`, `TextArea.vue:56-64`, `TextArea.vue:178-180`.
- `Test & publish` already renders as a split layout with a dominant left placeholder surface and a right support column containing versioning and readiness: `app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentWorkspacePublishPanel.vue:28-231`.
- The edit page already exposes the exact data needed for supportive publish context (`status`, `readiness`, `versions`) from `workspace_summary`: `AiAgentEditPage.vue:29-37`, `AiAgentEditPage.vue:254-260`.
- The reusable shell still supports an optional page-level right rail, but the current edit page does not use that slot anymore: `app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentsWorkspaceLayout.vue:21-25`, `AiAgentsWorkspaceLayout.vue:47-58`, `AiAgentEditPage.vue:155-264`.
- Current tests explicitly assert the one-heavy-area-at-a-time behavior and the right-side versioning/readiness support column inside `Test & publish`: `AiAgentEditPage.spec.js:332-437`, `AiAgentEditPage.spec.js:468-497`.

### Focus-style evidence

- `TextArea` uses a **border**-based state model: brand border on focus, ruby border on error-at-rest: `app/javascript/dashboard/components-next/textarea/TextArea.vue:150-163`.
- `Input` uses an **outline**-based state model: weak outline at rest, brand outline on focus, ruby outline on error: `app/javascript/dashboard/components-next/input/Input.vue:53-60`, `Input.vue:117-145`.
- `ComboBox` routes state through `Button` color variants (`ruby`, `blue`, `slate`) rather than matching the same wrapper treatment as `Input`/`TextArea`: `app/javascript/dashboard/components-next/combobox/ComboBox.vue:98-110`.

### Constraint observations

- There is no real simulator/chat implementation yet; the current left testing surface is still honest placeholder UI: `AiAgentWorkspacePublishPanel.vue:32-91`.
- Save draft and publish already live in the workspace header and should remain there as canonical actions: `AiAgentEditPage.vue:163-194`.
- Backend publish/version/restore semantics already exist and should be reused rather than redefined in frontend code: `AiAgentEditPage.vue:78-138`.
- Reusable layout primitives already exist and should be leveraged: `AiAgentsSectionCard.vue`, `AiAgentWorkspacePublishPanel.vue`, `AiAgentWorkspaceSubnav.vue`, `TextArea.vue`.

## Recommended IA / Layout Model

## Final recommendation

Use a **contextual split workspace**.

### Keep tabbed

1. **Instructions** (default)
2. **Tools**
3. **Channels & handoff**

### Make side-by-side on desktop

Inside **Instructions**, render a desktop split layout:

- **Left authoring pane (~60-65%)**
  - name
  - short description
  - enabled state
  - large prompt/instructions editor
  - collapsed advanced settings
- **Right contextual pane (~35-40%)**
  - test simulator/chat surface (placeholder first, real simulator later)
  - save/test guidance
  - readiness summary
  - draft/live/version context
  - version history / restore actions in a secondary section

### Do not keep as a separate peer tab on desktop

Remove **Test & publish** as a primary peer tab in the desktop mental model. The content belongs next to authoring, not behind another top-level step.

For smaller screens, keep the same content but stack it inside **Instructions**:

- prompt/editor first,
- test area second,
- readiness/versioning/publish support third.

If a compact secondary switch is needed inside the right column later, use it only **within** the contextual pane (for example `Test` / `Versions`), not as a page-level tab.

## Why this is the best fit

- It directly satisfies the new authoritative preference: write + save + test in one place.
- It avoids duplicate testing surfaces.
- It preserves Chatwoot-native simplicity by keeping only three understandable workspace tabs.
- It is implementation-realistic because the page already has the necessary data, layout primitives, and split test/publish component.

## Rejected alternatives

### Rejected: keep separate `Test & publish` tab and also add a mini tester to `Instructions`

- Duplicates the mental model.
- Risks drift between two test surfaces.
- Reintroduces clutter.

### Rejected: three-column desktop layout

- Too dense for SMB users.
- Would make versioning/readiness compete with both authoring and testing.

### Rejected: fully route-driven `Instructions/Test/Publish` pages

- Too much implementation cost for the current scope.
- Unnecessary when the current page already supports local tab state and shared draft data.

## Detailed Layout Proposal

## A. Header

- Keep `AiAgentsWorkspaceHeader` and current actions.
- Keep top-level `Agents` / `Tools` navigation unchanged.
- Keep `Save draft` and `Publish` as the canonical actions in the header.
- Keep a compact draft/live status indicator in the header.

## B. Summary strip

- Keep the compact summary strip below the header.
- Keep it orienting, not dominant.
- Recommended content:
  - purpose,
  - live inbox count/names,
  - selected tools count,
  - compact readiness badge,
  - compact version hint such as `Live v3` or `Draft changes`.

## C. Main workspace tabs

### Instructions (default)

**Desktop structure**

- `xl:grid-cols-[minmax(0,1.55fr)_minmax(22rem,0.95fr)]` or equivalent ratio.
- Maintain more whitespace between the two panes than inside either pane.

**Left authoring pane**

- top identity block:
  - agent name,
  - short description,
  - enabled toggle.
- primary authoring block:
  - large instructions prompt,
  - supportive helper copy,
  - character count,
  - comfortable writing height.
- advanced block:
  - provider,
  - model,
  - endpoint,
  - API key,
  - handoff prompt/message,
  - collapsed by default.

**Right contextual Test & publish pane**

- top card: **Test**
  - test conversation / simulator shell,
  - placeholder-first implementation,
  - clear copy that testing uses the latest saved draft,
  - quick reminder that header `Save draft` is the source of truth.
- middle card: **Readiness**
  - publish readiness summary,
  - inbox connected / missing,
  - credentials ready / missing.
- lower card: **Versions**
  - draft/live status,
  - latest live version,
  - restore action,
  - collapsible history if vertical space becomes tight.

### Tools

- Keep as its own tab.
- Single-column content.
- Keep selected tools summary and selection list.
- Keep “Manage tools” deep link.

### Channels & handoff

- Keep as its own tab.
- Single-column content.
- Keep inbox binding and conflict handling in this tab.
- Keep handoff prompt and customer-facing handoff message here only if that proves clearer during implementation; otherwise leave them collapsed in Instructions advanced settings for the smallest initial change.

## Placement Strategy for Versioning / Readiness / Publish Context

### Versioning

- Keep only a compact status/version hint in the header or summary strip.
- Move detailed version history and restore actions into the **right-side contextual pane** in **Instructions**.
- Style version history as a supportive card, not a primary destination.

### Readiness

- Keep a compact readiness chip in the summary strip.
- Keep the detailed checklist directly below the testing card in the right contextual pane.

### Publish context

- Keep `Publish` in the header.
- Use the right pane for explanatory context only:
  - whether draft differs from live,
  - whether prerequisites are met,
  - what version is live now.

### Why versioning/readiness belong here

- They are most useful immediately before or during testing.
- They should support authoring decisions, not compete with them all the time.
- This placement preserves simplicity while avoiding a separate “last step” wall.

## Prompt Authoring UX Direction

- Keep **Instructions** as the strongest visual priority.
- Keep the prompt in its own high-contrast section with more breathing room than secondary fields.
- Keep prompt height in the current `26rem+` range, with room to grow if the split workspace reduces the visible width.
- Use plain-language helper text oriented to SMB users.
- Do not add rich editing, prompt libraries, templates, or KB/RAG features.

## Focus / Input Styling Cleanup

## Goal

The AI Agents workspace should use one consistent form-state language:

- neutral at rest,
- brand highlight on focus,
- ruby only for actual validation/error state,
- no control-specific “red border here, blue outline there” mismatch.

## Recommended implementation direction

- Normalize focus/error treatment for the AI Agents workspace across `Input`, `TextArea`, and `ComboBox`.
- Because the inconsistency originates in shared atoms (`Input.vue`, `TextArea.vue`, `ComboBox.vue`), do **not** patch over it with page-only CSS hacks.
- Prefer one of these minimal options:
  1. add an optional shared form-field visual variant used by the AI Agents workspace only, or
  2. safely align the existing shared atom behavior if the analyzer confirms the broader blast radius is acceptable.

## Constraints

- Do not restyle unrelated product surfaces opportunistically.
- Do not create a second design system just for AI Agents.

## Mobile / Responsive Rules

- Keep the same IA on mobile; do not bring back a separate `Test & publish` top-level tab only for smaller screens.
- Below `xl`, stack the Instructions layout vertically:
  1. authoring,
  2. test,
  3. readiness/versioning.
- If vertical density becomes too high, collapse version history behind a disclosure inside the supportive pane before hiding test access.
- Keep header actions wrapping, consistent with the current header action area.

## Phased Implementation Direction From Current State

---

## Phase 1: Reframe the workspace IA around Instructions + contextual testing

**Owner**: @implementer (frontend/workspace)
**Dependencies**: None
**Complexity**: MEDIUM

### Tasks

- [ ] Update the per-agent workspace tab model in `app/javascript/dashboard/routes/dashboard/aiAgents/pages/AiAgentEditPage.vue` from four peer tabs to three peer tabs: `Instructions`, `Tools`, `Channels & handoff`.
- [ ] Replace the current mutually exclusive `Instructions` vs `Test & publish` desktop model with an `Instructions` layout that can host both authoring and the contextual right pane.
- [ ] Keep `Save draft` and `Publish` in the header.
- [ ] Keep top-level `Agents` and `Tools` navigation unchanged.
- [ ] Update page tests that currently enforce “one heavy area at a time” so they instead enforce “single primary workspace tab with split Instructions view.”
- [ ] Verify the canonical route and store data flow remain unchanged.

### Acceptance Criteria

- [ ] Users no longer need a peer workspace tab switch to move from writing to testing.
- [ ] The page still loads through the existing agent edit route.
- [ ] The workspace still has only three top-level task tabs.

---

## Phase 2: Build the split Instructions workspace

**Owner**: @implementer (frontend/authoring UX)
**Dependencies**: Phase 1
**Complexity**: MEDIUM

### Tasks

- [ ] Extract or reorganize the current instructions content from `AiAgentForm.vue` so the prompt authoring block can live in a dedicated left pane.
- [ ] Reuse the current `AiAgentWorkspacePublishPanel.vue` pieces to form a right contextual pane instead of a separate peer-tab screen.
- [ ] Keep the prompt editor dominant and the right pane secondary in width, spacing, and typography.
- [ ] Keep advanced technical settings collapsed and below the prompt.
- [ ] Keep the right pane honest in this phase: placeholder or future-shell test surface at the top, readiness/version support below.
- [ ] Add copy that makes save-and-test behavior understandable: test runs against the latest saved draft.
- [ ] Update UI tests for desktop split layout and responsive stacked layout.

### Acceptance Criteria

- [ ] The prompt editor is the dominant surface when the page opens.
- [ ] The testing surface is visible next to authoring on desktop.
- [ ] Readiness/versioning are visible but clearly supportive, not primary.
- [ ] The layout remains calmer than the older crowded workspace.

---

## Phase 3: Keep Tools and Channels task-specific, not crowded

**Owner**: @implementer (frontend/workspace)
**Dependencies**: Phase 2
**Complexity**: LOW

### Tasks

- [ ] Keep tool selection isolated to the `Tools` tab.
- [ ] Keep inbox binding/conflict messaging isolated to `Channels & handoff`.
- [ ] Verify neither tab inherits the contextual testing pane by default.
- [ ] Keep header and summary-strip status hints present across tabs.
- [ ] Update tests so the non-Instructions tabs stay simple single-column task views.

### Acceptance Criteria

- [ ] Tools selection does not visually compete with authoring/testing.
- [ ] Inbox deployment semantics remain unchanged.
- [ ] Only the Instructions tab carries the split write-and-test workspace.

---

## Phase 4: Normalize focus and validation styling for AI Agents fields

**Owner**: @implementer (frontend/design system)
**Dependencies**: Phase 2
**Complexity**: MEDIUM

### Tasks

- [ ] Audit the minimal shared atoms needed for AI Agents field parity: `Input.vue`, `TextArea.vue`, and `ComboBox.vue`.
- [ ] Implement the smallest safe alignment strategy so focus/error styling reads consistently in the AI Agents workspace.
- [ ] Update or add tests for error + focus states where component tests already exist; otherwise capture browser evidence through the workspace.
- [ ] Verify error state stays ruby, focus stays brand, and invalid-focused fields do not visually bounce between unrelated treatments.

### Acceptance Criteria

- [ ] AI Agents form fields no longer show a visually mixed red-border / blue-border / blue-outline language.
- [ ] Focus and error states remain accessible and understandable.
- [ ] The cleanup does not regress unrelated field layout behavior.

---

## Phase 5: Activate the real test simulator without changing the IA again

**Owner**: @implementer (frontend/ux + later backend when ready)
**Dependencies**: Phase 2
**Complexity**: MEDIUM

### Tasks

- [ ] Replace the placeholder test card with a real conversation-like simulator when the necessary API/store contract is ready.
- [ ] Keep the right-pane structure stable so the IA does not change again.
- [ ] Preserve versioning/readiness beneath the simulator rather than moving them elsewhere.
- [ ] Verify save-draft-then-test flow from the same Instructions view.
- [ ] Validate responsive behavior with browser snapshots.

### Acceptance Criteria

- [ ] Users can save draft and test from the same Instructions workspace.
- [ ] The testing surface feels Chatwoot-native rather than copied from another product.
- [ ] No additional top-level workspace tabs are required.

## Deliverables

| Phase   | Files Created/Modified                                                                                                                                                                                                                                                                                       |
| ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Phase 1 | `app/javascript/dashboard/routes/dashboard/aiAgents/pages/AiAgentEditPage.vue`, `app/javascript/dashboard/routes/dashboard/aiAgents/pages/AiAgentEditPage.spec.js`, `app/javascript/dashboard/i18n/locale/en/aiAgents.json`                                                                                  |
| Phase 2 | `app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentForm.vue` or `AiAgentWorkspaceInstructionsPanel.vue`, `app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentWorkspacePublishPanel.vue`, `app/javascript/dashboard/routes/dashboard/aiAgents/pages/AiAgentEditPage.vue` |
| Phase 3 | `app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentForm.vue` or extracted task-panel components, `app/javascript/dashboard/routes/dashboard/aiAgents/pages/AiAgentEditPage.spec.js`, `app/javascript/dashboard/i18n/locale/en/aiAgents.json`                                              |
| Phase 4 | `app/javascript/dashboard/components-next/input/Input.vue`, `app/javascript/dashboard/components-next/textarea/TextArea.vue`, `app/javascript/dashboard/components-next/combobox/ComboBox.vue`                                                                                                               |
| Phase 5 | `app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentWorkspacePublishPanel.vue`, optional `AiAgentWorkspaceSimulatorPanel.vue`, `app/javascript/dashboard/routes/dashboard/aiAgents/pages/AiAgentEditPage.spec.js`                                                                          |

## Blast Radius / Affected Entry Points

- `app/javascript/dashboard/routes/dashboard/aiAgents/pages/AiAgentEditPage.vue` - primary workspace composition and tab IA change.
- `app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentForm.vue` - current authoring surface likely needs extraction/reorganization.
- `app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentWorkspacePublishPanel.vue` - current separate tab panel becomes contextual support content.
- `app/javascript/dashboard/routes/dashboard/aiAgents/pages/AiAgentEditPage.spec.js` - current tests encode the now-obsolete separate test/publish step.
- `app/javascript/dashboard/components-next/input/Input.vue` - shared field atom if styling is normalized at the source.
- `app/javascript/dashboard/components-next/textarea/TextArea.vue` - shared field atom if styling is normalized at the source.
- `app/javascript/dashboard/components-next/combobox/ComboBox.vue` - shared field atom if styling is normalized at the source.

## Allowed Scope / Forbidden Scope

- Allowed: per-agent workspace IA, desktop/mobile layout, prompt editor sizing, contextual testing placement, summary/status copy, versioning/readiness placement, field-state visual consistency.
- Forbidden: KB/RAG scope, new top-level AI Agents navigation areas, backend publish/runtime changes, custom tool CRUD redesign, unrelated global form redesign, speculative test infrastructure.

## Invariants

| Invariant                                                        | Why it matters                        | How to verify                                           |
| ---------------------------------------------------------------- | ------------------------------------- | ------------------------------------------------------- |
| Top-level AI Agents nav remains `Agents` + `Tools`               | Prevents scope drift                  | Open workspace and confirm top tabs/navigation behavior |
| Existing agent route remains canonical                           | Avoids routing rewrite                | Open `/app/accounts/:accountId/ai-agents/:id`           |
| Save draft / Publish remain in workspace header                  | Users should not relearn core actions | Browser walkthrough across all tabs                     |
| Backend version/restore semantics remain reused                  | Frontend must not fork release logic  | Restore a version through existing action wiring        |
| Tools CRUD remains in the top-level Tools workspace              | Avoids duplicate admin surfaces       | Use deep link from agent tools selection                |
| Only Instructions gets the side-by-side authoring/testing layout | Keeps Tools and Channels simple       | Browser walkthrough across tabs                         |

## Behavior That Must Not Change

- Existing draft save and publish flows remain available without leaving the agent workspace.
- Inbox conflict messaging remains inline and backend-driven in `Channels & handoff`.
- Top-level Tools continues to own custom tool CRUD.
- Version restore continues to use the existing store action and payload shape.

## Validation Matrix

| Check                  | Command / Method                                                                                                   | Proves                                              |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------- |
| Exact regression path  | `pnpm dev` then `agent-browser open http://localhost:3000/app/accounts/:accountId/ai-agents/:id` and `snapshot -i` | Canonical workspace route still loads               |
| Primary UX path        | Browser walkthrough of `Instructions` on desktop width                                                             | Users can write and see testing context in one view |
| Save/test mental model | Save draft, remain on `Instructions`, inspect contextual test copy/state                                           | Save-and-test workflow is no longer step-separated  |
| Edge case              | Open an agent with no inboxes, no tools, no versions                                                               | Empty states still read clearly for SMB users       |
| Behavior preservation  | Bind/unbind inbox and inspect conflict messaging in `Channels & handoff`                                           | Deployment semantics remain intact                  |
| Focus styling cleanup  | Browser walkthrough of valid, focused, and invalid `Input` / `TextArea` / `ComboBox` fields in AI Agents workspace | Field states are visually consistent                |

## Evidence Owners

| Item                                             | Owner        | Proof Required                                  |
| ------------------------------------------------ | ------------ | ----------------------------------------------- |
| Write-and-test in one view is materially clearer | @implementer | before/after browser screenshots and snapshots  |
| Prompt remains primary                           | @implementer | browser evidence of dominant left pane          |
| Versioning/readiness stay supportive             | @analyzer    | rendered-layout review against plan             |
| Non-Instructions tabs remain simpler             | @analyzer    | tab-by-tab layout review                        |
| Focus styling is consistent                      | @implementer | browser evidence covering all three field types |
| Scope stayed frontend-only                       | @analyzer    | diff review confirming no backend/runtime drift |

## Failure Signals

- The redesigned workspace still requires a peer-tab jump to get from writing to testing on desktop.
- The right contextual pane becomes visually equal to or larger than the prompt pane.
- Version history crowds the testing surface or pushes testing below the fold too aggressively.
- Tools or inbox deployment controls leak back into the Instructions split workspace.
- Focus styling cleanup broadens into an unrelated app-wide redesign.
- The plan reintroduces a separate `Test & publish` mental step for desktop users.

## Review Gates

| Gate       | After Phase | Focus Area                                                                           |
| ---------- | ----------- | ------------------------------------------------------------------------------------ |
| **Gate 1** | Phase 1     | Does the IA now support side-by-side writing and testing without duplicate surfaces? |
| **Gate 2** | Phase 2     | Is the split Instructions workspace calm, readable, and SMB-friendly?                |
| **Gate 3** | Phase 3     | Are Tools and Channels still simpler than Instructions rather than equally heavy?    |
| **Gate 4** | Phase 4     | Are focus/error states consistent without unintended design-system regression?       |
| **Gate 5** | Phase 5     | Does the real simulator slot in without another IA rewrite?                          |

## Risk Assessment

| Risk                                                                                                      | Likelihood | Impact | Mitigation                                                                                 |
| --------------------------------------------------------------------------------------------------------- | ---------- | ------ | ------------------------------------------------------------------------------------------ |
| Removing the separate `Test & publish` tab may reduce discoverability for users who expect a release step | MEDIUM     | LOW    | Keep `Test & publish` naming visible as the right-pane heading and in summary/header hints |
| Side-by-side desktop layout could feel cramped on smaller laptops                                         | MEDIUM     | MEDIUM | Use a conservative split ratio and stack below `xl`                                        |
| Version history could crowd the contextual pane                                                           | MEDIUM     | MEDIUM | Collapse older versions or make history secondary beneath test/readiness                   |
| Shared field-atom styling cleanup could affect other surfaces                                             | MEDIUM     | MEDIUM | Use optional variant or tightly bounded shared changes validated by analyzer               |
| Future simulator requirements may exceed current placeholder assumptions                                  | MEDIUM     | MEDIUM | Keep Phase 5 isolated so IA stays stable even if simulator details evolve                  |

## Notes

- YAGNI: do not introduce new routes, new backend concepts, or duplicate simulator surfaces.
- KISS: three top-level task tabs are simpler than four when testing is contextual to authoring.
- DRY: reuse current store data, header actions, summary strip, `TextArea`, and publish/version actions.
- Refactoring UI guidance: use hierarchy through width, spacing, and restraint; do not let support panels fight the primary writing surface.

## Decision Log

| Decision                       | Chosen                                                              | Rejected                                               | Rationale                                                                         | Evidence                                                                                              |
| ------------------------------ | ------------------------------------------------------------------- | ------------------------------------------------------ | --------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Desktop IA model               | `Instructions` split workspace with contextual right pane           | Separate `Instructions` and `Test & publish` peer tabs | Matches latest user preference and removes mental context switch                  | `AiAgentEditPage.vue:47-64`, `AiAgentEditPage.vue:211-261`, `AiAgentWorkspacePublishPanel.vue:28-231` |
| Workspace tabs                 | `Instructions`, `Tools`, `Channels & handoff`                       | Keep four peer tabs                                    | Testing should support authoring, not sit as a separate desktop step              | `AiAgentEditPage.spec.js:332-437`                                                                     |
| Versioning/readiness placement | Supportive right-pane cards under testing                           | Always-visible page rail or separate tab-first step    | Supportive context is useful, but should not dominate the page                    | `AiAgentWorkspacePublishPanel.vue:93-231`                                                             |
| Focus-style cleanup            | Normalize shared field-state language with the smallest safe change | Page-only CSS patching                                 | The inconsistency originates in shared atoms, so local overrides would be brittle | `TextArea.vue:150-163`, `Input.vue:53-60`, `ComboBox.vue:98-110`                                      |
| Backend scope                  | Frontend IA/layout only                                             | Runtime or publish-semantic redesign                   | Current store/actions already provide required data and behavior                  | `AiAgentEditPage.vue:78-138`, `AiAgentEditPage.vue:254-260`                                           |
