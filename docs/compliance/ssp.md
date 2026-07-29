# System Security Plan (SSP) — CaseLight

_System categorization: **FedRAMP Moderate** baseline (NIST SP 800-53 Rev. 5), aligned to **SOC 2**
Trust Services Criteria (Security + Confidentiality + Privacy). Scope: the **application layer** of a
single-instance, self-hosted deployment. Owner: Lighthouse Nonprofit Technologies. Last updated:
2026-07-26 (post-Phase-7 hardening: enforcement flags ON, strict encryption mode, archive-gated
scheduled retention, tenant export, restore drill, noindex baseline)._

This SSP is a **pragmatic, honest** control statement: it documents the control families CaseLight
actually implements at the application layer, maps each to its code + evidence, names what is
**inherited** from the deployment infrastructure, and states plainly what is **not yet satisfied**
and gates production with real client data. It is deliberately **not** a full 300-control catalog of
mostly-inapplicable rows; coverage-theater would undermine the honest posture this project is built on
(see `SECURITY.md` "compliance framing"). Where a control is not implemented, it is marked
Inherited / Planned / N-A with a one-line reason.

Companion artifacts (the detail behind each row): `control-matrix.md` (SOC 2 view),
`pii-inventory.md`, `encryption-at-rest.md`, `audit-logging.md`, `audit-retention.md`,
`history-store-sc28-poam.md`, `vulnerability-poam.md`, `policies/`, and the production gate in
`SECURITY.md`.

---

## 1. System description

CaseLight is an AGPL-3.0 case-management system for refugee-resettlement and human-services
nonprofits — a modernized, security-hardened fork of OSCaR (Open Source Case-management and
Record-keeping). It is multi-tenant by **subdomain**, isolating each org's relational data in its own
PostgreSQL schema (the `ros-apartment` gem). Deployment target: a **single self-hosted instance**
(the pilot runs on one AWS EC2 box), reachable only via a reverse proxy; the database, document store,
cache, and job queue are not exposed to the network.

### Authoritative stack (pinned — this table supersedes any older version reference in the docs)

| Component | Version | Role |
|---|---|---|
| Ruby | 4.0.5 (`ruby:4.0`, Debian Trixie) | Runtime |
| Rails | 8.1.3 (Zeitwerk, Rack 3; POAM-020 **closed** 2026-07-19) | Framework |
| PostgreSQL | 17 (`pg` 1.6) | Primary relational store (schema-per-tenant) |
| MongoDB | 8.0 (Mongoid 9.0) | Change-history + access-audit store (single shared DB, tenant-field-scoped) |
| Redis + Sidekiq | 7 / 8.1.6 | Background jobs (mailers, reports) |
| Node | 24 LTS (build-time) | Terser JS compression / asset precompilation |
| Asset pipeline | Sprockets 4.2 + dart-sass (dartsass-rails 0.5) + ES2015+ JS, haml 7.2 (POAM-017e **closed**, R6/R9–R11) | SCSS/JS compilation |
| Browser UI | jQuery 4.0.0, **Bootstrap 5.3.8 + in-house `caselight_theme`** (POAM-017g **closed** 2026-07-13; INSPINIA removed — see `poam-017g-verification.md`), Trix 2.1, Tom Select 2.6, FullCalendar 6.1, formBuilder 3.23, Chart.js 4.4, vanillajs-datepicker 1.3.4, fileinput 5.5.4, Font Awesome 6.7.2 (v4 shims) | UI (whole POAM-017 family closed a–g; eval libraries replaced R12A/B; **enforced nonce-based CSP — POAM-017f closed**) |
| PDF engine | Chromium (distro package, baked in the image) driven by Ferrum — `PdfRenderer` | Warm render surface for per-flavor reporting; verified-PDF inline upload viewing (POAM-019 closed 2026-07-28: wkhtmltopdf/Qt-WebKit removed with the unrouted government-reports feature) |
| App server | puma 8 (threaded; config/puma.rb), behind Dockerized Caddy (`proxy` profile) | HTTP (replaced the sparsely-maintained thin, 2026-07) |

The CI service containers (`postgres:17`, `mongo:8.0`, `redis:7`) match this set. Auth is Devise
(+ two-factor, passkeys); authorization is CanCanCan (+ Pundit hooks).

### Trust boundary

