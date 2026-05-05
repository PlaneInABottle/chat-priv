# AI Agents Inline Simulator (OpenRouter Local Dev) - Implementation Plan

## Problem Statement

The approved AI Agent workspace now has the right structural foundation for inline testing: a dominant left authoring/testing area and a stable right-side support pane for readiness and versioning. The missing piece is a real simulator that can test the **current draft** safely, without creating messages, changing conversations, reintroducing Captain/Copilot configuration paths, or requiring provider secrets to be stored in persisted agent records for local development.

## Approach

Build a **draft-only, side-effect-free simulator endpoint and inline chat pane** that reuses the existing OSS AI Agent provider abstraction where safe, keeps versioning/readiness in the current right-side support column, and uses `.env.local` only for **local simulator transport config** via OpenRouter.

## Success Criteria

- [ ] A real large inline simulator/chat pane replaces the current placeholder in the approved side-by-side workspace.
- [ ] The simulator runs against the **current draft state**, not live published state.
- [ ] Local development can use OpenRouter strictly through `.env.local`, without InstallationConfig or Captain config.
- [ ] Simulator requests never create customer-visible messages, enqueue response jobs, or perform real handoff mutations.
- [ ] Tool usage and handoff intent are visible in the simulator UI as preview signals.
- [ ] End-to-end verification is possible with `agent-browser` from the real workspace UI.

## Executive summary

### Recommendation

Implement the simulator as a **new OSS-only simulation path**, not by reusing the live `AiAgents::Runtime::Runner` directly.

Why:

- the live runner posts messages and calls `conversation.bot_handoff!`: `app/services/ai_agents/runtime/runner.rb:109-143`
- custom tool execution performs real outbound HTTP: `app/services/ai_agents/tools/executor.rb:34-67`
- current workspace/store already support draft, publish, versions, and restore, but **no simulate endpoint exists yet**: `config/routes.rb:90-97`, `app/javascript/dashboard/api/aiAgents.js:9-23`

### Safest OpenRouter model string

Use:

- **`openai/codex-mini`**

Reason:

- OpenRouter’s model page is explicitly published at `openai/codex-mini`.
- The user phrase “codex 5.1 mini” is ambiguous, but `openai/codex-mini` is an observed exact OpenRouter identifier.
- Avoid planning around `codex-mini-latest` because it behaves like a moving alias; the fixed provider/model identifier is safer for a local implementation plan.

### Current state (evidence)

- The canonical agent workspace route already exists at `:id`, with `:id/edit` redirecting back to it: `app/javascript/dashboard/routes/dashboard/aiAgents/aiAgents.routes.js:39-53`.
- The current page already has a left authoring pane and a right support pane in Instructions mode: `app/javascript/dashboard/routes/dashboard/aiAgents/pages/AiAgentEditPage.vue:211-258`.
- The current support pane component already has the approved side-by-side layout primitive built in: `app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentWorkspacePublishPanel.vue:31-38`.
- The left side of that component is still only a simulator placeholder: `AiAgentWorkspacePublishPanel.vue:40-109`.
- The right side already renders readiness and version history with restore: `AiAgentWorkspacePublishPanel.vue:111-250`.
- The backend already exposes draft/publish/version restore actions and payloads: `app/controllers/api/v1/accounts/ai_agents_controller.rb:26-50`, `app/views/api/v1/models/_ai_agent.json.jbuilder:70-114`.
- The current provider abstraction already supports OpenAI-compatible endpoints via `OpenAI::Client.new(uri_base: ...)`: `app/services/ai_agents/providers/openai_compatible_service.rb:16-23`.
- Rails already loads `.env.local` through dotenv: `config/application.rb:12-15`; `dotenv-rails` is present in the Gemfile: `Gemfile:74`.

---

## Env/config plan

## Recommended local env strategy

Use **simulator-specific OSS env vars** in `.env.local`, not Captain/InstallationConfig values.

### `.env.local` keys to add

```bash
AI_AGENTS_SIMULATOR_PROVIDER=openai_compatible
AI_AGENTS_SIMULATOR_MODEL=openai/codex-mini
AI_AGENTS_SIMULATOR_ENDPOINT=https://openrouter.ai/api/v1
AI_AGENTS_SIMULATOR_API_KEY=<user-provided-openrouter-key>
AI_AGENTS_SIMULATOR_TIMEOUT_SECONDS=20
```

### Why these exact values

