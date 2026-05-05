# Chatwoot AI Agents Unified Workspace - Implementation Plan

## 1) Executive summary

Build the next AI Agents iteration as an additive evolution of the current v1 slice, not a greenfield rewrite. The highest-leverage order is: **(1) unify the per-agent workspace, (2) add lightweight draft/live versioning on top of the current live runtime, (3) add an inline simulator that exercises the current draft without customer-facing side effects**.

This stays grounded in the existing codebase:

- AI Agents already exists as a first-class dashboard area, but the setup flow is split across list, create, edit, tools, and inbox-binding pages (`app/javascript/dashboard/routes/dashboard/aiAgents/aiAgents.routes.js:16-54`, `docs/ai-agents-etkin-ux-gap-report.plan.md:7-21`).
- The current edit screen is a single long form inside a settings-style layout (`app/javascript/dashboard/routes/dashboard/aiAgents/pages/AiAgentEditPage.vue:50-97`, `app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentsWorkspaceLayout.vue:24-38`).
- Runtime currently reads the mutable live `AiAgent` row and live `tool_bindings` directly, so safe versioning must be additive and must not replace the current inbound runtime path (`app/services/ai_agents/runtime/runner.rb:6-19`, `:54-95`).

Recommended strategy: **ship the unified workspace first, then layer draft/live publish semantics and the simulator into that workspace**.

---

## 2) Goals / non-goals

### Goals

- Keep **AI Agents** as the first-class workspace.
- Replace the fragmented agent-detail flow with one operational workspace per agent.
- Introduce an SMB-friendly **draft/live** mental model with publish and simple history.
- Add an inline **simulator** that is clearly test-only and non-customer-facing.
- Preserve current runtime/binding/tool flows and fail-open handoff behavior.
- Include targeted tests and `agent-browser` verification after every phase.

### Non-goals

- Knowledge base / RAG.
- Advanced version trees, branching, rollback graphs, approvals, or arbitrary diff tools.
- Full observability/run-history dashboards.
- Captain / Enterprise feature work.
- Provider expansion, multi-step tool loops, or speculative “AI platform” abstractions.

---

## 3) Verified facts vs assumptions

### Verified facts

1. **Current UX is fragmented.** The AI Agents route tree exposes separate list, new, tools, edit, and inbox-binding pages (`app/javascript/dashboard/routes/dashboard/aiAgents/aiAgents.routes.js:16-54`).
2. **Current agent detail is just the edit page.** `AiAgentEditPage.vue` renders `AiAgentForm` and links out to a separate inbox-binding page (`app/javascript/dashboard/routes/dashboard/aiAgents/pages/AiAgentEditPage.vue:50-97`).
3. **Current workspace shell is settings-derived.** `AiAgentsWorkspaceLayout.vue` wraps `SettingsLayout` rather than a richer agent-detail workspace shell (`app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentsWorkspaceLayout.vue:1-39`).
4. **Inbox binding is already implemented and conflict-aware.** `AiAgents::InboxBindingService` prevents binding when another responder is already attached (`app/services/ai_agents/inbox_binding_service.rb:19-31`, `:53-73`).
5. **Runtime is live-row based today.** `AiAgents::Runtime::Runner` reads `run.ai_agent`, current conversation history, and current `tool_bindings` directly (`app/services/ai_agents/runtime/runner.rb:25-55`).
6. **Tool-binding writes are destructive replace-all.** `AiAgents::ToolBindingSyncService` destroys all bindings before recreating them (`app/services/ai_agents/tool_binding_sync_service.rb:7-13`).
7. **No versioning or simulator exists yet.** Current agent JSON exposes `knowledge_base: false` and `run_history: false`, and there is no current simulator/version history UI (`app/views/api/v1/models/_ai_agent.json.jbuilder:16-21`; repo investigation on AI Agents UI/backend found no existing simulator/version flows).
8. **The product/UX source of truth explicitly recommends unified workspace first, then lightweight versioning, then inline simulator** (`docs/ai-agents-etkin-ux-gap-report.plan.md:33-40`, `:460-518`, `:557-598`).
9. **Direct Enterprise overlays for OSS AI Agents were not found.** A lightweight overlay check is still warranted because overlay wiring is global (`config/initializers/01_inject_enterprise_edition_module.rb:24-40`).

### Assumptions

