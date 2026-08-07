# Trial product contract

## Safe prototype decisions

- Offer: a proposed 14-day free trial with no payment-card field in the current signup surface.
- Trial start language: the proposed trial starts when the account is created.
- Landing CTAs: all trial actions resolve only to `../signup-companion/index.html`.
- Login: prototype anchors retain the verified production target as metadata and stay inside the static document.
- Signup: business email and password are represented; the password contract is at least six characters with uppercase, lowercase, number, and special character.
- Validation: client-only, with no fetch, XHR, form action, account creation, or persistence.
- Evidence: controlled product and conversation fixtures remain explicitly disclosed.

## Verified production route mapping

- Marketing: `https://www.kozmopath.com/`
- Signup target: `https://app.kozmopath.com/app/auth/signup`
- Login target: `https://app.kozmopath.com/app/login`
- Frontend route helper: `frontendURL('auth/signup')`
- Availability gate: `requireSignupEnabled`, backed by `ENABLE_ACCOUNT_SIGNUP`

These values appear in `data-production-href` metadata only. They are not called by this prototype.

## Deferred backend lifecycle work

The repository contains no verified 14-day lifecycle or enforcement. Production implementation must define trial timestamps, eligibility, expiry behavior, account states, re-entry policy, authorization, worker behavior, notices, observability, support controls, and migration/rollback handling before the promise can ship.

## Deferred operations and publication gates

Before public use, operators must explicitly enable and validate account signup, Terms and Privacy destinations, email confirmation and delivery behavior where configured, CAPTCHA and OAuth configuration where configured, abuse controls, monitoring, and the full publication/release checklist. Pricing, cancellation, automatic billing, usage limits, and post-trial behavior remain unspecified and are intentionally absent.