Everything in the Docker Compose application stack (`app`/`sidekiq`/`db`/`mongo`/`redis`, and Caddy
when enabled) is CaseLight's responsibility. The **host, network, AWS account, EBS volume, KMS/secrets
storage, WAF, backups/DR, and WORM log storage** are inherited (§4). Data enters only through the
authenticated web UI and operator rake tasks; it leaves only through masked exports, the authorized
download controller, and the subject-access export (§3, AC/AU rows).

---

## 2. Data categorization (RA-2)

CaseLight processes **among the most sensitive PII categories that exist, stacked together**:
refugee/asylee **immigration status and documents**, **minors'** records (school, IEP, disciplinary),
**health and mental-health** needs, and government **identity documents**. A confidentiality breach is
a safety risk to vulnerable people, several of whom may be minors or have protection concerns.

- **Confidentiality: High** (special-category PII of a vulnerable population).
- **Integrity: Moderate** (case decisions rely on record accuracy; change audit required).
- **Availability: Low–Moderate** (a case-management pilot; downtime is disruptive, not life-safety).

Overall the system is managed to the **Moderate** baseline, with confidentiality controls
(encryption, field-level access control, audit) treated at the high end of Moderate. The complete
field-by-field data map — where each PII element lives, how it is protected, and how it leaves the
system — is `pii-inventory.md` (RA-2 / SI-12 evidence).

---

## 3. Application-layer controls (implemented)

Each row: **control → status → implementation anchor → evidence**. "Implemented" always has a
resolvable code path; run `rake compliance:evidence` for a machine-checked snapshot (§4).

### AC — Access Control
| Control | Status | Implementation | Evidence |
|---|---|---|---|
| AC-2 account management | Implemented | Devise users, one per staff (`app/models/user.rb`); admin CRUD; `disable` flag | AccessReview report + CSV (`app/controllers/access_reviews_controller.rb`, AC-2(j)) |
| AC-2(3) disable inactive accounts | Implemented | `accounts:disable_inactive` rake + `EnforcementSetting#inactive_disable_days` (per-tenant, report-only until set, last-admin guard) | `lib/tasks/accounts.rake`; `account_disabled` AccessLog event |
| AC-3 access enforcement | **Implemented (ENFORCED 2026-07-26)** | CanCanCan `app/classes/ability.rb`; mandatory-auth `check_authorization` + the `TenantBoundary` 409 refusal — production default ON (`config/environments/production.rb`; per-tenant panel overrides remain) after a shadow review recording ZERO divergences all-time | `authorization_coverage_guard_spec`; `authorization_cutover_route_smoke_spec` (every action × every role); flip evidence in the flip PR + `OPERATIONS.md` runbook |
| AC-6 least privilege | **Implemented (ENFORCED 2026-07-26)** | Role-scoped abilities narrowed (`least_privilege` production default ON — same flip/evidence); `SensitivityPolicy` + `SensitiveFields`/`SensitiveVersionScope` field masking is always-on and flag-independent | `least_privilege_shadow` history (zero events); persisted-path + config-path ON specs; `sensitive_field_masking_*` specs |
| AC-6 break-glass (emergency access) | Implemented | `BreakGlassGrant` — 1-hour self-elevation, mandatory reason, audit-written-first | `app/models/break_glass_grant.rb`; `break_glass:smoke` rake |
| AC-7 unsuccessful-logon lockout | Implemented | Devise `:lockable` (10/1h; floor ≥3 admin-brick guard) + rack-attack throttles | `config/initializers/rack_attack.rb`, `devise.rb`; `account_locked` AccessLog event |
| AC-12 session termination | Implemented | Devise `:timeoutable` (30 min, panel-tunable); secure session cookie | `config/initializers/session_store.rb`, `two_factor.rb` |

### AU — Audit & Accountability
| Control | Status | Implementation | Evidence |
|---|---|---|---|
| AU-2 / AU-12 auditable events & generation | Implemented | `AccessLog` (Mongo, append-only, tenant-scoped): read / login_failure / account_locked / access_denied / **record_destroyed / account_disabled / record_exported / enforcement_flag_changed**; `AccessAudit` concern + Warden hook + `rescue_from` | `audit-logging.md`; `app/models/access_log.rb` |
| AU-3 content / data-minimization | Implemented | id/type-only rows (never record contents); lograge JSON tags | `audit-logging.md` AU-3; `config/initializers/lograge.rb`, `filter_parameter_logging.rb` |
| AU-6 review | Implemented | Tenant-scoped indexed queries; AccessReview report | `access_reviews_controller.rb` |
| AU-9 protection | Implemented (app layer) | Append-only model (raise on update/destroy); tenant `default_scope`; single sanctioned purge path | `access_log.rb`; WORM/DB-ACL inherited (§4) |
| AU-11 retention | Implemented | `audit:purge` (90-day floor) + `retention:purge_*` (365-day floor); `policies/data-retention.md` | `lib/tasks/audit.rake`, `retention.rake`; `retention:report` |
| Change audit | Implemented | paper_trail `versions` (who/when/event), PII redacted at write | `encryption-at-rest.md`, `history-store-sc28-poam.md`; `config/initializers/paper_trail.rb` |