- `AI_AGENTS_SIMULATOR_PROVIDER=openai_compatible`
  - matches the current OSS AI Agents provider list: `app/javascript/dashboard/routes/dashboard/aiAgents/constants.js:1-4`
- `AI_AGENTS_SIMULATOR_MODEL=openai/codex-mini`
  - safest exact OpenRouter identifier observed from the model page
- `AI_AGENTS_SIMULATOR_ENDPOINT=https://openrouter.ai/api/v1`
  - correct for the OSS AI Agents path because `OpenAI::Client` receives `uri_base` directly in `AiAgents::Providers::OpenaiCompatibleService`: `app/services/ai_agents/providers/openai_compatible_service.rb:17-20`, `:51-57`
  - **do not** use the Captain initializer path here; `config/initializers/ai_agents.rb:16-18` appends `/v1`, which is the wrong integration seam for this feature
- `AI_AGENTS_SIMULATOR_API_KEY`
  - keeps the secret in `.env.local`, server-side only, and out of persisted agent drafts

### Precedence rules

For the simulator only:

1. Draft content remains primary for:
   - prompt template
   - handoff prompt/message
   - enabled flag
   - tool snapshot
2. Local env remains primary for **transport config in development**:
   - provider
   - model
   - endpoint
   - api key

This keeps the simulator local-dev/config driven without forcing the user to paste local secrets into the draft form.

### Explicit non-goals

- Do **not** write these env values into `InstallationConfig`
- Do **not** reuse `CAPTAIN_OPEN_AI_*`
- Do **not** auto-persist the OpenRouter secret into `AiAgentVersion` or `AiAgent`
- Do **not** expose the API key to the frontend

---

## Architecture choice and rationale

## Chosen architecture

Create a **simulation-specific endpoint and service path**:

- `POST /api/v1/accounts/:account_id/ai_agents/:id/simulate`
- controller action on the existing OSS `AiAgentsController`
- new service, e.g. `AiAgents::SimulationService`
- new draft-backed config adapter / PORO if needed
- frontend API/store action for `simulate`
- new large left-pane simulator UI inside `AiAgentWorkspacePublishPanel`

## Why not reuse `AiAgents::Runtime::Runner`

Rejected because the live runner:

- posts outgoing messages: `app/services/ai_agents/runtime/runner.rb:109-127`
- mutates conversation state via handoff: `app/services/ai_agents/runtime/runner.rb:137-143`
- fail-opens into handoff: `app/services/ai_agents/runtime/runner.rb:150-160`

That makes it unsafe for a simulator MVP.

## What should be reused

Reuse:

- the existing provider factory/service where possible: `app/services/ai_agents/providers/factory.rb`, `app/services/ai_agents/providers/openai_compatible_service.rb:1-58`
- current draft snapshot data model: `app/models/ai_agent_version.rb:1-74`
- current draft/readiness/version payloads in the show endpoint: `app/views/api/v1/models/_ai_agent.json.jbuilder:70-114`
- current right-side support column in `AiAgentWorkspacePublishPanel.vue:111-250`

Do not reuse directly:

- `AiAgents::Runtime::Runner`
- `AiAgents::ResponseJob`
- `AiAgents::Tools::Executor` for real custom HTTP execution
- Captain enterprise services

## Draft-vs-live behavior

### Recommendation

Simulate the **persisted draft**, never live.

### Frontend behavior

- If there are unsaved draft changes in the workspace, clicking **Test** should first call the existing `saveDraft` path.
- Then call `simulate` using the now-persisted draft snapshot.

Why this is the smallest safe path:

- current page already tracks draft payload state: `app/javascript/dashboard/routes/dashboard/aiAgents/pages/AiAgentEditPage.vue:38-45`, `:136-146`
- current backend draft update service already persists the relevant shape: `app/controllers/api/v1/accounts/ai_agents_controller.rb:26-30`, `:87-115`
- it avoids inventing a second ad hoc “unsaved draft simulation” payload contract

## Tool usage and handoff behavior in simulation

### Recommendation

Return **tool/handoff intent**, not real side effects.

#### Handoff

- If the model requests `handoff_to_human`, the simulator should return:
  - `handoff_requested: true`
  - `handoff_reason`
- The UI should show a clear preview state such as:
  - “Would hand off to your team”

#### Custom tools

- For MVP, do **not** execute custom HTTP tools.
- Instead return:
  - tool name
  - parsed arguments
  - `executed: false`
  - `preview_only: true`

This is required because current custom tool execution performs real HTTP requests: `app/services/ai_agents/tools/executor.rb:34-67`.

