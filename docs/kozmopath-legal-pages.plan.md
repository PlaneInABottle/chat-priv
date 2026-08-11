# Kozmopath Privacy Policy & Terms of Service Pages — Implementation Plan

## Problem Statement

`https://www.kozmopath.com/terms-of-service` and `/privacy-policy` are already referenced as absolute URLs by the signup flow (`config/installation_config.yml:46,50`, en/tr `signup.json` `TERMS_ACCEPT`, `Signup/Form.vue:55-65`), but no server-rendered pages exist at those paths on the marketing hosts (`config/routes.rb:17-24`). Visitors clicking the links today get a dashboard 404. This plan implements both pages on the existing Rails marketing surface (host-constrained `MarketingController`, `layout 'marketing'`, Turkish locale, Rails en/tr source parity), with per-page canonical/meta/JSON-LD, sitemap coverage, homepage footer links, and focused specs — using only verified product facts and the coordinator's explicit MVP decisions, without inventing legal/business facts.

## Approach

KISS/DRY server-rendered ERB on the existing marketing stack: two routes + two controller actions that set per-page metadata instance variables (layout falls back to homepage constants so homepage bytes stay identical), one locale-driven section-rendering partial shared by both legal views, one extracted footer partial shared by homepage and legal pages (homepage footer gains the two legal links), appended SCSS rules in the existing `marketing.scss` entrypoint, and one new request spec plus additive updates to the three existing marketing specs. No new models, no migrations, no JS, no consent machinery. The homepage design-contract fingerprint is re-anchored exactly once, using the repo's established failing-run protocol.

## Success Criteria

- [ ] `GET /privacy-policy` and `GET /terms-of-service` return 200 Turkish SSR pages on `kozmopath.com`, `www.kozmopath.com`, and `marketing.localhost` (test env); 404 on `app.kozmopath.com`
- [ ] Each page emits its own canonical, og:url, og:title/description, `<title>`, description, `index,follow` robots, and `WebPage` JSON-LD with `isPartOf` WebSite; homepage canonical/og/JSON-LD bytes unchanged
- [ ] Homepage footer renders links to both legal pages; sitemap.xml lists exactly 3 URLs (home, privacy, terms)
- [ ] Existing signup URLs continue to resolve (pages exist at the already-configured absolute URLs; `Signup/Form.vue` and `signup.json` untouched)
- [ ] `marketing.legal.*` en/tr key sets are identical (existing flatten parity spec covers automatically) and no page body contains "Translation missing"
- [ ] Privacy page renders exactly 13 iterable sections plus one final contact section; terms page exactly 17 plus one final contact section; per page exactly one `*-contact` section id and exactly one `mailto:support@kozmopath.com` link
- [ ] All marketing specs green, RuboCop clean on changed Ruby, browser evidence at 1440×900 and 390×844 on `marketing.localhost`
- [ ] `git diff --check` clean; one conventional commit `feat(marketing): add Kozmopath privacy policy and terms of service pages`

---

## Verified Facts vs Assumptions

| Item | Verified at | Evidence / Note |
|------|------------|-----------------|
| Marketing host constraints block | `config/routes.rb:17-24` | `%w[kozmopath.com www.kozmopath.com]` + `marketing.localhost` when not production; root `marketing#home`, `marketing#sitemap` |
| `MarketingController::CANONICAL_URL` / `DESIGN_CONTRACT_SHA` | `app/controllers/marketing_controller.rb:2-3` | Homepage canonical `https://www.kozmopath.com/`; SHA `c0c363...` |
| Layout head hardcodes homepage meta | `app/views/layouts/marketing.html.erb:8-20` | robots, description, og:*, canonical, title all from `marketing.meta.*` / constants; `@structured_data.to_json` rendered unconditionally at line 20 (legal actions must set it non-nil) |
| Sitemap contains only homepage | `app/views/marketing/sitemap.xml.erb:3-5`; asserted `spec/requests/marketing_homepage_spec.rb:211-222` | 1 URL; spec expects exactly `['https://www.kozmopath.com/']` |
| Homepage footer has no legal links; brand href `#hero` | `app/views/marketing/home.html.erb:389-401` | Footer inline; `.site-footer` styles at `marketing.scss:772-777`, mobile grid `:1036-1037` |
| Signup terms/privacy URLs configured | `config/installation_config.yml:45-52` | `TERMS_URL` = `https://www.kozmopath.com/terms-of-service`, `PRIVACY_URL` = `https://www.kozmopath.com/privacy-policy` |
| Signup Form replacement logic + spec contract | `app/javascript/v3/views/auth/signup/components/Signup/Form.vue:55-65`; `Form.spec.js:65-66,127-128,160-163` | `t('REGISTER.TERMS_ACCEPT')` replaces kozmopath URLs with `globalConfig.termsURL/privacyURL`; spec asserts final hrefs — untouched by this plan |
| en/tr signup acceptance strings | `app/javascript/dashboard/i18n/locale/en/signup.json:48`, `tr/signup.json:48` | `TERMS_ACCEPT` contains both kozmopath URLs |
| Support email default | `app/controllers/public_controller.rb:22-24`; `config/installation_config.yml:105` | `MAILER_SUPPORT_EMAIL` blank default → `support@kozmopath.com` |
| `GlobalConfigService.load` semantics | `lib/global_config_service.rb:2-16` | DB/ENV fallback to default; blank `MAILER_SUPPORT_EMAIL` yields the default in tests |
| Locale parity spec (flattens `marketing` subtree) | `spec/lib/marketing_controller_spec.rb:131-143` | New `marketing.legal.*` keys are covered automatically |
| I18n translation hash key shape | Repo-native probe 2026-08-12: `rbenv exec bundle exec rails runner` (read-only; key classes only, no values/secrets printed) — i18n 1.14.7, Rails 7.2.3.2 | `I18n.t('marketing', locale: :tr)` → plain `Hash` with **Symbol** keys (`:meta`); `I18n.t('marketing.controls.items', locale: :tr)` → Symbol keys (`:catalog`); section values Symbol-keyed (`:title`); leaf string lookups unaffected. `_legal_sections` and the request spec MUST use Symbol accessors (`section.fetch(:title)`, `section[:body]`, `section[:items]`) and Symbol-safe interpolation (`"#{prefix}-#{key}"` stringifies both key types predictably) |
| Digest neutralization method | `spec/requests/marketing_homepage_spec.rb:40-49` | gsub vite CSS asset + contract meta → SHA256; re-anchor protocol documented in `docs/marketing-mobile-scroll-performance.plan.md:311-314` (focused failing run → record actual digest → update constant → rerun green) |
| No Enterprise overlay for MarketingController | `rg -n "MarketingController" enterprise/` (no match) | OSS-only surface; no `prepend_mod_with` needed |
| Route-name collisions for `marketing_privacy_policy` / `marketing_terms_of_service` | Full read of `config/routes.rb` | No existing `privacy`/`terms` routes |
| Dev host authorization allows `marketing.localhost` | `config/environments/development.rb:63-64` (`config.hosts = nil`) | Host check disabled in dev |
| No `raise_on_missing_translations` | `config/environments/test.rb:52`, `development.rb:57` (commented) | Missing keys render as "Translation missing" text; specs assert absence |
| Marketing spec group duration | Probing run 2026-08-12: `rbenv exec bundle exec rspec spec/routing/marketing_routing_spec.rb spec/requests/marketing_homepage_spec.rb spec/lib/marketing_controller_spec.rb` → 43 examples, 0 failures, 38.65 s test time, 43.66 s wall | n=1 observation (baseline, pre-change) |
| Infra/runtime state | `docker compose ps` (postgres+redis healthy), `pm2 list` (`chatwoot-backend/worker/vite` online) | Reuse for M3 browser evidence |
| **DECISION** provider/controller name `Kozmopath`, contact `support@kozmopath.com` | Coordinator decision | Not a repo fact; legal copy uses these |
| **DECISION** governing law Türkiye without inventing city/court; "competent courts under applicable law" | Coordinator decision | En/tr copy per this wording |
| **DECISION** coverage: account, contacts/conversations, catalog/integrations, AI/tool usage, technical logs, optional Voice recordings/transcripts | Coordinator decision | Privacy "data we process" section mandates |
| **DECISION** effective/last-updated date 12 August 2026 (`12 Ağustos 2026` tr) | Coordinator decision | `marketing.legal.updated_on` |
| **DECISION** pages indexable, included in sitemap | Coordinator decision | robots `index,follow` (existing layout default), sitemap URLs |
| ⚠️ ASSUMED (LOW) `*.localhost` resolves to loopback in the M3 browser session | macOS/Chrome standard behavior | Not yet observed in this task; if it fails, use `curl -H 'Host: marketing.localhost'` fallback evidence |
| ⚠️ ASSUMED (LOW) Agent-browser profile / PM2 runtime remain available at M3 | Tooling-level | Runtime already online today; restart only task-owned processes |