### IA — Identification & Authentication
| Control | Status | Implementation | Evidence |
|---|---|---|---|
| IA-2(1) MFA | Implemented (opt-in; enforce flag) | devise-two-factor TOTP + `:two_factor_backupable`; per-tenant require-MFA nudge | `config/initializers/two_factor.rb`; AccessReview "MFA gap" column |
| IA-2 passwordless (passkeys) | Implemented | WebAuthn (`webauthn` gem) additive login | `config/initializers/webauthn.rb`; `webauthn_credentials` |
| IA-5 authenticator management | Implemented | devise-security: complexity ≥12 + classes, no-reuse (last 5), optional expiry (panel) | `config/initializers/devise.rb`; `old_passwords` |

### SC — System & Communications Protection
| Control | Status | Implementation | Evidence |
|---|---|---|---|
| SC-5 / AC-7 DoS / rate-limit | Implemented | rack-attack throttles on auth + 2FA + passkey endpoints | `config/initializers/rack_attack.rb` |
| SC-7 boundary / headers | Implemented | Explicit security headers; **enforced nonce-based CSP** (every directive `'self'`-pinned; violation reports → `/csp_reports`; `ENFORCE_CSP=false` kill switch = report-only shadow mode); force_ssl/assume_ssl behind proxy; `TenantBoundary` | `config/application.rb`, `content_security_policy.rb`, `csp_reports_controller.rb`, `tenant_boundary.rb` |
| SC-8 transit encryption | Implemented (pilot) / Inherited | force_ssl + HSTS in app; TLS termination is Dockerized Caddy/Let's Encrypt (`proxy` compose profile) — **operating on the pilot box** since 2026-06; production hostname/DNS remain a real-data-gate item (§5) | `OPERATIONS.md`; app: `production.rb` |
| SC-12 / SC-13 key mgmt & crypto | Implemented (pilot) / TBD (prod) | ActiveRecord Encryption; keys derived from `secret_key_base` in pilot — **real-data host MUST supply independent KMS-managed keys via ENV** | `config/initializers/active_record_encryption.rb`; `encryption-at-rest.md` §Key management |
| SC-28 / SC-28(1) at rest | Implemented (primary + history) | Field-level encryption Tiers 1–5 (names/narratives/address/staff-PII/custom-form JSONB); history stores redacted at source + scrubbed | `encryption-at-rest.md`; `history-store-sc28-poam.md` (REMEDIATED); `tier{1..4}_encryption_spec`, `paper_trail_redaction_spec` |
| SC-28 authorized file serving | Implemented | `DownloadsController` (CanCan + sensitivity gate + fail-closed); `UploadsStaticGuard` denies raw `/uploads/**` except org logo | `app/controllers/downloads_controller.rb`, `config/initializers/assets_uploads_guard.rb` |

### SI / RA / CM / MP
| Control | Status | Implementation | Evidence |
|---|---|---|---|
| SI-2 flaw remediation | Implemented | Dependabot + the POA&M ledger; all High dependency findings closed | `.github/dependabot.yml`, `vulnerability-poam.md` |
| SI-10 input validation | Implemented | Strong params; safe deserialization (`SafeVersionValue`, no `eval`); YAML safe_load allowlist | `app/classes/safe_version_value.rb`; `version_reify_yaml_spec` |
| SI-11 error handling | Implemented | Static error pages (no stack traces to users in prod); filtered params | `config/exceptions_app`, `filter_parameter_logging.rb` |
| RA-2 categorization | Implemented | §2 + `pii-inventory.md` | this doc |
| RA-5 vulnerability scanning | Implemented | CI: Brakeman (SAST, gate fails on new findings — §4), bundler-audit, gitleaks | `.github/workflows/ci.yml` |
| CM-3 / CM-5 change management | Implemented | branch → PR → green CI → review; `policies/change-management.md`; enforcement-flag control room is admin-only + audited | `enforcement_settings_controller.rb` |
| MP-6 media sanitization / deletion | Implemented | Guarded cascading destroy + `record_destroyed` audit + post-destroy Mongo purge; retention purges | `policies/data-retention.md`; `deletion_lifecycle_spec` |