### Suggested simulator response shape

```json
{
  "assistant_message": {
    "role": "assistant",
    "content": "..."
  },
  "tool_calls": [
    {
      "name": "lookup_order_status",
      "arguments": { "order_id": "123" },
      "executed": false,
      "preview_only": true
    }
  ],
  "handoff": {
    "requested": true,
    "reason": "Customer needs billing help"
  },
  "meta": {
    "model": "openai/codex-mini",
    "provider": "openai_compatible",
    "using_local_env": true
  }
}
```

This is enough for the UI to render:

- user bubbles
- assistant bubbles
- tool preview rows
- handoff preview rows
- local-env badge if needed in development

---

## Phase-by-phase implementation plan

## Phase 1: Local simulator env contract and backend request surface

**Owner**: @implementer (backend/api)
**Dependencies**: None
**Complexity**: LOW

### Tasks

- [ ] Define the simulator-only local env contract for `.env.local` and document it in repo-local development notes.
- [ ] Add `POST /api/v1/accounts/:account_id/ai_agents/:id/simulate` to the OSS AI Agents routes.
- [ ] Add `simulate` action to `Api::V1::Accounts::AiAgentsController` behind the existing feature guard and authorization flow.
- [ ] Accept a minimal payload of transcript messages from the simulator UI.
- [ ] Add request-spec coverage for authorization, malformed payload, and success response contract.
- [ ] Verify request specs pass locally.

### Exact likely file areas

- `config/routes.rb`
- `app/controllers/api/v1/accounts/ai_agents_controller.rb`
- `spec/controllers/api/v1/accounts/ai_agents_controller_spec.rb` or request-spec equivalent already used for AI Agents

### Acceptance Criteria

- [ ] The simulator endpoint exists only on the OSS AI Agents controller surface.
- [ ] Only authorized users can call it.
- [ ] The endpoint returns structured simulator data without mutating conversations.

---

## Phase 2: Draft-backed simulation service with OpenRouter local-dev transport override

**Owner**: @implementer (backend/domain)
**Dependencies**: Phase 1
**Complexity**: MEDIUM

### Tasks

- [ ] Add `AiAgents::SimulationService` that reads the current draft snapshot first, falling back to live only where draft data is absent.
- [ ] Add a small adapter/PORO if needed so the existing provider abstraction can be reused without mutating live rows.
- [ ] In `development` only, source provider/model/endpoint/api key from `.env.local` simulator vars instead of Captain config or persisted secrets.
- [ ] Reuse the existing provider generation path where possible; do not call `Runtime::Runner`.
- [ ] Build tool schema from `tool_bindings_snapshot`, not live tool bindings.
- [ ] Return tool/handoff intent only; do not execute custom HTTP tools.
- [ ] Add service specs covering: plain reply, handoff intent, tool call intent, missing local env, and zero side effects.
- [ ] Verify backend specs pass locally.

### Exact likely file areas

- `app/services/ai_agents/simulation_service.rb` (or `app/services/ai_agents/simulation/service.rb`)
- `app/services/ai_agents/providers/openai_compatible_service.rb` (only if a tiny extraction is needed)
- `spec/services/ai_agents/simulation_service_spec.rb`

### Acceptance Criteria

- [ ] Simulation runs against the current draft prompt/tool snapshot.
- [ ] OpenRouter local config stays in `.env.local` and is never written back into the draft.
- [ ] No `AiAgentRun`, no message creation, no job enqueue, and no `bot_handoff!` happen during simulation.

---

## Phase 3: Frontend API/store wiring for save-then-simulate

**Owner**: @implementer (frontend/state)
**Dependencies**: Phase 2
**Complexity**: LOW

### Tasks

- [ ] Add `simulate(id, payload)` to `app/javascript/dashboard/api/aiAgents.js`.
- [ ] Add simulator UI flags and a `simulate` action to the AI Agents Vuex module.
- [ ] Reuse the existing draft-save flow in `AiAgentEditPage.vue` so testing the latest changes first persists draft state, then calls `simulate`.
- [ ] Keep simulator transcript state local to the simulator component/page, not global workspace state.
- [ ] Add frontend unit/spec coverage for API/store action behavior and loading/error flags.
- [ ] Verify affected frontend tests pass.

### Exact likely file areas

- `app/javascript/dashboard/api/aiAgents.js`
- `app/javascript/dashboard/store/modules/aiAgents.js`
- `app/javascript/dashboard/routes/dashboard/aiAgents/pages/AiAgentEditPage.spec.js`