1. The current AI Agents v1 slice (phases 1-8) is merged and remains the baseline for this next iteration.
2. Admin test accounts with AI Agents enabled are available for browser verification.
3. This iteration does **not** need multi-user draft conflict resolution; last-write-wins on draft edits is acceptable.
4. Existing external consumers of `PATCH /ai_agents/:id` are limited enough that additive draft/version endpoints are safer than redefining the current live-update contract immediately.

If assumption 3 or 4 proves false during implementation, stop and re-plan before wiring publish behavior into the current UI.

---

## 4) Current state (evidence)

- Product source recommends one unified agent workspace with right-rail simulator/versioning, draft/live snapshots, and inline inbox deployment (`docs/ai-agents-etkin-ux-gap-report.plan.md:287-340`, `:344-411`).
- Current list page shows name/provider/status/readiness, but its CTAs are still separate Edit and Inboxes actions (`app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentsTable.vue:19-100`).
- Current edit form mixes business-facing and technical fields in one long form (`app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentForm.vue:172-315`).
- Current inbox binding already has a reusable card-style manager and availability logic worth reusing inside the new workspace (`app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentInboxBindingsManager.vue:31-179`).
- Current runtime and response job already preserve the core operational invariants we must not break: pending-only handling, inbox-bound agent resolution, stale-run skipping, and `Conversation#bot_handoff!` fail-open behavior (`app/services/ai_agents/inbound_router.rb:23-31`, `app/jobs/ai_agents/response_job.rb:13-23`, `:55-82`, `app/services/ai_agents/runtime/runner.rb:137-160`).

---

## 5) UX architecture for unified workspace

## Recommended IA

- Keep top-level navigation as:
  - **AI Agents**
    - **Agents**
    - **Tools**
- Add a **canonical per-agent workspace route**.
- Do **not** add top-level Simulator or Versions navigation.
- Retire standalone inbox binding as the primary path once inline deployment is stable.

## Recommended per-agent workspace structure

### Header

- Agent name
- Status badge: `Draft`, `Live`, `Disabled`, `Needs setup`
- Assigned inbox count
- Primary actions by state:
  - `Save draft`
  - `Publish changes`
  - `Disable` / `Enable`

### Main column

1. **Overview**
   - Description / purpose
   - Readiness checklist
   - Live inbox summary
2. **Behavior**
   - Prompt/instructions
   - Handoff prompt
   - Handoff message
   - Advanced provider/model/endpoint controls collapsed by default
3. **Tools**
   - Selected tools inline
   - Add/remove tools in context
   - Link out to full Tools workspace for CRUD
4. **Deployment**
   - Inline inbox assignment
   - Conflict warnings from existing responder rules
   - Human handoff explanation

### Right rail

1. **Simulator panel**
2. **Version panel**
3. **Readiness / publishing notes**

## Routing recommendation

- Add canonical route: `/app/accounts/:accountId/ai-agents/:id`
- Keep `/app/accounts/:accountId/ai-agents/:id/edit` as a temporary redirect or alias during migration.
- Keep `/app/accounts/:accountId/ai-agents/:id/inboxes` only as a temporary fallback until inline deployment is proven stable; remove it from primary navigation.

## Why this is the simplest viable shape

- It reuses the existing AI Agents route tree and workspace context.
- It keeps tool CRUD centralized instead of duplicating a cross-agent tool surface.
- It moves the real activation step (inbox assignment) next to the agent, matching Chatwoot’s inbox-first deployment model.
- It creates the exact landing surface needed for draft/live publish and inline simulator without inventing a separate control center.

---

## 6) Data/API implications for versioning and simulator

## Primary approach

Keep the current `AiAgent` + `AiAgentToolBinding` tables as the **live runtime source of truth** and add a new additive draft/version layer.

### Recommended versioning model

Introduce a single new persisted concept for additive safety:

- **`AiAgentVersion`** (recommended name)
  - one mutable `draft` row per `AiAgent`
  - many immutable `published` rows per `AiAgent`
  - stores the full non-customer-facing configuration snapshot needed for publish/restore

Recommended stored state:

- prompt fields
- provider/model/endpoint
- enabled state
- tool binding snapshot
- inbox assignment snapshot
- config JSON
- secret-presence metadata at minimum; encrypted draft secrets if exact publish parity is required
- published metadata (`version_number`, `published_at`, `published_by_id`, optional `note`)

### Publish semantics

