# Chatwoot AI Agents - Etkin Pattern Gap & UX Planning Report

## 1) Executive summary

Chatwoot already has the right **product foundation** for AI Agents: a top-level workspace, agent CRUD, tool management, inbox binding, and a safe fail-open runtime path that hands conversations back to humans when automation fails (`app/javascript/dashboard/routes/dashboard/aiAgents/aiAgents.routes.js:17-52`, `app/controllers/api/v1/accounts/ai_agents_controller.rb:7-25`, `app/services/ai_agents/inbox_binding_service.rb:19-33`, `app/services/ai_agents/runtime/runner.rb:150-160`).

The main gap is now **UX cohesion**, not core capability. Today the experience is split across:

- an agent list,
- a separate create page,
- a separate edit page,
- a separate tools page,
- and a separate inbox binding page.

That structure is functional for admins, but it is not yet the simplest mental model for SMB operators who mostly want to answer one question: **“Which AI agent is active on which inbox, what can it do, and how can I safely improve it?”**

The best Etkin-inspired ideas to adopt are:

1. **One unified AI agent workspace** per agent,
2. **Lightweight versioning for agent configuration**,
3. **An inline simulator on the same page as configuration**.

The recommendation is **not** to copy Etkin wholesale. Chatwoot should stay Chatwoot-native by building on existing strengths:

- inboxes as deployment surface,
- conversations as the real work object,
- human handoff as the safety valve,
- tools as controlled extensions,
- admin settings patterns already present in the dashboard.

### Recommended next move

Build a **unified agent detail workspace** as the next UX/product iteration, with:

- overview + configuration on one screen,
- inline inbox assignment,
- inline tool summary with link-out editing,
- a simple “Test agent” simulator panel,
- and **draft/published config snapshots** only (not full branching/version history yet).

---

## 2) Current Chatwoot AI Agents state

### Current state (evidence)

| Area                    | Current status                                                               | Evidence                                                                                                                                                                                                                                                           |
| ----------------------- | ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Top-level workspace     | Implemented as a first-class dashboard area with admin + feature-flag gating | `app/javascript/dashboard/routes/dashboard/aiAgents/aiAgents.routes.js:17-52`, `app/javascript/dashboard/components-next/sidebar/Sidebar.vue:396-418`                                                                                                              |
| Workspace structure     | Current workspace has only `Agents` and `Tools` tabs                         | `app/javascript/dashboard/routes/dashboard/aiAgents/constants.js:6-17`                                                                                                                                                                                             |
| Agent CRUD              | Implemented with REST controller and provisioning flow                       | `app/controllers/api/v1/accounts/ai_agents_controller.rb:7-25`, `app/services/ai_agents/provisioning_service.rb:7-24`                                                                                                                                              |
| Agent edit UX           | Separate create and edit pages use one long form                             | `app/javascript/dashboard/routes/dashboard/aiAgents/pages/AiAgentNewPage.vue:46-77`, `app/javascript/dashboard/routes/dashboard/aiAgents/pages/AiAgentEditPage.vue:50-97`, `app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentForm.vue:172-316` |
| Tools management        | Separate workspace tab with split-pane custom tools manager                  | `app/javascript/dashboard/routes/dashboard/aiAgents/pages/AiAgentsToolsPage.vue:8-27`, `app/javascript/dashboard/routes/dashboard/aiAgents/components/AiCustomToolsManager.vue:83-202`                                                                             |
| Inbox binding           | Separate per-agent page for binding inboxes                                  | `app/javascript/dashboard/routes/dashboard/aiAgents/pages/AiAgentBindingsPage.vue:25-48`, `app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentInboxBindingsManager.vue:99-180`                                                                   |
| Agent readiness in list | List shows status, inbox count, and credentials readiness                    | `app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentsTable.vue:19-101`, `app/views/api/v1/models/_ai_agent.json.jbuilder:13-20`                                                                                                                  |
| Runtime routing         | Messages are routed from the existing post-message hook                      | `app/services/message_templates/hook_execution_service.rb:16-21`, `app/services/ai_agents/inbound_router.rb:23-35`                                                                                                                                                 |
| Human fallback          | Runtime fail-open hands off to human if runtime errors                       | `app/services/ai_agents/runtime/runner.rb:150-160`, `app/models/conversation.rb:161-164`                                                                                                                                                                           |
| Inbox semantics reuse   | Existing inbox/pending lifecycle is reused through `AgentBot` binding        | `app/services/ai_agents/inbox_binding_service.rb:19-33`, `app/models/inbox.rb:169-172`                                                                                                                                                                             |