### Acceptance Criteria

- [ ] Clicking Test uses the saved draft, not stale live state.
- [ ] Simulator loading/error state is explicit.
- [ ] No new top-level route or tab is introduced.

---

## Phase 4: Real large inline simulator/chat pane in the left workspace area

**Owner**: @implementer (frontend/ux)
**Dependencies**: Phase 3
**Complexity**: MEDIUM

### Tasks

- [ ] Replace the placeholder block in `AiAgentWorkspacePublishPanel.vue:40-109` with a real simulator pane.
- [ ] Keep the current right-side support column unchanged for readiness/versioning.
- [ ] Add a large transcript region, a minimal composer, loading state, and test-only labels.
- [ ] Prefer a thin transcript implementation that can reuse `MessageList.vue` only if the adapter remains small; do not pull in `MessagesView.vue` or `ReplyBox.vue`.
- [ ] Render tool preview and handoff preview as explicit simulation events.
- [ ] Keep the pane dominant on desktop and stacked below `xl`.
- [ ] Add focused component specs for empty/loading/success/handoff/tool-preview/error states.
- [ ] Verify the split layout still feels calm and readable.

### Exact likely file areas

- `app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentWorkspacePublishPanel.vue`
- `app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentWorkspaceSimulatorPanel.vue`
- `app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentWorkspacePublishPanel.spec.js`

### Acceptance Criteria

- [ ] The left pane is a real, large test surface, not a placeholder.
- [ ] The right pane still owns readiness and versioning.
- [ ] The simulator reads as Chatwoot-native and clearly non-customer-facing.

---

## Phase 5: Browser-tested end-to-end simulator workflow

**Owner**: @implementer (verification)
**Dependencies**: Phase 4
**Complexity**: LOW

### Tasks

- [ ] Start the local stack with the required backend/frontend processes using the repo runbook.
- [ ] Configure `.env.local` with the simulator OpenRouter values.
- [ ] Seed or create an AI Agent with a valid prompt and visible draft state.
- [ ] Use `agent-browser` to open the workspace, edit instructions, save draft, send a simulator message, and observe the response.
- [ ] Verify versioning/readiness still render in the right-side support column.
- [ ] Verify the simulator does not create a real conversation message or trigger handoff side effects.
- [ ] Capture browser evidence (snapshots/screenshots) for the final path.

### Exact likely file areas

- `app/javascript/dashboard/routes/dashboard/aiAgents/pages/AiAgentEditPage.spec.js`
- `docs/ai-agents-inline-simulator.plan.md` (verification commands reference only)
- optional browser verification artifact path outside the repo if needed

### Acceptance Criteria

- [ ] The simulator can be exercised from the real workspace UI with `agent-browser`.
- [ ] Save draft -> test -> inspect result works end-to-end.
- [ ] No live customer-facing state changes occur.

---

## Deliverables

| Phase   | Files Created/Modified                                                                                                                                                                                                                                                                                     |
| ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Phase 1 | `config/routes.rb`, `app/controllers/api/v1/accounts/ai_agents_controller.rb`, `spec/controllers/api/v1/accounts/ai_agents_controller_spec.rb`                                                                                                                                                             |
| Phase 2 | `app/services/ai_agents/simulation_service.rb`, optional `app/services/ai_agents/simulation_draft_config.rb`, `spec/services/ai_agents/simulation_service_spec.rb`                                                                                                                                         |
| Phase 3 | `app/javascript/dashboard/api/aiAgents.js`, `app/javascript/dashboard/store/modules/aiAgents.js`, `app/javascript/dashboard/routes/dashboard/aiAgents/pages/AiAgentEditPage.spec.js`                                                                                                                       |
| Phase 4 | `app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentWorkspaceSimulatorPanel.vue`, `app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentWorkspacePublishPanel.vue`, `app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentWorkspacePublishPanel.spec.js` |
| Phase 5 | `.env.local` (local-only, untracked), browser verification commands/evidence, optional small spec updates in `AiAgentEditPage.spec.js`                                                                                                                                                                     |

## Blast Radius / Affected Entry Points

