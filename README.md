<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="app/assets/images/brand/caselight-logo-ondark.png">
    <img alt="CaseLight" src="app/assets/images/brand/caselight-logo.png" width="420">
  </picture>
</p>

<p align="center"><em>Open-source case management for nonprofits — by Lighthouse Nonprofit Technologies.</em></p>

**CaseLight** is a containerized, modernized fork of **OSCaR** (Open Source
Case-management and Record-keeping), maintained by **Lighthouse Nonprofit Technologies**
for nonprofit case management — tracking individuals, households, programs, assessments,
and case notes.

## Status

CaseLight runs a **modernized, supported stack**. The application was migrated off the
end-of-life **Ruby 2.3.3 / Rails 4.2** it inherited from upstream OSCaR up to current,
maintained versions:

- **Ruby 4.0.5 / Rails 7.2.3.1** — migrated rung by rung (4.2 → 5.0 → 5.1 → 5.2 → 6.0 →
  6.1 → 7.0 → 7.1 → 7.2), each step verified green before the next. Zeitwerk autoloading and a
  modern gem set throughout (Devise 5, Mongoid 8, ros-apartment 3.4, active_model_serializers 0.10,
  paper_trail 15, factory_bot 6, …).
- **PostgreSQL 17** as the primary store (was 9.6), **MongoDB 6.0** for change/audit history
  (was 3.6), **Redis + Sidekiq** for background jobs — all migrated to current versions.
- **Containerized deployment** so the runtime lives only inside a pinned Docker image and
  the host OS never has to carry the toolchain.
