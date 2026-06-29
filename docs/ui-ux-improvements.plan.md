# Frontend UI/UX Improvement Plan (OSS)

**Scope**: OSS-only frontend under `app/javascript/**` plus shared `theme/colors.js` and SCSS token files. Excludes `enterprise/` overlays. Captain (Enterprise) is out of scope; the OSS **AI Agent** pages (`routes/dashboard/settings/aiAgent/**`) are in scope.

**Branch**: `feat/ui-ux-improvements` (off `feat/voice-ai-ops-ux`)

## Audit Sources
- OSS AI Agent pages audit
- Voice/Call UX audit (floating widget, in-thread bubble, transcript, VoiceAiSettings)
- Dashboard consistency audit (legacy vs `components-next`, tokens, a11y)
- General app audit (conversation view, list/sidebar, contacts, reports, campaigns, help center, settings, onboarding/empty states, global)

## Phases

### Phase 0 — Screenshot Baseline
Capture before-screenshots for: conversation list + empty state + ChatTypeTabs; conversation view (header, message list, ReplyBox, contact panel); AI Agent list/new/detail/test/usage; Voice (floating widget, in-thread bubble, transcript, VoiceAiSettings tabs); Contacts/Reports/Campaigns/HelpCenter empty states; Sidebar (collapsed + expanded) + notification bell; a mixed legacy/next view (ChatList).

### Phase 1 — Quick Wins (<1 day each)
1. Fix `cucursor-pointer` typo → `cursor-pointer` — `ConversationHeader.vue:152`
2. Add keyboard handler to `ConversationCard` (`tabindex="0"`, `@keydown.enter/space.prevent`) — `ConversationCard.vue:88-91`
3. Add `aria-label` to SidepanelSwitch + SidebarNotificationBell buttons — `SidepanelSwitch.vue:62,76`, `SidebarNotificationBell.vue:28-38`
4. Fix invalid `<a>` wrapping `<button>` in AI Agent list item — `AiAgentListItem.vue:61-75`
5. Make test-conversation delete button always visible (remove `opacity-40`) — `TestConversationListItem.vue:54-59`
6. Replace hardcoded "PaperLayer"/"Kozmopath" in campaign empty states with generic names or `installationName` — `CampaignEmptyStateContent.js`
7. Add active-tab underline to ChatTypeTabs for mobile clarity — `ChatTypeTabs.vue:49-63`

### Phase 2 — Voice/Call UX
1. Responsive floating widget: `w-[400px]` → `max-w-[400px] w-[90vw] sm:w-[400px]` — `FloatingCallWidget.vue:318`
2. Widget a11y: `role="dialog"`, `aria-modal`, `aria-label`, Escape handler, focus trap, autofocus Accept — `FloatingCallWidget.vue:316-353`
3. Voice status in next-gen ConversationCard: detect `voice_call` contentType and render `VoiceCallStatus` — `ConversationCard/ConversationCard.vue`, `CardMessagePreview.vue`
4. Status taxonomy alignment: add `busy`/`canceled`/`missed`/`ended` to `VOICE_CALL_STATUS` + icons/colors/labels — `message/constants.js:81-96`, `voice.js:7-15`, `VoiceCall.vue`
5. Distinguish "Declined" from "Missed" in card preview via `endReason` — both `VoiceCallStatus.vue` files
6. Collapsible call bubble: wrap recording/summary/LiveKit sections in `<details>` — `VoiceCall.vue:526-660`
7. Transcript grouping: wrap a call's transcript+tool events in a container with heading + collapse — `MessageList.vue:149-183`
8. Expandable tool-event details in conversation (match settings page `<details>`) — `VoiceToolEventSegment.vue:58-76`
9. Live duration in in-thread bubble + join-progress indicator — `VoiceCall.vue:191-197`, `useLivekitVoiceSession.js`
10. Re-introduce call-widget color tokens for distinct dark-card appearance — `_next-colors.scss`, `theme/colors.js`, `CallCard.vue`