**Zero CRITICAL/HIGH items remain ASSUMED.** All content, routing, metadata, and contract facts are verified above; the only assumptions are LOW tooling/environment ones.

---

## Milestone 1: Marketing plumbing — routes, controller metadata, layout, sitemap, homepage footer

**Owner**: @implementer (fullstack)
**Dependencies**: None (base commit `b79b3bb321`, clean tree)
**Complexity**: MEDIUM
**Milestone Gate**: `bundle exec rspec spec/routing/marketing_routing_spec.rb spec/requests/marketing_homepage_spec.rb` green with the re-anchored `DESIGN_CONTRACT_SHA`; `bundle exec rubocop` clean on the changed Ruby files.

### Subphase 1.1: Routes, controller per-page metadata, layout fallbacks, sitemap

- [ ] `config/routes.rb` — inside the `constraints marketing_host` block (after line 23) add:
  ```ruby
  get '/privacy-policy', to: 'marketing#privacy_policy', as: :marketing_privacy_policy
  get '/terms-of-service', to: 'marketing#terms_of_service', as: :marketing_terms_of_service
  ```
- [ ] `app/controllers/marketing_controller.rb` — add (keep `CANONICAL_URL`, `DESIGN_CONTRACT_SHA`, `home`, `sitemap` behavior identical):
  ```ruby
  LEGAL_PAGE_URLS = {
    privacy_policy: 'https://www.kozmopath.com/privacy-policy',
    terms_of_service: 'https://www.kozmopath.com/terms-of-service'
  }.freeze

  def privacy_policy
    set_legal_meta(:privacy_policy)
  end

  def terms_of_service
    set_legal_meta(:terms_of_service)
  end
  ```
  and private:
  ```ruby
  def set_legal_meta(page_key)
    @canonical_url = LEGAL_PAGE_URLS.fetch(page_key)
    @meta_title = I18n.t("marketing.legal.#{page_key}.meta.title")
    @meta_description = I18n.t("marketing.legal.#{page_key}.meta.description")
    @structured_data = {
      '@context': 'https://schema.org',
      '@type': 'WebPage',
      name: @meta_title,
      url: @canonical_url,
      inLanguage: 'tr-TR',
      isPartOf: { '@type': 'WebSite', name: 'Kozmopath', url: CANONICAL_URL }
    }
    @support_email = public_support_email
  end
  ```
  (`use_turkish_locale` around_action already makes these tr.)
- [ ] `app/views/layouts/marketing.html.erb` — make head meta fall back to per-page ivars, rendering byte-identical output for the homepage (nil || constant):
  - `<meta name="description" content="<%= @meta_description || t('marketing.meta.description') %>">`
  - `og:title`/`og:description`/`og:url` and `<link rel="canonical">` → `@meta_title || t('marketing.meta.title')`, `@meta_description || t('marketing.meta.description')`, `@canonical_url || MarketingController::CANONICAL_URL`
  - `<title>` → `@meta_title || t('marketing.meta.title')`
  - Do NOT change robots, og:type, og:locale, og:site_name, theme-color, color-scheme, charset, viewport, the design-contract meta, or the JSON-LD script line.
- [ ] `app/views/marketing/sitemap.xml.erb` — add the two legal URLs after the homepage URL (exact strings from `LEGAL_PAGE_URLS`):
  ```erb
  <% MarketingController::LEGAL_PAGE_URLS.each_value do |url| %>
    <url><loc><%= url %></loc></url>
  <% end %>
  ```
- [ ] `spec/routing/marketing_routing_spec.rb` — add: both paths route to `marketing#privacy_policy` / `marketing#terms_of_service` on `kozmopath.com` and `www.kozmopath.com`; `https://app.kozmopath.com/privacy-policy` and `/terms-of-service` are `not_to be_routable`.
- [ ] `spec/requests/marketing_homepage_spec.rb` — update sitemap example (lines 211-222): expect exactly `['https://www.kozmopath.com/', 'https://www.kozmopath.com/privacy-policy', 'https://www.kozmopath.com/terms-of-service']` in that order.
- [ ] Run INNER gate (below); record first observation of the two-file group duration.

**INNER (S1.1)**: `rbenv exec bundle exec rspec spec/routing/marketing_routing_spec.rb spec/requests/marketing_homepage_spec.rb` → green (homepage digest still matches the unchanged constant at this point, because no homepage-rendered markup changed yet).

### Subphase 1.2: Shared footer extraction, homepage legal links, digest re-anchor

- [ ] Create `app/views/marketing/_footer.html.erb` — move the exact footer markup from `home.html.erb:389-401` into the partial with **byte-identical indentation/markup**, parameterizing only:
  - brand `href`: `<%= local_assigns[:brand_href] || '/' %>` (home passes `#hero`)
  - append two nav links after the existing four, using route helpers: `<a href="<%= marketing_privacy_policy_path %>"><%= t('marketing.legal.nav.privacy') %></a>` and `<a href="<%= marketing_terms_of_service_path %>"><%= t('marketing.legal.nav.terms') %></a>`