### Product readout

What is already strong:

- AI Agents already feels like a real product area in navigation.
- Core lifecycle exists end-to-end.
- Chatwoot-native deployment object is clear: **bind an agent to an inbox**.
- Runtime safety is well aligned with Chatwoot’s human-handoff model.

What feels incomplete for UX:

- Too much context switching between screens.
- Binding inboxes is treated as a side task instead of the core deployment step.
- Tools are managed in a separate tab, but selected in the agent form.
- No simulator on the agent page.
- No visible versioning / “safe publish” concept.
- Current form exposes provider/model/prompt fields directly, which is fine for advanced admins but not ideal for SMB users who do not understand AI deeply.

---

## 3) Etkin.ai patterns worth adopting

> Note: this report uses the user-confirmed Etkin patterns as the primary source of truth. The repository contains no internal Etkin analysis docs, and the public marketing site only supports broad product positioning, not exact app behavior (`docs/ai-agents-v1-implementation.plan.md:17-26`; repo search found no Etkin planning artifacts).

### A. Unified AI agent workspace

Why it is worth adopting:

- Reduces navigation overhead.
- Lets a business see **setup + deployment + testing** in one place.
- Better matches the operational question: “Is this agent ready to handle customers?”

Why it fits Chatwoot:

- Chatwoot already has a top-level AI Agents area.
- Inbox binding is the real activation step, so it belongs near agent configuration.

### B. Versioned assistant configs

Why it is worth adopting:

- Businesses are afraid of breaking working automations.
- Versioning turns prompt/model/tool changes into a safer workflow.
- It creates a simple “draft vs live” mental model, which is easier than raw prompt editing.

Why it fits Chatwoot:

- Chatwoot already has strong operational concepts around safe handoff and visibility.
- A lightweight publish model complements the existing fail-open runtime behavior.

### C. Inline simulator on the same page

Why it is worth adopting:

- Gives fast feedback after edits.
- Helps non-technical admins test behavior without sending real customer messages.
- Makes prompt editing less abstract.

Why it fits Chatwoot:

- Chatwoot already centers conversations; a simulator can borrow that familiar mental model.
- It makes agent setup feel less like “editing system fields” and more like “previewing customer experience.”

### D. Business-first framing

Likely pattern from Etkin worth preserving in spirit:

- Speak in business outcomes, not AI jargon.
- Emphasize fast setup, clear deployment, and confidence before going live.

Chatwoot-native translation:

- Use labels like **Where this agent works**, **When to hand off**, **Try a customer message**, not only prompt/model/provider language.

---

## 4) Etkin.ai patterns not worth copying directly

| Pattern to avoid copying directly                                             | Why not                                                                     | Chatwoot-native alternative                                                       |
| ----------------------------------------------------------------------------- | --------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| Full competitor information architecture                                      | Chatwoot already has inboxes, conversations, settings, and handoff patterns | Keep AI Agents anchored to inbox deployment + conversation support workflows      |
| Over-abstracted AI control center                                             | SMB users do not need a “control plane” mental model                        | Use one clear agent workspace with simple sections                                |
| Heavy AI jargon and provider-centric setup                                    | Most SMB operators do not think in prompts, models, or tool schemas         | Progressive disclosure: show advanced settings only when needed                   |
| Enterprise-grade version trees / branching                                    | Too much complexity for current product maturity                            | Ship only draft/published snapshots in v1                                         |
| Full simulation lab with traces, tool-call inspectors, token stats            | Useful later, but not the first UX simplification win                       | Ship a basic inline simulator with response preview + handoff/tool indicators     |
| Duplicating omni-channel control concepts already covered by Chatwoot inboxes | Chatwoot already owns channel abstraction through inboxes                   | Treat inboxes as the deployment surface for AI Agents                             |
| Duplicating human-assist workflows                                            | Chatwoot already has conversation routing + handoff                         | Keep AI as augmentation of existing support flows, not a parallel workflow engine |

---

## 5) Product-gap matrix: Etkin.ai pattern vs current Chatwoot status vs recommendation