### Phase 3 — AI Agent Pages (OSS)
1. Migrate `woot-input` → components-next `Input` — `AiAgentNew.vue:58`, `AiAgentDetail.vue:423`
2. Associate inbox checkboxes with labels (`<label for>`) or use a Checkbox primitive — `AiAgentDetail.vue:479-499`
3. `role="progressbar"` + aria values on usage bar — `AiAgentUsageSummary.vue:141-156`
4. Inline error state for failed test messages (keep optimistic msg with retry) — `TestConversationChatPanel.vue`, store `aiAgentTestConversations.js:176`
5. Keep delete dialog open on API failure with inline error — `AiAgentList.vue:49-55`
6. Unsaved-changes guard on detail route (`onBeforeRouteLeave`) — `AiAgentDetail.vue`
7. Autofocus test-conversation input on selection — `TestConversationChatPanel.vue:182`
8. Handle usage fetch failure (show "unavailable" instead of permanent "Loading…") — `AiAgentUsageSummary.vue`, store `aiAgent.js:60`
9. Reduce prompt editor min-height (24rem → 12rem) — `AiAgentPromptEditor.vue:45`
10. Separate `isDeleting` vs `isClearing` flags — `aiAgentTestConversations.js:118,135`
11. Show server-specific errors on create instead of generic message — `AiAgentNew.vue:38-40`

### Phase 4 — General App UX
1. Contextual conversation empty states: 3 variants (no inboxes / no conversations / select one) using `EmptyStateLayout` — `EmptyState.vue`, `EmptyStateMessage.vue`
2. Skeleton loading states: reusable `SkeletonCard` for conversation/contacts/reports lists — replace spinners
3. Sticky ReplyBox bottom bar + reserved banner space to stop layout reflow — `ReplyBox.vue`, `ResizableEditorWrapper.vue`
4. Discoverable sidebar reordering: drag-handle icon + "Reset order" — `ContactPanel.vue`
5. Add assignee display to ConversationHeader (currently hidden in contact panel)
6. Reports migration: convert `Index.vue` to `<script setup>`, replace `fluent-icon` with `Icon` — `ReportMetricCard.vue:34`, `Index.vue`
7. SidebarProfileMenu: replace `document.querySelector('ninja-keys')` hack with proper event/ref — `SidebarProfileMenu.vue:79`

### Phase 5 — Design-System Consolidation
1. Shared `Badge` primitive consolidating `UnreadBadge.vue` + `SidebarUnreadBadge.vue`
2. Shared `Tooltip` wrapper with consistent delay/position
3. ARIA + arrow-key nav on `DropdownMenu` and `TabBar`
4. Dialog a11y: `aria-labelledby`/`aria-describedby`, focus trap, autofocus — `Dialog.vue`
5. Unify Table: port tanstack sorting + sticky header into `BaseTable`, deprecate legacy `Table.vue`
6. Migrate `fluent-icon` → Lucide/Phosphor across 37 legacy instances
7. Fix `role="button"` divs across `ConversationCard.vue:89`, `InboxCard.vue:156`, `SidebarGroupHeader.vue:30`
8. Contrast token fix: darken `n-slate-11`/`n-slate-10` to meet WCAG AA — `_next-colors.scss`
9. Remove global `outline: none` in `_base.scss:63`, rely on `focus-visible` ring per component
10. Add skip-to-content link + route-change focus management
11. Fix SidebarGroup route-nesting TODO: proper nested routes, remove manual `activeChild` logic — `SidebarGroup.vue:128-166`

## Verification per phase
- `pnpm eslint` / `pnpm eslint:fix` after each frontend change
- `pnpm test` for affected Vitest specs
- Histoire stories (`pnpm story:dev`) for visual verification of touched components
- `agent-browser` screenshots for before/after comparison on the key screens from Phase 0
- `bundle exec rspec` only if a Ruby file is touched

## Commit Strategy
- One commit per phase (or per logical sub-group within a phase)
- Conventional Commits format: `fix(ui): ...`, `feat(ui): ...`, `fix(a11y): ...`
- No AI tool references in commit messages
