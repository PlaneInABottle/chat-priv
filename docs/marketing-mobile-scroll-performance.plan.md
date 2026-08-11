# Marketing Hero Mobile Scroll Performance — Implementation Plan

**Status:** READY (planning only — no code changes made)
**Amendment (Vite fingerprint resolution):** the verified content-hash contradiction is resolved per Analyzer resolution B — the request-spec fingerprint test normalizes the hashed marketing CSS URL (anchored 8-char base64url regex + loud include assertion) and `DESIGN_CONTRACT_SHA` is re-anchored ONCE to the normalized digest (see §3 F16-F17, §10 Phase 1 tasks 1.10-1.13, §14). CSS/performance/visual intent unchanged.
**Scope of this document:** exact CSS replacement, spec updates, performance/visual/accessibility gates, rollback, and phase boundaries for eliminating hero scroll jank on mobile.
**Authoritative runtime evidence:** the verified A/B diagnosis supplied by the requester (headless software-compositor Chromium at 390x844 DPR3). Re-measurement is not required to plan; the same harness is reused as the post-change gate.

---

## 1. Problem Statement

Scrolling the marketing homepage hero on a mobile-class viewport (390x844, DPR3) drops up to ~30% of frames beyond 33ms because the two hero panels carry `backdrop-filter: blur(16px)`. The filter forces per-frame re-rasterization of the large translucent surfaces during scroll (`SoftwareRenderer::DoDrawQuad` 1306ms → 188ms when disabled). The fix is a clean visual replacement: opaque palette surfaces with the project's existing card vocabulary (border + restrained shadow), removing the root cause at every breakpoint — no mobile-only fallback, no `@supports`, no compatibility layer.

## 2. Success Criteria

- [ ] **Atomic implementation phase:** the CSS replacement, its source-contract spec, and the fingerprint fix land as ONE green unit in exactly four code files — `app/javascript/entrypoints/marketing.scss`, `spec/lib/marketing_controller_spec.rb`, `spec/requests/marketing_homepage_spec.rb` and `app/controllers/marketing_controller.rb` (CSS + source contract + asset-URL normalization + one-time digest re-anchor). No phase ends in an intentionally red state; the targeted RSpec + RuboCop gates are green at the end of the implementation phase.
- [ ] `.product-proof` and `.flow-strip` no longer declare `backdrop-filter` anywhere in `app/javascript/entrypoints/marketing.scss`; the only remaining `backdrop-filter` in the file is the below-fold `.anatomy-media figcaption` (`marketing.scss:605`).
- [ ] Performance — **HARD gate** (agent-browser, same methodology as baseline): 0 frames >33ms in every one of 3 runs at 390x844 DPR3; 0 long tasks >50ms; CLS 0. **TARGETS (diagnostic, bounded-variance policy, analyzer review on miss):** p95 ≤ 16.8ms; max ≤ 20ms; ≤ 20% of frames >16.7ms.
- [ ] Visual acceptance: human-reviewed baseline/current/diff screenshots at 390x844 DPR3 and 1440x900 (Turkish freemium state, normal + reduced motion, scroll 0 and first section) show the hero hierarchy preserved — panels read as solid cards, text/CTA legible, no overflow.
- [ ] Accessibility: computed WCAG contrast for `.flow-strip span` (4.78:1) and `.contact-copy small` (4.92:1) on the new opaque surface ≥ 4.5:1; focus/hover rules untouched.
- [ ] Specs: the new selector-scoped source-contract assertions (no `backdrop-filter` in the two hero rule blocks; figcaption blur retained; `var(--paper-strong)` surfaces) and the two contrast-pair backgrounds (`#fffdf7`) land in the same phase as the CSS — never a phase apart; the fingerprint test normalizes the Vite asset URL before hashing and `DESIGN_CONTRACT_SHA` is re-anchored exactly once to the normalized digest, after which CSS content/build-hash churn does not rotate it (DOM/copy/meta/template/entry-reference changes still do).
- [ ] Validation phase is source-edit-free (no file changes) and is not marked complete until all thresholds pass — or the analyzer-review decision under the bounded-variance policy (§7.2) is recorded.
- [ ] Rollout is a separate operational step after implementation + validation: one focused commit + asset build + deploy + smoke; rollback is a revert of that commit + asset rebuild (no migration, no flag).

## 3. Verified Facts vs Assumptions

### Verified Facts (source evidence)