- [ ] `app/views/marketing/home.html.erb` — replace lines 389-401 with `<%= render 'marketing/footer', brand_href: '#hero' %>`.
- [ ] `config/locales/en.yml` + `config/locales/tr.yml` — add the shared legal nav labels under the `marketing:` block:
  ```yaml
  legal:
    nav:
      privacy: "Privacy Policy"            # tr: "Gizlilik Politikası"
      terms: "Terms of Service"            # tr: "Kullanım Koşulları"
  ```
  (Full `marketing.legal` content lands in M2; keep only `legal.nav.*` here so the partial renders.)
- [ ] `spec/requests/marketing_homepage_spec.rb` — add to the shared example ("the approved marketing surface"): footer contains `<a href="/privacy-policy">` and `<a href="/terms-of-service">` (relative same-host links, tr labels from locale).
- [ ] **Digest re-anchor (exact repo protocol, `docs/marketing-mobile-scroll-performance.plan.md:311-314`)**: run `rbenv exec bundle exec rspec spec/requests/marketing_homepage_spec.rb` — the fingerprint test fails and prints `expected: <old constant> ... got: <new digest>`; record the new digest, set it as `MarketingController::DESIGN_CONTRACT_SHA`, rerun green. Before re-anchoring, sanity-verify the diff is footer-only: render the homepage before/after extraction (test env), apply the spec's two neutralizations (vite CSS asset + contract meta), and confirm the only body difference is the two added footer links. If the diff is larger (indentation drift), fix the partial first — do not mask it with a digest change.
- [ ] Run RuboCop on the changed Ruby files.

**CHECKPOINT (S1.2)**: `rbenv exec bundle exec rubocop config/routes.rb app/controllers/marketing_controller.rb spec/routing/marketing_routing_spec.rb spec/requests/marketing_homepage_spec.rb` and `rbenv exec bundle exec rspec spec/routing/marketing_routing_spec.rb spec/requests/marketing_homepage_spec.rb` → both green.

### Acceptance Criteria (M1)

- [ ] Routes render only on marketing hosts; `app.kozmopath.com` 404s both paths (request + routing level)
- [ ] Homepage byte-diff (neutralized) is limited to the two new footer links; `DESIGN_CONTRACT_SHA` matches the re-anchored digest; sitemap has exactly 3 URLs
- [ ] Layout head renders identically for the homepage (canonical `https://www.kozmopath.com/`, WebSite JSON-LD unchanged)
- [ ] Stop conditions did not occur (see Failure Signals)

---

## Milestone 2: Legal page content, styles, and rendering contract

**Owner**: @implementer (fullstack)
**Dependencies**: M1
**Complexity**: HIGH
**Milestone Gate**: full focused marketing group green — `rbenv exec bundle exec rspec spec/routing/marketing_routing_spec.rb spec/requests/marketing_homepage_spec.rb spec/requests/marketing_legal_pages_spec.rb spec/lib/marketing_controller_spec.rb`; RuboCop clean on changed Ruby.

### Subphase 2.1: en/tr legal locale content, shared partials, legal views, request spec