- `app/controllers/api/v1/accounts/ai_agents_controller.rb` - new simulator action on the existing OSS API surface.
- `app/services/ai_agents/runtime/runner.rb` - must remain unchanged in behavior; simulator must not couple to its side effects.
- `app/services/ai_agents/providers/openai_compatible_service.rb` - reuse carefully without broadening provider semantics.
- `app/services/ai_agents/tools/executor.rb` - do not reuse for real custom-tool execution in simulation.
- `app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentWorkspacePublishPanel.vue` - primary UI replacement of placeholder simulator surface.
- `app/javascript/dashboard/store/modules/aiAgents.js` - simulator action/loading state.

## Allowed Scope / Forbidden Scope

- Allowed: OSS simulator endpoint, draft-backed simulation service, local `.env.local` simulator config, inline simulator UI, right-pane reuse, agent-browser verification.
- Forbidden: Captain bridge reintroduction, enterprise simulator path, live runtime mutation, custom tool real execution, KB/RAG, run history product, new top-level nav, writing secrets into repo docs or tracked config.

## Invariants

| Invariant                                                | Why it matters                                     | How to verify                                                                        |
| -------------------------------------------------------- | -------------------------------------------------- | ------------------------------------------------------------------------------------ |
| Simulator uses draft content, not live published content | Testing must reflect current workspace editing     | Edit prompt, save draft, simulate, then confirm unpublished live state unchanged     |
| Simulator has zero conversation side effects             | Prevents accidental customer-facing mutations      | Verify no message created and no handoff mutation occurs                             |
| OpenRouter config stays local-dev only                   | Avoids Captain/config drift and secret persistence | Check `.env.local`-driven behavior in development and DB state after use             |
| Right-side versioning/readiness pane remains stable      | Approved workspace IA should not churn again       | Browser walkthrough of left simulator + right support column                         |
| Captain bridge remains removed                           | Explicit user constraint                           | Diff review excludes `config/initializers/ai_agents.rb` and enterprise Captain files |

## Behavior That Must Not Change

- Draft save and publish remain in the workspace header - validated by browser walkthrough.
- Version restore continues to use the current restore action and payload shape - validated by restore from the right-side pane.
- Tools CRUD remains in the top-level Tools workspace - validated by separate Tools navigation.
- Simulator must not create outgoing messages or call `conversation.bot_handoff!` - validated by datastore inspection and UI behavior.

## Validation/browser verification plan

## Core browser path

1. Start the local app with the repo-supported development stack (`pnpm start:dev` or the Procfile.dev workflow from the runbook).
2. Ensure `.env.local` contains the simulator OpenRouter variables.
3. Open the workspace with `agent-browser`.
4. Confirm the Instructions split layout renders.
5. Edit the prompt, save draft, and verify the draft success toast.
6. Enter a test customer message in the simulator composer.
7. Wait for the simulated reply.
8. Re-snapshot and verify:
   - assistant reply rendered,
   - tool preview or handoff preview if applicable,
   - readiness/versioning still visible on the right.
9. Verify no real customer conversation was created or changed.

## Validation Matrix

| Check                 | Command / Method                                                                                       | Proves                                                |
| --------------------- | ------------------------------------------------------------------------------------------------------ | ----------------------------------------------------- |
| Exact regression path | `pnpm start:dev` then `agent-browser open http://localhost:3000/app/accounts/:accountId/ai-agents/:id` | Canonical workspace still loads                       |
| Save-then-test flow   | Edit prompt -> click Save draft -> submit simulator message in browser                                 | Simulator runs against current draft state            |
| Local-dev transport   | Run with `.env.local` OpenRouter vars and inspect simulator meta/debug behavior if surfaced            | OpenRouter is local-dev/config driven                 |
| Tool intent safety    | Use a draft with a custom tool bound and trigger a tool-using prompt                                   | Tool usage is represented without real HTTP execution |
| Handoff safety        | Use a prompt that requests escalation                                                                  | Handoff is represented as preview intent only         |
| Behavior preservation | Restore a version from the right pane after simulator use                                              | Versioning support remains intact                     |

## Evidence Owners

| Item                                 | Owner        | Proof Required                                        |
| ------------------------------------ | ------------ | ----------------------------------------------------- |
| Simulator uses draft state           | @implementer | browser walkthrough + API/debug evidence              |
| OpenRouter stays local-only          | @implementer | `.env.local` usage proof + no DB persistence evidence |
| No side effects occur                | @implementer | browser evidence plus datastore/API inspection        |
| Right-side support pane stays stable | @analyzer    | layout review against approved design                 |
| No Captain path returns              | @analyzer    | diff review excluding Captain/enterprise config seams |

## Failure Signals