| Pattern                        | Current Chatwoot status                                                                  | Gap                          | Recommendation                                                                |
| ------------------------------ | ---------------------------------------------------------------------------------------- | ---------------------------- | ----------------------------------------------------------------------------- |
| Unified AI workspace           | Partial: top-level workspace exists, but detail flow is fragmented across multiple pages | High                         | **Ship in v1 UX refresh**                                                     |
| Versioned assistant configs    | None visible in UX or model contract                                                     | High                         | **Ship lightweight draft/published only**                                     |
| Inline simulator on agent page | None                                                                                     | High                         | **Ship basic simulator**                                                      |
| Deployment clarity             | Partial: inbox count shown, binding exists, but binding lives on separate page           | High                         | **Move inbox placement into agent detail page**                               |
| Readiness overview             | Partial: list shows inbox count + credentials                                            | Medium                       | **Expand with clearer readiness checklist**                                   |
| Non-technical onboarding       | Limited: current form is field-driven                                                    | High                         | **Reframe around business tasks and outcomes**                                |
| Safe editing workflow          | Limited: changes appear immediate; no publish step                                       | High                         | **Introduce review/publish checkpoint**                                       |
| Tool management proximity      | Partial: tools tab exists, tools selectable in form                                      | Medium                       | **Inline selected tools summary; keep full tool CRUD in separate tools area** |
| Simulator + version connection | None                                                                                     | Medium                       | **Simulator should test current draft before publish**                        |
| Run history / observability    | Explicitly absent in capabilities                                                        | Low for immediate UX refresh | **Defer** (`app/views/api/v1/models/_ai_agent.json.jbuilder:16-20`)           |
| Knowledge base                 | Explicitly absent in capabilities                                                        | Low for immediate UX refresh | **Defer** (`app/views/api/v1/models/_ai_agent.json.jbuilder:16-20`)           |
| Advanced optimization controls | Not present                                                                              | Low                          | **Defer**                                                                     |

---

## 6) Recommended v1 UX strategy for Chatwoot AI Agents aimed at non-technical businesses

### Core strategy

Design the AI Agents experience around 4 business questions:

1. **What does this agent do?**
2. **Where is it live?**
3. **What can it use?**
4. **What will happen if it fails or gets stuck?**

### UX principles

- **Business-first labels** over AI-native labels.
- **One primary screen per agent**.
- **Progressive disclosure** for advanced model/prompt details.
- **Safe-to-edit workflow** with draft and publish.
- **Conversation-shaped simulator** so setup feels familiar.
- **Inbox-first deployment model** because that is the Chatwoot-native activation step.

### What the user should feel

Instead of: “I am configuring an LLM.”

They should feel: “I am setting up an AI teammate for these inboxes, testing it, and deciding when it should hand off to my team.”

---

## 7) Information architecture recommendation

## Recommended IA

### Top-level navigation

- **AI Agents**
  - **Agents**
  - **Tools**

### Within Agents

- Agents list/index
- Agent create flow
- Agent detail workspace

### Within a single agent detail workspace

1. **Overview**
2. **Behavior**
3. **Deployment**
4. **Test**
5. **Versions**

### IA guidance

- Keep **Tools** as a separate top-level tab inside the AI Agents workspace because tool CRUD is cross-agent and more admin-heavy.
- Do **not** keep inbox binding as a separate page in the long term; it is agent deployment state, not a separate object from the user’s perspective.
- Do **not** add a top-level “Simulator” nav item. Testing belongs in context of an agent.
- Do **not** add a top-level “Versions” index yet. Versions are only meaningful per agent in v1.

---

## 8) Detailed page-level UX proposal for a unified AI Agent workspace

### A. List / index

#### Current state

- Table shows name, provider/model, status, readiness, edit, inboxes (`app/javascript/dashboard/routes/dashboard/aiAgents/components/AiAgentsTable.vue:19-101`).

#### Proposed v1 refresh

- Keep table/list foundation.
- Add stronger operational columns:
  - **Assigned inboxes** (names, not just count)
  - **Live version**
  - **Last updated**
  - **Status badge**: Draft / Live / Disabled / Needs setup
- Replace separate “Inboxes” action with **Open workspace** as primary CTA.
- Optional secondary row actions:
  - Duplicate
  - Disable/Enable

#### Why

- The list should answer “which agents are live and where?” at a glance.

### B. Create flow

#### Recommended approach