- [ ] `config/locales/en.yml` + `config/locales/tr.yml` — complete the `marketing.legal` block (same key tree in both; tr is the rendered language, en is the maintained source). Exact schema:
  ```yaml
  legal:
    nav: { privacy:, terms: }                    # added in M1
    updated_label: "Last updated:"               # tr: "Son güncelleme:"
    updated_on: "12 August 2026"                 # tr: "12 Ağustos 2026"
    privacy:
      meta:
        title: "Privacy Policy — Kozmopath"      # tr: "Gizlilik Politikası — Kozmopath"
        description: "..."                       # 1-2 sentence SEO description, conservative
      title: "Privacy Policy"                    # tr: "Gizlilik Politikası" (rendered as h1)
      intro: "..."                               # short scope/effective-date note, plain paragraph
      sections: { <key>: { title:, body:, items?: [...] }, ... }   # EXACTLY 13 iterable keys — contact is NOT a section key
      contact: { title:, body: }                 # final explicit contact section, rendered exactly once by _legal_sections
    terms:
      meta: { title:, description: }
      title: "Terms of Service"                  # tr: "Kullanım Koşulları" (h1)
      intro: "..."
      sections: { <key>: { title:, body:, items?: [...] }, ... }   # EXACTLY 17 iterable keys — contact is NOT a section key
      contact: { title:, body: }
  ```
  Section keys and required content mandates (write conservative, accurate copy; see Legal-Content Limitations):
  - `privacy.sections` — EXACTLY 13 keys, in this order: `controller_contact` (controller "Kozmopath"; no entity/address invented), `scope`, `data_we_process` (items: account/profile; customer/contact/conversation content; catalog/integration credentials and data; AI/tool interaction and output; optional Voice audio, recordings and transcripts; device, log, cookie and local-storage data), `sources`, `purposes` (service delivery, support, product improvement, security, legal compliance), `legal_bases` (items, conservative only: contract/service delivery; legal obligations; legitimate interests where applicable; consent where required), `sharing` (items: categories only — service providers bound by instructions, legal requirements, business-transfer caveat; NO named processors), `international_processing` (caveat only; no destination promises), `retention` (purpose/account/legal-obligation based; explicitly NO fixed periods promised), `security` (controls; no guarantees), `your_rights` (items: access, rectification, erasure, restriction, portability, objection, consent withdrawal; KVKK/GDPR-style "as applicable"; exercise via support email), `children`, `updates`.
  - `privacy.contact` — `title` + `body`; body sentence WITHOUT the email (`_legal_sections` appends the mailto link after it). Rendered exactly once as the final `.legal-section#privacy-contact`.
  - `terms.sections` — EXACTLY 17 keys, in this order: `acceptance`, `eligibility` (age of majority / business use), `account` (credentials, security responsibility), `service_description`, `connected_accounts` (store/channel permissions; customer-consent responsibility), `customer_content` (you own content; license to operate; lawful-use responsibility), `ai_limitations` (AI output may be inaccurate; no guarantee; human review/handoff available; don't rely solely), `quotas_and_fees` (current free quotas described in general terms; paid plans/fees may be introduced with notice; no billing implementation claims), `acceptable_use` (no abuse/spam/phishing/illegal content), `ip_feedback` (our IP; feedback license), `privacy` (points to the privacy policy), `availability` (changes/disruptions; best-effort), `suspension_termination` (may suspend/terminate; export/retrieve data before termination; deletion caveats), `disclaimers` ("as is" to the extent permitted by law), `liability` (proportionate; subject to mandatory law), `governing_law` (Türkiye; competent courts under applicable law — NO city/court invented), `changes`.
  - `terms.contact` — same pattern as `privacy.contact`; rendered as the final `.legal-section#terms-contact`.
- [ ] Create `app/views/marketing/_legal_header.html.erb` — skip-link (copy of `home.html.erb:5`) + `<header class="site-header">` containing only the brand linking to `/` (logo `/brand-assets/logo.svg`, aria-label `marketing.common.home_label`, width 170 height 32, `fetchpriority="high"`).
- [ ] Create `app/views/marketing/_legal_sections.html.erb` — pure locale-driven renderer, no interpolation machinery. **Uses Symbol-key accessors per the locally verified I18n shape** (`t` returns Symbol-keyed hashes in this repo — see Verified Facts); `fetch(:title)` fails loud if the shape ever drifts. `"#{prefix}-#{key}"` stringifies Symbol keys predictably (`privacy-data_we_process`). The optional `contact_scope` local renders the final contact section exactly once (single source for the mailto markup):
  ```erb
  <% scope = local_assigns.fetch(:scope) %>
  <% prefix = local_assigns.fetch(:prefix) %>
  <% t("#{scope}.sections").each do |key, section| %>
    <section class="legal-section" id="<%= prefix %>-<%= key %>">
      <h2><%= section.fetch(:title) %></h2>
      <% if section[:body].present? %><p><%= section[:body] %></p><% end %>
      <% if section[:items].present? %>
        <ul><% section[:items].each { |item| %><li><%= item %></li><% } %></ul>
      <% end %>
    </section>
  <% end %>
  <% if (contact_scope = local_assigns[:contact_scope]) %>
    <section class="legal-section" id="<%= prefix %>-contact">
      <h2><%= t("#{contact_scope}.title") %></h2>
      <p><%= t("#{contact_scope}.body") %> <a href="mailto:<%= @support_email %>"><%= @support_email %></a></p>
    </section>
  <% end %>
  ```
- [ ] Create `app/views/marketing/privacy_policy.html.erb` and `app/views/marketing/terms_of_service.html.erb` — structure per view:
  ```erb
  <%= render 'marketing/legal_header' %>
  <main id="main" class="legal-page">
    <div class="legal-shell">
      <h1><%= t('marketing.legal.privacy.title') %></h1>
      <p class="legal-updated"><%= t('marketing.legal.updated_label') %> <%= t('marketing.legal.updated_on') %></p>
      <p class="legal-intro"><%= t('marketing.legal.privacy.intro') %></p>
      <%= render 'marketing/legal_sections', scope: 'marketing.legal.privacy', prefix: 'privacy', contact_scope: 'marketing.legal.privacy.contact' %>
    </div>
  </main>
  <%= render 'marketing/footer' %>
  ```
  (terms page mirrors with `terms` scope/prefix and `contact_scope: 'marketing.legal.terms.contact'`. The contact section renders exactly once, last, from `privacy.contact`/`terms.contact` — `_legal_sections` owns the single mailto markup; no hand-written duplicate and no `%{email}` tokens anywhere.)
- [ ] Create `spec/requests/marketing_legal_pages_spec.rb` — shared example over hosts `%w[kozmopath.com www.kozmopath.com marketing.localhost]` × pages (paths `/privacy-policy`, `/terms-of-service`; canonical from `MarketingController::LEGAL_PAGE_URLS`; h1 from tr `marketing.legal.<page>.title`; tr meta title/description via `I18n.t(..., locale: :tr)`; updated date `12 Ağustos 2026`; section ids from `I18n.t("marketing.legal.<page>.sections", locale: :tr).keys` — **Symbol keys, stringified via `"#{prefix}-#{key}"`** — prefixed `privacy-`/`terms-`, then exactly one final `privacy-contact`/`terms-contact` appended). Assertions per page:
  - 200; `html[lang]="tr"`; `<title>` == tr meta title; canonical == page canonical; og:url == canonical; og:title/og:description == tr meta keys; `meta[name="description"]` == tr meta description; robots `index,follow,max-image-preview:large`; design-contract meta == `MarketingController::DESIGN_CONTRACT_SHA`
  - JSON-LD: `@type` WebPage, `url` == canonical, `inLanguage` `tr-TR`, `isPartOf` == `{'@type' => 'WebSite', 'name' => 'Kozmopath', 'url' => MarketingController::CANONICAL_URL}`
  - exactly one `h1`; `.legal-section` ids equal the FULL ordered array — the 13 (privacy) / 17 (terms) section keys in locale order followed by the single `*-contact` id last (equality over the ordered array also proves no duplicates and exactly one contact section); exactly one `a[href="mailto:support@kozmopath.com"]` per page (assert `document.css('a[href^="mailto:"]').length == 1`) and body includes `support@kozmopath.com`; `.legal-updated` includes `12 Ağustos 2026`
  - content anchors: privacy tr body includes `KVKK`; terms tr body includes `Türkiye` and `KVKK` (implementer keeps these words in the tr copy; en mirrors semantically)
  - SSR-only: no `script` other than `application/ld+json`; skip-link `href="#main"`; header brand href `/`; footer contains exactly `/privacy-policy` and `/terms-of-service` links; body has no "Translation missing"
  - Stub `GlobalConfigService` for the support email: `allow(GlobalConfigService).to receive(:load).with('MAILER_SUPPORT_EMAIL', 'support@kozmopath.com').and_return('support@kozmopath.com')` (mirrors the homepage spec's `account_signup_enabled?` stub pattern)
  - Negative: on `app.kozmopath.com`, both paths return 404 (request-level complement to the routing spec)
- [ ] INNER gate below. Note: `pnpm sync:i18n` is NOT needed (dashboard import lists unchanged); no Vue files are touched.

**INNER (S2.1)**: `rbenv exec bundle exec rspec spec/requests/marketing_legal_pages_spec.rb` → green (views + locales + partials complete); `rbenv exec bundle exec rspec spec/lib/marketing_controller_spec.rb` → green (en/tr flatten parity now includes `marketing.legal`).

### Subphase 2.2: Legal SCSS styles + additive controller/lib contract spec

- [ ] `app/javascript/entrypoints/marketing.scss` — append a top-level "Legal pages" block **after** the `@media (max-width: 800px)` block (line 1038) and before the `prefers-reduced-motion` block (line 1040), reusing existing tokens:
  - `.legal-page` (background `var(--paper)`, padding `72px 0 96px`), `.legal-shell` (`width: min(calc(100% - 64px), 760px); margin: 0 auto` — ~65ch measure)
  - `h1` Georgia serif, `clamp(38px, 5vw, 52px)`, weight 400, tight leading, balance; `.legal-updated` (`#5c6a65`, 14px, 700); `.legal-intro` (`#283834`, 18px, line-height 1.65)
  - `.legal-section` (`padding: 34px 0 4px; border-top: 1px solid var(--line)`); `h2` Georgia 28px; `p`/`ul` (`#4d5b57`, 16px, line-height 1.7/1.65, `li { margin-top: 8px }`)
  - links: `color: #4057ad; text-decoration: underline; text-underline-offset: 3px` + hover `#2e3f8f`; `:focus-visible { outline: 3px solid var(--blue); outline-offset: 4px }` (matches existing focus convention)
  - `@media (max-width: 800px)`: `.legal-page` padding `48px 0 64px`; `.legal-shell` `calc(100% - 40px)`; h1 `clamp(32px, 9vw, 40px)`; intro 16px; h2 24px; p/ul 15px
  - No `backdrop-filter`, no new fonts, no animation; the global `prefers-reduced-motion` rule already covers legal pages
- [ ] `spec/lib/marketing_controller_spec.rb` — additive only:
  - extend `contrast_pairs` (lines 45-65) with `['.legal-section p', '#f3f0e8']`, `['.legal-section a', '#f3f0e8']`, `['.legal-updated', '#f3f0e8']`
  - new `it` blocks: stylesheet includes `.legal-page`, `.legal-shell`, `.legal-section`, `@media (max-width: 800px)` rules for `.legal-shell`, and `:focus-visible` outline for `.legal-page a`; stylesheet has no `.trial-` / `[data-trial-` additions (keep the existing guard intact)
  - new `it` block "keeps signup legal-link configuration and source parity": read `config/installation_config.yml` (YAML) and assert `TERMS_URL`/`PRIVACY_URL` values equal the two `MarketingController::LEGAL_PAGE_URLS` values; read `app/javascript/dashboard/i18n/locale/{en,tr}/signup.json` and assert both `TERMS_ACCEPT` strings include the two kozmopath URLs
- [ ] Run the full focused group + RuboCop on all changed Ruby/spec files.

**CHECKPOINT (S2.2)**: full focused group green (4 spec files); RuboCop clean; `git diff --check` clean.

### Acceptance Criteria (M2)

- [ ] Both legal pages render complete Turkish copy with all mandated sections, correct metadata, WebPage JSON-LD, mailto contact, and no missing translations on all three marketing hosts
- [ ] Privacy renders exactly 13 iterable sections + one final `privacy-contact`; terms exactly 17 + one final `terms-contact`; no duplicate section ids; exactly one mailto link per page (request-spec asserted via the ordered id array + mailto count)
- [ ] en/tr `marketing.legal` key trees identical; signup config/strings contract pinned by specs
- [ ] Legal styles pass the repo's programmatic AA contrast checks; mobile rules present
- [ ] Stop conditions did not occur

---

## Milestone 3: Runtime/browser evidence, final review, commit

**Owner**: @implementer (fullstack) + @analyzer (FINAL review)
**Dependencies**: M2
**Complexity**: MEDIUM
**Milestone Gate**: FINAL — independent parallel jobs below; then one conventional commit.

### Subphase 3.1: Runtime readiness + browser evidence (1440×900 and 390×844)

- [ ] Inspect `pm2 list` and `docker compose ps`; reuse healthy `postgres`/`redis` containers and task-owned PM2 processes (`chatwoot-backend`, `chatwoot-worker`, `chatwoot-vite`) per `chatwoot-ai-native-test` skill; after code changes land, `pm2 restart chatwoot-backend chatwoot-worker chatwoot-vite` and require `curl -sSf http://localhost:3000/health` → `{"status":"woot"}`.
- [ ] Browser (agent-browser with the repo-standard Chatwoot browser profile per AGENTS.md) on `http://marketing.localhost:3000`:
  - `/privacy-policy` and `/terms-of-service` at 1440×900 and 390×844: page renders, no horizontal scroll, headings readable, footer legal links visible and clickable, contact mailto link present
  - homepage (`/`): footer shows both legal links; clicking `/privacy-policy` navigates to the legal page
  - `/sitemap.xml` shows 3 `<loc>` URLs; `robots.txt` unchanged and still references the sitemap
  - Spot a11y: single h1, h2 section order matches locale order, skip-link visible on keyboard focus, links have visible focus rings, text contrast passes visual spot check
- [ ] If `marketing.localhost` resolution fails in the browser, fall back to `curl -H 'Host: marketing.localhost' http://localhost:3000/...` for HTTP evidence and record the browser limitation (LOW assumption).

**INNER (S3.1)**: readiness probe + curl HTML assertions (`lang="tr"`, canonical, mailto) + screenshots at both viewports; record evidence table per ai-native-workflow.

### Subphase 3.2: Final review + commit

- [ ] `git diff --check`; `rbenv exec bundle exec rubocop` on all changed Ruby; re-run the full focused group on the exact final diff (PASS evidence from earlier subphases is invalidated by any later edit)
- [ ] Review the diff for: no homepage byte changes beyond the footer links and digest constant; no changes to `Form.vue`, `signup.json`, `installation_config.yml`, `robots.txt`, dashboard, or `enterprise/`
- [ ] @analyzer FULL review at this gate (contract/SEO/content boundary): `spec/requests/marketing_legal_pages_spec.rb` coverage vs plan mandates; digest method correctness; no invented legal/business facts in copy
- [ ] Commit (only after user confirmation per session rules): single conventional commit `feat(marketing): add Kozmopath privacy policy and terms of service pages`. Recommendation: **include `docs/kozmopath-legal-pages.plan.md` in this commit** — the repo convention tracks plan docs alongside feature work (16 tracked `docs/*.plan.md`, e.g., `docs/kozmopath-freemium-quotas.plan.md`), and this plan was explicitly requested as the implementation artifact. Do NOT commit during the planning phase itself. No push (out of scope).

**FINAL**: three independent jobs on the final diff — (1) focused RSpec group, (2) RuboCop + `git diff --check`, (3) browser evidence re-check of one viewport pair if any rendering-adjacent file changed since S3.1; otherwise reuse S3.1 evidence.

### Acceptance Criteria (M3)

- [ ] All evidence rows VERIFIED (or explicitly UNVERIFIED with reason); no unresolved unsafe side effects; PM2/process state restored to pre-task ownership
- [ ] Single feature commit created as specified; worktree clean afterwards
- [ ] Stop conditions did not occur

---

## Deliverables

| Milestone / Subphase | Files Created / Modified |
|----------------------|--------------------------|
| M1 / S1.1 | `config/routes.rb`, `app/controllers/marketing_controller.rb`, `app/views/layouts/marketing.html.erb`, `app/views/marketing/sitemap.xml.erb`, `spec/routing/marketing_routing_spec.rb`, `spec/requests/marketing_homepage_spec.rb` |
| M1 / S1.2 | `app/views/marketing/_footer.html.erb` (new), `app/views/marketing/home.html.erb`, `config/locales/en.yml`, `config/locales/tr.yml`, `app/controllers/marketing_controller.rb` (digest constant only) |
| M2 / S2.1 | `config/locales/en.yml`, `config/locales/tr.yml`, `app/views/marketing/_legal_header.html.erb` (new), `app/views/marketing/_legal_sections.html.erb` (new), `app/views/marketing/privacy_policy.html.erb` (new), `app/views/marketing/terms_of_service.html.erb` (new), `spec/requests/marketing_legal_pages_spec.rb` (new) |
| M2 / S2.2 | `app/javascript/entrypoints/marketing.scss`, `spec/lib/marketing_controller_spec.rb` |
| M3 / S3.1 | none (runtime/browser evidence only) |
| M3 / S3.2 | `docs/kozmopath-legal-pages.plan.md` (this file, if included in the feature commit) |

## Gate Plan

| Subphase / Milestone | Gate | Exact Commands / Methods | Evidence Invalidation Paths | Expected Duration Evidence |
|----------------------|------|--------------------------|-----------------------------|----------------------------|
| M1 / S1.1 | INNER | `rbenv exec bundle exec rspec spec/routing/marketing_routing_spec.rb spec/requests/marketing_homepage_spec.rb` | any edit to routes/controller/layout/sitemap after the run | Baseline n=1 (2026-08-12): same-style 3-file group 43 examples in 38.65 s test / 43.66 s wall; this 2-file subset UNKNOWN — collect first observation |
| M1 / S1.2 | CHECKPOINT | same two-file command + `rbenv exec bundle exec rubocop config/routes.rb app/controllers/marketing_controller.rb spec/routing/marketing_routing_spec.rb spec/requests/marketing_homepage_spec.rb` | footer/partial/locale edits after the run | UNKNOWN — first observation at S1.1; RuboCop single-file baseline UNKNOWN |
| Milestone 1 | MILESTONE | two-file RSpec green with re-anchored digest + RuboCop clean | digest constant or footer markup edits | reuse S1.1/S1.2 observations |
| M2 / S2.1 | INNER | `rbenv exec bundle exec rspec spec/requests/marketing_legal_pages_spec.rb` then `rbenv exec bundle exec rspec spec/lib/marketing_controller_spec.rb` | locale/view/partial edits after the run | UNKNOWN — collect first observation (new spec ~20 examples) |
| M2 / S2.2 | CHECKPOINT | full focused group (4 files) + RuboCop on changed Ruby + `git diff --check` | any file edit after the run | UNKNOWN until first 4-file run; expect ~55-90 s wall given 38.65 s baseline + new spec (not an estimate — collect) |
| Milestone 2 | MILESTONE | full focused group green + RuboCop clean | post-run edits | reuse S2.2 observation |
| M3 / S3.1 | INNER | `pm2 restart chatwoot-backend chatwoot-worker chatwoot-vite`; `curl -sSf http://localhost:3000/health`; agent-browser profile sessions at 1440×900 + 390×844; `curl -sSf http://marketing.localhost:3000/sitemap.xml` | code edits after evidence capture; process ownership changes | UNKNOWN — collect first observation; browser session ~2-4 min expected, not assumed |
| M3 / S3.2 | FINAL | parallel: (1) `rbenv exec bundle exec rspec spec/routing/marketing_routing_spec.rb spec/requests/marketing_homepage_spec.rb spec/requests/marketing_legal_pages_spec.rb spec/lib/marketing_controller_spec.rb`; (2) RuboCop changed files + `git diff --check`; (3) browser spot re-check only if rendering-adjacent files changed since S3.1 | final diff edits; environment changes | reuse S2.2 + S3.1 observations; job (3) skipped when S3.1 evidence applies to the final diff |
| Final | FINAL gate | @analyzer FULL review of contract/SEO/content + commit `feat(marketing): add Kozmopath privacy policy and terms of service pages` | review findings | review scope, not timed |

Rules applied: no full-suite/build rituals (only the focused marketing group, which is the entire affected surface); no repeated unchanged PASS evidence — S3.2 reruns only because the diff is final; duration evidence is observed (n=1 baseline) or explicitly UNKNOWN until first collection.

## Blast Radius / Affected Entry Points

- `config/routes.rb` constraints block (lines 17-24) — only marketing hosts gain routes; `app.kozmopath.com` and all non-marketing hosts unchanged (spec-pinned)
- `MarketingController` — `home`/`sitemap` actions byte-identical; new actions only; `CANONICAL_URL` unchanged
- `app/views/layouts/marketing.html.erb` — head fallbacks render identically for homepage (digest-verified); affects every page using this layout (only marketing)
- `app/views/marketing/home.html.erb` footer → shared `_footer` partial — homepage markup changes only by the two added footer links (byte-diff verified)
- `app/views/marketing/sitemap.xml.erb` — sitemap consumers (search engines); spec-pinned to 3 URLs
- `app/javascript/entrypoints/marketing.scss` — appended rules only; existing selectors untouched (spec-guarded)
- `config/locales/{en,tr}.yml` — appended `marketing.legal` block; existing keys untouched (parity + homepage specs guard)
- Signup flow (`Form.vue`, `signup.json`, `installation_config.yml`) — NOT modified; previously-dead URLs now resolve; contract pinned by specs
- Background jobs/webhooks/dashboard/API — unaffected (no code paths touch these pages)

## Allowed Scope / Forbidden Scope

- Allowed: the 17 files in Deliverables; content copy in `config/locales/{en,tr}.yml`; runtime/process operations owned by this task during M3
- Forbidden: dashboard/authenticated surfaces; consent checkboxes beyond the existing signup acceptance; cookie banner/CMP; DB models/migrations; inventing legal entity/address, fixed retention periods, named processors, certifications, guarantees, or specific courts/cities; billing implementation; other community locales; `robots.txt` changes; `Form.vue`/`signup.json`/`installation_config.yml` edits; deployment/push; `pnpm sync:i18n`; global `pm2 reload all`/`kill`

## UI/UX Composition Specification

### Screen Composition (legal pages — both pages identical skeleton)

```
#### [Zone: Skip link] (fixed, off-screen until focused)
└── "Skip to content" → #main (reuses existing .skip-link pattern)

#### [Zone: Header] (non-sticky, reuses .site-header, width min(100% - 64px, 1168px))
└── Left: brand logo (logo.svg, 170×32) linking to "/" (aria-label: home)

#### [Zone: Main Content] (.legal-page, background var(--paper))
└── .legal-shell (max-width 760px, centered, ~65ch)
    ├── h1 (Georgia serif, clamp(38px,5vw,52px)) — page title
    ├── .legal-updated — "Son güncelleme: 12 Ağustos 2026" (muted #5c6a65, 14px, 700)
    ├── .legal-intro — one short paragraph (#283834, 18px, 1.65)
    └── .legal-section list (border-top hairline separators)
        ├── h2 (Georgia, 28px) + p body (16px, 1.7) [+ ul items 16px, 1.65]
        └── final .legal-section#privacy-contact / #terms-contact: body sentence + mailto link

#### [Zone: Footer] (shared _footer, .site-footer dark #0b1715)
├── Left: brand (logo_dark.svg, 170×32) → "/" on legal pages
└── Right: nav — How it works · Product flow · Human handoff · Log in · Privacy Policy · Terms of Service
```

### Action Placement Rules

| Action | Position | Variant | Visibility Condition |
|--------|----------|---------|----------------------|
| Mailto contact link | Inline at end of the contact section body | text link (`#4057ad`, underlined) | Always |
| Privacy/terms footer links | End of footer nav, after "Log in" | footer nav link (existing `.site-footer nav a` style) | Always, both pages + homepage |
| Brand → home | Header left + footer left | image link | Always |

### Content Flow (Reading Order)

1. Skip link → 2. Brand header → 3. h1 title → 4. Last-updated line → 5. Intro paragraph → 6. Numbered-in-order sections (h2 + paragraphs + bullets) → 7. Contact section with mailto → 8. Footer with legal links

### Component Mapping

| Need | Reuse Existing | New Component | Reference Pattern |
|------|---------------|---------------|-------------------|
| Skip link | `.skip-link` (home.html.erb:5 + marketing.scss:23-33) | `_legal_header.html.erb` | home header markup |
| Header/brand | `.site-header`, `.brand`, `.brand-logo` | `_legal_header.html.erb` | home.html.erb:16-19 |
| Section list | — | `_legal_sections.html.erb` | locale-driven, both pages |
| Footer | `.site-footer` (marketing.scss:772-777, mobile 1036-1037) | `_footer.html.erb` (extracted from home) | home.html.erb:389-401 |
| Text links | `a { color: inherit }` + new `.legal-page a` rules | — | — |

### Responsive Behavior

| Breakpoint | Layout Change |
|------------|--------------|
| Mobile (<800px) | `.legal-shell` width `calc(100% - 40px)`; h1 `clamp(32px,9vw,40px)`; section h2 24px; body 15px; page padding `48px 0 64px`; footer nav becomes 2-column grid (existing rule handles 6 links as 3 rows) |
| Desktop (≥801px) | `.legal-shell` `min(calc(100% - 64px), 760px)`; h1 clamp to 52px; 18px intro |
| All | No horizontal scroll (body `overflow-x: hidden` exists); `prefers-reduced-motion` global rule applies |

### States

| State | Affected Zone | Treatment |
|-------|--------------|-----------|
| Loading | none | SSR-only page, no client-side loading state |
| Link focus | All links | `:focus-visible` 3px `var(--blue)` outline + 4px offset (extends existing convention) |
| Footer link hover | Footer nav | Existing: white text + underline |
| Content link hover | Legal sections | `#2e3f8f` + underline |

## Invariants

| Invariant | Why it matters | How to verify |
|-----------|----------------|---------------|
| Homepage neutralized digest == `DESIGN_CONTRACT_SHA` | Guards every homepage/layout rendering change | `spec/requests/marketing_homepage_spec.rb:40-49` |
| Homepage canonical `https://www.kozmopath.com/` + WebSite JSON-LD unchanged | SEO contract for the primary page | homepage spec metadata example (lines 178-189) |
| Legal pages: one canonical URL per page == `LEGAL_PAGE_URLS` == sitemap URL == signup config URL | Single source of truth for each legal URL | new request spec + lib spec config contract + sitemap spec |
| en/tr `marketing` key trees identical (incl. `legal`) | Maintained-locale parity policy | `spec/lib/marketing_controller_spec.rb:131-143` |
| Legal pages render only on marketing hosts | Host-constraint security/scope boundary | routing spec `not_to be_routable` + request 404 on app host |
| Exactly one contact section (last, id `*-contact`) and exactly one mailto link per legal page | Duplicate headings/ids would break SEO, landmarks, and the contact UX | request spec: ordered `.legal-section` id array equality + `a[href^="mailto:"]` count == 1 |
| No "Translation missing" in any rendered body | Locale completeness on the only rendered locale (tr) | request specs + homepage spec line 37 |
| Legal copy contains no invented entity/address/retention/processors/courts | Legal-content limitation (see below) | @analyzer FINAL review of en/tr copy |

## Behavior That Must Not Change

- Homepage title/description/canonical/og/JSON-LD/design-contract — validated by homepage request spec (unchanged examples + digest)
- `robots.txt` — validated by `spec/lib/marketing_controller_spec.rb:150-157` (untouched)
- Signup `TERMS_ACCEPT` rendering and `Form.vue` URL replacement — validated by untouched `Form.spec.js` + new config contract spec
- Marketing host set and app-host routing — validated by routing spec (existing + new examples)
- `marketing.scss` homepage selectors and contrast pairs — validated by `spec/lib/marketing_controller_spec.rb` (additive changes only)
- Sitemap XML media type and format — validated by homepage spec sitemap example
- `sitemap`/`home` controller actions and `CANONICAL_URL` constant — validated by routing + request specs

## Legacy / Malformed Persisted State

Not applicable — this plan introduces no database models, migrations, jobs, or queued data, and touches no persisted records. The only config-dependent value is `@support_email`, resolved through the existing `GlobalConfigService.load('MAILER_SUPPORT_EMAIL', 'support@kozmopath.com')` chain (`lib/global_config_service.rb:2-16`, `public_controller.rb:22-24`); a blank/legacy DB value falls back to the default, and a custom value is surfaced as-is (intended behavior), with specs stubbing the lookup for determinism. No legacy shapes need sanitizing.

## Enterprise Check

`rg -n "MarketingController|marketing" enterprise/` finds no overlay (only unrelated `marketing_attribution` services and LLM content-curation copy). No `prepend_mod_with`/`include_mod_with` or `spec/enterprise` mirror is required. The legal pages are OSS-only and Enterprise ships the same public surface; keep the controller/route contract plain OSS.

## SEO / Canonical / Sitemap Strategy

- Canonical: one per page from `LEGAL_PAGE_URLS` (www origin), used identically for `<link rel="canonical">`, `og:url`, sitemap `<loc>`, and JSON-LD `url` — single constant prevents drift; apex-host requests still canonicalize to www (same convention as homepage)
- Meta: per-page `meta.description`, `og:title`, `og:description`, `<title>` from tr `marketing.legal.<page>.meta.*`
- Robots: pages inherit `index,follow,max-image-preview:large` (coordinator decision: indexable); `robots.txt` unchanged and still points at the sitemap
- Structured data: `WebPage` + `isPartOf WebSite` (homepage keeps `WebSite`); `inLanguage tr-TR`
- Sitemap: exactly 3 URLs, homepage first, generated from the same constant
- Digest: `DESIGN_CONTRACT_SHA` protects the homepage rendering contract; legal pages are asserted via their own canonical/meta spec instead of a second fingerprint (avoid misusing the homepage fingerprint for different content)

## Legal-Content Limitations

These pages are product/legal drafts for the Kozmopath MVP. Copy must be accurate and conservative: no fabricated certifications, guarantees, fixed retention periods, named processors, universal legal-basis claims, or specific courts/cities. Governing law is Türkiye with "competent courts under applicable law" (coordinator decision — no city/court invented). Retention language is purpose/account/legal-obligation based only. AI sections state limitations and human-review/handoff availability without performance promises. Quotas/fees sections describe current free quotas in general terms and note that paid plans/fees may be introduced with notice — no billing implementation claims. Rights sections are KVKK/GDPR-style "as applicable" with the support-email process. A lawyer's review is out of scope and should be noted in the PR description.

## Validation Matrix

| Check | Command / Method | Proves |
|------|-------------------|--------|
| Regression: signup URLs now resolve | new request spec (`/privacy-policy`, `/terms-of-service` 200 on marketing hosts; 404 on app host) + routing spec | previously-dead links are live, host boundary intact |
| Edge: non-production `marketing.localhost` | same request spec includes the host | dev/browser verification surface works |
| Behavior preservation: homepage | homepage request spec + digest + sitemap 3-URL example | homepage rendering contract preserved |
| Locale parity | `spec/lib/marketing_controller_spec.rb:131-143` | en/tr key trees identical |
| No missing translations | request spec + homepage spec body assertions | tr renders completely |
| Signup config contract | lib spec YAML/JSON assertions + untouched `Form.spec.js` | config, strings, and Form replacement agree |
| Single contact rendering | new request spec: full ordered `.legal-section` id array (13/17 keys + `*-contact` last) + `a[href^="mailto:"]` count == 1 | no duplicate contact heading/id; exactly one mailto per page |
| Contrast AA | lib spec contrast pairs (extended) | legal text/link colors pass programmatic check |
| Browser/responsive | agent-browser 1440×900 + 390×844 on `marketing.localhost` | pages render, no overflow, links work |

## Visual Baseline Policy

No visual-regression baseline system is in use for these pages (repo uses content contracts, not screenshot baselines). Earlier subphases may capture diagnostic screenshots during M3 only; no baselines are written or approved. The homepage design-contract fingerprint is the functional equivalent and is re-anchored exactly once in M1/S1.2 with a verified footer-only diff.

## Evidence Owners

| Item | Owner | Proof Required |
|------|-------|----------------|
| Digest re-anchor with footer-only diff | @implementer | failing-run digest + neutralized before/after diff + green rerun |
| Legal page rendering contract (meta/JSON-LD/sections/contact) | @implementer | `marketing_legal_pages_spec.rb` green (all 3 hosts) |
| en/tr parity + no missing translations | @implementer | lib parity spec + body assertions |
| Signup link contract | @implementer | lib config-contract spec + untouched Form.spec.js green in CI history |
| Contrast/responsive CSS rules | @implementer | lib spec additions green |
| Browser evidence | @implementer | readiness + screenshots/assertions at both viewports |
| Copy accuracy (no invented facts) + final contract review | @analyzer | FULL review at M3 gate + FINAL |

## Failure Signals

- Neutralized homepage diff larger than the two footer links → stop; fix extraction indentation before touching the digest
- `marketing_legal_pages_spec.rb` requires stubbing beyond `GlobalConfigService`/`host!` → the controller/layout design leaks test-only state; stop and restructure before continuing
- Digest test fails with an unexplained body change in M2 → a subphase accidentally edited shared layout/partials; stop, revert, and re-verify M1 gate evidence
- Browser evidence at M3 shows horizontal overflow or missing focus states → treat as implementation defect, not tooling noise (S3.1 recovery budget: 2 attempts per failure class per ai-native-workflow)
- Any scope drift into consent/CMP/billing/dashboard or locale edits beyond en/tr → stop and report

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Footer partial extraction changes homepage bytes beyond the two links | MEDIUM | MEDIUM | Byte-diff protocol before digest re-anchor; fix indentation rather than masking |
| Legal copy drift into invented facts (entity, retention, processors, courts) | MEDIUM | HIGH | Per-section content mandates in S2.1 + @analyzer FULL copy review; PR note for lawyer review |
| `marketing.localhost` host resolution fails in browser | LOW | LOW | curl `-H 'Host:'` fallback evidence; constraint is spec-proven |
| Digest spec churn from Vite asset naming changes | LOW | LOW | Existing loud regex + normalization in spec already guards this |
| Route/URL drift between canonical, sitemap, and signup config | LOW | MEDIUM | Single `LEGAL_PAGE_URLS` constant + config-contract spec pins all three |
| Duration estimates wrong for new specs | LOW | LOW | Observed baseline n=1; UNKNOWN markers until first collection; native timeouts (600 s) |

## Decision Log

| Decision | Chosen | Rejected | Rationale | Evidence |
|----------|--------|----------|-----------|---------|
| Metadata mechanism | Controller ivars with layout fallback (`@canonical_url`/`@meta_title`/`@meta_description`) | `content_for` blocks; per-page layouts; second fingerprint | Testable, single source in one action helper; homepage bytes identical via nil-fallback | `marketing_controller.rb:2-3`, `marketing.html.erb:8-20` |
| View architecture | One locale-driven `_legal_sections` partial (13/17 iterable sections + optional `contact_scope` contact block); plain ERB iteration over `t(scope).sections` | Generic "policy document" data model, markdown renderer, per-paragraph partials | KISS: no speculative abstraction; exactly two consumers; email stays out of locale strings (no interpolation tokens) | M2/S2.1 file list |
| Footer | Extract shared `_footer` partial (home + legal) | Duplicate inline footer on legal pages | DRY; single source for legal links; digest re-anchored once with verified diff | `home.html.erb:389-401` |
| Support email | `@support_email = public_support_email`; rendered as `mail_to` in the partial's contact block | `%{email}` interpolation tokens in locale copy | No `%`-formatting hazards; clickable mailto; config-overridable; spec-stubbable | `public_controller.rb:22-24` |
| Contact placement | `contact` OUTSIDE the iterable `sections` subtree (`privacy.contact` / `terms.contact`), rendered exactly once by `_legal_sections` via the `contact_scope` local | `contact` as an iterable section key + a separate hand-written section in each view | The original draft rendered contact twice (partial iteration over `sections.contact` plus a hand-written block) — duplicate heading, duplicate `*-contact` id, duplicate mailto; single source removes all three | coordinator review of this plan |
| I18n hash access | Symbol accessors (`section.fetch(:title)`, `section[:body]`, `section[:items]`) + `"#{prefix}-#{key}"` id interpolation | String accessors (`section['title']`) | Repo probe 2026-08-12: `I18n.t` returns Symbol-keyed hashes at every level (i18n 1.14.7, Rails 7.2.3.2); `fetch` fails loud if the shape drifts | runner probe (Verified Facts row) |
| Route names | `marketing_privacy_policy` / `marketing_terms_of_service` with explicit `as:` | Default `privacy_policy` helpers | Deterministic, collision-free, matches `marketing_home` naming | full `routes.rb` read |
| Digest re-anchor | Repo's failing-run protocol (record actual digest → update constant → rerun green) | Independent hash script | Consistent with prior convention and the spec's own neutralization | `docs/marketing-mobile-scroll-performance.plan.md:311-314` |
| Plan file in feature commit | Include (repo convention) | Exclude | 16 tracked `docs/*.plan.md` pair with feature commits | `git ls-files docs/` |
| Compliance framing | Türkiye law, "competent courts under applicable law", KVKK/GDPR-style "as applicable", no fixed retention/processors | Specific courts, named processors, fixed periods | Coordinator decisions; no invented facts | coordinator decisions + Legal-Content Limitations |

## Notes

- Use `rbenv exec bundle exec` for all Ruby commands (AGENTS.md; system Ruby lacks bundler 4.0.3 — observed)
- `pnpm sync:i18n` not needed; dashboard import lists unchanged; no Vue files change, so no ESLint/vitest gates are scheduled (Form.spec.js untouched)
- Do not power Captain/Copilot during M3 runtime work (chatwoot-ai-native-test skill boundary); only task-owned PM2 processes may be restarted
- NO new database tables, models, migrations, or consent/CMP machinery