- The implementation touches `config/initializers/ai_agents.rb` or `CAPTAIN_OPEN_AI_*` wiring.
- Simulator execution requires live conversations or creates `AiAgentRun` records.
- Custom tools begin making real HTTP requests during simulation.
- The simulator depends on persisted API secrets in the draft instead of local env for local dev.
- The right-side support pane is reworked or moved again to accommodate the simulator.

## Review Gates

| Gate       | After Phase | Focus Area                                                                                       |
| ---------- | ----------- | ------------------------------------------------------------------------------------------------ |
| **Gate 1** | Phase 1     | Is the new endpoint constrained to the existing OSS AI Agents API surface?                       |
| **Gate 2** | Phase 2     | Does the simulation service stay side-effect-free and Captain-free?                              |
| **Gate 3** | Phase 3     | Does save-then-simulate use draft state without extra IA complexity?                             |
| **Gate 4** | Phase 4     | Does the simulator feel large and Chatwoot-native while keeping the right support column stable? |
| **Gate 5** | Phase 5     | Does the full browser-tested workflow prove the intended local-dev experience?                   |

## Risks and rollback notes

| Risk                                                             | Likelihood | Impact | Mitigation                                                                                  |
| ---------------------------------------------------------------- | ---------- | ------ | ------------------------------------------------------------------------------------------- |
| OpenRouter model naming mismatch causes failed local tests       | LOW        | MEDIUM | Use fixed `openai/codex-mini`; only fall back after verifying provider error response       |
| Simulator service drifts toward a second runtime implementation  | MEDIUM     | HIGH   | Keep scope to one-turn/iterative transcript generation and reuse provider code only         |
| Custom tools create unsafe external effects                      | HIGH       | HIGH   | Preview tool intent only for MVP; no real custom HTTP execution                             |
| Local env override causes confusion vs persisted model fields    | MEDIUM     | MEDIUM | Scope override to simulator in development only and show a subtle local-dev label if needed |
| UI reuse of full conversation components drags in store coupling | MEDIUM     | MEDIUM | Reuse only thin transcript primitives; avoid `MessagesView` / `ReplyBox`                    |

## Rollback path

- Backend rollback: remove the `simulate` member action and service, leaving draft/publish/versioning untouched.
- Frontend rollback: restore the existing placeholder block in `AiAgentWorkspacePublishPanel.vue` and keep the right support column intact.
- Local config rollback: remove the simulator env vars from `.env.local`; no persisted data migration is required.

## Clear recommendation on the first implementation phase

**Build Phase 1 first: the simulator endpoint contract and local env contract.**

Why this is the highest-leverage next move:

- it locks the correct seam: OSS AI Agents controller + service, not Captain
- it defines how `.env.local` is used without leaking secrets into persisted records
- it unblocks both backend simulation logic and frontend browser-tested UI work
- it keeps the approved workspace design stable while replacing only the placeholder surface

## Decision Log

| Decision                          | Chosen                                             | Rejected                                         | Rationale                                                     | Evidence                                                                |
| --------------------------------- | -------------------------------------------------- | ------------------------------------------------ | ------------------------------------------------------------- | ----------------------------------------------------------------------- |
| Simulator integration seam        | New OSS `simulate` endpoint + service              | Reuse `Runtime::Runner` directly                 | Live runner has message/handoff side effects                  | `runtime/runner.rb:109-160`                                             |
| Local provider config source      | `.env.local` simulator-only env vars               | `CAPTAIN_OPEN_AI_*` / InstallationConfig         | User requested local-dev/config-driven, OSS-only path         | `config/application.rb:12-15`, `config/initializers/ai_agents.rb:9-20`  |
| OpenRouter model string           | `openai/codex-mini`                                | guessing `codex 5.1 mini` or alias-first strings | Observed exact OpenRouter identifier is safer than guessing   | OpenRouter model page `/openai/codex-mini`                              |
| Draft-vs-live simulator state     | Persisted draft                                    | live published config                            | Matches current workspace editing model and avoids live drift | `_ai_agent.json.jbuilder:70-114`, `AiAgentEditPage.vue:74-115`          |
| Custom tool behavior in simulator | preview only                                       | real HTTP execution                              | Current tool executor is side-effectful and unsafe for MVP    | `tools/executor.rb:34-67`                                               |
| UI shape                          | Replace left placeholder in existing publish panel | new route or new top-level tab                   | Current side-by-side layout already exists and is approved    | `AiAgentWorkspacePublishPanel.vue:31-38`, `AiAgentEditPage.vue:211-258` |
