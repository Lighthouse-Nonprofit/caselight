# CaseLight

**CaseLight** is a containerized, security-hardened fork of **OSCaR** (Open Source
Case-management and Record-keeping), maintained by **Lighthouse Nonprofit Technologies**
for nonprofit case management — tracking clients, families, programs, assessments, and
case notes.

## Honest status

CaseLight does **not** modernize the underlying application. The app is still
**Ruby 2.3.3 and Rails 4.2** — both end-of-life — inherited from upstream OSCaR. What this
fork adds today is the operational layer *around* that EOL stack:

- **Containerized deployment** that isolates the legacy Ruby/Rails toolchain so it never
  has to be installed on, or fought with, a modern host OS. The EOL runtime lives only
  inside a pinned Docker image.
- A **documented, security-conscious deployment posture**: secrets stay out of the image
  and out of git, services bind to localhost behind a reverse proxy, and per-deploy
  secrets are generated rather than shipped.
- **English-only** UI (upstream shipped English + Khmer).
- **Local asset-serving fixes** so the app renders correctly when self-hosted, without
  external object storage.

Modernizing the Ruby/Rails stack itself is **ongoing future work** — it is not something
this fork has done yet. Please do not read "containerized / hardened" as "modern stack."

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
| Ruby | 2.3.3 | EOL; runs only inside the Docker image |
| Rails | 4.2 | EOL |
| PostgreSQL | 9.6 | primary relational store |
| MongoDB | 3.6 | change / audit history |
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

# 2. Build the image (compiles the pinned EOL gems; the first build is slow).
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
- This is an end-of-life stack. Keep it isolated inside the container, behind a proxy, and
  patched at the edges (host OS, proxy, TLS). Treat stack modernization as the priority for
  any production use beyond a pilot.