- An **application-layer security baseline** being hardened toward **FedRAMP Moderate** and
  **SOC 2** auditability — multi-factor authentication (TOTP + WebAuthn passkeys), account
  lockout and brute-force throttling, enforced HTTPS/HSTS and a strict security-header set,
  field-level encryption, and a CI security pipeline (SAST + dependency-CVE + secret scanning).
  See **[Security & authentication](#security--authentication)** below and
  [`docs/compliance/`](docs/compliance).
- **English-only** UI (upstream shipped English + Khmer) and **local asset-serving** so the
  app renders correctly self-hosted, without external object storage.

Intentionally **not** carried over from upstream for the current pilot scope: the Khmer
locale, the Thredded community forum, and the v1 mobile API.

## Credits & license

CaseLight is a fork of **OSCaR — Open Source Case-management and Record-keeping**,
originally built by **Rotati Consulting** and **Children in Families**.

- Upstream project: https://github.com/pannsamnang/oscar-web-os

OSCaR is licensed under **AGPL-3.0**, and CaseLight preserves it (see [`LICENSE`](LICENSE)).
The AGPL's **network-use clause** is important: if you run a modified version of CaseLight
as a network service, you must make your modified source available to its users. Publish
your fork's source accordingly.

## Stack

| Component | Version | Notes |
|---|---|---|
| Ruby | 4.0.5 | runs inside the Docker image (`ruby:4.0`, Debian Trixie) |
| Rails | 7.2.3.1 | |
| PostgreSQL | 17 | primary relational store (pg 1.5) |
| MongoDB | 6.0 | change / audit history (Mongoid 8.1) |
| Redis + Sidekiq | redis 5 / sidekiq 4 | background jobs |
| Auth | Devise 5 + MFA | TOTP (devise-two-factor) + WebAuthn passkeys (webauthn), password policy (devise-security) |
| App server | thin | behind a TLS reverse proxy (force_ssl + HSTS) |

## Quickstart

Requires Docker and the Docker Compose plugin on a Linux host.

```sh
git clone <your-fork-url> caselight
cd caselight

# 1. Create your environment file from the template, then fill in real values.
cp .env.example .env
#    Generate strong secrets, e.g.:
#      SECRET_KEY_BASE=$(openssl rand -hex 64)
#      DATABASE_PASSWORD=$(openssl rand -hex 24)
#    Edit .env accordingly. .env is gitignored — never commit it.

# 2. Build the image (compiles native gems; the first build is slow).
docker compose build

# 3. Start the datastores, then create + migrate the database.
docker compose up -d db mongo redis
docker compose run --rm app bundle exec rake db:create db:migrate

# 4. Create your first tenant (OSCaR is multi-tenant by subdomain; the
#    short_name is the subdomain label and Postgres schema — lowercase, no underscores).
docker compose run --rm app bundle exec rails runner \
  "Organization.create_and_build_tanent(short_name: 'yourorg', full_name: 'Your Organization')"

# 5. Seed reference data, then bring up the app and worker.
docker compose run --rm app bundle exec rake db:seed
docker compose up -d app sidekiq
```

The app listens on `127.0.0.1:3000`. Put a TLS-terminating reverse proxy in front of it
for any non-local use. See [`Dockerfile`](Dockerfile) and
[`docker-compose.yml`](docker-compose.yml) for the full build and service definitions, and
[`bootstrap.sh`](bootstrap.sh) for an end-to-end deploy script (clone → build → migrate →
tenant → seed → up); tune the `TENANT_SHORT` / `TENANT_FULL` values at the top first.

## Security & authentication

CaseLight is being hardened, phase by phase, toward **FedRAMP Moderate** and **SOC 2 (Security ·
Confidentiality · Privacy)** auditability at the application layer. What's in place today:

**Authentication & sessions**
- **Multi-factor authentication** — opt-in **TOTP** (authenticator app) with one-time recovery codes,
  plus phishing-resistant **WebAuthn passkeys** as an additional sign-in method. A config flag can
  require MFA for privileged roles.
- **Account lockout** after repeated failed logins, **idle-session timeout**, and **brute-force
  rate-limiting** (rack-attack) on the login, password-reset, MFA, and passkey endpoints.
- **Password policy** — minimum length 12 with character-class complexity and no-reuse history.

**Transport & application hardening**
- **Enforced HTTPS** with HSTS (trusting the reverse proxy's TLS), a **Content-Security-Policy** and a
  strict security-header set (X-Frame-Options, X-Content-Type-Options, Referrer-Policy, …), and
  **secure / HttpOnly / SameSite** session cookies.
- **Field-level encryption at rest** (Rails ActiveRecord Encryption) for sensitive values, and
  **parameter-log redaction** of credentials and PII.

**Audit & access logging**
- **Structured request logs** — `lograge` emits one JSON line per request, tagged with `request_id`,
  `user_id`, `tenant`, and `remote_ip`. Disabled in `test`.
- **Access log of record reads** — an append-only, tenant-isolated `AccessLog` (MongoDB via Mongoid)
  records successful reads (`show` / `index`) of sensitive resources (Clients, Progress Notes,
  Assessments, Case Notes) via the `AccessAudit` concern. Only identifiers (resource type/id) and a
  denormalized `user_email` are stored — never record contents. Toggled by
  `config.x.access_logging_enabled` (defaults on; fails safe to on).
- **Security events** — failed logins and account lockouts (a Warden `before_failure` hook) and
  authorization denials (CanCanCan / Pundit) are written to the same `AccessLog`, always. Logging never
  raises into the request it audits.
- **Tenant isolation & immutability** — `AccessLog` is per-tenant by `default_scope` (Mongo is a shared
  DB) and append-only at the app layer (`before_update` / `before_destroy` raise); true WORM is an infra
  hand-off.
- **Retention** — per [`docs/compliance/audit-retention.md`](docs/compliance/audit-retention.md);
  removed only by the sanctioned `rake audit:purge`. Control narrative in
  [`docs/compliance/audit-logging.md`](docs/compliance/audit-logging.md) (FedRAMP **AU-2/3/6/9/11/12**,
  SOC 2 **CC7.2/7.3**).

**Secure SDLC**
- Every pull request runs **Brakeman** (SAST), **bundler-audit** (dependency CVEs), **gitleaks**
  (secret scanning), and the full test suite; **Dependabot** keeps dependencies current. Open findings
  are tracked in a **POA&M** under [`docs/compliance/`](docs/compliance).

**Deployment**
- Secrets live only in `.env` (gitignored); the image ships none, and per-deploy secrets are generated.
- The app binds to localhost — expose it only via a **TLS-terminating reverse proxy**.
- The stack carries **no end-of-life components**; rebuild the image to pick up gem/security updates,
  and keep the edges patched (host OS, proxy, TLS).
- **Pilot data is synthetic only.** Real client records are a deliberate, separate gate — see
  [`SECURITY.md`](SECURITY.md) for the controls required first.