| # | Fact | Evidence |
|---|------|----------|
| F1 | `.product-proof` declares `backdrop-filter: blur(16px)` | `app/javascript/entrypoints/marketing.scss:207` |
| F2 | `.flow-strip` declares `backdrop-filter: blur(16px)` | `app/javascript/entrypoints/marketing.scss:359` |
| F3 | These are the ONLY two `backdrop-filter` declarations in the live marketing stylesheet besides the below-fold figcaption | `marketing.scss:605` (`rg` across `app/`, `enterprise/`; the design-prototypes copy at `design-prototypes/kozmopath-trial-conversion/iterations/001/shared/marketing-base.css:207,359,607` is a standalone prototype artifact, NOT a build input — it is linked only by prototype HTML pages and a prototype test) |
| F4 | Panel surfaces are translucent today: `.product-proof` `background: rgba(255,253,247,.91)`, `.flow-strip` `background: rgba(255,253,247,.76)` | `marketing.scss:205, 358` |
| F5 | `.product-proof` border is white `rgba(255,255,255,.64)`; shadow is `0 28px 80px rgba(16,33,31,.20)` | `marketing.scss:203, 206` |
| F6 | No per-breakpoint overrides of background/border/shadow/backdrop-filter for either panel exist (mobile block `marketing.scss:866-902` and desktop block `:389-432` only override layout/geometry) — one base-rule edit covers all breakpoints | `marketing.scss` |
| F7 | Palette tokens exist and are used by sibling cards: `--paper-strong: #fffdf7`, `--line: rgba(16,33,31,0.16)` | `marketing.scss:4-8` |
| F8 | Light-surface card vocabulary in the same file: `.reasoning-board` `0 30px 90px rgba(16,33,31,.12)` (`marketing.scss:495`), `.catalog-anatomy-sheet` `0 30px 80px rgba(16,33,31,.10)` (`marketing.scss:600`); dark panels use alpha .20–.24. A light card at `.20` alpha is the outlier | `marketing.scss` |
| F9 | `marketing.scss` is loaded only by the marketing layout via `vite_stylesheet_tag 'marketing.scss'`; page has zero own JS (request spec asserts no scripts besides ld+json) | `app/views/layouts/marketing.html.erb:19`; `spec/requests/marketing_homepage_spec.rb:36` |
| F10 | Hero DOM (`.product-proof.hybrid-proof`, `.flow-strip`) lives in `app/views/marketing/home.html.erb:48-115`; no template change needed for this fix | read |
| F11 | `DESIGN_CONTRACT_SHA` is a SHA256 of the meta-neutralized **HTML response body** — and in the test environment that body INCLUDES the Vite stylesheet tag whose URL carries the content hash: `vite_stylesheet_tag` renders `/vite-test/assets/marketing-<8-char base64url>.css` (test `autoBuild: true`, `publicOutputDir: vite-test`), so CSS edits rotate the digest through the asset URL. The fingerprint spec therefore normalizes that URL before hashing (F16) | `app/controllers/marketing_controller.rb:3`; `app/views/layouts/marketing.html.erb:10, 19`; `config/vite.json:11-14`; implementer focused failing run (request specs red solely on the digest mismatch) |
| F12 | Existing marketing specs read `marketing.scss` content directly (source-contract pattern) and recompute WCAG contrast from parsed rules — the natural home for the new assertions | `spec/lib/marketing_controller_spec.rb:23-41, 43-96` |
| F13 | Freemium (variant-a) render is gated by `ENABLE_ACCOUNT_SIGNUP != 'false'`; default is disabled → local screenshots of the freemium Turkish state require the env var set in the local dev runtime | `lib/global_config_service.rb:18-20`; `docs/kozmopath-freemium-quotas.plan.md:50` |
| F14 | Baseline runtime metrics (authoritative, requester-verified): baseline 43-49% frames >16.7ms, 25-30% >33ms; with only `backdrop-filter` disabled: 15-18% >16.7ms, 0% >33ms, max 16.8ms, DoDrawQuad 1306ms→188ms; all-effects-off ≈ filter-off; shadow removal alone halves >33ms only while the filter remains | requester runtime evidence |
| F15 | `.ambient` gradients keep `filter: blur(20px)` (`marketing.scss:112-136`); reduced-motion block untouched (`:1066-1069`); `html { scroll-behavior: smooth }` (`:19`) | read |
| F16 | Implementer proved the request specs fail ONLY because test-env Vite autoBuild embeds the content-hashed marketing CSS URL in the rendered body; with that URL normalized, the digest is stable and CSS-only edits no longer rotate `DESIGN_CONTRACT_SHA` | focused failing run (digest mismatch is the sole failure); `config/vite.json:11-14`; `marketing.html.erb:19` |
| F17 | Analyzer independently approved resolution B: normalize `/vite-test/assets/marketing-<8-char base64url>.css` in `spec/requests/marketing_homepage_spec.rb` (anchored regex + loud include assertion) and re-anchor `DESIGN_CONTRACT_SHA` once to the normalized digest; raw digest rotation per CSS/toolchain change is rejected | analyzer approval (resolution B); implementer failing-run proof; `marketing_homepage_spec.rb:40-47` |

### Assumptions (none HIGH)

| # | Severity | Assumption | Why it is safe / how it is resolved |
|---|----------|-----------|--------------------------------------|
| A1 | LOW | agent-browser `set device "iPhone 14"` maps to 390x844 @3x (devicePixelRatio 3) | iPhone 14 viewport is 390x844 @3x; the gate asserts `devicePixelRatio===3 && innerWidth===390 && innerHeight===844` before measuring and aborts the run otherwise (CDP device-metrics override fallback, same as the baseline harness) |
| A2 | LOW | ImageMagick `magick compare` available for diff artifacts | Diff step is conditional: if `magick` is missing, produce side-by-side PNGs and rely on human review (documented in §7) |
| A3 | LOW | The baseline perf harness may not be preserved | Gate re-creates it per the exact spec in §7 under `/tmp/opencode/marketing-scroll-perf/` (temp, not committed) — same method, same parameters |
| A4 | LOW | Freemium state must be reachable locally for screenshots | Set `ENABLE_ACCOUNT_SIGNUP=true` in the local dev runtime env (AGENTS.md managed runtime); verify `.marketing-home.variant-a` present before capture, else record and fix the runtime state (not the code) |
| A5 | LOW | Contrast math below (4.78/4.92) is correct | Independently enforced by the spec's own contrast computation (`spec/lib/marketing_controller_spec.rb:43-96`); a failure fails the phase gate, never silently accepted |
| A6 | LOW | iOS Safari real-device behavior remains unverified without a physical device | Blur removal strictly reduces rasterization work; real-device check is optional and explicitly marked UNVERIFIED if no device (§7) |
| A7 | LOW | The test-env Vite asset hash stays an 8-char base64url suffix on `marketing-*.css` (observed shape) | If Vite changes hash length/alphabet/path, the loud include assertion fails FIRST and the regex is updated deliberately under the approved procedure — the drift is visible, never a silent no-op |

---

## 4. Goals / Non-Goals

**Goals**
- Eliminate the scroll-jank root cause: remove `backdrop-filter` from both hero panels at every breakpoint.
- Preserve the polished hero hierarchy with existing palette tokens and the file's own card vocabulary (opaque surface + 1px border + restrained shadow).
- Add a selector-scoped source-contract spec and keep all existing marketing specs green.
- Make the fingerprint CSS-stable: normalize the Vite asset URL in the request-spec fingerprint test and re-anchor `DESIGN_CONTRACT_SHA` once to the normalized digest, so CSS content/build-hash churn no longer rotates it while DOM/copy/meta/template/entry-reference changes still do.
- Define deterministic performance, visual, and accessibility gates with exact commands and thresholds.