- Editing updates the mutable **draft** only.
- Publishing copies draft state into live `AiAgent` + `AiAgentToolBinding` + inbox bindings.
- Publishing also writes an immutable `published` snapshot row.
- Restore copies a selected published snapshot back into the mutable draft.

### Why this is safer than mutating live rows directly

- The current runtime reads the live `AiAgent` row directly (`app/services/ai_agents/runtime/runner.rb:25-55`).
- Tool binding sync is destructive replace-all (`app/services/ai_agents/tool_binding_sync_service.rb:7-13`).
- Inbox binding is live operational state with responder exclusivity checks (`app/services/ai_agents/inbox_binding_service.rb:19-31`, `:53-73`).

This means draft editing must stay outside the live runtime path until publish.

## Recommended API additions

Keep current CRUD endpoints intact for compatibility during migration, and add additive nested endpoints for the new flow:

- `GET /api/v1/accounts/:account_id/ai_agents/:id` → enrich response with workspace summary and draft/live metadata
- `GET /api/v1/accounts/:account_id/ai_agents/:id/versions` → simple version list + draft/live summary
- `PATCH /api/v1/accounts/:account_id/ai_agents/:id/draft` → update mutable draft only
- `POST /api/v1/accounts/:account_id/ai_agents/:id/publish` → publish draft to live
- `POST /api/v1/accounts/:account_id/ai_agents/:id/versions/:version_id/restore` → restore published snapshot to draft
- `POST /api/v1/accounts/:account_id/ai_agents/:id/simulate` → simulate current draft without posting a real message

## Simulator service recommendation

Add a side-effect-free simulation service that reuses runtime preparation logic where safe, but **does not**:

- create customer-facing messages
- change conversation state
- call `bot_handoff!`
- enqueue background work

Preferred direction:

- extract reusable provider/message/tool-building helpers from the current runtime path
- keep `AiAgents::Runtime::Runner` as the live-message path
- create a dedicated `AiAgents::Simulator::Runner` or `AiAgents::Simulation::Runner` for the draft path

## Alternative rejected

- **Rejected:** make runtime read directly from version snapshots.
- **Why rejected:** it would increase blast radius across `InboundRouter`, `ResponseJob`, and `Runtime::Runner` for little user-facing gain in this iteration.

---

## 7) Phase-by-phase implementation plan

## Phase 1: Workspace summary read model

**Owner**: @implementer (backend/api)
**Dependencies**: None
**Complexity**: LOW

### Tasks

- [ ] Add additive workspace summary fields to the AI agent show/list payload: inbox names, selected tool summary, readiness flags, and placeholder draft/live status metadata.
- [ ] Keep existing secret-masking behavior unchanged.
- [ ] Add request-spec coverage for new payload fields and unchanged auth/secret behavior.
- [ ] Verify affected request specs pass locally.

### Exact likely file areas

- `app/views/api/v1/models/_ai_agent.json.jbuilder`
- `app/controllers/api/v1/accounts/ai_agents_controller.rb`
- `spec/controllers/api/v1/accounts/ai_agents_controller_spec.rb`

### Acceptance criteria

- [ ] Workspace payload answers “what does this agent do, where is it live, and is it ready?” without another API round trip.
- [ ] Decrypted secrets are still never returned.
- [ ] Admin-only access stays unchanged.

### Regression checks

- `GET /ai_agents` still works for current list UI.
- Current edit page can still render from enriched payload without breakage.

### Browser verification

- Open AI Agents index and verify current list still renders.
- Open one agent detail route and confirm no broken loading/error state before UI redesign lands.

### Stop conditions

- Stop if payload work starts redefining draft/live write behavior.
- Stop if new fields require changing runtime or inbox-binding semantics.

---

## Phase 2: Unified workspace shell and route migration

**Owner**: @implementer (frontend/routing)
**Dependencies**: Phase 1
**Complexity**: MEDIUM

### Tasks

- [ ] Introduce a canonical agent workspace route (`:id`) while preserving temporary compatibility for `:id/edit`.
- [ ] Replace the settings-style body composition with a dedicated two-column agent workspace shell.
- [ ] Move “manage inboxes” out of header CTA and reserve right rail slots for versioning/simulator placeholders.
- [ ] Add/adjust route-level frontend tests for the new canonical route.
- [ ] Verify the route tree and load states pass in UI tests.

### Exact likely file areas

