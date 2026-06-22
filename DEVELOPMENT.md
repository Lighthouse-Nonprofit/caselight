# DEVELOPMENT.md - running CaseLight locally

CaseLight is a containerized fork of OSCaR (Rails 4.2 / Ruby 2.3, EOL). You never
install that toolchain on your machine; the same Docker stack you deploy is the one
you develop against. Local dev is simpler than production: development mode reloads
code on the fly, compiles assets dynamically, and skips the S3 asset-host config, so
the styling "just works" with no precompile step.

## Prerequisites

- Docker Desktop with the WSL2 backend (Windows) or Docker Engine (Linux/macOS).
- An x86_64 machine. On ARM (Apple Silicon, Snapdragon Windows) the pinned amd64
  images run under emulation, which is slow and occasionally flaky.
- On Windows: clone and work **inside the WSL2 filesystem** (e.g. `~/caselight`), not
  under `/mnt/c`. Volume mounts and file-watching across the Windows/WSL boundary are
  slow, and Rails code reloading depends on file-watching. A Claude Code session
  launched from that WSL2 directory also gets a real Unix environment.

## First-time setup

1. Clone into WSL2:
   ```bash
   git clone git@github.com:<your-org>/caselight.git ~/caselight
   cd ~/caselight
   ```

2. Create a local `.env` (gitignored; dev-only values, safe to be simple):
   ```ini
   DATABASE_NAME=oscar_development
   DATABASE_NAME_TEST=oscar_test
   DATABASE_USER=oscar
   DATABASE_PASSWORD=devpassword
   DATABASE_HOST=db
   DATABASE_PORT=5432
   HISTORY_DATABASE_NAME=oscar_history_dev
   HISTORY_DATABASE_HOST=mongo
   REDIS_URL=redis://redis:6379/0
   RAILS_ENV=development
   SECRET_KEY_BASE=dev-only-value-not-a-real-secret
   SENDER_EMAIL=nil
   DEV_EMAIL=nil
   ABLE_MANAGER_EMAIL=nil
   GOOGLE_CLIENT_ID=nil
   GOOGLE_CLIENT_SECRET=nil
   ```
   `RAILS_ENV=development` is what flips the whole stack into dev mode. The
   `SECRET_KEY_BASE` is a throwaway; do not reuse it anywhere real.

3. Build and initialize:
   ```bash
   make dev-build      # installs gems into the image (slow the first time)
   make dev-setup      # creates + migrates the dev DB, the `cases` tenant, seeds
   ```

4. Create a dev admin (a console avoids shell-quoting pain):
   ```bash
   make dev-console
   ```
   then in the console:
   ```ruby
   Apartment::Tenant.switch!('cases')
   User.create!(email: 'dev@local.test', password: 'devpassword',
                password_confirmation: 'devpassword', roles: 'admin',
                first_name: 'Dev', last_name: 'Admin')
   ```

## Running

```bash
make dev
```

Then browse `http://cases.localhost:3000` and log in with the dev admin. The `cases`
subdomain is required; OSCaR routes tenants by subdomain, and modern browsers resolve
`*.localhost` to loopback automatically. `cases.lvh.me:3000` also works if you prefer.

## The dev loop

- Edit code locally. Because the source is mounted, changes apply on the next request
  with no rebuild.
- Change the Gemfile? Run `make dev-build` to reinstall gems, then `make dev`.
- Commit and push to the repo. The production box pulls and rebuilds from the repo;
  you do not edit or push from the box anymore. The repo is the source of truth.

## Why `docker-compose.dev.yml` and not `docker-compose.override.yml`

Compose auto-merges a file literally named `docker-compose.override.yml` on every
`docker compose up`. Since the production box pulls this same repo and runs
`docker compose up`, an override file would silently put prod into development mode
with your laptop's source-mount semantics. Naming it `docker-compose.dev.yml` and
loading it only via explicit `-f` flags (which the Makefile does) keeps that overlay
strictly local.

## Rules and caveats

- **Synthetic data only.** Never pull the production database to your laptop. It holds
  sensitive PII, and dev should run on fake data regardless.
- **Tests:** model and request specs run fine; the Capybara JS feature specs depend on
  PhantomJS, which is abandoned and effectively dead. Skip or replace those rather than
  fighting the install.
- Keep `.env` out of git. It is gitignored; confirm before any `git add`.