**Non-goals (explicitly excluded)**
- NO image format/srcset/lazy-load changes — the sweater thumbnails and wordmarks are a separate load optimization, not the jank root cause (image paint was minor in the A/B).
- NO Cloudflare beacon / third-party script changes (no own JS on the page; beacon is outside this fix).
- NO template, copy, locale, asset-config, or layout changes. NO raw `DESIGN_CONTRACT_SHA` rotation per CSS/toolchain change — the ONE approved re-anchor to the normalized-body digest (resolution B) is the only permitted constant change; after it, CSS content/build-hash churn must not rotate the constant. The controller is touched ONLY for that single constant value. The plan document itself stays a planning artifact and is NOT part of the focused implementation commit unless explicitly authorized.
- NO changes to `.anatomy-media figcaption` blur (`marketing.scss:605`), ambient gradients, smooth-scroll, reduced-motion block, focus/hover rules, or any below-hero section styling.
- NO new design-system abstraction, no permanent screenshot framework, no feature flag.
- NO edits to `design-prototypes/` (standalone historical artifact, not a build source).

---

## 5. Options Considered

| Option | Description | Tradeoffs | Verdict |
|--------|-------------|-----------|---------|
| **A. Remove backdrop-filter entirely; opaque surfaces (SELECTED)** | Delete both `backdrop-filter` declarations; replace translucent backgrounds with `var(--paper-strong)`; swap white border → `var(--line)`; reduce shadow alpha .20 → .12 | Fixes the root cause at all breakpoints with 5 declaration edits; matches sibling-card vocabulary; no fallback/dead code; observed behavior (BF_OFF) already proves 0% >33ms. Visual change is a deliberate design decision gated by human review | **Selected** |
| B. Mobile-only override (`@media (max-width:800px)` or `@supports`) | Keep the filter on desktop, remove it only where jank occurs | Leaves the jank source live on desktop (lower-end devices still scroll); duplicate selectors; `@supports` is exactly the fallback/compatibility pattern the user forbade; dead declarations remain | Rejected |
| C. Pre-rendered / static "frost" treatment (gradient or blurred background image mimicking the glass) | Bake the frosted look into a static asset or CSS gradient | Adds asset bytes and a second visual system for two selectors; images are explicitly out of scope; evidence shows no visual need for frost once surfaces are opaque (the panels' content is already full-bleed UI, not text-over-photo) | Rejected |
| D. Keep the filter, reduce radius (16px → 8px) | Smaller blur cost | Any active backdrop-filter on large scroll-surface elements forces re-rasterization per frame on software compositors; only filter-off reached 0% >33ms in the A/B; partial measure, root cause remains | Rejected |
| E. Remove the shadow entirely | Delete `box-shadow` | Flattens the hero's focal card against the ambient gradients; every sibling light card in the file has a shadow; shadow has no perf role once the filter is gone (A/B: filter-off ≈ all-off) — so this would be a speculative visual change, not an evidence-driven one | Rejected (reduce alpha instead) |

---

## 6. Exact Design / CSS Contract

### 6.1 Deletions (`app/javascript/entrypoints/marketing.scss`)

- **Line 207** — remove `backdrop-filter: blur(16px);` from the `.product-proof` rule block (lines 196-209).
- **Line 359** — remove `backdrop-filter: blur(16px);` from the `.flow-strip` rule block (lines 344-364).

*Line numbers in §6.1-6.2 (and the pre-change declaration references in §3 F1-F2, F4-F5) are the pre-edit (HEAD) positions; the current working tree already contains these edits and they are immutable for this task — re-verify, do not re-edit. All other line references in this document reflect the current working tree (two net lines removed → later positions shifted by −2).*

No `-webkit-backdrop-filter` exists anywhere in the file (verified) — nothing else to remove.

### 6.2 Edits (same file)

| Line | Current | Proposed | Rationale |
|------|---------|----------|-----------|
| 203 | `border: 1px solid rgba(255,255,255,.64);` | `border: 1px solid var(--line);` | White border only defined frosted edges; on an opaque `--paper-strong` surface it is invisible. `--line` is the file's card-edge token (`.mobile-menu nav` precedent, `marketing.scss:837`). Visible 1px ink hairline per design contract |
| 205 | `background: rgba(255,253,247,.91);` | `background: var(--paper-strong);` | Opaque replacement; `--paper-strong` (#fffdf7) is the token for light cards (`marketing.scss:490`). No translucency left to blur |
| 206 | `box-shadow: 0 28px 80px rgba(16,33,31,.20);` | `box-shadow: 0 28px 80px rgba(16,33,31,.12);` | Keep geometry, drop alpha to the light-surface vocabulary (.10-.16). Hierarchy: the proof card is the hero's elevated focal layer over ambient gradients and keeps elevation; `.20` alpha belongs to dark panels (`marketing.scss:746`). Pure design decision — shadow has no perf role once the filter is gone |
| 358 | `background: rgba(255,253,247,.76);` | `background: var(--paper-strong);` | Same opaque replacement for the flow strip; it stays flat (no shadow — it is an in-flow bar, and "if everything floats, nothing feels elevated") |

### 6.3 Resulting rule blocks (exact final state)

```scss
.product-proof {
  width: 410px;
  position: absolute;
  z-index: 3;
  right: max(30px, calc((100vw - 1300px) / 2));
  top: 340px;
  overflow: hidden;
  border: 1px solid var(--line);
  border-radius: 24px;
  background: var(--paper-strong);
  box-shadow: 0 28px 80px rgba(16,33,31,.12);
  transform: rotate(2.2deg);
}
```

```scss
.flow-strip {
  width: min(calc(100% - 64px), 1168px);
  min-height: 88px;
  padding: 0 20px;
  position: absolute;
  left: 50%;
  bottom: 18px;
  z-index: 5;
  transform: translateX(-50%);
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  align-items: center;
  border: 1px solid var(--line);
  border-radius: 20px;
  background: var(--paper-strong);
}
```

All other declarations in both blocks and everywhere else in the file are untouched. Both mobile (`:866-902`) and desktop (`:389-432`) overrides inherit the new base values — the fix is breakpoint-agnostic by construction.

### 6.4 Contrast math (WCAG 2.1 AA, normal text ≥ 4.5:1) on the new opaque surface `#fffdf7`

| Text | Color | Ratio on `#fffdf7` | Verdict |
|------|-------|--------------------|---------|
| `.flow-strip span` | `#68746f` | 4.78:1 | PASS |
| `.contact-copy small` | `#66726e` | 4.92:1 | PASS |
| `.connection-state` | `#60706a` | 5.13:1 | PASS |
| `.handoff` | `#566761` | 5.88:1 | PASS |
| `.product-meta span` | `#65726e` | 4.93:1 | PASS |
| `.flow-strip strong` (inherits `--ink` `#10211f`) | — | > 10:1 | PASS |

Opaque panels strictly improve readability over the gradients (no 9-24% translucency left). Buttons/CTAs sit on the hero background (`--paper`), not on the panels — unchanged.

---

## 7. Validation Matrix

### 7.1 Runtime prerequisites (per AGENTS.md + chatwoot-ai-native-test)

1. `scripts/server/...` is NOT involved — this is the local dev runtime: PM2 processes `chatwoot-backend`, `chatwoot-worker`, `chatwoot-vite` started via `.agents/skills/chatwoot-ai-native-test/scripts/with-chatwoot-env.sh` (Vite with `.nvmrc` Node).
2. Readiness: `curl -sSf http://localhost:3000/health` → `{"status":"woot"}`.
3. Freemium state: set `ENABLE_ACCOUNT_SIGNUP=true` in the local env used by the runtime (see `lib/global_config_service.rb:18-20`); verify `agent-browser get count ".marketing-home.variant-a"` → 1 and the freemium announcement text present before screenshots/perf runs. Do NOT touch any server/production config.

### 7.2 Performance gate (agent-browser; the exact baseline methodology)

Harness (reuse the baseline script if preserved; else recreate under `/tmp/opencode/marketing-scroll-perf/harness.mjs`, NOT committed):

```bash
agent-browser --session-name marketing-perf open http://localhost:3000/
# 1) Device metrics: 390x844 @ DPR3 via CDP Emulation.setDeviceMetricsOverride (same override as baseline;
#    agent-browser `set device "iPhone 14"` is the CLI fallback; the harness asserts the environment before measuring)
# 2) Warm cache: full load, wait document.fonts.ready, one reload
# 3) eval --stdin: rAF-stepped programmatic scroll window.scrollTo 0 → 960px over 1500ms (~90 frames);
#    capture per-frame rAF deltas + PerformanceObserver('longtask') + LayoutShift observer
# 4) 3 runs, fresh warm session per run (new tab + reload), JSON summary per run
```

Environment self-check (abort run if false): `devicePixelRatio === 3 && innerWidth === 390 && innerHeight === 844`.

**Gate structure — HARD vs diagnostic targets.** The distinction matters because the baseline BF_OFF evidence itself shows 15-18% of frames >16.7ms and a 16.8ms max on the same headless software compositor: sub-33ms jitter persists even in the good state, and software compositing adds run-to-run variance. Thresholds therefore split:

| Metric | Baseline (authoritative BF_OFF) | Post-change gate |
|--------|---------------------------------|------------------|
| **HARD — any failure blocks the phase and returns to Phase 1** | | |
| Frames > 33ms (each of 3 runs) | 0% | **0** |
| Long tasks > 50ms | 0 | **0** |
| Layout shifts during scroll | 0 | **CLS = 0** |
| Environment self-check (DPR3, 390x844) | — | **true** (run invalid otherwise, rerun — not a result) |
| No horizontal overflow (`scrollWidth <= innerWidth`) | — | **true** |
| **TARGETS — diagnostic; bounded-variance policy below** | | |
| Frames > 16.7ms | 15-18% | ≤ 20% |
| p95 frame time | ≤ 16.8ms (max observed) | ≤ 16.8ms |
| Max frame time | 16.8ms | ≤ 20ms (headless variance allowance; hard cap < 33ms) |

**Bounded-variance policy (targets):** targets are diagnostic signals, not standalone pass/fail switches. If a target misses while (a) the hard gate passes and (b) trace attribution is materially improved vs the recorded baseline (e.g., `SoftwareRenderer::DoDrawQuad` composite time at or near the BF_OFF level, ~188ms vs 1306ms), the validation phase must NOT fail silently and thresholds must NOT be relaxed to make the run pass. Instead, route the 3-run JSON + compositor trace to @analyzer, who examines run-to-run spread (a p95 spread >1ms across runs flags variance), environment drift, and the trace. Analyzer outcome (recorded in the decision log, §14): (1) accept with documented rationale, (2) re-run after variance stabilization, or (3) return to Phase 1 with a specific CSS adjustment. Threshold values change only through a recorded decision — never to convert a failing run into a pass. A hard-gate failure is unambiguous: the phase is incomplete and the root cause remains; return to Phase 1 with the failure data.

Report the per-run JSON to `/tmp/opencode/marketing-scroll-perf/perf-post.json` and compare against the recorded baseline (`perf-baseline.json`, captured in Phase 1 Task 0, and the authoritative A/B in §3 F14).

### 7.3 Visual acceptance (temporary artifacts; human review; NO permanent framework)

Capture order: **baseline artifacts are captured on the pre-change page (Phase 1 Task 0; already present under `/tmp/opencode/marketing-scroll-perf/baseline/` — reuse)**; post-change captures happen in the validation phase (Phase 2). The authoritative A/B numbers in §3 F14 remain the primary comparison reference. Artifacts in `/tmp/opencode/marketing-scroll-perf/{baseline,current,diff}/`:

```bash
# Mobile, normal motion, freemium Turkish: scrollY 0 and scrollY 960 (first section boundary)
agent-browser --session-name marketing-shot set device "iPhone 14"
agent-browser screenshot /tmp/opencode/marketing-scroll-perf/baseline/mobile-hero.png        # scrollY 0
agent-browser eval --stdin <<'EOF'   # window.scrollTo(0, 960); await new Promise(r => setTimeout(r, 300))
EOF
agent-browser screenshot /tmp/opencode/marketing-scroll-perf/baseline/mobile-first-section.png
# Repeat with: agent-browser set media light reduced-motion   (static page; diff vs normal must be ~nil)
# Desktop: agent-browser set viewport 1440 900 → same two positions
```

Diff (only if `magick` is installed; otherwise side-by-side review):

```bash
magick compare -metric AE baseline/mobile-hero.png current/mobile-hero.png diff/mobile-hero.png
```

**Human review checklist (owner: requester/maintainer; implementer provides artifacts):**
- [ ] Panels read as solid cards; no visible translucency "noise" where gradients pass behind.
- [ ] Text, toolbar, disclosure, and CTA legibility unchanged; hierarchy: proof card > strip > copy preserved.
- [ ] No horizontal overflow (`document.documentElement.scrollWidth <= innerWidth` at both viewports); no layout shift between the two capture positions.
- [ ] Desktop 1440x900: rotated proof card, border, and shadow look native (not heavier/lighter than `.reasoning-board`).
- [ ] Reduced-motion captures match normal-motion captures in composition.
- [ ] Below-fold figcaption blur (`marketing.scss:605`) visually unchanged (sanity, scroll to catalog section if desired).

### 7.4 Accessibility checks

| Check | Method | Pass |
|-------|--------|------|
| Contrast on new surfaces | Spec computation (`spec/lib/marketing_controller_spec.rb:43-96`, updated pairs) + §6.4 table | ≥ 4.5:1 |
| Text/CTA over gradients | Opaque panels (no translucency remains) + screenshot review | no legibility regression |
| Focus/hover states | No rule touched (`marketing.scss:80-98`); `agent-browser snapshot -i` shows all links/buttons | unchanged |
| Semantic structure / landmarks | Existing request-spec assertions (`marketing_homepage_spec.rb:122-129`) | green |
| Overflow / layout shifts | `scrollWidth` check + CLS observer in perf harness | no overflow; CLS 0 |
| Reduced motion | `agent-browser set media light reduced-motion` capture; `marketing.scss:1066-1069` untouched | unchanged behavior |

### 7.5 Optional real-device check (UNVERIFIED without a device)

If an iPhone (Safari, ~390x844) is available: quick manual scroll of the hero with and without `Reduce Motion`; look for dropped frames/artifacts. **If no device is available, this cell is reported UNVERIFIED — it is not a blocker** (blur removal strictly reduces rasterization work on every engine).

---

## 8. Invariants and Behavior That Must Not Change

| Invariant | Why | Verification |
|-----------|-----|--------------|
| Hero DOM and copy in `home.html.erb:48-115` unchanged | Body digest contract + Turkish freemium copy tests | Request spec green; `git diff` shows no template change |
| `DESIGN_CONTRACT_SHA` re-anchored ONCE to the normalized digest | The fingerprint spec hashes the meta- AND asset-URL-neutralized HTML response body (`marketing_homepage_spec.rb:40-47`); after the one-time re-anchor, CSS content/build-hash churn does not rotate it, while DOM/copy/meta/template/entry-reference changes still do | Both fingerprint tests green after the re-anchor; `git diff` shows exactly one constant-value change |
| `.anatomy-media figcaption` keeps `backdrop-filter: blur(10px)` | Below-fold, not in the scroll-jank path; the spec asserts it stays | Source-contract spec |
| Ambient gradients + `.ambient` `blur(20px)` kept | A/B showed marginal/inconsistent impact; brand depth; static elements rasterize once | `marketing.scss:112-136` untouched; diff check |
| `html { scroll-behavior: smooth }` and reduced-motion block kept | Ruled out as jank cause; separate concern | `marketing.scss:19, 1066-1069` untouched |
| Selector names, DOM attributes, aria labels, i18n keys unchanged | Request/layout/copy specs; the freemium selector-rename plan (`docs/kozmopath-freemium-quotas.plan.md`) remains its own future scope | `git diff` review |
| Product-proof rotation (`rotate(2.2deg)` / mobile `none`), overflow clipping, radius values unchanged | Visual contract | Screenshot review |

---

## 9. Blast Radius / Files / Enterprise Check

**Files that change (exactly four — Phase 1 atomic unit):**
| File | Change |
|------|--------|
| `app/javascript/entrypoints/marketing.scss` | 2 deletions (backdrop-filter lines 207, 359) + 4 declaration edits (lines 203, 205, 206, 358) — already applied in the working tree (immutable) |
| `spec/lib/marketing_controller_spec.rb` | 1 new `it` block (hero-panel blur contract) + 2 contrast-pair background updates — already applied (immutable) |
| `spec/requests/marketing_homepage_spec.rb` | Fingerprint test (lines 40-47) gains asset-URL normalization (anchored 8-char base64url regex → fixed token) + loud include assertion; digest computed over the meta- and URL-neutralized body |
| `app/controllers/marketing_controller.rb` | One-time `DESIGN_CONTRACT_SHA` re-anchor to the normalized digest (line 3) — the only permitted constant change |

Phase mapping: **Phase 1** changes exactly these four files (the atomic commit unit). **Phase 2** (validation) changes zero files. **Phase 3** (rollout) commits the Phase 1 diff as one focused commit — the four code files only; the plan document stays an untracked planning artifact and is NOT part of the commit unless explicitly authorized.

**Affected entry points / callers:**
- Marketing layout (`app/views/layouts/marketing.html.erb:19`) serves the SCSS via Vite; the only consumer of these classes is `home.html.erb:70-114` (`product-proof hybrid-proof`, `flow-strip`). No other page or layout loads `marketing.scss` (verified).
- Test-env Vite autoBuild (`config/vite.json:11-14`, `publicOutputDir: vite-test`) injects the content-hashed CSS URL into the rendered body — the fingerprint normalization must stay matched to that exact URL shape (loud assertion guards drift; F16-F17).
- Fingerprint contract: `DESIGN_CONTRACT_SHA` (`marketing_controller.rb:3`) is rendered into the layout meta tag (`marketing.html.erb:10`) and asserted by the request-spec fingerprint tests (`marketing_homepage_spec.rb:33, 40-47`); the re-anchor changes the meta value AND the constant together — the two fingerprint tests remain the contract's enforcement point.
- Production runtime (home server): CSS ships inside Vite-compiled assets → rollout includes an asset precompile (AGENTS.md home-server sequence: locked deps + precompile with `.nvmrc` Node + backup + `db:chatwoot_prepare` + `scripts/server/reload-pm2.sh`). Rollback = revert commit + rebuild assets.
- Design-prototypes mirror (`marketing-base.css`) is **not** a build input (linked only by prototype HTML and `tests/verify-contract.mjs`); intentionally left untouched — out of scope by the clean-replacement directive (no parallel system, no drift fix-up).

**Enterprise check:** `rg -n -i marketing enterprise/` shows only account-attribution/analytics code (e.g., `MarketingAttributionService`, conversion-tracking job) — no overlay touches `MarketingController`, the marketing layout, or `marketing.scss`. No `prepend_mod_with` needed. OSS-only change.

---

## 10. Implementation Plan (one phase at a time)

**Atomicity rule (why the CSS, both spec contracts, and the re-anchor are one unit):** the new source-contract assertions (no `backdrop-filter` in the `.product-proof`/`.flow-strip` rule blocks) fail against the pre-change stylesheet by design — they are the regression net for this exact bug. Independently, the request-spec fingerprint tests fail with the CSS edit ALONE: test-env Vite autoBuild embeds the content-hashed marketing CSS URL in the rendered body, so the digest rotates until the asset URL is normalized and `DESIGN_CONTRACT_SHA` is re-anchored (F16-F17). Splitting these across phases would create intentionally red intermediate states, violating the independent-green gate. The CSS replacement, the source-contract spec, the fingerprint normalization, and the one-time re-anchor therefore land together in Phase 1, and the repo is fully green at the end of that phase. Phase 2 is validation-only (zero source edits); Phase 3 is the operational rollout. **No phase is marked complete until its gate passes.**

### Phase 1 — Atomic implementation: CSS replacement + spec contracts + fingerprint re-anchor

- **Owner:** @implementer (frontend/SCSS + backend specs)
- **Dependencies:** none
- **Complexity:** LOW
- **Allowed files (exactly four):** `app/javascript/entrypoints/marketing.scss`, `spec/lib/marketing_controller_spec.rb`, `spec/requests/marketing_homepage_spec.rb`, `app/controllers/marketing_controller.rb` (the controller ONLY for the single constant re-anchor; the request spec ONLY for the normalization + loud assertion). Task 0 is runtime capture only (writes temp artifacts under `/tmp/opencode/marketing-scroll-perf/`, edits no source file).

**Tasks**
- [ ] 0.1 **Baseline capture (runtime-only, pre-change page):** §7.3 baseline screenshots (390x844 DPR3 + 1440x900, normal + reduced motion, freemium Turkish, scrollY 0 and 960) and one baseline perf run (identical harness) into `/tmp/opencode/marketing-scroll-perf/baseline/` + `perf-baseline.json`. Baseline artifacts are ALREADY captured (present under `/tmp/opencode/marketing-scroll-perf/` — reuse them; recapture only if they are missing or predate the verified pre-change state). These artifacts anchor the A/B diff and the §7.2 variance policy; the authoritative numbers in §3 F14 are the primary reference.
- [ ] 1.1-1.6 **CSS edits (already applied in the working tree — verify only, do not re-edit):** delete `backdrop-filter: blur(16px);` at lines 207/359 and apply the four declaration edits (203, 205, 206, 358) per §6.2. `git diff app/javascript/entrypoints/marketing.scss` must match §6.2 exactly.
- [ ] 1.7 Verify with `rg -n "backdrop-filter" app/javascript/entrypoints/marketing.scss` → exactly one hit (line 605, figcaption). Verify `rg -n "rgba\(255,253,247,\.(76|91)\)" app/javascript/entrypoints/marketing.scss` → zero hits.
- [ ] 1.8 Add the selector-scoped source-contract `it` block ("keeps hero panels free of backdrop-filter while the below-fold figcaption keeps its blur") using the file's existing rule-scan pattern (`spec/lib/marketing_controller_spec.rb:81`): the `.product-proof` and `.flow-strip` declaration blocks contain no `backdrop-filter` and contain `background: var(--paper-strong)`; the `.anatomy-media figcaption` block retains `backdrop-filter: blur(10px)`. Deliberately NOT a global `backdrop-filter` ban — the figcaption legitimately keeps it. (Already applied in the working tree — verify only, do not re-edit.)
- [ ] 1.9 Update the two affected contrast-pair entries to the exact new effective background `#fffdf7` (`marketing.scss:4`): `.contact-copy small` (`#fefcf6` → `#fffdf7`, ratio 4.92) and `.flow-strip span` (`#fcfaf3` → `#fffdf7`, ratio 4.78). All other pairs untouched. (Already applied — verify only, do not re-edit.)
- [ ] 1.10 **Fingerprint normalization (spec/requests/marketing_homepage_spec.rb:40-47):** in the "keeps the design contract fingerprint stable" `it` block, add a LOUD assertion that the raw body actually contains the hashed asset URL — `expect(response.body).to match(%r{/vite-test/assets/marketing-[A-Za-z0-9_-]{8}\.css})` — then neutralize that URL with the same anchored regex (replace with a fixed token, e.g. `/vite-test/assets/marketing-normalized.css`). The loud assertion guarantees a Vite shape change (hash length/alphabet/path) fails the test instead of silently normalizing nothing. Digest is then computed over the meta- AND URL-neutralized body.
- [ ] 1.11 **Obtain the normalized digest (focused failing run):** run `bundle exec rspec spec/requests/marketing_homepage_spec.rb` — the fingerprint test is EXPECTED to fail with `expected: <old constant> ... got: <new digest>`; the ACTUAL digest printed in the failure diff is the new normalized-body digest. Record it. (The test is red here by design — the atomicity check.)
- [ ] 1.12 **One-time re-anchor:** set `MarketingController::DESIGN_CONTRACT_SHA` (`app/controllers/marketing_controller.rb:3`) to the recorded normalized digest. This is the ONLY permitted change to the constant; do not rotate it for individual CSS/toolchain changes afterwards (resolution B; §14).
- [ ] 1.13 **Rerun green (atomicity check):** `bundle exec rspec spec/lib/marketing_controller_spec.rb spec/requests/marketing_homepage_spec.rb` → all green, including the source-contract assertions, the loud asset-URL assertion, and both fingerprint tests (for both marketing hosts via the shared examples).
- [ ] 1.14 Lint gate: `bundle exec rubocop spec/lib/marketing_controller_spec.rb spec/requests/marketing_homepage_spec.rb` → clean (controller not linted: single-constant-value edit; run RuboCop on it only if the repo's focused check surfaces an issue — not a speculative gate).
- [ ] 1.15 `git diff --stat` shows exactly the four allowed code files (no template, layout, locale, or asset-config changes; plan doc stays untracked).

**Success gate (all required — phase not complete otherwise)**
- [ ] New source-contract assertions pass against the Phase 1 stylesheet (they fail against the pre-change file by design — the atomicity check).
- [ ] All existing marketing specs green (targeted RSpec run) and RuboCop clean on both changed spec files.
- [ ] `rg` proofs from 1.7 hold; diff limited to the four allowed files; `DESIGN_CONTRACT_SHA` re-anchored exactly once to the normalized digest (loud asset-URL assertion active; no raw per-CSS rotation).

**Rollback (Phase 1):** revert the working-tree change — no data, no migration, no cache invalidation beyond Vite rebuild. Do not ship or commit Phase 1 without its full contract (CSS + both specs + normalization + re-anchor — one unit).

### Phase 2 — Validation only (no source edits)

- **Owner:** @implementer (verification) + @analyzer (variance review on target miss, per §7.2)
- **Dependencies:** Phase 1 complete and green
- **Complexity:** LOW
- **Allowed files: none** — zero source edits of any kind. Only runtime capture and temporary artifacts under `/tmp/opencode/marketing-scroll-perf/`.

**Tasks**
- [ ] 2.1 Performance rerun (A/B-equivalent): §7.2 harness against the Phase 1 page, 3 runs with environment self-check; per-run JSON to `perf-post.json`; compare against the §3 F14 A/B and the Task 0.1 baseline artifacts. Record compositor trace attribution (`SoftwareRenderer::DoDrawQuad` time) for the §7.2 variance policy.
- [ ] 2.2 Post-change screenshots into `current/` and diffs vs `baseline/` (ImageMagick if installed, else side-by-side) per §7.3.
- [ ] 2.3 Human review checklist (§7.3): mobile + desktop + reduced-motion composition, legibility, no overflow; accessibility spot-checks (§7.4: `agent-browser snapshot -i` for focus/hover targets, `scrollWidth` check, contrast already locked by the Phase 1 spec).
- [ ] 2.4 Optional real-device Safari check (§7.5) — reported UNVERIFIED if no device is available; not a blocker.
- [ ] 2.5 Artifact cleanup and session close (§13): close `--session-name marketing-perf` / `--session-name marketing-shot`; report the metrics table, screenshot matrix, and review verdicts.

**Success gate (phase not complete until thresholds pass or the analyzer decision is recorded)**
- [ ] **HARD (any failure ⇒ phase incomplete; return to Phase 1 with the failure data — root cause remains):** 0 frames >33ms in every run; 0 long tasks >50ms; CLS 0; environment self-check true; no horizontal overflow.
- [ ] **TARGETS:** p95 ≤ 16.8ms; max ≤ 20ms; ≤ 20% frames >16.7ms. A target miss with the hard gate passing and materially improved trace attribution (DoDrawQuad ≈ BF_OFF level, ~188ms vs 1306ms) routes to @analyzer under the §7.2 bounded-variance policy — never a silent failure, never a silent threshold relaxation.
- [ ] Human review approves the screenshots (visual + reduced-motion + desktop + a11y legibility).

**Rollback (Phase 2):** not applicable — zero source edits; rollback is cleaning up temp artifacts and closing sessions.

### Phase 3 — Rollout (operational step, NOT an implementer source-edit phase)

- **Owner:** coordinator / release operator (AGENTS.md release path)
- **Dependencies:** Phase 1 + Phase 2 complete (all gates passed or analyzer decision recorded)
- **Complexity:** LOW (operational)
- **Allowed changes:** none to source; the commit contains exactly the Phase 1 diff.

**Steps**
- [ ] 3.1 One focused commit: `fix(marketing): remove hero backdrop-filter for mobile scroll performance` containing exactly the four Phase 1 code files (Conventional Commits per AGENTS.md; no AI-tool mentions). If working-tree steps were committed separately, squash to this single commit. The plan document stays untracked and is NOT part of this commit unless explicitly authorized.
- [ ] 3.2 Release path (home server): install locked deps → precompile assets with `.nvmrc` Node → backup + `db:chatwoot_prepare` (unchanged procedure; no migrations) → `scripts/server/reload-pm2.sh` (AGENTS.md).
- [ ] 3.3 Post-deploy smoke: readiness probes (health + 9090/9091 per AGENTS.md), then the §7.2 perf rerun against the deployed page (hard gate), plus public smoke of the marketing page (HTTP 200, variant-a state, no console errors).
- [ ] 3.4 **Rollback:** `git revert` the single commit + rebuild assets + reload PM2. No flag, no compatibility selector — see §12.

**Success:** deploy healthy; post-deploy perf rerun passes the hard gate.

---

## 11. Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Human reviewer rejects the new panel look (border/shadow/opacity) | MEDIUM | LOW (cosmetic; revert trivial) | Human review is the Phase 2 gate; fallback decisions documented (§6.2) — e.g., border could move to `rgba(16,33,31,.13)` (`.reasoning-board`) or shadow to `0 30px 90px rgba(16,33,31,.12)` if the alpha-only change reads unexpectedly; any adjustment returns to Phase 1 and must stay in the existing vocabulary |
| Perf target variance in headless (p95/max overshoot) | MEDIUM | LOW | 3-run protocol, environment self-check (DPR/dimensions), hard-vs-target split (§7.2): hard gate (0 frames >33ms, long tasks, CLS) is unambiguous; target misses with material trace improvement route to @analyzer under the bounded-variance policy — never silent failure, never silent relaxation |
| Contrast spec fails after pair update | LOW | LOW | My computed ratios (4.78/4.92) exceed 4.5 with margin; spec recomputes independently; never raise the threshold — fix colors instead |
| iOS Safari real-device difference | LOW (perf) / MEDIUM (visual) | LOW | Removing blur strictly reduces rasterization; visual state covered by headless review; real-device cell marked UNVERIFIED if no device |
| Stale Vite cache serving old CSS during verification | MEDIUM | LOW | Hard-reload / fresh session per run; dev Vite recompiles on save; production smoke uses precompiled assets |
| Fingerprint normalization drift (Vite hash shape changes, e.g. longer/shorter hash) | LOW | LOW | Loud anchored assertion in the fingerprint test fails FIRST, flagging the shape change; regex updated deliberately under the approved procedure (F17, A7) — never a silent no-op |
| Wrong digest pasted during re-anchor | LOW | LOW | The digest comes from the focused failing run's diff (task 1.11); task 1.13 reruns the full focused suite green before the phase gate |
| Spec brittleness (global ban temptation) | LOW | LOW | Explicit selector-scoped assertions; figcaption exception asserted positively |
| Accidental scope creep (images, beacon, template) | LOW | LOW | Non-goals §4; allowed-files list per phase; `git diff` review |

## 12. Breaking-Change / No-Fallback / Dead-Code Statement

This plan **deliberately breaks** the previous frosted-glass appearance of the two hero panels and removes the declarations outright:

- `backdrop-filter` is deleted, not hidden behind `@supports` or a mobile media query. There is no fallback CSS, no duplicate selectors, no prefixed variant (none existed), no "legacy" path retained anywhere.
- Translucent background declarations are replaced in place (no dead `rgba(...)` lines, no commented-out originals).
- The design-prototypes mirror is intentionally NOT synced: it is a historical prototype artifact, not a build source, and the clean-replacement directive forbids parallel drift-fix systems.
- **Deviation from generic feature-flag guidance, explained:** a flag or `@supports` wrapper would preserve dead code paths and the old behavior — which the requester explicitly forbade ("Breaking changes are allowed; do not preserve old behavior through compatibility layers, fallback CSS, duplicate selectors, dead code"). A flag is also unnecessary here: this is a source-only change (CSS + specs + one constant) with no data migration, no API contract, and a trivial revert path, so the safety a flag would buy is already provided by git revert + asset rebuild. The only `DESIGN_CONTRACT_SHA` impact is the single approved re-anchor to the normalized-body digest (resolution B) — no raw per-CSS rotation, no DOM impact, no rollout-ordering constraints.

## 13. Cleanup / Artifacts

- Temporary artifacts under `/tmp/opencode/marketing-scroll-perf/` (`baseline/`, `current/`, `diff/`, `perf-baseline.json`, `perf-post.json`, optional `harness.mjs`) — captured in Phase 1 Task 0 and Phase 2; removed after Phase 2 approval (Task 2.5) unless the requester asks to keep them; nothing committed to the repo.
- Close the agent-browser sessions (`--session-name marketing-perf`, `--session-name marketing-shot`) during Phase 2 cleanup; leave the PM2 dev processes in the state they were found (AGENTS.md).
- No temporary code, no debug instrumentation, no spec stubs left behind.

## 14. Decision Log

| Decision | Chosen | Rejected | Rationale | Evidence |
|----------|--------|----------|-----------|----------|
| Blur handling | Delete both `backdrop-filter` declarations entirely | `@supports` / mobile-only override | Root-cause elimination at all breakpoints; user forbids fallbacks; only filter-off reached 0% >33ms | F14; `marketing.scss:207,359` |
| Panel surface | Opaque `var(--paper-strong)` | Keep translucency (any %) | No blur left to justify translucency; token + sibling-card precedent; improves readability over gradients | F7-F8; `marketing.scss:205,358` |
| Border | `var(--line)` (ink hairline) | Keep white border | White border was frosted-edge definition; invisible on opaque surface; `--line` is the card-edge token | F5; `marketing.scss:203` |
| Shadow | `0 28px 80px rgba(16,33,31,.12)` (alpha-only) | Remove entirely / keep .20 | Hierarchy: focal card keeps elevation; .20 alpha is dark-panel vocabulary; no perf role after filter removal | F8, F14; `marketing.scss:206` |
| Spec strategy | Selector-scoped contract in existing spec file | New spec file / global backdrop-filter ban | Existing pattern (`marketing_controller_spec.rb:23-41`); figcaption exception needs positive assertion | F12; `marketing.scss:605` |
| Phase atomicity | CSS + source-contract spec + fingerprint normalization + one-time re-anchor in ONE implementation phase (four files) | CSS-first/spec-second phases; normalization deferred to a later phase | The source-contract assertions AND the fingerprint tests are red against the pre-change stylesheet by design (F16); splitting phases creates intentionally red intermediate states violating the independent-green gate | F12, F16-F17; `marketing.scss:207,359`; `config/vite.json:11-14` |
| Threshold policy | HARD (0 >33ms, long tasks, CLS) vs diagnostic targets (p95/max/%>16.7) with analyzer review | All-or-nothing pass / silent relaxation | BF_OFF evidence shows sub-33ms jitter persists even in the good state; headless software-compositor variance must not produce arbitrary failure | F14; §7.2 |
| Validation phase | Source-edit-free validation phase (zero file changes) with explicit not-complete-until-thresholds gate | Validation folded into implementation phases | Keeps implementation atomic and reviewable; makes completion criteria unambiguous | §10 |
| `DESIGN_CONTRACT_SHA` | One-time re-anchor to the normalized-body digest (Analyzer resolution B); after that, CSS content/build-hash churn does NOT rotate it — DOM/copy/meta/template/entry-reference changes still do | Raw rotation per CSS/toolchain change; leaving the constant stale against the hashed asset URL (specs stay red) | Test-env Vite autoBuild embeds the content-hashed CSS URL in the rendered body, so CSS edits rotate the digest; normalizing the URL restores a stable, still-load-bearing fingerprint | F11, F16-F17; `config/vite.json:11-14`; implementer failing run; analyzer approval |
| Asset URL normalization | Anchored `marketing-[A-Za-z0-9_-]{8}.css` regex + loud include assertion in the fingerprint test (`marketing_homepage_spec.rb:40-47`) | Broad/unanchored gsub; manifest-based extraction; dropping the fingerprint test | Minimal, targeted neutralization; the loud assertion turns Vite shape drift into a visible failure instead of a silent no-op; keeps digest coverage of DOM/copy/meta/template/entry-reference | F16-F17; A7 |
| Prototype mirror | Untouched | Syncing the change | Not a build input; scope discipline | verified link graph |

---

*Plan file: `docs/marketing-mobile-scroll-performance.plan.md` — status READY (amended: Vite asset-hash fingerprint resolution). Phase 1 is the single atomic implementation unit (CSS + source-contract spec + fingerprint normalization + one-time `DESIGN_CONTRACT_SHA` re-anchor, four code files, fully green on completion); Phase 2 is validation-only (zero source edits, not complete until thresholds pass or the analyzer decision is recorded); Phase 3 is the operational rollout step. Phases execute strictly one at a time.*