---

## 4. Inherited controls (deployment infrastructure)

CaseLight is the application layer; the following are provided and operated by the AWS/host
infrastructure and are documented with the deployment, not implemented in this repo. The application
is designed to sit correctly on top of them (e.g. `force_ssl` assumes a TLS-terminating proxy;
`AccessLog` guarantees the code won't tamper, infra guarantees no one else can).

| Control area | Inherited responsibility |
|---|---|
| SC-28 disk-at-rest | EBS volume encryption (defense-in-depth beneath field-level encryption; sole layer for the documented plaintext residuals) |
| SC-8 transit | TLS termination + cert lifecycle (Caddy/Let's Encrypt) — **operating on the pilot box** (auto-renewing; §5 covers the production hostname) |
| SC-12 keys | KMS / Secrets Manager for the real-data host's AR-Encryption keys |
| SC-7 network | Security groups (SSH via SSM only, zero inbound; DB/Mongo/Redis never exposed), private subnet/VPC, WAF |
| AU-8 time | Trusted NTP time source |
| AU-9 WORM | Immutable/object-lock log storage; MongoDB access control (least-privilege DB users) |
| CP / backups | Encrypted EBS snapshots + retention (inherited). The **restore drill is app-side and DONE** — first execution PASS 2026-07-26 (`drills/`), runbook in `OPERATIONS.md`; snapshot automation remains the inherited half |
| IR | Incident-response operations (the app provides detection signal; see `policies/incident-response.md`) |
| PE | Physical security (AWS data centers) |

---

## 5. Residual risk & production gate (TBD before real client data)

The pilot runs **synthetic data only** (`SECURITY.md` hard rule). The following must be resolved,
accepted, or verified before any real client record is entered. This section IS the control detail
behind `SECURITY.md`'s production gate.

**Hard gates (must close):**
- **KMS-managed encryption keys** — replace the pilot's `secret_key_base`-derived AR-Encryption keys
  with independent ENV/KMS keys (deferred to its own session: deterministic-key rotation breaks
  login/name equality until re-encrypted, and the gem-managed `otp_secret` sits outside the
  registry — needs a dev spike first). **The strict-mode half is DONE (2026-07-26):**
  `support_unencrypted_data=false` shipped after every tier verified as ciphertext in every tenant
  on dev and the box; only the migration rakes re-open the window, for their own process.
- **History-store SC-28** — POAM-SC28-HIST is **CLOSED (2026-07-12)**: box scrub + both verifies PASS
  at the production deploy; closure evidence attached in `history-store-sc28-poam.md`.
- **`cases.exit_note` plaintext** (POAM-012) — ~~encrypt or read-through before real data (High)~~
  **CLOSED (2026-07-26):** encrypted (Tier 1, non-deterministic) with the fan-out write path moved
  off `update_all`; historical rows backfill + verify at every deploy (bootstrap stage 7b), and the
  one-time Mongo scrub now covers embedded Case snapshots (`history:scrub_client_histories`).
- **Live client-record retention window** — currently **TBD and blocking** (`policies/data-retention.md`
  §2); set with the org (immigration + minors' records especially).
- **TLS in operation** — ~~stand up Caddy/Let's Encrypt~~ **live on the pilot box** (Dockerized
  Caddy, auto-renewing Let's Encrypt). Remaining for real data: a production domain (the pilot
  uses a nip.io hostname) and restricting 80/443 to pilot IPs/VPN per `SECURITY.md`.
- **Incident/breach response plan with named owners** (`policies/incident-response.md` — owners TBD).
- **Encrypted, tested backups + restore drill** — the **restore drill is DONE (2026-07-26,
  first execution PASS**: dumps restored into throwaway stores; counts matched the live baseline;
  encrypted values decrypted to exact live values under the box keys; PASS standard + runbook now
  in `docs/compliance/drills/` + `OPERATIONS.md`, incl. the dumps+`.env` recovery-unit finding).
  Still open: automated EBS snapshots + **WAF** + **network isolation** (inherited, must be
  confirmed operating).
- **Enforcement-flag flip** — ~~the AC-3/AC-6 flags ship shadow-first (OFF); flip per-environment
  after a shadow-window review of the AccessReview tables~~ **DONE (2026-07-26):** all three flags
  (AC-3, AC-6, SC-7) are the production default after the review found ZERO shadow-divergence
  events all-time across every tenant; per-tenant panel overrides remain the audited runtime
  switch, and the flip runbook (incl. the enforcement-window policy — `require_mfa` stays OFF
  until staff enroll their auth of choice) lives in `OPERATIONS.md`.

**Accepted residuals (documented, lower risk):** `Client.date_of_birth` plaintext (query/reporting
need; locked), `users.pin_number` plaintext (not an authenticator; hash-if-repurposed), slug/org-code
plaintext (routing identifiers). POAM-014/015 — tracked in `vulnerability-poam.md`, none blocking
the synthetic-data pilot (POAM-011 closed 2026-07-12, POAM-016 closed 2026-07-19, POAM-013 closed
2026-07-26 PR #206, **POAM-AC3-COMPARE closed 2026-07-26** — `api/clients#compare` is
current-tenant-only with a minimal `{id, organization}` payload, a required name field, and a
values-free `client_compare_probe` audit; the cross-tenant read path and its TenantBoundary
allowlist entry are gone).

**Licensing (clean-fork handoff):** CaseLight is AGPL-3.0 (network use is a distribution trigger — a
hosted client is owed the modified source). **Upstream license VERIFIED (2026-07-26, POAM-021
closed):** the maintained upstream repo's README (`github.com/Children-in-Families/oscar-web`,
License section) releases OSCaR under AGPL — the fork-time AGPL-3.0 `LICENSE` is confirmed correct;
same license, no relicensing. **POAM-024 closed 2026-07-28**: Tier-5 custom-form search moved off
the O(n)-decrypt path onto the deterministic search-entry sidecar (shadow-first cutover, zero
divergences; every-deploy backfill/verify gate in bootstrap step 7d) — the pre-real-data
performance gate it tracked is satisfied; the residual `is_empty`-on-scalar decrypt-scan is split
to POAM-025 (low, ~10-line fix ledgered).

---

## 6. Evidence & verification (RA-5 / CA-2 posture)

Evidence is **reproducible on demand**, not a point-in-time artifact:

- **`rake compliance:evidence`** — runs the verifiers (`encryption:verify`,
  `history:verify_versions`/`verify_client_histories`, `break_glass:smoke`, `retention:report`,
  `bundle-audit`) into a timestamped bundle under `tmp/evidence/<ts>/`, exiting non-zero if any gate
  fails (doubles as a pre-deploy check). This is the "where's the proof for control X" index.
- **CI gates** (`.github/workflows/ci.yml`): Brakeman `--compare` (fails on **new** SAST findings +
  uploads the report), bundler-audit (fails on un-ignored CVEs), gitleaks (fails on secrets), the
  rspec CI subset. Every bundler-audit ignore maps to a POA&M row.
- **Doc-honesty drift guards** (fail CI if code and docs diverge): `paper_trail_redaction_spec`
  (skip lists ⊇ encrypted attributes), `HistoryPiiFilter.scrub_keys_for`, the `ENCRYPTION_TIERS`
  registry, and `version_reify_yaml_spec` (the YAML permitted-classes guard).
- **In-app**: the AccessReview report/CSV (AC-2(j) recertification) and the enforcement-settings panel
  (AC-3/CM-5, per-flip audited) with inline shadow-divergence evidence.

## 7. Production-readiness statement

At the application layer, CaseLight today provides: role-based + field-level access control with
break-glass, MFA/passkeys, lockout + rate-limiting, comprehensive access + change auditing with
retention, field-level encryption of PII at rest across the primary and history stores, authorized-only
document serving, a full deletion/retention/subject-access lifecycle, and a CI pipeline that gates SAST
/ dependency-CVE / secret findings. All known High dependency findings are closed.

It is **ready to operate on synthetic data** under the pilot baseline — and since 2026-07-26 that
operation runs with the authorization/least-privilege/tenant-boundary flags **enforcing**, encryption
in **strict mode**, retention **archive-gated on a live schedule**, and a **passed restore drill**.
It is **not yet cleared for real client data**: the remaining §5 hard gates — KMS-managed keys, a
production hostname, the live-record retention decision, automated EBS snapshots + WAF + network
isolation confirmation, and a named-owner incident plan — must be met and the risk formally accepted
first. That gate is a deliberate, separate decision, exactly as `SECURITY.md` requires.
