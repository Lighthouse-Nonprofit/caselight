#!/usr/bin/env bash
# bootstrap.sh — one-shot, idempotent deploy of CaseLight on the pilot box.
#
# CaseLight is modernized (Ruby 4.0 / Rails 8.1 / PostgreSQL 17 / Mongo 8.0). The repo carries
# the Dockerfile and compose files, so there is nothing to scp — just run this script.
# Rerun any time to deploy the latest main: it fetches, hard-resets to origin/$BRANCH,
# rebuilds, migrates (shared template + every tenant), encrypts existing rows at rest
# (Phase 4 / SC-28), and restarts the stack.
#
# Prereqs: Docker + the compose plugin installed, and the docker group active for the
# run user (see OPERATIONS.md). Run as the deploy user.
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
PRE_SYNC_SHA="$(git rev-parse HEAD)"
git fetch origin --tags
git reset --hard "origin/$BRANCH"
echo "    now at: $(git log --oneline -1)"

# Self-update guard: bash keeps executing the OLD text of a script whose file changed mid-run,
# so a deploy that itself updates bootstrap.sh would run WITHOUT the new stages (on 2026-07-22
# this skipped the reencrypt stage and the stale backfill destroyed the client names). If the
# sync touched this script, re-exec the fresh copy exactly once.
if [ "${BOOTSTRAP_REEXEC:-0}" != "1" ] && ! git diff --quiet "$PRE_SYNC_SHA" HEAD -- bootstrap.sh; then
  echo "==> bootstrap.sh changed in this sync — re-exec'ing the updated script"
  BOOTSTRAP_REEXEC=1 exec bash "$APP_DIR/bootstrap.sh"
fi

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

# --- Flavor (Y1) ---
# One server = one flavor. Picks the locale overlay (config/flavors/<FLAVOR>/) and
# which taxonomy `rake flavor:seed` plants. Whitelisted at boot: resettlement | youth.
# SEED_DEMO=true additionally plants SYNTHETIC demo records (demo boxes ONLY — never
# on a production box). Youth boxes should also set ASSESSMENT_MIN_INTERVAL_DAYS=84.
FLAVOR=resettlement
SEED_DEMO=false
# Minimum days between a client's assessments (Y2c). Unset = legacy 6 calendar
# months; youth boxes set 84 (12-week SEL pre/post cadence).
# ASSESSMENT_MIN_INTERVAL_DAYS=84
# CSP kill switch (POAM-017f): the Content-Security-Policy is ENFORCED by default.
# Uncomment to fall back to report-only shadow mode (violations logged via /csp_reports,
# nothing blocked) — e.g. for a post-redeploy observation window. Restart required.
# ENFORCE_CSP=false

# --- Public hostname (Rails 7 host authorization + Caddy TLS) ---
# Set to your public hostname (e.g. cases.example.org) to restrict allowed hosts to it and
# its subdomains AND to tell the Caddy proxy which host to serve + obtain a cert for. Leave
# unset for tunnel-only/local access (host authorization is then disabled).
# APP_HOST=

# --- Mail / Google Calendar OAuth (optional; nil = feature dormant) ---
# D6: empty = unset (the old literal "nil" string leaked into from-headers; the app
# treats 'nil'/blank as unconfigured either way). Set a real verified SES sender +
# AWS_SES_USER_NAME/PASSWORD to flip on staff mail AND client-direct reminders.
SENDER_EMAIL=
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

# 3. Build the image (Ruby 4.0 / Rails 8.1; native gems compile here — slow on first build).
echo "==> docker compose build"
docker compose build

# 4. Data services first, then wait for Postgres to accept connections.
echo "==> starting db / mongo / redis"
docker compose up -d db mongo redis
DB_USER="$(grep -E '^DATABASE_USER=' .env | cut -d= -f2)"
echo "==> waiting for postgres"
until docker compose exec -T db pg_isready -U "$DB_USER" >/dev/null 2>&1; do sleep 2; done
echo "==> waiting for mongo"
until docker compose exec -T mongo mongosh --quiet --eval 'db.runCommand({ping:1}).ok' >/dev/null 2>&1; do sleep 2; done

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

# 7a. Flavor taxonomy (Y1). Older boxes predate the FLAVOR/SEED_DEMO keys — upsert them
#     into .env idempotently (the heredoc above only runs on first boot; chmod stays 600).
grep -q '^FLAVOR=' .env || printf '\nFLAVOR=resettlement\n' >> .env
grep -q '^SEED_DEMO=' .env || printf 'SEED_DEMO=false\n' >> .env
FLAVOR_ACTIVE="$(grep -E '^FLAVOR=' .env | tail -1 | cut -d= -f2)"
SEED_DEMO_ACTIVE="$(grep -E '^SEED_DEMO=' .env | tail -1 | cut -d= -f2)"
#     Stamp-gated per flavor: seed_domains destructively reconciles and seed_taxonomy
#     reverts hand-edits, so this must NOT rerun every deploy. To re-apply an updated
#     taxonomy deliberately: rm ".flavor_seeded.<flavor>" and rerun (read the
#     destructive-reconcile warning in OPERATIONS.md first). A flavor FLIP works
#     naturally — the new flavor's stamp is absent, so its seeds run.
if [ ! -f ".flavor_seeded.$FLAVOR_ACTIVE" ]; then
  echo "==> seeding $FLAVOR_ACTIVE flavor taxonomy"
  docker compose run --rm -e TENANT="$TENANT_SHORT" app bundle exec rake flavor:seed
  touch ".flavor_seeded.$FLAVOR_ACTIVE"
