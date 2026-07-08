# Access Control Policy — CaseLight

_NIST 800-53: AC-2, AC-3, AC-6, AC-7, AC-12, IA-2, IA-5. SOC 2: CC6.1–CC6.3. Owner: the operating
nonprofit. Review: annually or on any role/authorization change._

## Purpose
Ensure only authorized staff reach client data, each sees only what their role needs, and access is
recertified and revoked. This policy is **enforced in code** — the citations are the enforcing
mechanism, not aspiration.

## Policy

1. **One account per person (AC-2).** No shared logins. Each staff member is a distinct Devise `User`
   so the audit trail is attributable. Accounts are created and role-assigned by an administrator.
2. **Role-based access (AC-3).** Authorization is CanCanCan (`app/classes/ability.rb`), eight roles
   (admin, case worker, four manager roles, strategic overviewer). Tenants are isolated by PostgreSQL
   schema (Apartment) + the `TenantBoundary` concern; a user in one org cannot reach another's data.
3. **Least privilege + field-level sensitivity (AC-6).** Beyond record-level rules, sensitive custom
   fields and assessment domains are classified (standard / restricted / emergency-only) and masked
   per role by `SensitivityPolicy` + the `SensitiveFields` concern. Emergency-only fields require
   **break-glass** (`BreakGlassGrant`): a 1-hour self-elevation with a mandatory reason, audit written
   first (fail-closed). The least-privilege and mandatory-authorization enforcement flags ship OFF
   (shadow-first) and are flipped per environment only after reviewing the AccessReview shadow tables.
4. **Strong authentication (IA-2/IA-5).** MFA (TOTP) and passkeys (WebAuthn) are available; MFA is
   required for privileged roles once the org enables the flag. Passwords: ≥12 chars with complexity,
   no reuse of the last 5 (devise-security). Rate-limiting on auth endpoints (rack-attack).
5. **Lockout & session timeout (AC-7/AC-12).** Accounts lock after repeated failures (default 10,
   floor ≥3 to prevent admin brick); idle sessions time out (default 30 min). Both tunable per tenant
   in the enforcement-settings panel.
6. **Recertification (AC-2(j)).** Administrators review the **AccessReview report** (`/admin/access_review`,
   HTML + CSV) at least quarterly: role, last sign-in, MFA gap, lock/disabled status, and caseload.
7. **Deprovisioning (AC-2).** Departing staff are **disabled** (login blocked, records retained). Their
   caseload must be reassigned (surfaced in the AccessReview "disabled staff with caseload" list).
   Dormant accounts auto-disable after the org-set inactivity threshold (`accounts:disable_inactive`,
   AC-2(3)); the last enabled admin is never auto-disabled.

## Enforcement anchors
`app/classes/ability.rb`, `app/classes/sensitivity_policy.rb`, `app/models/break_glass_grant.rb`,
`app/models/enforcement_setting.rb`, `app/controllers/access_reviews_controller.rb`,
`config/initializers/{two_factor,webauthn,devise,rack_attack}.rb`,
`app/controllers/concerns/{tenant_boundary,sensitive_fields}.rb`, `lib/tasks/accounts.rake`.
See `ssp.md` §3 (AC/IA rows) for status + evidence.
