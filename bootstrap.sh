#!/usr/bin/env bash
# bootstrap.sh — one-shot, idempotent deploy of CaseLight on the pilot box.
#
# CaseLight is modernized (Ruby 4.0 / Rails 7.2 / PostgreSQL 17 / Mongo 6.0). The repo carries
# the Dockerfile and compose files, so there is nothing to scp — just run this script.
# Rerun any time to deploy the latest main: it fetches, hard-resets to origin/$BRANCH,
# rebuilds, migrates (shared template + every tenant), encrypts existing rows at rest
# (Phase 4 / SC-28), and restarts the stack.
#
# Prereqs: Docker + the compose plugin installed, and the docker group active for the
# run user (see provision.sh / OPERATIONS.md). Run as the deploy user.
set -euo pipefail

REPO_URL="${REPO_URL:-git@github.com:Lighthouse-Nonprofit/caselight.git}"  # only used for the first clone
APP_DIR="${APP_DIR:-$HOME/oscar}"
BRANCH="${BRANCH:-main}"
TENANT_SHORT="${TENANT_SHORT:-cases}"        # lowercase, no underscores; = subdomain label = PG schema
TENANT_FULL="${TENANT_FULL:-Slo Home Pilot}"

# 1. Code — clone on first run, then always fast-sync to origin/$BRANCH.
if [ ! -d "$APP_DIR/.git" ]; then
  echo "==> cloning CaseLight into $APP_DIR"
  git clone "$REPO_URL" "$APP_DIR"
fi
cd "$APP_DIR"
echo "==> syncing to origin/$BRANCH"
git fetch origin --tags
git reset --hard "origin/$BRANCH"
echo "    now at: $(git log --oneline -1)"

# 2. .env — generated once with fresh secrets; never committed. Edit afterwards as needed.
if [ ! -f .env ]; then
  echo "==> generating .env with fresh secrets"
  cat > .env <<EOF
# --- Postgres (primary store) ---
DATABASE_NAME=oscar_production
DATABASE_NAME_TEST=oscar_test
DATABASE_USER=oscar
DATABASE_PASSWORD=$(openssl rand -hex 24)
DATABASE_HOST=db
DATABASE_PORT=5432

# --- Mongo (change/audit history) ---
HISTORY_DATABASE_NAME=oscar_history
HISTORY_DATABASE_HOST=mongo

# --- Redis / Sidekiq ---
REDIS_URL=redis://redis:6379/0

# --- Rails ---
RAILS_ENV=production
SECRET_KEY_BASE=$(openssl rand -hex 64)
RAILS_SERVE_STATIC_FILES=true

# --- Public hostname (Rails 7 host authorization + Caddy TLS) ---
# Set to your public hostname (e.g. cases.example.org) to restrict allowed hosts to it and
# its subdomains AND to tell the Caddy proxy which host to serve + obtain a cert for. Leave
# unset for tunnel-only/local access (host authorization is then disabled).
# APP_HOST=

# --- Mail / Google Calendar OAuth (optional; nil = feature dormant) ---
SENDER_EMAIL=nil
DEV_EMAIL=nil
ABLE_MANAGER_EMAIL=nil
GOOGLE_CLIENT_ID=nil
GOOGLE_CLIENT_SECRET=nil

# --- Document storage ---
# Defaults to local disk (CarrierWave :file, persisted in the 'uploads' volume).
# To use S3 instead: set STORAGE_BACKEND=s3 plus real AWS_*/FOG_* values.
# STORAGE_BACKEND=s3
# AWS_ACCESS_KEY_ID=
# AWS_SECRET_ACCESS_KEY=
# FOG_DIRECTORY=
# FOG_REGION=us-east-1
EOF
  chmod 600 .env
fi

# 3. Build the image (Ruby 4.0 / Rails 7.2; native gems compile here — slow on first build).
echo "==> docker compose build"
docker compose build

# 4. Data services first, then wait for Postgres to accept connections.
echo "==> starting db / mongo / redis"
docker compose up -d db mongo redis
DB_USER="$(grep -E '^DATABASE_USER=' .env | cut -d= -f2)"
echo "==> waiting for postgres"
until docker compose exec -T db pg_isready -U "$DB_USER" >/dev/null 2>&1; do sleep 2; done

# 5. Migrations — shared/template schema, then every tenant schema.
docker compose run --rm app bundle exec rake db:create 2>/dev/null || true
docker compose run --rm app bundle exec rake db:migrate
docker compose run --rm app bundle exec rake apartment:migrate

# 6. Tenant — create only if the org row is absent (idempotent).
echo "==> ensuring tenant '$TENANT_SHORT'"
if docker compose run --rm app bundle exec rails runner \
     "exit(Organization.where(short_name: '$TENANT_SHORT').exists? ? 0 : 1)"; then
  echo "    tenant already present, skipping create"
else
  docker compose run --rm app bundle exec rails runner \
    "Organization.create_and_build_tanent(short_name: '$TENANT_SHORT', full_name: '$TENANT_FULL')"
fi

# 7. Seed base reference data once.
if [ ! -f .seeded ]; then
  echo "==> seeding base data"
  docker compose run --rm app bundle exec rake db:seed && touch .seeded
fi

# 7b. Encrypt existing rows at rest — Phase 4 (FedRAMP SC-28 / SOC 2 C1.1). IDEMPOTENT and safe to run on
#     EVERY deploy: a no-op on a fresh or already-encrypted box (writing the decrypted value back round-trips
#     the same plaintext), and on an UPGRADE box with pre-encryption plaintext it converts every row to
#     ciphertext. It runs BEFORE the app comes up (step 8) on purpose: Tier 3 deterministically encrypts the
#     Devise login email, so a not-yet-backfilled plaintext row would fail the equality lookup and lock that
#     user out — backfilling before `up` means the app never serves an un-backfilled row (no login-broken
#     window). `verify` then gates each tier (non-zero exit on any plaintext straggler -> set -e halts the
#     deploy so you investigate before relying on login/search). Tiers: 1 narratives, 2 address/location,
#     3 user/staff PII, 4 client names, 5 custom-form JSONB. See docs/compliance/encryption-at-rest.md.
echo "==> encrypting existing rows at rest (backfill + verify, all tiers)"
for TIER in 1 2 3 4 5; do
  docker compose run --rm app bundle exec rake encryption:backfill TIER="$TIER" CONFIRM=1
  docker compose run --rm app bundle exec rake encryption:verify   TIER="$TIER"
done

# 8. Up the app + worker.
echo "==> starting app + sidekiq"
docker compose up -d app sidekiq

echo "==> done. App on 127.0.0.1:3000 (reach via the SSM/SSH tunnel)."
echo "    Public HTTPS: set APP_HOST in .env, point DNS at this box, open SG 80/443, then"
echo "      docker compose --profile proxy up -d caddy"
echo "    Redeploy: rerun this script. Tenant schema changes: rake apartment:migrate."