- `app/javascript/dashboard/routes/dashboard/aiAgents/aiAgents.routes.js`
- `app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentsWorkspaceLayout.vue`
- `app/javascript/dashboard/routes/dashboard/aiAgents/pages/AiAgentEditPage.vue` (or replacement detail page)

### Acceptance criteria

- [ ] Every agent has one primary “workspace” route.
- [ ] Workspace layout supports main-column + right-rail composition.
- [ ] Legacy edit URL still resolves safely during migration.

### Regression checks

- AI Agents index and Tools tab still load.
- Feature gating and admin-only access remain unchanged.

### Browser verification

- Use `agent-browser` to open `/app/accounts/:accountId/ai-agents/:id`.
- Confirm snapshot shows one workspace page, not a form-only page plus separate inbox CTA.
- Confirm navigating from list row CTA lands in workspace.

### Stop conditions

- Stop if route migration requires sidebar or feature-flag rewrites outside AI Agents.
- Stop if layout refactor starts pulling Tools CRUD into the detail route.

---

## Phase 3: Inline overview, behavior, tools, and deployment sections

**Owner**: @implementer (frontend/workspace)
**Dependencies**: Phase 2
**Complexity**: MEDIUM

### Tasks

- [ ] Split the current long form into workspace sections: Overview, Behavior, Tools, Deployment.
- [ ] Reuse existing inbox-binding behavior inline rather than maintaining the separate bindings page as the primary surface.
- [ ] Reuse current tool-selection patterns but keep full tool CRUD in the Tools tab.
- [ ] Add readiness checklist copy that is business-first, not provider-first.
- [ ] Update frontend specs for section rendering and inline deployment/tool interactions.
- [ ] Verify section-level UI tests pass.

### Exact likely file areas

- `app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentForm.vue`
- `app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentInboxBindingsManager.vue`
- `app/javascript/dashboard/i18n/locale/en/aiAgents.json`

### Acceptance criteria

- [ ] Inbox assignment is manageable inside the agent workspace.
- [ ] Tool selection is visible in context with a clear deep link to Tools.
- [ ] Advanced provider/model fields are demoted behind progressive disclosure.

### Regression checks

- Existing responder-conflict behavior still comes from `AiAgents::InboxBindingService`.
- Tools tab still owns full custom-tool CRUD.

### Browser verification

- Bind and unbind an eligible inbox from the workspace.
- Confirm a conflicting inbox still shows as unavailable or warned.
- Add/remove a tool in the workspace and confirm the selection summary updates.

### Stop conditions

- Stop if inline deployment requires duplicating inbox-binding rules in frontend-only logic.
- Stop if the plan starts removing the Tools tab or the centralized custom tools manager.

---

## Phase 4: Lightweight versioning backend

**Owner**: @implementer (backend/domain)
**Dependencies**: Phase 3
**Complexity**: HIGH

### Tasks

- [ ] Add an additive draft/version persistence model for AI agent configuration.
- [ ] Seed/initialize a draft snapshot for existing agents.
- [ ] Add publish and restore services that copy snapshot state into live `AiAgent`, live tool bindings, and live inbox bindings.
- [ ] Add simple version-list endpoints and draft-update endpoints.
- [ ] Add request/service/model specs covering publish, restore, and unchanged runtime behavior.
- [ ] Verify backend specs pass locally.

### Exact likely file areas

- `db/migrate/*create_ai_agent_versions*.rb`
- `app/models/ai_agent_version.rb` (new)
- `app/services/ai_agents/` (new publish/restore/draft services)

### Acceptance criteria

- [ ] One mutable draft exists per agent.
- [ ] Publish updates live runtime state only at publish time.
- [ ] Version list is simple: version number, published by, published at, optional note.
- [ ] Restore writes back to draft, not directly to live.

### Regression checks

- `AiAgents::InboundRouter`, `AiAgents::ResponseJob`, and `AiAgents::Runtime::Runner` stay unchanged in behavior for live traffic.
- Existing inbox binding exclusivity still applies at publish time.
- Existing live runtime still posts replies and fail-opens to `bot_handoff!` exactly as before.

### Browser verification

- Not primary in this backend phase; use API- and spec-driven verification, then smoke-check that current workspace still loads live agent data.

### Stop conditions

- Stop if draft/live support requires runtime to read snapshots directly.
- Stop if publish cannot remain additive and starts rewriting message-routing behavior.

---