- Use a **guided create flow**, not a blank long form.

#### Step 1: Basics

- Agent name
- Short description
- Optional starter behavior template

#### Step 2: Where it works

- Choose inboxes immediately

#### Step 3: First behavior

- Primary instruction prompt
- Handoff guidance

#### Step 4: Review & create draft

- Summary card
- Create as draft, then land in agent detail workspace

#### Why

- For SMBs, choosing deployment surface early is easier than filling technical fields first.

### C. Detail / edit screen

#### Replace today’s long-form page with a unified workspace layout

### Recommended layout

#### Header

- Agent name
- Status badge: Draft / Live / Disabled
- Assigned inbox count
- Primary actions:
  - Save draft
  - Publish changes
  - Disable / Enable

#### Main left column

1. **Overview card**

   - purpose/description
   - readiness checklist
   - live inboxes

2. **Behavior section**

   - system prompt / instructions
   - handoff prompt
   - handoff customer message
   - advanced model/provider settings collapsed by default

3. **Tools section**

   - selected tools summary inline
   - add/remove tools
   - “Manage tools” deep link to workspace tools tab

4. **Deployment section**
   - inbox binding inline
   - warnings for conflicting responders
   - human handoff explanation

#### Right column

1. **Inline simulator**
2. **Version panel**
3. **Readiness / publishing notes**

### D. Placement of tools, inboxes, simulator, versioning

| Element    | Placement                                                 | Why                                                                          |
| ---------- | --------------------------------------------------------- | ---------------------------------------------------------------------------- |
| Tools      | Inline in agent detail, with link to full Tools workspace | Agent-specific selection should stay in context; tool CRUD stays centralized |
| Inboxes    | Inline in agent detail under Deployment                   | Inbox binding is core activation state                                       |
| Simulator  | Right-side panel on detail page                           | Supports fast edit-test loop                                                 |
| Versioning | Compact right-side panel + publish action in header       | Makes safety visible without taking over the screen                          |

---

## 9) Versioning proposal

### v1 should include

**Model:** lightweight config snapshots only.

Recommended v1 behavior:

- One **live version** per agent.
- One editable **draft** state.
- On publish, save a snapshot of:
  - prompt fields,
  - provider/model settings,
  - enabled tools,
  - inbox assignments,
  - enabled/disabled state.
- Show simple version list:
  - Version number
  - Published by
  - Published at
  - Optional short note
- Allow **restore previous version to draft**.

### v1 should defer

- branching
- compare diffs between arbitrary versions
- environment promotion
- approval workflows
- multi-user review states
- granular simulator history per version

### Why this is enough

It solves the real SMB fear: **“If I change this and it gets worse, can I go back?”**

It does not introduce enterprise-grade release management before Chatwoot needs it.

---

## 10) Inline simulator proposal

### v1 should include

- A simulator panel embedded in the agent detail page.
- One-thread test conversation UI using familiar chat bubbles.
- Admin enters a sample customer message.
- System shows:
  - simulated AI reply,
  - whether a tool would be called,
  - whether handoff would happen.
- Clear label that this is **test mode**, not a real customer conversation.
- Simulator should test the **current draft**, not only the live version.

### v1 should defer

- multi-turn transcript saving
- full tool-call JSON inspection
- latency/token/cost analytics
- simulation against historical conversations
- simulator personas or datasets
- auto-regression suites

### Chatwoot-native design recommendation

- Use a conversation-like UI, not a developer console.
- Copy should say **Try a customer message** or **Preview response**, not “Run prompt” or “Execute model.”
- Include one visible safety message: **If this goes wrong in production, the conversation hands off to a human** to reinforce Chatwoot’s operational model.

---

## 11) Simplicity rules / anti-overcomplexity guardrails for SMB users

1. **No exposed AI jargon by default**

   - Hide terms like temperature, stop sequence, tool schema unless user opens advanced settings.

2. **One screen should answer readiness**

   - Name, behavior, inboxes, tools, test result, publish state.

3. **No more than one primary action per state**

   - Draft state: Publish changes.
   - Live unchanged state: Test / Edit.

4. **Do not require understanding versions to use the feature**

   - Versioning should be safety infrastructure, not a workflow tax.

5. **Do not split setup across many routes**

   - A user should not need to hunt for tools, inboxes, and testing in separate places to launch one agent.

