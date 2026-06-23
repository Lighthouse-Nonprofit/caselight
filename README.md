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

- **Ruby 3.3.11 / Rails 7.1.5.1** — migrated rung by rung (4.2 → 5.0 → 5.1 → 5.2 → 6.0 →
  6.1 → 7.0 → 7.1), each step verified green before the next. Zeitwerk autoloading and a
  modern gem set throughout (Mongoid 8, ros-apartment 3.4, active_model_serializers 0.10,
  paper_trail 15, factory_bot 6, …).
- **MongoDB 6.0** for change/audit history (was 3.6), **PostgreSQL 9.6** as the primary
  store, **Redis + Sidekiq** for background jobs.
- **Containerized deployment** so the runtime lives only inside a pinned Docker image and
  the host OS never has to carry the toolchain.
- A **security-conscious posture**: secrets stay out of the image and out of git, services
  bind to localhost behind a reverse proxy, and per-deploy secrets are generated rather
  than shipped.
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
| Ruby | 3.3.11 | runs inside the Docker image (`ruby:3.3`, Debian Bookworm) |
| Rails | 7.1.5.1 | |
| PostgreSQL | 9.6 | primary relational store (pg 1.6) |
| MongoDB | 6.0 | change / audit history (Mongoid 8.1) |
| Redis + Sidekiq | redis 5 / sidekiq 4 | background jobs |
| App server | thin | behind a reverse proxy |

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

## Security notes

- Secrets live only in `.env`, which is gitignored; the image ships none.
- The app binds to localhost — expose it only via a TLS reverse proxy.
- The stack is current (Ruby 3.3 / Rails 7.1), but still runs containerized for isolation and
  reproducibility. Keep the edges patched (host OS, proxy, TLS) and rebuild the image to pick
  up gem/security updates. PostgreSQL is still pinned at 9.6 — plan a bump (→ 14+) before any
  production use beyond the pilot.