fi
if [ "$SEED_DEMO_ACTIVE" = "true" ] && [ ! -f ".flavor_demo_seeded.$FLAVOR_ACTIVE" ]; then
  echo "==> seeding $FLAVOR_ACTIVE flavor DEMO data (synthetic)"
  docker compose run --rm -e TENANT="$TENANT_SHORT" app bundle exec rake flavor:seed_demo
  touch ".flavor_demo_seeded.$FLAVOR_ACTIVE"
fi

# 7b. Encrypt existing rows at rest — Phase 4 (FedRAMP SC-28 / SOC 2 C1.1). IDEMPOTENT and safe to run on
#     EVERY deploy: a no-op on a fresh or already-encrypted box (writing the decrypted value back round-trips
#     the same plaintext), and on an UPGRADE box with pre-encryption plaintext it converts every row to
#     ciphertext. It runs BEFORE the app comes up (step 8) on purpose: Tier 3 deterministically encrypts the
#     Devise login email, so a not-yet-backfilled plaintext row would fail the equality lookup and lock that
#     user out — backfilling before `up` means the app never serves an un-backfilled row (no login-broken
#     window). `verify` then gates each tier (non-zero exit on any plaintext straggler -> set -e halts the
#     deploy so you investigate before relying on login/search). Tiers: 1 narratives, 2 address/location,
#     3 user/staff PII, 4 client names, 5 custom-form JSONB, 6 credentials (born-encrypted; backfill is a
#     structural no-op). See docs/compliance/encryption-at-rest.md.
echo "==> encrypting existing rows at rest (backfill + verify, all tiers)"
for TIER in 1 2 3 4 5 6; do
  docker compose run --rm app bundle exec rake encryption:backfill TIER="$TIER" CONFIRM=1
  docker compose run --rm app bundle exec rake encryption:verify   TIER="$TIER"
done

# 7c. UX round 3 (C1): rewrite the four client-name columns under the ignore_case scheme and
#     populate their original_* display sidecars. MUST run before `up` — with ignore_case the
#     reader prefers the sidecar for encrypted rows, so a legacy row without one reads as NIL
#     (names would render blank) until this rewrites it. Idempotent BY SKIPPING (hotfix #203,
#     2026-07-23): rows whose sidecar is already populated are untouched — a re-run must NOT
#     round-trip them (read_attribute returns the DOWNCASED column on a migrated row; writing
#     it into the sidecar destroys display case). A routine redeploy reports re-encrypted=0.
#     Runs AFTER the tier loop on purpose: the TIER=4 backfill re-ciphers the name columns but
#     leaves the sidecars alone.
echo "==> re-encrypting client names under the ignore_case scheme (C1)"
docker compose run --rm app bundle exec rake encryption:reencrypt_client_names CONFIRM=1

# 7d. POAM-024: rebuild/diff-sync the Tier-5 search-entry sidecar, then verify it. IDEMPOTENT BY
#     CONSTRUCTION: the sync inserts only missing pairs and deletes only stale rows, so a routine
#     redeploy MUST report added=0 removed=0 — a non-zero line here means entries drifted and
#     verify will say where (verify non-zero-exits on drift; set -e halts the deploy). Runs AFTER
#     7b (rows must be ciphertext before this walk reads them under strict mode) and BEFORE `up`
#     so search never serves a half-built sidecar. NB the TIER=5 loop in 7b also re-writes the
#     entry VALUES themselves (the entry models are registered born-encrypted for verify/drift
#     coverage); deterministic ciphertext is byte-stable so that pass is a no-op rewrite — the
#     zero-PROOF lives here, in this step's added=0 removed=0 line.
echo "==> rebuilding the Tier-5 search-entry sidecar (backfill + verify, POAM-024)"
docker compose run --rm app bundle exec rake properties_search:backfill CONFIRM=1
docker compose run --rm app bundle exec rake properties_search:verify

# 8. Up the app + worker.
echo "==> starting app + sidekiq"
docker compose up -d app sidekiq

# 9. POAM-015: install the whenever schedule into the HOST crontab (the box had NO crontab
#    before 2026-07-26 -- config/schedule.rb was dead code). schedule.rb wraps every job in
#    `docker compose exec -T app ...`, so the host needs no Ruby; job output appends to
#    log/cron.log / log/whenever.log under this directory. `crontab -` REPLACES the user
#    crontab -- this deploy owns it (verified empty before the first install; OPERATIONS.md).
#    The retention purges carry CONFIRM=1 but REFUSE in code unless their window has a
#    verified archive (retention:archive -> retention:verify_archive), so scheduling them is
#    fail-safe.
echo "==> installing the whenever crontab (app schedule + archive-gated retention)"
mkdir -p log
docker compose run --rm app bundle exec whenever | crontab -
echo "    installed $(crontab -l | grep -c "docker compose exec") cron job(s)"

echo "==> done. App on 127.0.0.1:3000 (reach via the SSM/SSH tunnel)."
echo "    Public HTTPS: set APP_HOST in .env, point DNS at this box, open SG 80/443, then"
echo "      docker compose --profile proxy up -d caddy"
echo "    Redeploy: rerun this script. Tenant schema changes: rake apartment:migrate."