6. **Keep deployment mental model concrete**

   - “This agent answers messages in these inboxes.”

7. **Keep advanced controls secondary**

   - Provider endpoint, secret management, advanced model controls belong behind collapsible UI.

8. **Use warnings, not blockers, wherever possible**

   - Example: “No inboxes assigned yet” should be a clear readiness warning.

9. **Human handoff must stay obvious**

   - Users should always understand that AI is assistive and can fall back safely.

10. **Do not introduce duplicate Chatwoot concepts**

- No separate channel system, no separate human escalation workflow, no separate conversation model.

---

## 12) Prioritized implementation roadmap for the next UX/product iteration

### Phase 1 - Unified agent detail workspace

**Ship in v1 UX refresh**

Scope:

- replace separate edit + inbox binding flow with one workspace-oriented detail screen
- inline inbox assignment
- inline selected tools summary
- readiness checklist

Outcome:

- biggest reduction in user confusion
- strongest alignment with unified-workspace goal

### Phase 2 - Guided create flow

**Ship in v1 UX refresh**

Scope:

- step-based create flow
- choose inboxes early
- create draft first

Outcome:

- easier onboarding for non-technical businesses

### Phase 3 - Lightweight versioning

**Ship in v1 UX refresh if scope allows; otherwise v1.1**

Scope:

- draft/live snapshot model
- publish action
- restore older version to draft

Outcome:

- safer editing and clearer live-state mental model

### Phase 4 - Inline simulator

**Ship in v1 UX refresh if backend support is straightforward; otherwise v1.1 immediately after**

Scope:

- same-page simulation using draft config
- response preview + tool/handoff indicators

Outcome:

- confidence before publish

### Phase 5 - List page upgrades

**Ship in v1 UX refresh**

Scope:

- readiness and deployment visibility
- live version status
- stronger primary CTA into agent workspace

### Phase 6 - Advanced operator enhancements

**Defer**

Scope:

- run history
- diagnostics
- deeper tool traces
- historical replay
- knowledge base
- analytics

---

## 13) Risks / tradeoffs

| Risk                                                  | Tradeoff                                                         | Mitigation                                                             |
| ----------------------------------------------------- | ---------------------------------------------------------------- | ---------------------------------------------------------------------- |
| Unified page becomes too dense                        | More power on one screen can create clutter                      | Use section cards, progressive disclosure, right-rail secondary panels |
| Versioning adds conceptual load                       | Safer workflow but more states                                   | Keep only Draft and Live in v1                                         |
| Simulator may imply production accuracy               | Test output may not perfectly match live runtime                 | Label clearly as preview and keep it lightweight                       |
| Inline inbox binding may complicate the page          | More functionality in one place                                  | Worth it because inbox binding is central deployment state             |
| Tools inline + tools tab can feel duplicated          | Two surfaces for related concerns                                | Keep selection inline; keep CRUD centralized                           |
| Competitor inspiration can drift into product cloning | Team may copy structure without filtering for Chatwoot strengths | Use explicit adoption/defer rules and Chatwoot-native principles       |

---

## 14) Clear recommendation on what to build next

### Build next

**A unified AI Agent detail workspace with inline inbox assignment, inline tool selection summary, a readiness checklist, and a right-rail placeholder for simulator/versioning.**

If only one thing is built next, it should be this.

### Why this is the highest-leverage next step

- It fixes the biggest usability problem in the current implementation: fragmented setup.
- It makes the existing phases 1-8 feel like one product instead of several admin screens.
- It sets up the right foundation for both versioning and simulator without overcommitting to either.
- It is Chatwoot-native because it centers inbox deployment and human handoff, not competitor-specific abstractions.

### Final recommendation stack

#### Ship in v1 UX refresh

- Unified agent detail workspace
- Guided create flow
- Inline inbox assignment
- Inline tools summary + centralized tool management link
- Readiness checklist
- Improved list/index visibility

#### Ship if feasible in same cycle, otherwise v1.1

- Draft/live versioning
- Inline simulator

#### Defer

- Advanced version management
- run history UX
- diagnostics and traces
- KB and retrieval UX
- advanced analytics/optimization surfaces

## Recommendation summary in one sentence

Adopt Etkin’s **workspace cohesion, safe editing, and inline testing ideas**, but implement them in a **Chatwoot-native inbox-and-handoff workflow** rather than cloning a competitor control panel.