## Phase 5: Versioning UI and draft/live workspace wiring

**Owner**: @implementer (frontend/state)
**Dependencies**: Phase 4
**Complexity**: HIGH

### Tasks

- [ ] Add draft-aware store/API methods for load draft, save draft, publish, restore, and fetch simple history.
- [ ] Wire the workspace header to draft/live status and publish actions.
- [ ] Add a compact right-rail version panel.
- [ ] Update list/index badges and primary CTA to reflect Draft/Live/Disabled/Needs setup.
- [ ] Add frontend specs for draft save, publish CTA states, and restore flow.
- [ ] Verify affected frontend tests pass.

### Exact likely file areas

- `app/javascript/dashboard/store/modules/aiAgents.js`
- `app/javascript/dashboard/api/aiAgents.js`
- `app/javascript/dashboard/routes/dashboard/aiAgents/components/` (workspace header/right-rail version panel)

### Acceptance criteria

- [ ] Editing in the workspace no longer changes live behavior immediately.
- [ ] Users can see whether they are editing draft vs viewing live state.
- [ ] Publish and restore are discoverable without exposing advanced release-management concepts.

### Regression checks

- Existing list and detail pages still load if history/version metadata is absent for older records during rollout.
- Secrets remain masked in all draft/live responses.

### Browser verification

- Edit an agent, save draft, reload, and verify live status remains unchanged until publish.
- Publish changes and verify badge / history row update.
- Restore an older version to draft and confirm workspace fields repopulate without going live automatically.

### Stop conditions

- Stop if UI state management starts requiring a second full AI Agents store tree.
- Stop if version UX grows past draft/live + simple history.

---

## Phase 6: Inline simulator backend

**Owner**: @implementer (backend/runtime)
**Dependencies**: Phase 5
**Complexity**: MEDIUM

### Tasks

- [ ] Extract safe reusable runtime preparation helpers where justified.
- [ ] Add a side-effect-free simulator service that evaluates the current draft configuration.
- [ ] Add a simulate endpoint returning reply text, tool indicator, and handoff indicator.
- [ ] Add service/request specs covering non-side-effect guarantees.
- [ ] Verify backend specs pass locally.

### Exact likely file areas

- `app/services/ai_agents/runtime/runner.rb` (only if shared extraction is minimal)
- `app/services/ai_agents/simulator/` (new)
- `spec/services/ai_agents/` + request spec for simulate endpoint

### Acceptance criteria

- [ ] Simulation never creates a customer-visible message.
- [ ] Simulation never changes conversation status.
- [ ] Simulation response is sufficient for the right-rail UI: reply preview, tool indicator, handoff indicator, error state.

### Regression checks

- Live runtime specs continue passing unchanged.
- No background job enqueue path is added for simulation.

### Browser verification

- Not full UI yet; confirm endpoint contract via backend tests and optional manual API smoke test.

### Stop conditions

- Stop if simulator implementation starts forking large chunks of runtime logic with no shared extraction boundary.
- Stop if simulator starts depending on real conversation mutation.

---

## Phase 7: Inline simulator UI and final workspace polish

**Owner**: @implementer (frontend/ux)
**Dependencies**: Phase 6
**Complexity**: MEDIUM

### Tasks

- [ ] Add the right-rail simulator UI using conversation-like test bubbles.
- [ ] Label the panel clearly as test-only / non-customer-facing.
- [ ] Show reply preview, tool-used indicator, handoff indicator, and basic error feedback.
- [ ] Add final list/index polish for stronger workspace CTA and status visibility.
- [ ] Add frontend specs for simulator state handling.
- [ ] Verify browser checks and affected frontend tests pass.

### Exact likely file areas

- `app/javascript/dashboard/routes/dashboard/aiAgents/pages/AiAgentEditPage.vue` (or workspace page)
- `app/javascript/dashboard/routes/dashboard/aiAgents/components/` (new simulator panel)
- `app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentsTable.vue`

### Acceptance criteria

- [ ] Admin can try a sample customer message without leaving the agent workspace.
- [ ] Simulator clearly communicates that it is not a real customer conversation.
- [ ] List/index now emphasizes “open workspace” and live/deployment visibility.

### Regression checks

- Workspace remains usable without simulator interaction.
- Tools and deployment sections still work after right-rail integration.

### Browser verification

