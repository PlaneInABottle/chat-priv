# Production implementation map

This is a design handoff, not an implementation authorization.

| Prototype concern | Verified production surface | Follow-up required |
| --- | --- | --- |
| Landing CTA | Rails marketing view and `https://app.kozmopath.com/app/auth/signup` | Replace local href only after trial lifecycle and signup availability are approved. |
| Signup availability | Vue `requireSignupEnabled`; installation config `ENABLE_ACCOUNT_SIGNUP` | Confirm environment/config precedence and unavailable-state UX. |
| Account creation | Current signup registration API | Preserve server validation, CAPTCHA/OAuth branches, and confirmation behavior. Do not infer trial state from frontend copy. |
| Password | Existing six-character complexity validator | Reuse the current validator and translated requirement states. |
| Terms and Privacy | Existing signup legal links | Confirm final legal destinations and consent language. |
| Trial lifecycle | Not present | Add backend-owned eligibility, start/end timestamps, expiry state, authorization, jobs, auditability, and tests. |
| Analytics | Not specified | Define consent-aware conversion events without customer-content leakage. |

Optional Google OAuth and invisible hCaptcha are current conditional implementation branches. They are notes here, not fabricated controls in the companion UI.