- Enter a sample customer message and confirm the simulator returns a visible preview.
- Confirm tool/handoff badges render when applicable.
- Confirm no real conversation or inbox state changes occur from simulation.

### Stop conditions

- Stop if simulator UI starts turning into a saved transcript/history product.
- Stop if list/index work grows into a separate analytics dashboard.

---

## 8) Exact likely file areas per phase

| Phase | Likely file areas                                                                                                                                                             |
| ----- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1     | `app/views/api/v1/models/_ai_agent.json.jbuilder`, `app/controllers/api/v1/accounts/ai_agents_controller.rb`, `spec/controllers/api/v1/accounts/ai_agents_controller_spec.rb` |
| 2     | `app/javascript/dashboard/routes/dashboard/aiAgents/aiAgents.routes.js`, `.../components/AiAgentsWorkspaceLayout.vue`, `.../pages/AiAgentEditPage.vue`                        |
| 3     | `.../components/AiAgentForm.vue`, `.../components/AiAgentInboxBindingsManager.vue`, `app/javascript/dashboard/i18n/locale/en/aiAgents.json`                                   |
| 4     | `db/migrate/*create_ai_agent_versions*.rb`, `app/models/ai_agent_version.rb`, `app/services/ai_agents/*`                                                                      |
| 5     | `app/javascript/dashboard/store/modules/aiAgents.js`, `app/javascript/dashboard/api/aiAgents.js`, `.../components/*Version*.vue`                                              |
| 6     | `app/services/ai_agents/runtime/runner.rb`, `app/services/ai_agents/simulator/*`, `spec/services/ai_agents/*`                                                                 |
| 7     | `.../components/*Simulator*.vue`, `.../pages/AiAgentEditPage.vue`, `.../components/AiAgentsTable.vue`                                                                         |

---

## 9) Test and browser verification matrix per phase

| Phase | Targeted tests                                                                                  | Browser verification (`agent-browser`)                                                       | Proves                                                       |
| ----- | ----------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| 1     | `bundle exec rspec spec/controllers/api/v1/accounts/ai_agents_controller_spec.rb`               | Open index + one existing detail route; verify no render regressions                         | Enriched payload is additive and UI-safe                     |
| 2     | Existing route/component AI Agents frontend specs + `pnpm test` for affected UI files           | Open canonical workspace route, confirm one-page workspace layout and route migration        | Workspace shell works and legacy route still resolves        |
| 3     | Affected AI Agents frontend specs + `pnpm test`; inbox binding request/service specs if touched | Bind/unbind inbox inline; confirm conflict visibility; add/remove tool selection             | Unified workspace replaces fragmented deployment/setup flow  |
| 4     | New model/service/request specs for versions + `bundle exec rspec` on affected AI Agents specs  | Smoke-check workspace still loads; no primary UI workflow required yet                       | Draft/live backend is additive and runtime-safe              |
| 5     | Draft/publish/restore UI specs + `pnpm test`; affected request specs                            | Save draft, reload, publish, restore older version to draft                                  | Draft/live workflow is understandable and not immediate-live |
| 6     | New simulator service/request specs + existing runtime specs                                    | Optional manual API smoke only                                                               | Simulator path is side-effect-free                           |
| 7     | Simulator UI specs + `pnpm test`; selective backend specs still green                           | Run sample test message, verify preview/tool/handoff signals and no customer-visible effects | Inline simulator is safe, useful, and clearly test-only      |

### Browser baseline for all UI phases

Use the repo-standard local runtime flow from the loaded runbook, then verify with `agent-browser`:

1. Start local app stack with the existing Chatwoot dev flow.
2. Open `/app/accounts/:accountId/ai-agents`.
3. Run `agent-browser snapshot -i` before every interaction.
4. Re-snapshot after every route change, publish action, modal open, or simulated response.
5. Capture at least one screenshot at the end of each UI phase for visual regression comparison.

---

## 10) Blast radius / affected entry points

- `app/javascript/dashboard/routes/dashboard/aiAgents/**` - primary UX surface for the new workspace.
- `app/javascript/dashboard/store/modules/aiAgents.js` - state contract will expand from simple CRUD into draft/live actions.
- `app/views/api/v1/models/_ai_agent.json.jbuilder` - serialized contract for list/detail pages.
- `app/controllers/api/v1/accounts/ai_agents_controller.rb` and new nested endpoints - admin API contract for draft/publish/simulate.
- `app/services/ai_agents/inbox_binding_service.rb` - publish and inline deployment must keep this as the source of truth for live inbox exclusivity.
- `app/services/ai_agents/runtime/runner.rb`, `app/jobs/ai_agents/response_job.rb`, `app/services/ai_agents/inbound_router.rb` - must remain behaviorally unchanged for live traffic.
- `config/routes.rb` - additive route surface for versions/simulate.
- Overlay check only: `config/initializers/01_inject_enterprise_edition_module.rb` and any adjacent Captain custom tool surfaces, even though Enterprise work is out of scope.

---

## 11) Allowed scope / forbidden scope

### Allowed scope

- AI Agents workspace routes, pages, components, i18n, store, and API clients.
- Additive AI agent draft/version/simulator backend support.
- Additive serializer/controller/service/model work required by those three features.
- Targeted tests and browser validation for those paths.

### Forbidden scope

- Changing the live inbound runtime contract beyond minimal helper extraction.
- Knowledge base or retrieval features.
- Multi-version trees, approvals, branch management, or observability dashboards.
- Enterprise/Captain feature implementation.
- Replacing the centralized Tools workspace with per-agent tool CRUD.

---

## 12) Invariants / unchanged behavior

| Invariant                                                                  | Why it matters                                              | How to verify                                            |
| -------------------------------------------------------------------------- | ----------------------------------------------------------- | -------------------------------------------------------- |
| Live customer traffic still resolves the live `AiAgent` bound to the inbox | Prevents draft edits from affecting production unexpectedly | Existing runtime specs + publish-only live changes       |
| `Conversation#bot_handoff!` remains the only human handoff primitive       | Preserves Chatwoot-native safety valve                      | Existing runtime spec + simulator non-side-effect checks |
| Inbox responder exclusivity still comes from backend binding rules         | Prevents UI-only divergence and invalid deployment states   | Inbox binding specs + browser conflict check             |
| Secrets are never echoed in API responses                                  | Prevents admin secret leakage                               | Existing AI agents controller specs                      |
| Tools remain centralized in the Tools workspace for CRUD                   | Avoids duplicate tool-management systems                    | Browser check + unchanged Tools page                     |

## Behavior that must not change

- Existing pending-conversation runtime behavior for live inbox-bound AI agents.
- Existing stale-run skip behavior in `AiAgents::Runtime::Runner`.
- Existing admin-only visibility and feature-flag gating for AI Agents.
- Existing separate Tools workspace functionality.

---

## 13) Risks and rollback notes

| Risk                                           | Likelihood | Impact | Mitigation                                                                         | Rollback                                                                   |
| ---------------------------------------------- | ---------- | ------ | ---------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| Draft/live model leaks into live runtime path  | MEDIUM     | HIGH   | Keep live runtime tables unchanged; publish copies draft to live                   | Revert versioning routes/services; keep current live CRUD                  |
| Workspace becomes visually dense               | MEDIUM     | MEDIUM | Use section cards, collapsed advanced settings, right-rail secondary panels        | Revert to current form sections while keeping route shell                  |
| Simulator implies guaranteed production output | MEDIUM     | MEDIUM | Strong “test mode” labeling and no analytics overclaim                             | Hide simulator panel behind feature flag while keeping backend endpoint    |
| Publish flow breaks inbox bindings             | LOW        | HIGH   | Reuse `AiAgents::InboxBindingService` during publish; add binding regression specs | Disable publish endpoint and keep draft-only edits out of UI               |
| Versioning adds too much SMB complexity        | LOW        | MEDIUM | Limit UI to draft/live + simple history list                                       | Remove restore/history UI; keep publish only                               |
| Hidden overlay interaction appears late        | LOW        | MEDIUM | Add explicit overlay check gate before backend merge                               | Revert additive routes/services if overlay contract unexpectedly conflicts |

---

## 14) Failure signals

- Draft edits change live customer-facing behavior before publish.
- Publish requires modifying `InboundRouter`, `ResponseJob`, or runtime applicability checks.
- Inline deployment duplicates responder-conflict rules in frontend-only code.
- Simulator creates messages, changes conversation status, or enqueues jobs.
- Version UI starts requiring branch/diff/review concepts beyond draft/live.

---

## 15) Review gates

| Gate   | After phase | Focus area                                                                       |
| ------ | ----------- | -------------------------------------------------------------------------------- |
| Gate 1 | Phase 1     | Payload remains additive; secrets/auth unchanged                                 |
| Gate 2 | Phase 3     | Unified workspace reduces route fragmentation without duplicating business rules |
| Gate 3 | Phase 4     | Draft/live backend is additive and runtime-safe                                  |
| Gate 4 | Phase 5     | Draft/publish UX is SMB-friendly and not over-complex                            |
| Gate 5 | Phase 7     | Simulator is clearly test-only and side-effect-free                              |

---

## 16) Evidence owners

| Item                                    | Owner                    | Proof required                                       |
| --------------------------------------- | ------------------------ | ---------------------------------------------------- |
| Live runtime invariants preserved       | @implementer / @analyzer | Existing AI runtime specs still pass                 |
| Workspace consolidation works           | @implementer             | Browser walkthrough + affected frontend tests        |
| Draft edits stay non-live until publish | @implementer / @analyzer | Publish/restore request specs + browser verification |
| Simulator causes no side effects        | @implementer / @analyzer | Simulator service/request specs + browser smoke      |
| Overlay blast radius remains contained  | @implementer             | Explicit search/review note before merge             |

---

## 17) Definition of done for this iteration

- [ ] AI Agents has a canonical unified per-agent workspace.
- [ ] Inbox deployment and tool selection are manageable inside that workspace.
- [ ] Draft/live versioning exists with save draft, publish, and simple history/restore.
- [ ] Inline simulator works from the same page against the current draft.
- [ ] Existing live runtime, handoff, binding exclusivity, and tool flows remain unchanged.
- [ ] Every phase has targeted tests and browser verification evidence.
- [ ] No scope-out items were pulled in.

---

## 18) Recommended first phase to execute next

**Start with Phase 1: Workspace summary read model.**

Why this first:

- It is the smallest additive backend change.
- It supports the unified workspace without forcing draft/live decisions immediately.
- It gives the next frontend phase better data for overview/readiness cards.
- It has the lowest runtime risk and the clearest rollback path.

If implementation capacity allows one larger vertical slice immediately after, follow with **Phase 2 + Phase 3** as the first reviewable UX milestone.

---

## 19) Decision log

| Decision                  | Chosen                                            | Rejected                                 | Rationale                                                                                        | Evidence                                                                                                                                                     |
| ------------------------- | ------------------------------------------------- | ---------------------------------------- | ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| First capability to build | Unified workspace first                           | Simulator or versioning first            | Source-of-truth doc explicitly positions workspace as the foundation for both later capabilities | `docs/ai-agents-etkin-ux-gap-report.plan.md:559-570`                                                                                                         |
| Runtime source of truth   | Keep live `AiAgent` runtime unchanged             | Read runtime directly from snapshots     | Smallest blast radius; current runtime is already working and approved                           | `app/services/ai_agents/runtime/runner.rb:6-19`, `:54-95`                                                                                                    |
| Deployment location       | Inline in agent workspace                         | Keep separate inbox page as primary flow | Inbox binding is the real activation step and already reusable                                   | `docs/ai-agents-etkin-ux-gap-report.plan.md:322-340`, `app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentInboxBindingsManager.vue:99-179` |
| Tool management strategy  | Inline selection + separate Tools CRUD tab        | Full per-agent tool CRUD                 | Avoid duplicate systems; matches current AI Agents structure                                     | `docs/ai-agents-etkin-ux-gap-report.plan.md:333-340`, `app/javascript/dashboard/routes/dashboard/aiAgents/pages/AiAgentsToolsPage.vue:8-27`                  |
| Versioning scope          | Draft/live + simple history                       | Branches/diffs/approvals                 | Matches SMB-friendly scope and avoids enterprise release-management complexity                   | `docs/ai-agents-etkin-ux-gap-report.plan.md:344-380`                                                                                                         |
| Simulator scope           | Inline preview with reply/tool/handoff indicators | Full trace lab/history analytics         | Delivers confidence with minimal complexity                                                      | `docs/ai-agents-etkin-ux-gap-report.plan.md:384-411`                                                                                                         |

---

## 20) Skill update recommendation

No skill update is recommended at planning time.

Reason:

- The loaded skills used here (`ai-native-workflow`, `agent-browser`, `chatwoot-dev-runbook`, `skill-maintainer`) still match current repository and verification workflows.
- This plan does not reveal stale skill instructions that would mislead the next implementer.
